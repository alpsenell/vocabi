import Foundation

/// Loads and filters the vocabulary: the bundled seed merged with any downloaded AI word packs
/// (`PackStore`). Entries are cached after first load; call `invalidate()` after packs change.
public final class VocabularyRepository: @unchecked Sendable {
    public static let shared = VocabularyRepository(loader: {
        try VocabularyRepository.loadBundled() + PackStore.shared.allEntries()
    })

    private let lock = NSLock()
    private var cache: [VocabEntry]?
    private let loader: () throws -> [VocabEntry]

    public init(loader: @escaping () throws -> [VocabEntry] = VocabularyRepository.loadBundled) {
        self.loader = loader
    }

    /// Drops the cache so the next read re-merges the seed with the current packs.
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cache = nil
    }

    public convenience init(entries: [VocabEntry]) {
        self.init(loader: { entries })
    }

    /// All entries, sorted by id for determinism.
    public var allEntries: [VocabEntry] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        var seen = Set<String>()
        let loaded = ((try? loader()) ?? [])
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
        cache = loaded
        return loaded
    }

    public func entry(id: String) -> VocabEntry? { allEntries.first { $0.id == id } }

    /// Entries matching the user's difficulty selection and either a selected category (entries
    /// without a topic) or one of the user's custom topics. Falls back to the whole pool if the
    /// filter would leave fewer than `2 * maxWidgetSlots` entries.
    public func pool(for settings: UserSettings) -> [VocabEntry] {
        let topics = Set(settings.customTopics.map(UserSettings.normalizeTopic))
        let filtered = allEntries.filter { e in
            guard settings.difficulties.contains(e.difficulty) else { return false }
            // AI packs are generated per language pair; never show one that lacks the current pair.
            if e.isAIGenerated,
               e.terms[settings.targetLanguage] == nil || e.terms[settings.nativeLanguage] == nil {
                return false
            }
            if let topic = e.topic { return topics.contains(UserSettings.normalizeTopic(topic)) }
            return settings.categories.contains(e.category)
        }
        return filtered.count >= 2 * maxWidgetSlots ? filtered : allEntries
    }

    public static func loadBundled() throws -> [VocabEntry] {
        guard let url = Bundle.module.url(forResource: "vocabulary", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([VocabEntry].self, from: Data(contentsOf: url))
    }
}
