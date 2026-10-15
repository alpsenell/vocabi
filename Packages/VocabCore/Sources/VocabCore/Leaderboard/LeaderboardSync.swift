import Foundation

/// A quiz result waiting to be sent to the leaderboard backend.
public struct PendingLeaderboardSubmission: Codable, Equatable, Sendable, Identifiable {
    public var result: QuizResult
    public var nickname: String
    public var enqueuedAt: Date

    public var id: UUID { result.id }

    public init(result: QuizResult, nickname: String, enqueuedAt: Date = Date()) {
        self.result = result
        self.nickname = nickname
        self.enqueuedAt = enqueuedAt
    }
}

/// Persistent FIFO of submissions that have not reached the server yet (App Group UserDefaults).
public final class PendingLeaderboardQueue: @unchecked Sendable {
    public static let defaultKey = "leaderboard.pendingResults.v1"
    /// Hard cap on stored submissions; the oldest are dropped first.
    public static let maxEntries = 50
    /// Results older than this no longer affect any visible period (monthly is the longest) and are dropped.
    public static let maxAge: TimeInterval = 40 * 86_400

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults, key: String = PendingLeaderboardQueue.defaultKey,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    public var all: [PendingLeaderboardSubmission] {
        lock.withLock { pruned(load()) }
    }

    public var first: PendingLeaderboardSubmission? { all.first }

    public var count: Int { all.count }

    /// Adds a submission unless one with the same result id is already queued.
    public func enqueue(_ item: PendingLeaderboardSubmission) {
        lock.withLock {
            var items = pruned(load())
            guard !items.contains(where: { $0.id == item.id }) else { return }
            items.append(item)
            if items.count > Self.maxEntries { items.removeFirst(items.count - Self.maxEntries) }
            save(items)
        }
    }

    public func remove(id: UUID) {
        lock.withLock {
            var items = load()
            items.removeAll { $0.id == id }
            save(pruned(items))
        }
    }

    public func removeAll() {
        lock.withLock { defaults.removeObject(forKey: key) }
    }

    private func pruned(_ items: [PendingLeaderboardSubmission]) -> [PendingLeaderboardSubmission] {
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        return items.filter { $0.result.date >= cutoff }
    }

    private func load() -> [PendingLeaderboardSubmission] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingLeaderboardSubmission].self, from: data)) ?? []
    }

    private func save(_ items: [PendingLeaderboardSubmission]) {
        if items.isEmpty { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}

/// Wraps a backend `LeaderboardService` with an offline queue:
/// every submission is persisted first, then the whole queue is flushed in order.
/// Fetches flush the queue opportunistically before reading.
public actor LeaderboardSyncCoordinator: LeaderboardService {
    private let service: LeaderboardService
    private let queue: PendingLeaderboardQueue
    private var isFlushing = false

    public init(service: LeaderboardService, queue: PendingLeaderboardQueue) {
        self.service = service
        self.queue = queue
    }

    public var pendingCount: Int { queue.count }

    /// Queues `result` and tries to send everything that is pending.
    /// Implausible results (score ≤ 0 or above the per-quiz maximum) are ignored.
    public func submit(_ result: QuizResult, nickname: String) async throws {
        guard LeaderboardRanking.isSubmittable(result) else { return }
        queue.enqueue(PendingLeaderboardSubmission(result: result, nickname: nickname))
        try await flush()
    }

    /// Sends queued submissions oldest-first. Stops at the first failure and rethrows it;
    /// the failed item and everything after it stay queued. Returns the number sent.
    /// A flush already in progress picks up newly queued items, so concurrent calls return 0.
    @discardableResult
    public func flush() async throws -> Int {
        guard !isFlushing else { return 0 }
        isFlushing = true
        defer { isFlushing = false }

        var sent = 0
        while let next = queue.first {
            try await service.submit(next.result, nickname: next.nickname)
            queue.remove(id: next.id)
            sent += 1
        }
        return sent
    }

    public func fetch(period: LeaderboardPeriod, targetLanguage: Language) async throws -> [LeaderboardEntry] {
        _ = try? await flush()
        return try await service.fetch(period: period, targetLanguage: targetLanguage)
    }
}
