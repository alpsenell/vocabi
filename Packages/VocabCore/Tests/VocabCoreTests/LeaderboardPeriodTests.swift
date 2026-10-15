import XCTest
@testable import VocabCore

final class LeaderboardPeriodTests: XCTestCase {
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, m, d, h, min, s)
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testDailyKey() {
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: utc(2026, 10, 15)), "2026-10-15")
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: utc(2026, 1, 5)), "2026-01-05")
    }

    func testMonthlyKey() {
        XCTAssertEqual(LeaderboardPeriod.monthly.key(for: utc(2026, 10, 15)), "2026-10")
        XCTAssertEqual(LeaderboardPeriod.monthly.key(for: utc(2027, 1, 1, 0, 0, 0)), "2027-01")
        XCTAssertEqual(LeaderboardPeriod.monthly.key(for: utc(2026, 12, 31, 23, 59, 59)), "2026-12")
    }

    func testWeeklyKeyMidYear() {
        // 2026-10-15 is a Thursday in ISO week 42.
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2026, 10, 15)), "2026-W42")
    }

    func testWeeklyKeyIsoYearBoundaries() {
        // 2027-01-01 is a Friday → belongs to ISO week 53 of 2026.
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2027, 1, 1)), "2026-W53")
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2027, 1, 3, 23, 59, 59)), "2026-W53") // Sunday
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2027, 1, 4, 0, 0, 0)), "2027-W01")    // Monday
        // 2024-12-30 (Monday) is already ISO week 1 of 2025.
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2024, 12, 30)), "2025-W01")
        // 2021-01-03 (Sunday) still belongs to 2020-W53.
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2021, 1, 3)), "2020-W53")
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2026, 1, 1)), "2026-W01") // Thursday
    }

    func testWeekStartsMondayUTC() {
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2026, 10, 18, 23, 59, 59)), "2026-W42") // Sunday
        XCTAssertEqual(LeaderboardPeriod.weekly.key(for: utc(2026, 10, 19, 0, 0, 0)), "2026-W43")    // Monday
    }

    func testKeysUseUTCNotLocalTime() {
        // 23:30 UTC on Oct 15 is already Oct 16 in Istanbul (+3) — key must stay the UTC day.
        let date = utc(2026, 10, 15, 23, 30)
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Istanbul")!
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: date), "2026-10-15")
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: utc(2026, 10, 16, 1, 0)), "2026-10-16")
        // Month boundary in UTC.
        XCTAssertEqual(LeaderboardPeriod.monthly.key(for: utc(2026, 10, 31, 23, 59, 59)), "2026-10")
        XCTAssertEqual(LeaderboardPeriod.monthly.key(for: utc(2026, 11, 1, 0, 0, 0)), "2026-11")
    }

    func testDailyBoundaryAtMidnightUTC() {
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: utc(2026, 10, 15, 23, 59, 59)), "2026-10-15")
        XCTAssertEqual(LeaderboardPeriod.daily.key(for: utc(2026, 10, 16, 0, 0, 0)), "2026-10-16")
    }
}

// MARK: - Ranking

final class LeaderboardRankingTests: XCTestCase {
    private func row(_ id: String, _ total: Int, _ nick: String? = nil) -> LeaderboardScoreRow {
        LeaderboardScoreRow(playerId: id, nickname: nick ?? "n-\(id)", total: total)
    }

    func testCompetitionRankingWithTies() {
        let e = LeaderboardRanking.entries(top: [row("a", 300), row("b", 500), row("c", 300), row("d", 100)],
                                           currentPlayerId: nil, currentRow: nil, playersAhead: nil)
        XCTAssertEqual(e.map(\.id), ["b", "a", "c", "d"])
        XCTAssertEqual(e.map(\.rank), [1, 2, 2, 4])
        XCTAssertFalse(e.contains { $0.isCurrentUser })
    }

    func testDedupesAndDropsZeroTotals() {
        let e = LeaderboardRanking.entries(top: [row("a", 100), row("a", 250), row("z", 0)],
                                           currentPlayerId: nil, currentRow: nil, playersAhead: nil)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].total, 250)
    }

    func testCurrentUserInsideTopIsHighlightedNotAppended() {
        let me = row("me", 400)
        let e = LeaderboardRanking.entries(top: [row("a", 500), me, row("b", 100)],
                                           currentPlayerId: "me", currentRow: me, playersAhead: 1)
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e.filter(\.isCurrentUser).map(\.id), ["me"])
        XCTAssertEqual(e[1].rank, 2)
    }

    func testFresherOwnRowReplacesStaleTopRow() {
        let e = LeaderboardRanking.entries(top: [row("a", 500), row("me", 100)],
                                           currentPlayerId: "me", currentRow: row("me", 900), playersAhead: 0)
        XCTAssertEqual(e.first?.id, "me")
        XCTAssertEqual(e.first?.rank, 1)
        XCTAssertEqual(e.count, 2)
    }

    func testCurrentUserOutsideTopIsAppendedWithCountedRank() {
        let top = (0..<100).map { row("p\($0)", 10_000 - $0) }
        let e = LeaderboardRanking.entries(top: top, currentPlayerId: "me", currentRow: row("me", 50),
                                           playersAhead: 341)
        XCTAssertEqual(e.count, 101)
        XCTAssertEqual(e.last?.id, "me")
        XCTAssertEqual(e.last?.rank, 342)
        XCTAssertTrue(e.last?.isCurrentUser == true)
        XCTAssertEqual(LeaderboardRanking.rankLabel(e.last!.rank), "342")
    }

    func testTopIsCappedAt100() {
        let top = (0..<150).map { row("p\($0)", 10_000 - $0) }
        let e = LeaderboardRanking.entries(top: top, currentPlayerId: nil, currentRow: nil, playersAhead: nil)
        XCTAssertEqual(e.count, LeaderboardRanking.topLimit)
    }

    func testUncountableRankIsApproximated100Plus() {
        let top = (0..<100).map { row("p\($0)", 10_000 - $0) }
        let e = LeaderboardRanking.entries(top: top, currentPlayerId: "me", currentRow: row("me", 5),
                                           playersAhead: nil)
        let rank = e.last!.rank
        XCTAssertTrue(LeaderboardRanking.isApproximate(rank))
        XCTAssertEqual(LeaderboardRanking.rankLabel(rank), "100+")
    }

    func testCappedCountIsApproximated() {
        let top = (0..<100).map { row("p\($0)", 10_000 - $0) }
        let e = LeaderboardRanking.entries(top: top, currentPlayerId: "me", currentRow: row("me", 5),
                                           playersAhead: LeaderboardRanking.rankCountCap)
        XCTAssertEqual(LeaderboardRanking.rankLabel(e.last!.rank), "1000+")
    }

    func testCountNeverRanksAboveVisiblyHigherPlayers() {
        // Stale count says 0 ahead but 3 visible rows have more points.
        let top = [row("a", 900), row("b", 800), row("c", 700)]
        let e = LeaderboardRanking.entries(top: top, currentPlayerId: "me", currentRow: row("me", 10),
                                           playersAhead: 0)
        // "me" would normally be inside the top here; this checks the safety net when the top list is truncated.
        XCTAssertEqual(e.last?.id, "me")
        XCTAssertEqual(e.last?.rank, 4)
    }

    func testNoOwnRowWhenNotPlayed() {
        let e = LeaderboardRanking.entries(top: [row("a", 10)], currentPlayerId: "me", currentRow: nil,
                                           playersAhead: nil)
        XCTAssertEqual(e.map(\.id), ["a"])
    }

    func testNicknameSanitizing() {
        XCTAssertEqual(LeaderboardRanking.displayNickname("  Alp \n", playerId: "x"), "Alp")
        XCTAssertEqual(LeaderboardRanking.displayNickname("", playerId: "_abcdef1234"), "Player-1234")
        XCTAssertEqual(LeaderboardRanking.displayNickname("a\u{0007}b", playerId: "x"), "ab")
        XCTAssertEqual(LeaderboardRanking.displayNickname(String(repeating: "x", count: 50), playerId: "p").count,
                       LeaderboardRanking.maxNicknameLength)
    }

    func testRecordName() {
        XCTAssertEqual(LeaderboardRanking.recordName(playerId: "_abc", period: .weekly, periodKey: "2026-W42",
                                                     targetLanguage: .french),
                       "_abc|weekly|2026-W42|fr")
    }

    func testSubmittableScores() {
        func r(_ s: Int) -> QuizResult { QuizResult(score: s, correct: 1, total: 10, targetLanguage: .english) }
        XCTAssertFalse(LeaderboardRanking.isSubmittable(r(0)))
        XCTAssertFalse(LeaderboardRanking.isSubmittable(r(-5)))
        XCTAssertTrue(LeaderboardRanking.isSubmittable(r(1500)))
        XCTAssertFalse(LeaderboardRanking.isSubmittable(r(1501)))
    }
}

// MARK: - Offline queue + coordinator with a mock service

private actor MockLeaderboardService: LeaderboardService {
    var submitted: [QuizResult] = []
    var failuresRemaining = 0
    var failure: LeaderboardError = .network
    var fetchCount = 0
    var rows: [LeaderboardEntry] = []

    func setFailures(_ n: Int, _ error: LeaderboardError = .network) { failuresRemaining = n; failure = error }

    func submit(_ result: QuizResult, nickname: String) async throws {
        if failuresRemaining > 0 { failuresRemaining -= 1; throw failure }
        submitted.append(result)
    }

    func fetch(period: LeaderboardPeriod, targetLanguage: Language) async throws -> [LeaderboardEntry] {
        fetchCount += 1
        return rows
    }
}

final class LeaderboardSyncTests: XCTestCase {
    private func makeQueue(now: @escaping @Sendable () -> Date = { Date() }) -> PendingLeaderboardQueue {
        let suite = "test.lb.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return PendingLeaderboardQueue(defaults: d, now: now)
    }

    private func result(_ score: Int, date: Date = Date()) -> QuizResult {
        QuizResult(date: date, score: score, correct: 5, total: 10, targetLanguage: .english)
    }

    func testSuccessfulSubmitLeavesQueueEmpty() async throws {
        let mock = MockLeaderboardService()
        let q = makeQueue()
        let sync = LeaderboardSyncCoordinator(service: mock, queue: q)
        try await sync.submit(result(500), nickname: "alp")
        let sent = await mock.submitted
        XCTAssertEqual(sent.map(\.score), [500])
        XCTAssertEqual(q.count, 0)
    }

    func testFailedSubmitIsQueuedAndRetriedInOrderOnNextSubmit() async throws {
        let mock = MockLeaderboardService()
        let q = makeQueue()
        let sync = LeaderboardSyncCoordinator(service: mock, queue: q)
        await mock.setFailures(1)
        do {
            try await sync.submit(result(100), nickname: "alp")
            XCTFail("expected failure")
        } catch let e as LeaderboardError {
            XCTAssertEqual(e, .network)
        }
        XCTAssertEqual(q.count, 1)

        try await sync.submit(result(200), nickname: "alp")
        let sent = await mock.submitted
        XCTAssertEqual(sent.map(\.score), [100, 200])
        XCTAssertEqual(q.count, 0)
    }

    func testFetchFlushesPendingAndStillReturnsWhenFlushFails() async throws {
        let mock = MockLeaderboardService()
        let q = makeQueue()
        let sync = LeaderboardSyncCoordinator(service: mock, queue: q)
        await mock.setFailures(2, .notSignedIn)
        _ = try? await sync.submit(result(300), nickname: "a")
        _ = try await sync.fetch(period: .daily, targetLanguage: .english) // flush fails again, fetch proceeds
        XCTAssertEqual(q.count, 1)
        _ = try await sync.fetch(period: .weekly, targetLanguage: .english) // flush succeeds
        XCTAssertEqual(q.count, 0)
        let sent = await mock.submitted
        let fetches = await mock.fetchCount
        XCTAssertEqual(sent.map(\.score), [300])
        XCTAssertEqual(fetches, 2)
    }

    func testImplausibleScoresAreIgnored() async throws {
        let mock = MockLeaderboardService()
        let q = makeQueue()
        let sync = LeaderboardSyncCoordinator(service: mock, queue: q)
        try await sync.submit(result(0), nickname: "a")
        try await sync.submit(result(99_999), nickname: "a")
        let sent = await mock.submitted
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(q.count, 0)
    }

    func testQueueDedupesCapsAndExpires() {
        let now = Date()
        let q = makeQueue(now: { now })
        let r = result(10)
        q.enqueue(.init(result: r, nickname: "a"))
        q.enqueue(.init(result: r, nickname: "a"))
        XCTAssertEqual(q.count, 1)

        q.enqueue(.init(result: result(10, date: now.addingTimeInterval(-41 * 86_400)), nickname: "old"))
        XCTAssertEqual(q.count, 1, "results older than maxAge are dropped")

        for _ in 0..<(PendingLeaderboardQueue.maxEntries + 10) { q.enqueue(.init(result: result(1), nickname: "x")) }
        XCTAssertEqual(q.count, PendingLeaderboardQueue.maxEntries)
        XCTAssertNotEqual(q.first?.id, r.id, "oldest entries are dropped first")
    }

    func testQueuePersistsAcrossInstances() {
        let suite = "test.lb.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let r = result(42)
        PendingLeaderboardQueue(defaults: d).enqueue(.init(result: r, nickname: "a"))
        XCTAssertEqual(PendingLeaderboardQueue(defaults: d).first?.result, r)
        XCTAssertNotNil(d.data(forKey: "leaderboard.pendingResults.v1"))
    }
}
