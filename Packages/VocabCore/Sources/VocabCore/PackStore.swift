import Foundation

/// A set of AI-generated vocabulary entries for one language pair, level and category/topic.
/// Produced by the Vocabi pack server and cached on device in the App Group container.
public struct WordPack: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let nativeLanguage: Language
    public let targetLanguage: Language
    public let difficulty: Difficulty
    public let category: Category
    /// Normalized custom topic, or `nil` for a standard-category pack.
    public let topic: String?
    public let entries: [VocabEntry]
    public let createdAt: Date
    /// Generator version reported by the server; bump server-side to force clients to refresh.
    public let version: Int

    public init(id: String, nativeLanguage: Language, targetLanguage: Language, difficulty: Difficulty,
                category: Category, topic: String?, entries: [VocabEntry], createdAt: Date, version: Int) {
        self.id = id
        self.nativeLanguage = nativeLanguage
        self.targetLanguage = targetLanguage
        self.difficulty = difficulty
        self.category = category
        self.topic = topic
        self.entries = entries
        self.createdAt = createdAt
        self.version = version
    }

    /// Deterministic pack id shared by client and server: `ai-<native>-<target>-<level>-<category|topic>-<page>`.
    public static func makeID(native: Language, target: Language, difficulty: Difficulty,
                              category: Category, topic: String?, page: Int) -> String {
        let subject = topic.map { "t_" + UserSettings.normalizeTopic($0).replacingOccurrences(of: " ", with: "_") }
            ?? category.rawValue
        return "ai-\(native.rawValue)-\(target.rawValue)-\(difficulty.rawValue)-\(subject)-\(page)"
    }
}

/// Persists downloaded `WordPack`s as JSON files in the App Group container so both the app
/// and the widget extension read the same data. Thread-safe.
public final class PackStore: @unchecked Sendable {
    public static let shared = PackStore()

    private let directory: URL
    private let lock = NSLock()
    private var cache: [WordPack]?
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
                .appendingPathComponent("packs", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("packs", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    public var allPacks: [WordPack] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let packs = urls.filter { $0.pathExtension == "json" }
            .compactMap { url -> WordPack? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(WordPack.self, from: data)
            }
            .sorted { $0.id < $1.id }
        cache = packs
        return packs
    }

    public func allEntries() -> [VocabEntry] { allPacks.flatMap(\.entries) }

    public func pack(id: String) -> WordPack? { allPacks.first { $0.id == id } }

    public func save(_ pack: WordPack) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try encoder.encode(pack)
        try data.write(to: fileURL(for: pack.id), options: .atomic)
        cache = nil
        VocabularyRepository.shared.invalidate()
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        cache = nil
        VocabularyRepository.shared.invalidate()
    }

    /// Removes every pack (used by "Reset progress" and tests).
    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = nil
        VocabularyRepository.shared.invalidate()
    }

    private func fileURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }
}
