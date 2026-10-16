import Foundation

/// Pure planning logic: which packs to request next for the user's settings, given what is
/// already on device.
///
/// Order (highest priority first):
/// 1. page 1 of every custom topic (in the order the user added them),
/// 2. page 1 of every selected difficulty × selected category (difficulty ascending, category in
///    `Category.allCases` order),
/// 3. page 2 of every custom topic, then page 2 of every standard pack in the same order.
///
/// Packs already stored are skipped unless they are stale (standard packs older than
/// `staleAfter`; custom-topic packs never go stale since they are the expensive ones).
/// At most `maxRequestsPerSync` requests are returned.
public struct PackPlanner: Sendable {
    public static let maxRequestsPerSync = 6
    public static let pagesPerSubject = 2
    public static let staleAfter: TimeInterval = 90 * 86_400
    /// Category sent for custom-topic packs (the server keys topic packs by topic, not category).
    public static let topicCategory: Category = .dailyLife

    public var maxRequests: Int
    public var staleAfter: TimeInterval

    public init(maxRequests: Int = PackPlanner.maxRequestsPerSync, staleAfter: TimeInterval = PackPlanner.staleAfter) {
        self.maxRequests = maxRequests
        self.staleAfter = staleAfter
    }

    /// Every pack the settings call for, in priority order, ignoring what is stored.
    public func candidates(for settings: UserSettings) -> [PackRequest] {
        let native = settings.nativeLanguage, target = settings.targetLanguage
        guard native != target else { return [] }
        let topics = Self.topics(from: settings)
        let topicDifficulty = settings.difficulties.min() ?? .beginner
        let difficulties = settings.difficulties.sorted()
        let categories = Category.allCases.filter(settings.categories.contains)

        var out: [PackRequest] = []
        for page in 1...Self.pagesPerSubject {
            for topic in topics {
                out.append(PackRequest(native: native, target: target, difficulty: topicDifficulty,
                                       category: Self.topicCategory, topic: topic, page: page))
            }
            for d in difficulties {
                for c in categories {
                    out.append(PackRequest(native: native, target: target, difficulty: d, category: c, topic: nil, page: page))
                }
            }
        }
        return out
    }

    /// The next requests to send, after skipping fresh stored packs and applying the cap.
    /// `knownTerms` is filled with target-language terms from stored packs of the same subject.
    public func plan(settings: UserSettings, stored: [WordPack], now: Date = Date()) -> [PackRequest] {
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.createdAt >= b.createdAt ? a : b })
        var out: [PackRequest] = []
        for var request in candidates(for: settings) {
            guard out.count < maxRequests else { break }
            if let existing = byID[request.id], !isStale(existing, now: now) { continue }
            let known = stored
                .filter { Self.sameSubject($0, request) && $0.id != request.id }
                .flatMap { $0.entries.map { $0.term(in: request.target) } }
            request.knownTerms = known.isEmpty ? nil : Array(Set(known)).sorted()
            out.append(request)
        }
        return out
    }

    public func isStale(_ pack: WordPack, now: Date) -> Bool {
        guard pack.topic == nil else { return false }
        return now.timeIntervalSince(pack.createdAt) > staleAfter
    }

    /// Normalized, de-duplicated, non-empty topics, capped at `UserSettings.maxCustomTopics`.
    public static func topics(from settings: UserSettings) -> [String] {
        var seen = Set<String>()
        return settings.customTopics
            .map(UserSettings.normalizeTopic)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(UserSettings.maxCustomTopics)
            .map { $0 }
    }

    private static func sameSubject(_ pack: WordPack, _ r: PackRequest) -> Bool {
        guard pack.nativeLanguage == r.native, pack.targetLanguage == r.target else { return false }
        if let topic = r.topic { return pack.topic.map(UserSettings.normalizeTopic) == topic }
        return pack.topic == nil && pack.difficulty == r.difficulty && pack.category == r.category
    }
}

/// Summary for the Settings "AI word packs" row.
public struct PackLibrarySummary: Equatable, Sendable {
    public let packCount: Int
    public let wordCount: Int
    public let newestPackDate: Date?

    public init(packs: [WordPack]) {
        packCount = packs.count
        wordCount = Set(packs.flatMap { $0.entries.map(\.id) }).count
        newestPackDate = packs.map(\.createdAt).max()
    }
}
