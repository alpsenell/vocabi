import Foundation

/// Single point of access to state shared between the app and the widget extension (App Group).
/// Thread-safe through an internal serial queue; all methods are synchronous and cheap.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.com.alpsenel.wordwidget"
    public static let shared = SharedStore(defaults: UserDefaults(suiteName: appGroupID) ?? .standard)

    private enum Key {
        static let settings = "settings.v1"
        static let deckSeed = "deckSeed.v1"
        static let seen = "seenEntries.v1"        // [entryId: lastSeenTimestamp]
        static let tapCursor = "tapCursor.v1"      // Int
        static let slotAssignments = "slotAssignments.v1" // [String(slot): entryId]
        static let quizHistory = "quizHistory.v1"  // [QuizResult]
    }

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.alpsenel.wordwidget.sharedstore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: Settings

    public var settings: UserSettings {
        get { queue.sync { load(UserSettings.self, Key.settings) ?? .default } }
        set { queue.sync { save(newValue, Key.settings) } }
    }

    // MARK: Deck seed (stable per install; shuffles the pool so users don't all start with the same word)

    public var deckSeed: UInt64 {
        queue.sync {
            if let existing = defaults.object(forKey: Key.deckSeed) as? UInt64 { return existing }
            let seed = UInt64.random(in: 1...UInt64.max)
            defaults.set(seed, forKey: Key.deckSeed)
            return seed
        }
    }

    // MARK: Seen words (fed by widgets, consumed by the quiz)

    public func markSeen(_ entryIDs: [String], at date: Date = Date()) {
        guard !entryIDs.isEmpty else { return }
        queue.sync {
            var seen = load([String: Double].self, Key.seen) ?? [:]
            for id in entryIDs { seen[id] = date.timeIntervalSince1970 }
            save(seen, Key.seen)
        }
    }

    /// Entry ids the user has actually seen as of now (widgets may pre-record future timeline
    /// entries with their scheduled date), ordered by most recently seen first.
    public var seenEntryIDs: [String] { seenEntryIDs(asOf: Date()) }

    public func seenEntryIDs(asOf date: Date) -> [String] {
        let cutoff = date.timeIntervalSince1970
        return queue.sync {
            (load([String: Double].self, Key.seen) ?? [:])
                .filter { $0.value <= cutoff }
                .sorted { $0.value > $1.value }
                .map(\.key)
        }
    }

    public var seenCount: Int { seenEntryIDs.count }

    // MARK: On-tap mode state

    public var tapCursor: Int {
        get { queue.sync { defaults.integer(forKey: Key.tapCursor) } }
        set { queue.sync { defaults.set(newValue, forKey: Key.tapCursor) } }
    }

    public var slotAssignments: [Int: String] {
        get {
            queue.sync {
                let raw = load([String: String].self, Key.slotAssignments) ?? [:]
                return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
            }
        }
        set {
            queue.sync {
                save(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) }), Key.slotAssignments)
            }
        }
    }

    // MARK: Quiz history (local)

    public var quizHistory: [QuizResult] {
        get { queue.sync { load([QuizResult].self, Key.quizHistory) ?? [] } }
        set { queue.sync { save(newValue, Key.quizHistory) } }
    }

    public func appendQuizResult(_ result: QuizResult) {
        queue.sync {
            var h = load([QuizResult].self, Key.quizHistory) ?? []
            h.append(result)
            if h.count > 500 { h.removeFirst(h.count - 500) }
            save(h, Key.quizHistory)
        }
    }

    /// Wipes all shared state (used by tests and "Reset progress").
    public func resetAll() {
        queue.sync {
            [Key.settings, Key.deckSeed, Key.seen, Key.tapCursor, Key.slotAssignments, Key.quizHistory]
                .forEach(defaults.removeObject(forKey:))
        }
    }

    // MARK: Helpers

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }
}

/// Outcome of one quiz session, persisted locally and submitted to the leaderboard.
public struct QuizResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var score: Int
    public var correct: Int
    public var total: Int
    public var targetLanguage: Language

    public init(id: UUID = UUID(), date: Date = Date(), score: Int, correct: Int, total: Int, targetLanguage: Language) {
        self.id = id
        self.date = date
        self.score = score
        self.correct = correct
        self.total = total
        self.targetLanguage = targetLanguage
    }
}
