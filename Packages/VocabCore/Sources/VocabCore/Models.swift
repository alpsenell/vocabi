import Foundation

/// Languages supported at launch. Raw values are ISO 639-1 codes and are used as JSON keys.
public enum Language: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case english = "en"
    case turkish = "tr"
    case french = "fr"
    case spanish = "es"

    public var id: String { rawValue }

    /// Name of the language written in that language (for pickers).
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .french: return "Français"
        case .spanish: return "Español"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .turkish: return "🇹🇷"
        case .french: return "🇫🇷"
        case .spanish: return "🇪🇸"
        }
    }
}

public enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable, Hashable, Comparable {
    case beginner, intermediate, advanced

    public var id: String { rawValue }

    private var order: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced: return 2
        }
    }

    public static func < (lhs: Difficulty, rhs: Difficulty) -> Bool { lhs.order < rhs.order }
}

public enum Category: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case business, school, dailyLife, travel, technology, health, food

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .business: return "briefcase.fill"
        case .school: return "graduationcap.fill"
        case .dailyLife: return "house.fill"
        case .travel: return "airplane"
        case .technology: return "laptopcomputer"
        case .health: return "heart.fill"
        case .food: return "fork.knife"
        }
    }
}

/// One vocabulary concept with its word, definition and example in every supported language.
public struct VocabEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let category: Category
    public let difficulty: Difficulty
    public let terms: [Language: String]
    public let definitions: [Language: String]
    public let examples: [Language: String]?

    public init(id: String, category: Category, difficulty: Difficulty,
                terms: [Language: String], definitions: [Language: String],
                examples: [Language: String]? = nil) {
        self.id = id
        self.category = category
        self.difficulty = difficulty
        self.terms = terms
        self.definitions = definitions
        self.examples = examples
    }

    public func term(in language: Language) -> String { terms[language] ?? terms[.english] ?? id }
    public func definition(in language: Language) -> String { definitions[language] ?? definitions[.english] ?? "" }
    public func example(in language: Language) -> String? { examples?[language] }

    // MARK: Codable with string-keyed dictionaries ("en": "...").

    private enum CodingKeys: String, CodingKey { case id, category, difficulty, terms, definitions, examples }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(Category.self, forKey: .category)
        difficulty = try c.decode(Difficulty.self, forKey: .difficulty)
        terms = Self.languageMap(try c.decode([String: String].self, forKey: .terms))
        definitions = Self.languageMap(try c.decode([String: String].self, forKey: .definitions))
        examples = try c.decodeIfPresent([String: String].self, forKey: .examples).map(Self.languageMap)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(Self.stringMap(terms), forKey: .terms)
        try c.encode(Self.stringMap(definitions), forKey: .definitions)
        try c.encodeIfPresent(examples.map(Self.stringMap), forKey: .examples)
    }

    private static func languageMap(_ raw: [String: String]) -> [Language: String] {
        var out: [Language: String] = [:]
        for (k, v) in raw { if let l = Language(rawValue: k) { out[l] = v } }
        return out
    }

    private static func stringMap(_ m: [Language: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: m.map { ($0.key.rawValue, $0.value) })
    }
}

/// A word as shown in a widget: resolved for the user's language pair.
public struct WordCard: Hashable, Sendable, Identifiable {
    public let entry: VocabEntry
    public let targetLanguage: Language
    public let nativeLanguage: Language

    public init(entry: VocabEntry, targetLanguage: Language, nativeLanguage: Language) {
        self.entry = entry
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
    }

    public var id: String { entry.id }
    public var word: String { entry.term(in: targetLanguage) }
    public var description: String { entry.definition(in: nativeLanguage) }
    public var translation: String { entry.term(in: nativeLanguage) }
    public var example: String? { entry.example(in: targetLanguage) }
}
