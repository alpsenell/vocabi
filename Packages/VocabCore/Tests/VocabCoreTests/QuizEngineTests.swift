import XCTest
@testable import VocabCore

final class QuizEngineTests: XCTestCase {
    private let categories: [VocabCore.Category] = [.business, .travel, .food]

    /// 3 categories × `perCategory` entries with unique texts.
    private func makeEntries(perCategory: Int = 10) -> [VocabEntry] {
        categories.flatMap { cat in
            (0..<perCategory).map { i in
                let id = "\(cat.rawValue)-\(String(format: "%03d", i))"
                return VocabEntry(id: id, category: cat, difficulty: i % 2 == 0 ? .beginner : .advanced,
                                  terms: [.english: "w-\(id)", .turkish: "k-\(id)", .french: "m-\(id)", .spanish: "p-\(id)"],
                                  definitions: [.english: "d-\(id)", .turkish: "t-\(id)", .french: "f-\(id)", .spanish: "s-\(id)"])
            }
        }
    }

    private func makeEngine(_ entries: [VocabEntry]? = nil,
                            settings: UserSettings = UserSettings(nativeLanguage: .turkish, targetLanguage: .french)) -> QuizEngine {
        let all = entries ?? makeEntries()
        return QuizEngine(settings: settings, repository: VocabularyRepository(entries: all))
    }

    func testSessionHasTenQuestionsWithFourUniqueOptions() {
        var rng = SplitMix64(seed: 1)
        let session = makeEngine().makeSession(seenEntryIDs: [], using: &rng)
        XCTAssertEqual(session.questions.count, 10)
        XCTAssertEqual(Set(session.questions.map(\.entry.id)).count, 10, "no repeated entries")
        for q in session.questions {
            XCTAssertEqual(q.options.count, 4)
            XCTAssertEqual(Set(q.options.map(\.text)).count, 4, "duplicate option text")
            XCTAssertEqual(Set(q.options.map(\.entryID)).count, 4)
            XCTAssertEqual(q.correctOption.entryID, q.entry.id)
        }
    }

    func testDeterministicForSameSeed() {
        let engine = makeEngine()
        var a = SplitMix64(seed: 77), b = SplitMix64(seed: 77)
        let s1 = engine.makeSession(seenEntryIDs: ["food-001", "travel-002"], using: &a)
        let s2 = engine.makeSession(seenEntryIDs: ["food-001", "travel-002"], using: &b)
        XCTAssertEqual(s1, s2)
    }

    func testUsesSeenEntriesFirstAndPadsFromPool() {
        let seen = ["food-001", "travel-002", "business-003"]
        var rng = SplitMix64(seed: 5)
        let session = makeEngine().makeSession(seenEntryIDs: seen, using: &rng)
        let ids = Set(session.questions.map(\.entry.id))
        XCTAssertTrue(Set(seen).isSubset(of: ids))
        XCTAssertEqual(session.questions.count, 10)
    }

    func testOnlySeenEntriesWhenEnoughSeen() {
        let seen = (0..<10).map { "travel-\(String(format: "%03d", $0))" } + ["food-000", "food-001"]
        var rng = SplitMix64(seed: 9)
        let session = makeEngine().makeSession(seenEntryIDs: seen, using: &rng)
        XCTAssertEqual(session.questions.count, 10)
        XCTAssertTrue(Set(session.questions.map(\.entry.id)).isSubset(of: Set(seen)))
    }

    func testPaddingRespectsFilteredPool() {
        // Pool = beginner travel only (15 entries ≥ 12 so the repository filter applies).
        let all = makeEntries(perCategory: 30)
        let settings = UserSettings(nativeLanguage: .english, targetLanguage: .spanish,
                                    difficulties: [.beginner], categories: [.travel])
        var rng = SplitMix64(seed: 3)
        let session = makeEngine(all, settings: settings).makeSession(seenEntryIDs: [], using: &rng)
        XCTAssertTrue(session.questions.allSatisfy { $0.entry.category == .travel && $0.entry.difficulty == .beginner })
    }

    func testDistractorsComeFromSameCategory() {
        var rng = SplitMix64(seed: 11)
        let engine = makeEngine()
        let session = engine.makeSession(seenEntryIDs: [], using: &rng)
        let byID = Dictionary(uniqueKeysWithValues: engine.allEntries.map { ($0.id, $0) })
        for q in session.questions {
            for o in q.options { XCTAssertEqual(byID[o.entryID]?.category, q.entry.category) }
        }
    }

    func testFallsBackToOtherCategoriesWhenNeeded() {
        var entries = makeEntries(perCategory: 10)
        entries.append(VocabEntry(id: "health-000", category: .health, difficulty: .beginner,
                                  terms: [.english: "doctor", .french: "médecin", .turkish: "doktor", .spanish: "médico"],
                                  definitions: [.english: "x", .french: "y", .turkish: "z", .spanish: "w"]))
        let engine = makeEngine(entries)
        let health = entries.last!
        var rng = SplitMix64(seed: 2)
        let q = engine.makeQuestion(id: 0, entry: health, style: .definitionToWord, using: &rng)
        XCTAssertEqual(q.options.count, 4)
        XCTAssertEqual(Set(q.options.map(\.text)).count, 4)
    }

    func testDuplicateTextsAreNeverOffered() {
        // Three entries share the same French word as the asked entry.
        var entries = makeEntries()
        for i in 0..<3 {
            entries.append(VocabEntry(id: "food-dup-\(i)", category: .food, difficulty: .beginner,
                                      terms: [.english: "e\(i)", .french: "M-FOOD-000", .turkish: "t\(i)", .spanish: "s\(i)"],
                                      definitions: [.english: "x\(i)", .french: "y\(i)", .turkish: "z\(i)", .spanish: "w\(i)"]))
        }
        let engine = makeEngine(entries)
        let asked = entries.first { $0.id == "food-000" }!
        for seed in 0..<20 as Range<UInt64> {
            var rng = SplitMix64(seed: seed)
            let q = engine.makeQuestion(id: 0, entry: asked, style: .definitionToWord, using: &rng)
            let normalized = q.options.map { QuizEngine.normalized($0.text) }
            XCTAssertEqual(Set(normalized).count, 4)
        }
    }

    func testStylesAreMixedAndResolvedForLanguagePair() {
        var rng = SplitMix64(seed: 4)
        let session = makeEngine().makeSession(seenEntryIDs: [], using: &rng)
        let w2d = session.questions.filter { $0.style == .wordToDefinition }
        let d2w = session.questions.filter { $0.style == .definitionToWord }
        XCTAssertEqual(w2d.count, 5)
        XCTAssertEqual(d2w.count, 5)
        for q in w2d {
            XCTAssertEqual(q.prompt, q.entry.term(in: .french))
            XCTAssertEqual(q.correctOption.text, q.entry.definition(in: .turkish))
        }
        for q in d2w {
            XCTAssertEqual(q.prompt, q.entry.definition(in: .turkish))
            XCTAssertEqual(q.correctOption.text, q.entry.term(in: .french))
        }
    }

    func testFewerEntriesThanQuestionsYieldsShorterSession() {
        let tiny = Array(makeEntries(perCategory: 2))  // 6 entries
        var rng = SplitMix64(seed: 1)
        let session = makeEngine(tiny).makeSession(seenEntryIDs: [], using: &rng)
        XCTAssertEqual(session.questions.count, 6)
        XCTAssertTrue(session.questions.allSatisfy { $0.options.count == 4 })
    }

    // MARK: Scoring

    func testScoring() {
        XCTAssertEqual(QuizScoring.points(isCorrect: true, elapsed: 0), 150)
        XCTAssertEqual(QuizScoring.points(isCorrect: true, elapsed: 5), 125)
        XCTAssertEqual(QuizScoring.points(isCorrect: true, elapsed: 10), 100)
        XCTAssertEqual(QuizScoring.points(isCorrect: true, elapsed: 2.5), 138) // 37.5 rounds to 38
        XCTAssertEqual(QuizScoring.points(isCorrect: false, elapsed: 1), 0)
        XCTAssertEqual(QuizScoring.points(isCorrect: true, elapsed: 10.5), 0)
        XCTAssertEqual(QuizScoring.maxScore(questionCount: 10), 1500)
    }

    func testSessionFlowProducesResult() {
        var rng = SplitMix64(seed: 8)
        var session = makeEngine().makeSession(seenEntryIDs: [], using: &rng)
        for (i, q) in session.questions.enumerated() {
            if i < 7 { session.answer(selectedIndex: q.correctIndex, elapsed: 0) }
            else if i < 9 { session.answer(selectedIndex: (q.correctIndex + 1) % 4, elapsed: 3) }
            else { session.answer(selectedIndex: nil, elapsed: 10) }
        }
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.answer(selectedIndex: 0, elapsed: 1))
        let date = Date(timeIntervalSince1970: 1_000)
        let result = session.makeResult(date: date)
        XCTAssertEqual(result.score, 7 * 150)
        XCTAssertEqual(result.correct, 7)
        XCTAssertEqual(result.total, 10)
        XCTAssertEqual(result.targetLanguage, .french)
        XCTAssertEqual(result.date, date)
    }
}
