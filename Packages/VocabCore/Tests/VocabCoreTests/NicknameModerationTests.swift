import XCTest
@testable import VocabCore

final class NicknameModerationTests: XCTestCase {
    private func assertBlocked(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        for name in names {
            XCTAssertFalse(NicknameModeration.isAllowed(name), "\"\(name)\" should be blocked", file: file, line: line)
        }
    }

    private func assertAllowed(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        for name in names {
            XCTAssertTrue(NicknameModeration.isAllowed(name), "\"\(name)\" should be allowed", file: file, line: line)
        }
    }

    func testListLoadsFromBundle() {
        XCTAssertGreaterThan(NicknameModeration.terms.wholeWord.count, 200)
        XCTAssertTrue(NicknameModeration.terms.wholeWord.contains("cono"), "terms are normalized (coño)")
        XCTAssertFalse(NicknameModeration.terms.substring.contains("nique"), "=terms are whole-word only")
        XCTAssertTrue(NicknameModeration.terms.substring.contains("fuck"), "term* forces substring matching")
    }

    func testBlocksEnglish() {
        assertBlocked(["fuck", "FuckYou", "shit", "Big Ass", "bitch_queen", "asshole", "cunt", "nigger",
                       "faggot", "whore", "motherfucker", "pussycat", "Hitler fan"])
    }

    func testBlocksTurkish() {
        assertBlocked(["orospu", "Orospu Çocuğu", "siktir", "sik", "amk", "yarrak", "ibne", "piç",
                       "Amına Koyayım", "pezevenk", "yavşak", "OROSPU"])
    }

    func testBlocksFrench() {
        assertBlocked(["merde", "Putain", "connard", "salope", "enculé", "Fils de pute", "nique ta mère",
                       "bâtard", "pute"])
    }

    func testBlocksSpanish() {
        assertBlocked(["puta", "mierda", "Cabrón", "pendejo", "gilipollas", "coño", "hijo de puta",
                       "maricón", "chingada", "verga"])
    }

    func testBlocksLeetspeakAndDiacriticEvasions() {
        assertBlocked(["fuck3r", "4ss", "sh1t", "5h1t", "b1tch", "@ss", "a$$", "pu7a", "m3rd3", "0r0spu",
                       "s1kt1r", "c0ño", "putaín", "ŞİKTİR", "SİKTİR", "p3n1s", "b00bs"])
    }

    func testBlocksSeparatorAndRepetitionEvasions() {
        assertBlocked(["f.u.c.k", "f u c k", "f_u_c_k", "fuuuuck", "shiiiit", "a s s", "assss",
                       "pen island", "xX_penis_Xx", "puta-puta", "-=bitch=-", "fuckface99"])
    }

    func testAllowsOrdinaryNames() {
        assertAllowed(["Cassandra", "Scunthorpe", "Alp", "Ayşe", "Matthias", "Assunta", "Dick", "Dickens",
                       "Dominique", "Monique", "Maricarmen", "Amina", "Vergara", "Negrete", "Işık", "Hancock",
                       "Arsenal", "Analía", "Sussex", "Penelope", "Classic", "Bass", "Kumar", "Cockburn",
                       "Niger", "Nigeria", "Pollack", "Sikander", "Computas", "Grape", "Therapist",
                       "Shiitake", "Bitte", "Göktuğ", "Çağla", "Şükrü", "İsmail", "Ömer", "José", "Ñandú",
                       "François", "Hélène", "Zoë", "Chiara", "Mehmet", "Fanny", "Willy", "Raccoon",
                       "Assassin", "Puss in Boots",
                       "Kike", "Assess", "Molasses", "Alp1990", "Ayşe_92", "Mr. Bean", "Van Dyke", "Technique", "Pinchera", "Bitcoin"])
    }

    func testEmptyAndSymbolsOnlyAreAllowed() {
        assertAllowed(["", "   ", "!!!", "😀😀😀"])
    }

    func testNormalization() {
        XCTAssertEqual(NicknameModeration.words(in: "Ayşe Iğdır"), ["ayse", "igdir"])
        XCTAssertEqual(NicknameModeration.words(in: "İSMAİL ılık"), ["ismail", "ilik"])
        XCTAssertEqual(NicknameModeration.words(in: "Ñoño Éclair"), ["nono", "eclair"])
        XCTAssertEqual(NicknameModeration.words(in: "h3ll0 w0rld"), ["hello", "world"])
        XCTAssertEqual(NicknameModeration.words(in: "@$5"), ["ass"])
        XCTAssertEqual(NicknameModeration.words(in: "x f u c k x"), ["xfuckx"])
        XCTAssertEqual(NicknameModeration.words(in: "Alp_92"), ["alp"])
        XCTAssertEqual(NicknameModeration.squeezed("fuuuck"), "fuck")
        XCTAssertEqual(NicknameModeration.limitingRuns("assssss"), "ass")
    }

    func testParseMarkers() {
        let list = NicknameModeration.parse("""
        # comment
        ass
        =nique
        fuck*
        orospu

        Coño
        """)
        XCTAssertEqual(list.wholeWord, ["ass", "nique", "fuck", "orospu", "cono"])
        XCTAssertEqual(list.substring, ["fuck", "orospu"])
        XCTAssertTrue(NicknameModeration.isAllowed("Cassandra", terms: list))
        XCTAssertTrue(NicknameModeration.isAllowed("Monique", terms: list))
        XCTAssertFalse(NicknameModeration.isAllowed("nique", terms: list))
        XCTAssertFalse(NicknameModeration.isAllowed("superfuckhero", terms: list))
    }

    // MARK: Display

    func testDisplayNicknameReplacesBlockedNames() {
        XCTAssertEqual(LeaderboardRanking.displayNickname("fuck you", playerId: "_abcdef1234"), "Player-1234")
        XCTAssertEqual(LeaderboardRanking.displayNickname("  0r0spu ", playerId: "_abcdef1234"), "Player-1234")
        XCTAssertEqual(LeaderboardRanking.displayNickname("Cassandra", playerId: "_abcdef1234"), "Cassandra")
    }

    func testRankedEntriesNeverShowBlockedNames() {
        let entries = LeaderboardRanking.entries(
            top: [LeaderboardScoreRow(playerId: "p1", nickname: "Ayşe", total: 300),
                  LeaderboardScoreRow(playerId: "_xyz9876", nickname: "sh1t head", total: 200)],
            currentPlayerId: "p1", currentRow: nil, playersAhead: nil)
        XCTAssertEqual(entries.map(\.nickname), ["Ayşe", "Player-9876"])
    }
}

final class NicknameReportTests: XCTestCase {
    private actor MockReportService: NicknameReportService {
        var reports: [(String, String)] = []
        var error: Error?

        init(error: Error? = nil) { self.error = error }

        func reportNickname(recordName: String, nickname: String) async throws {
            if let error { throw error }
            reports.append((recordName, nickname))
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "test.reports.\(UUID().uuidString)"))
    }

    private func entry(_ id: String, me: Bool = false) -> LeaderboardEntry {
        LeaderboardEntry(id: id, nickname: id, total: 100, rank: 1, isCurrentUser: me)
    }

    func testReportSendsAndHidesPlayer() async throws {
        let defaults = try makeDefaults()
        let service = MockReportService()
        let store = ReportedNicknameStore(defaults: defaults)
        let reporter = NicknameReporter(service: service, store: store)

        let outcome = await reporter.report(recordName: "p2|weekly|2026-W42|en", nickname: "Rude")
        XCTAssertEqual(outcome, .sent)
        let reports = await service.reports
        XCTAssertEqual(reports.map(\.0), ["p2|weekly|2026-W42|en"])
        XCTAssertEqual(reports.map(\.1), ["Rude"])
        XCTAssertEqual(defaults.stringArray(forKey: "leaderboard.reportedRecords.v1"), ["p2|weekly|2026-W42|en"])

        // Hidden in every period, persisted across instances; own row never hidden.
        let fresh = ReportedNicknameStore(defaults: defaults)
        XCTAssertEqual(fresh.filter([entry("p1", me: true), entry("p2"), entry("p3")]).map(\.id), ["p1", "p3"])
    }

    func testNotSignedInStillHidesLocally() async throws {
        let defaults = try makeDefaults()
        let store = ReportedNicknameStore(defaults: defaults)
        let reporter = NicknameReporter(service: MockReportService(error: LeaderboardError.notSignedIn), store: store)

        let outcome = await reporter.report(recordName: "p2|daily|2026-10-16|tr", nickname: "x")
        XCTAssertEqual(outcome, .hiddenOnly(.notSignedIn))
        XCTAssertEqual(reporter.filter([entry("p2"), entry("p3")]).map(\.id), ["p3"])
    }

    func testOtherErrorsAreWrapped() async throws {
        struct Boom: Error {}
        let reporter = NicknameReporter(service: MockReportService(error: Boom()),
                                        store: ReportedNicknameStore(defaults: try makeDefaults()))
        let outcome = await reporter.report(recordName: "p9|monthly|2026-10|fr", nickname: "x")
        guard case .hiddenOnly(.unknown) = outcome else { return XCTFail("unexpected \(outcome)") }
    }

    func testStoreDedupesAndCaps() throws {
        let store = ReportedNicknameStore(defaults: try makeDefaults())
        store.add("a|daily|k|en")
        store.add("a|daily|k|en")
        XCTAssertEqual(store.recordNames, ["a|daily|k|en"])
        for i in 0..<(ReportedNicknameStore.limit + 5) { store.add("p\(i)|daily|k|en") }
        XCTAssertEqual(store.recordNames.count, ReportedNicknameStore.limit)
        XCTAssertFalse(store.recordNames.contains("a|daily|k|en"))
    }

    func testRecordNameForEntry() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 10, 15, 12)
        c.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(NicknameReporter.recordName(for: entry("_abc"), period: .weekly, date: date, targetLanguage: .english),
                       "_abc|weekly|2026-W42|en")
    }
}
