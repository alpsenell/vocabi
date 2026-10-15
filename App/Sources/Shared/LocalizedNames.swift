import SwiftUI
import VocabCore

// User-visible names for core enums. Keys live in Localizable.xcstrings.

extension Difficulty {
    var localizedName: String {
        switch self {
        case .beginner: return String(localized: "Beginner")
        case .intermediate: return String(localized: "Intermediate")
        case .advanced: return String(localized: "Advanced")
        }
    }

    var symbolName: String {
        switch self {
        case .beginner: return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .advanced: return "3.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

extension VocabCore.Category {
    var localizedName: String {
        switch self {
        case .business: return String(localized: "Business")
        case .school: return String(localized: "School")
        case .dailyLife: return String(localized: "Daily life")
        case .travel: return String(localized: "Travel")
        case .technology: return String(localized: "Technology")
        case .health: return String(localized: "Health")
        case .food: return String(localized: "Food")
        }
    }
}

extension RefreshFrequency {
    var localizedName: String {
        switch self {
        case .hourly: return String(localized: "Every hour")
        case .daily: return String(localized: "Every day")
        case .weekly: return String(localized: "Every week")
        case .onTap: return String(localized: "On tap")
        }
    }

    var localizedDetail: String {
        switch self {
        case .hourly: return String(localized: "A new word every hour.")
        case .daily: return String(localized: "A new word every day.")
        case .weekly: return String(localized: "A new word every week.")
        case .onTap: return String(localized: "Tap the widget to see the next word.")
        }
    }

    var symbolName: String {
        switch self {
        case .hourly: return "clock"
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .onTap: return "hand.tap"
        }
    }
}

extension Language {
    var label: String { "\(flag) \(nativeName)" }
}
