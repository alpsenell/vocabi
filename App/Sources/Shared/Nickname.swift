import Foundation
import VocabCore

enum Nickname {
    static let lengthRange = 3...20

    enum Problem: Equatable {
        case length
        case blocked
    }

    static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first rule `raw` breaks, or nil when it can be saved.
    static func problem(_ raw: String) -> Problem? {
        let cleaned = clean(raw)
        if !lengthRange.contains(cleaned.count) { return .length }
        if !NicknameModeration.isAllowed(cleaned) { return .blocked }
        return nil
    }

    static func isValid(_ raw: String) -> Bool {
        problem(raw) == nil
    }
}
