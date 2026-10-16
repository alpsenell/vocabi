import Foundation
import VocabCore
import WidgetKit

/// Downloads AI word packs for Pro users: plans with `PackPlanner`, fetches with `PackClient`,
/// stores in `PackStore.shared`, then reloads widgets. Runs on launch, after settings change
/// (debounced) and when Pro becomes active.
@MainActor
final class PackSyncService: ObservableObject {
    enum State: Equatable {
        case idle
        case syncing(done: Int, total: Int)
        case failed(String)
    }

    private static let lastSyncKey = "pack.lastSync.v1"

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSync: Date?
    @Published private(set) var summary: PackLibrarySummary

    /// Called on the main actor after packs were added (e.g. to refresh `AppModel`).
    var onPacksChanged: (() -> Void)?

    private let client: PackClient
    private let packStore: PackStore
    private let planner: PackPlanner
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var resyncRequested: (settings: UserSettings, isEntitled: Bool)?

    init(client: PackClient = PackSyncService.makeDefaultClient(),
         packStore: PackStore = .shared,
         planner: PackPlanner = PackPlanner(),
         defaults: UserDefaults = ProEntitlement.sharedDefaults) {
        self.client = client
        self.packStore = packStore
        self.planner = planner
        self.defaults = defaults
        self.summary = PackLibrarySummary(packs: packStore.allPacks)
        self.lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    nonisolated static func makeDefaultClient() -> PackClient {
        URLSessionPackClient(baseURL: AppInfo.packServerURL, installID: PackInstallID.current(),
                             tokenProvider: { await StoreManager.packServerToken() })
    }

    var isSyncing: Bool { if case .syncing = state { return true } else { return false } }

    /// Settings changed: wait briefly so a burst of toggles results in one sync.
    func scheduleSync(settings: UserSettings, isEntitled: Bool, delay: Duration = .seconds(2)) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.sync(settings: settings, isEntitled: isEntitled)
        }
    }

    /// Starts a sync unless one is running (then it re-runs once with the latest settings).
    func sync(settings: UserSettings, isEntitled: Bool) {
        guard isEntitled else {
            if isSyncing == false { state = .idle }
            return
        }
        guard settings.isValid else { return }
        if syncTask != nil {
            resyncRequested = (settings, isEntitled)
            return
        }
        syncTask = Task { [weak self] in
            await self?.run(settings: settings)
            guard let self else { return }
            self.syncTask = nil
            if let next = self.resyncRequested {
                self.resyncRequested = nil
                self.sync(settings: next.settings, isEntitled: next.isEntitled)
            }
        }
    }

    /// Clears local packs (Reset progress).
    func removeAllPacks() {
        syncTask?.cancel()
        packStore.removeAll()
        defaults.removeObject(forKey: Self.lastSyncKey)
        lastSync = nil
        state = .idle
        summary = PackLibrarySummary(packs: [])
        WidgetCenter.shared.reloadAllTimelines()
        onPacksChanged?()
    }

    private func run(settings: UserSettings) async {
        let plan = planner.plan(settings: settings, stored: packStore.allPacks)
        guard !plan.isEmpty else {
            markSynced()
            state = .idle
            return
        }
        state = .syncing(done: 0, total: plan.count)
        var saved = 0
        var lastError: Error?
        for (i, request) in plan.enumerated() {
            if Task.isCancelled { break }
            do {
                let pack = try await client.fetchPack(request)
                try packStore.save(pack)
                saved += 1
                summary = PackLibrarySummary(packs: packStore.allPacks)
            } catch let error as PackClientError {
                lastError = error
                if error.abortsSync { break }
            } catch is CancellationError {
                break
            } catch {
                lastError = error
            }
            state = .syncing(done: i + 1, total: plan.count)
        }
        if saved > 0 {
            WidgetCenter.shared.reloadAllTimelines()
            onPacksChanged?()
        }
        if let lastError, saved < plan.count {
            state = .failed(Self.message(for: lastError))
        } else {
            markSynced()
            state = .idle
        }
    }

    private func markSynced() {
        let now = Date()
        lastSync = now
        defaults.set(now, forKey: Self.lastSyncKey)
        summary = PackLibrarySummary(packs: packStore.allPacks)
    }

    static func message(for error: Error) -> String {
        switch error as? PackClientError {
        case .network?:
            return String(localized: "Can't reach the word pack server. Check your connection and try again.")
        case .missingToken?, .subscriptionInvalid?:
            return String(localized: "Your Vocabi Pro subscription couldn't be verified. Try Restore purchases.")
        case .rateLimited?:
            return String(localized: "You've requested a lot of new words. Try again later.")
        case .generationFailed?, .server?, .invalidResponse?:
            return String(localized: "New words couldn't be prepared right now. Try again later.")
        case nil:
            return String(localized: "New words couldn't be saved. Try again later.")
        }
    }
}
