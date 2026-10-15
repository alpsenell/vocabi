import Foundation

enum Nickname {
    static let lengthRange = 3...20

    static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ raw: String) -> Bool {
        lengthRange.contains(clean(raw).count)
    }
}
