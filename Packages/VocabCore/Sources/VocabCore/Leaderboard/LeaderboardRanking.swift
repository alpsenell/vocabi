import Foundation

/// A raw per-player total as stored by the backend, before ranks are assigned.
public struct LeaderboardScoreRow: Hashable, Sendable {
    public let playerId: String
    public let nickname: String
    public let total: Int

    public init(playerId: String, nickname: String, total: Int) {
        self.playerId = playerId
        self.nickname = nickname
        self.total = total
    }
}

/// Pure ranking / merging rules shared by every `LeaderboardService` implementation.
public enum LeaderboardRanking {
    /// Number of rows fetched for the visible top list.
    public static let topLimit = 100
    /// Counting players ahead of the current user stops here; beyond it the rank is shown as "1000+".
    public static let rankCountCap = 1000
    /// Highest score a single quiz can produce (10 questions × (100 + 50 speed bonus)).
    public static let maxScorePerQuiz = 1500
    /// Nicknames are trimmed to this many characters.
    public static let maxNicknameLength = 20

    // MARK: Approximate ranks

    /// Ranks are `Int` in `LeaderboardEntry`; an approximate rank ("at least N") is encoded as `-N`.
    public static func approximateRank(atLeast lowerBound: Int) -> Int { -max(1, lowerBound) }

    public static func isApproximate(_ rank: Int) -> Bool { rank < 0 }

    /// "7", or "100+" for an approximate rank.
    public static func rankLabel(_ rank: Int) -> String {
        rank < 0 ? "\(-rank - 1)+" : "\(rank)"
    }

    // MARK: Merging

    /// Builds the displayed leaderboard.
    ///
    /// - Parameters:
    ///   - top: rows returned by the top query (any order, may contain duplicates).
    ///   - currentPlayerId: the signed-in player, if known.
    ///   - currentRow: the player's own row for the period (nil if they have not played yet).
    ///   - playersAhead: number of players with a strictly higher total than `currentRow`,
    ///     or nil when it could not be counted. Values ≥ `rankCountCap` are treated as capped.
    /// - Returns: up to `topLimit` ranked rows (competition ranking: 1, 2, 2, 4) plus, when the current
    ///   player is not among them, their own row appended at the end.
    public static func entries(top: [LeaderboardScoreRow],
                               currentPlayerId: String?,
                               currentRow: LeaderboardScoreRow?,
                               playersAhead: Int?) -> [LeaderboardEntry] {
        // Dedupe by player (keep the highest total), fold in the fresher own row.
        var best: [String: LeaderboardScoreRow] = [:]
        for row in top where row.total > 0 {
            if let existing = best[row.playerId], existing.total >= row.total { continue }
            best[row.playerId] = row
        }
        if let me = currentRow, let existing = best[me.playerId], me.total > existing.total {
            best[me.playerId] = me
        }

        let sorted = best.values.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            let n = $0.nickname.localizedCaseInsensitiveCompare($1.nickname)
            if n != .orderedSame { return n == .orderedAscending }
            return $0.playerId < $1.playerId
        }.prefix(topLimit)

        var result: [LeaderboardEntry] = []
        result.reserveCapacity(sorted.count + 1)
        var rank = 0
        var previousTotal: Int?
        for (index, row) in sorted.enumerated() {
            if row.total != previousTotal { rank = index + 1; previousTotal = row.total }
            result.append(LeaderboardEntry(id: row.playerId,
                                           nickname: displayNickname(row.nickname, playerId: row.playerId),
                                           total: row.total,
                                           rank: rank,
                                           isCurrentUser: row.playerId == currentPlayerId))
        }

        guard let me = currentRow, me.total > 0, me.playerId == currentPlayerId,
              !result.contains(where: { $0.id == me.playerId }) else { return result }

        // Everyone in the visible list with a higher total is definitely ahead.
        let visiblyAhead = result.filter { $0.total > me.total }.count
        let myRank: Int
        if let ahead = playersAhead {
            myRank = ahead >= rankCountCap
                ? approximateRank(atLeast: rankCountCap + 1)
                : max(ahead, visiblyAhead) + 1
        } else {
            // Outside the top list and we could not count: "100+".
            myRank = approximateRank(atLeast: max(result.count, topLimit) + 1)
        }
        result.append(LeaderboardEntry(id: me.playerId,
                                       nickname: displayNickname(me.nickname, playerId: me.playerId),
                                       total: me.total,
                                       rank: myRank,
                                       isCurrentUser: true))
        return result
    }

    // MARK: Nicknames

    /// Trims whitespace/newlines, collapses control characters and limits length.
    /// Falls back to "Player-XXXX" derived from the player id when empty or blocked by
    /// `NicknameModeration` (so old or tampered records never show profanity).
    public static func displayNickname(_ raw: String, playerId: String) -> String {
        let cleaned = raw
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || !NicknameModeration.isAllowed(cleaned) { return fallbackNickname(playerId: playerId) }
        let trimmed = String(cleaned.prefix(maxNicknameLength))
        return NicknameModeration.isAllowed(trimmed) ? trimmed : fallbackNickname(playerId: playerId)
    }

    public static func fallbackNickname(playerId: String) -> String {
        let alnum = playerId.filter { $0.isLetter || $0.isNumber }
        let suffix = alnum.suffix(4).uppercased()
        return suffix.isEmpty ? "Player" : "Player-\(suffix)"
    }

    // MARK: Record naming

    /// Deterministic record name: "<playerId>|<period>|<periodKey>|<targetLanguage>".
    public static func recordName(playerId: String, period: LeaderboardPeriod, periodKey: String,
                                  targetLanguage: Language) -> String {
        "\(playerId)|\(period.rawValue)|\(periodKey)|\(targetLanguage.rawValue)"
    }

    /// Whether a quiz result is plausible enough to submit.
    public static func isSubmittable(_ result: QuizResult) -> Bool {
        result.score > 0 && result.score <= maxScorePerQuiz
    }
}
