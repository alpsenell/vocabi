import Foundation

/// Loads and filters the bundled vocabulary. Entries are cached after first load.
public final class VocabularyRepository: @unchecked Sendable {
    public static let shared = VocabularyRepository()

    private let lock = NSLock()
    private var cache: [VocabEntry]?
    private let loader: () throws -> [VocabEntry]

    public init(loader: @escaping () throws -> [VocabEntry] = VocabularyRepository.loadBundled) {
        self.loader = loader
    }

    public convenience init(entries: [VocabEntry]) {
        self.init(loader: { entries })
    }

    /// All entries, sorted by id for determinism.
    public var allEntries: [VocabEntry] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let loaded = ((try? loader()) ?? []).sorted { $0.id < $1.id }
        cache = loaded
        return loaded
    }

    public func entry(id: String) -> VocabEntry? { allEntries.first { $0.id == id } }

    /// Entries matching the user's difficulty and category selection. Falls back to the whole
    /// pool if the filter would leave fewer than `2 * maxWidgetSlots` entries.
    public func pool(for settings: UserSettings) -> [VocabEntry] {
        let filtered = allEntries.filter {
            settings.difficulties.contains($0.difficulty) && settings.categories.contains($0.category)
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
