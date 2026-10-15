import Foundation

/// Ranking windows shown in the app. Keys are computed in UTC so all players share the same window.
public enum LeaderboardPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly

    public var id: String { rawValue }

    /// Stable key for the window containing `date`, e.g. "2026-10-15", "2026-W42", "2026-10".
    public func key(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .weekOfYear, .yearForWeekOfYear], from: date)
        switch self {
        case .daily: return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .weekly: return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        case .monthly: return String(format: "%04d-%02d", c.year!, c.month!)
        }
    }
}

/// One row of a leaderboard.
public struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    public let id: String        // player id
    public let nickname: String
    public let total: Int
    public let rank: Int
    public let isCurrentUser: Bool

    public init(id: String, nickname: String, total: Int, rank: Int, isCurrentUser: Bool) {
        self.id = id
        self.nickname = nickname
        self.total = total
        self.rank = rank
        self.isCurrentUser = isCurrentUser
    }
}

public enum LeaderboardError: Error, Sendable, Equatable {
    case notSignedIn
    case network
    case unknown(String)
}

/// Abstraction over the ranking backend. Implemented with CloudKit in the app target.
public protocol LeaderboardService: Sendable {
    /// Adds `result.score` to the player's totals for all three periods.
    func submit(_ result: QuizResult, nickname: String) async throws
    /// Top players for the period containing now (max 100) plus the current user's row if outside the top.
    func fetch(period: LeaderboardPeriod, targetLanguage: Language) async throws -> [LeaderboardEntry]
}
