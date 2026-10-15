import Foundation

/// `vocabi://word/<entryId>` and `vocabi://quiz`.
enum DeepLink: Equatable {
    case word(String)
    case quiz

    init?(url: URL) {
        guard url.scheme?.lowercased() == "vocabi" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host()?.lowercased() {
        case "word":
            guard let id = parts.first, !id.isEmpty else { return nil }
            self = .word(id)
        case "quiz":
            self = .quiz
        default:
            return nil
        }
    }
}
