import Foundation

/// How often a widget moves to a new word.
public enum RefreshFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly, daily, weekly, onTap

    public var id: String { rawValue }

    /// Length of one scheduling bucket in seconds, `nil` for `onTap`.
    public var bucketLength: TimeInterval? {
        switch self {
        case .hourly: return 3600
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        case .onTap: return nil
        }
    }
}

/// Global, user-configurable settings. Persisted as JSON in the App Group via `SharedStore`.
public struct UserSettings: Codable, Equatable, Sendable {
    public var nativeLanguage: Language
    public var targetLanguage: Language
    public var frequency: RefreshFrequency
    public var difficulties: Set<Difficulty>
    public var categories: Set<Category>
    public var nickname: String
    public var hasCompletedOnboarding: Bool
    /// User-typed topics for AI word packs (Pro feature), e.g. ["sailing", "job interviews"]. Max 5.
    public var customTopics: [String]

    public static let maxCustomTopics = 5

    public init(nativeLanguage: Language = .turkish,
                targetLanguage: Language = .english,
                frequency: RefreshFrequency = .daily,
                difficulties: Set<Difficulty> = [.beginner, .intermediate],
                categories: Set<Category> = Set(Category.allCases),
                nickname: String = "",
                hasCompletedOnboarding: Bool = false,
                customTopics: [String] = []) {
        self.nativeLanguage = nativeLanguage
        self.targetLanguage = targetLanguage
        self.frequency = frequency
        self.difficulties = difficulties
        self.categories = categories
        self.nickname = nickname
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.customTopics = customTopics
    }

    // Tolerant decoding so settings saved by older app versions keep working when fields are added.
    private enum CodingKeys: String, CodingKey {
        case nativeLanguage, targetLanguage, frequency, difficulties, categories, nickname, hasCompletedOnboarding, customTopics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings.default
        nativeLanguage = try c.decodeIfPresent(Language.self, forKey: .nativeLanguage) ?? d.nativeLanguage
        targetLanguage = try c.decodeIfPresent(Language.self, forKey: .targetLanguage) ?? d.targetLanguage
        frequency = try c.decodeIfPresent(RefreshFrequency.self, forKey: .frequency) ?? d.frequency
        difficulties = try c.decodeIfPresent(Set<Difficulty>.self, forKey: .difficulties) ?? d.difficulties
        categories = try c.decodeIfPresent(Set<Category>.self, forKey: .categories) ?? d.categories
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? d.nickname
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        customTopics = try c.decodeIfPresent([String].self, forKey: .customTopics) ?? []
    }

    /// Normalized topic key used for pack ids and matching: trimmed, lowercased, single spaces.
    public static func normalizeTopic(_ topic: String) -> String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public static let `default` = UserSettings()

    /// Settings are valid only when the two languages differ and at least one difficulty/category is chosen.
    public var isValid: Bool {
        nativeLanguage != targetLanguage && !difficulties.isEmpty && !categories.isEmpty
    }
}

/// Maximum number of simultaneously placed widgets whose words are guaranteed distinct.
public let maxWidgetSlots = 6
