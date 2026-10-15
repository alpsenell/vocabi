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

    public init(nativeLanguage: Language = .turkish,
                targetLanguage: Language = .english,
                frequency: RefreshFrequency = .daily,
                difficulties: Set<Difficulty> = [.beginner, .intermediate],
                categories: Set<Category> = Set(Category.allCases),
                nickname: String = "",
                hasCompletedOnboarding: Bool = false) {
        self.nativeLanguage = nativeLanguage
        self.targetLanguage = targetLanguage
        self.frequency = frequency
        self.difficulties = difficulties
        self.categories = categories
        self.nickname = nickname
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = UserSettings()

    /// Settings are valid only when the two languages differ and at least one difficulty/category is chosen.
    public var isValid: Bool {
        nativeLanguage != targetLanguage && !difficulties.isEmpty && !categories.isEmpty
    }
}

/// Maximum number of simultaneously placed widgets whose words are guaranteed distinct.
public let maxWidgetSlots = 6
