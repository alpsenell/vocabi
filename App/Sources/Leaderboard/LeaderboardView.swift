import SwiftUI
import VocabCore

// OWNED BY THE LEADERBOARD TEAMMATE. The app shell only instantiates `LeaderboardView()`
// and calls `LeaderboardSubmitter.submit(_:)` after a quiz.

// MARK: - Shared backend

enum LeaderboardBackend {
    static let defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard

    /// CloudKit service wrapped in the offline queue (App Group key "leaderboard.pendingResults.v1").
    static let shared = LeaderboardSyncCoordinator(service: CloudKitLeaderboardService(defaults: defaults),
                                                   queue: PendingLeaderboardQueue(defaults: defaults))

    /// Posted on the main queue after queued results reached the server.
    static let didSubmitNotification = Notification.Name("LeaderboardBackend.didSubmit")
    /// Posted on the main queue when a submission could not reach the server (it stays queued).
    static let didFailNotification = Notification.Name("LeaderboardBackend.didFail")
}

enum LeaderboardSubmitter {
    /// Fire-and-forget submission; never throws into the quiz flow.
    /// The result is persisted first, so failures are retried on the next submit or leaderboard fetch.
    static func submit(_ result: QuizResult) {
        let nickname = SharedStore.shared.settings.nickname
        Task.detached(priority: .utility) {
            do {
                try await LeaderboardBackend.shared.submit(result, nickname: nickname)
                await MainActor.run {
                    NotificationCenter.default.post(name: LeaderboardBackend.didSubmitNotification, object: nil)
                }
            } catch {
                // Swallowed on purpose: the submission stays queued for the next attempt.
                await MainActor.run {
                    NotificationCenter.default.post(name: LeaderboardBackend.didFailNotification, object: nil)
                }
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class LeaderboardViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([LeaderboardEntry])
        case failed(LeaderboardError)
    }

    var period: LeaderboardPeriod = .weekly
    private(set) var states: [LeaderboardPeriod: LoadState] = [:]
    private(set) var targetLanguage: Language = SharedStore.shared.settings.targetLanguage
    private(set) var pendingCount = 0

    private let service: LeaderboardService
    private let pendingCounter: (@Sendable () async -> Int)?

    init(service: LeaderboardService = LeaderboardBackend.shared) {
        self.service = service
        if let coordinator = service as? LeaderboardSyncCoordinator {
            pendingCounter = { await coordinator.pendingCount }
        } else {
            pendingCounter = nil
        }
    }

    var state: LoadState { states[period] ?? .idle }

    var currentEntry: LeaderboardEntry? {
        if case .loaded(let entries) = state { return entries.first(where: \.isCurrentUser) }
        return nil
    }

    /// Loads the selected period (cached unless `force`); invalidates the cache when the target language changed.
    /// Keeps the previous rows visible while refreshing.
    func load(force: Bool = false) async {
        let language = SharedStore.shared.settings.targetLanguage
        if language != targetLanguage {
            targetLanguage = language
            states.removeAll()
        }
        let period = self.period
        if !force, case .loaded = states[period] { return }
        if case .loaded = states[period] {} else { states[period] = .loading }

        do {
            let entries = try await service.fetch(period: period, targetLanguage: language)
            states[period] = .loaded(entries)
        } catch let error as LeaderboardError {
            states[period] = .failed(error)
        } catch {
            states[period] = .failed(.unknown(error.localizedDescription))
        }
        pendingCount = await pendingCounter?() ?? 0
    }

    func invalidateAll() { states.removeAll() }
}

// MARK: - View

struct LeaderboardView: View {
    @State private var model = LeaderboardViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                content
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Leaderboard"))
            .refreshable { await model.load(force: true) }
            .task(id: model.period) { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: LeaderboardBackend.didSubmitNotification)) { _ in
                model.invalidateAll()
                Task { await model.load(force: true) }
            }
            .animation(.default, value: model.state)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $model.period) {
                ForEach(LeaderboardPeriod.allCases) { p in
                    Text(p.localizedName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label(model.period.windowLabel(for: Date()), systemImage: "calendar")
                Spacer()
                Text("Learning \(model.targetLanguage.flag) \(model.targetLanguage.nativeName)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if case .loaded = model.state {
                OwnRankCard(entry: model.currentEntry)
            }
            if model.pendingCount > 0 {
                Label("Some scores will sync when you're back online.", systemImage: "icloud.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            Section {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
            }
        case .failed(.notSignedIn):
            Section {
                ContentUnavailableView {
                    Label("iCloud required", systemImage: "icloud.slash")
                } description: {
                    Text("Sign in to iCloud in Settings to join the global ranking.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        case .failed:
            Section {
                ContentUnavailableView {
                    Label("Couldn't load the leaderboard", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await model.load(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        case .loaded(let entries) where entries.isEmpty:
            Section {
                ContentUnavailableView("No scores yet", systemImage: "trophy",
                                       description: Text("Be the first to finish a quiz this period!"))
                    .listRowBackground(Color.clear)
            }
        case .loaded(let entries):
            Section {
                ForEach(entries) { entry in
                    LeaderboardRow(entry: entry)
                        .listRowBackground(entry.isCurrentUser ? Color.accentColor.opacity(0.15) : nil)
                }
            }
        }
    }
}

// MARK: - Rows

private struct OwnRankCard: View {
    let entry: LeaderboardEntry?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your rank").font(.caption).foregroundStyle(.secondary)
                if let entry {
                    Text("#\(LeaderboardRanking.rankLabel(entry.rank))")
                        .font(.title2.bold())
                        .monospacedDigit()
                } else {
                    Text("Not ranked yet").font(.headline)
                    Text("Finish a quiz to get on the board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let entry {
                Text("\(entry.total) pts")
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            Text(entry.nickname)
                .font(entry.isCurrentUser ? .body.bold() : .body)
                .lineLimit(1)
            if entry.isCurrentUser {
                Text("You")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            Spacer()
            Text("\(entry.total) pts")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rankBadge: some View {
        let label = LeaderboardRanking.rankLabel(entry.rank)
        if let medal = medalColor {
            Image(systemName: "medal.fill")
                .foregroundStyle(medal)
                .frame(width: 40)
                .accessibilityLabel(Text(label))
        } else {
            Text(label)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 40)
                .foregroundStyle(.secondary)
        }
    }

    private var medalColor: Color? {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return nil
        }
    }
}

// MARK: - Labels

extension LeaderboardPeriod {
    var localizedName: String {
        switch self {
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }

    /// "Oct 15", "Week 42", "October 2026" — computed in UTC like the period keys.
    func windowLabel(for date: Date) -> String {
        let utc = TimeZone(identifier: "UTC")!
        switch self {
        case .daily:
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.timeZone = utc
            return date.formatted(style)
        case .weekly:
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = utc
            let week = cal.component(.weekOfYear, from: date)
            return String(localized: "Week \(week)")
        case .monthly:
            var style = Date.FormatStyle.dateTime.month(.wide).year()
            style.timeZone = utc
            return date.formatted(style)
        }
    }
}

#Preview {
    LeaderboardView()
}
