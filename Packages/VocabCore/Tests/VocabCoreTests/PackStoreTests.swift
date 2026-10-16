import XCTest
@testable import VocabCore

final class PackStoreTests: XCTestCase {
    private func entry(_ id: String, topic: String? = nil, category: VocabCore.Category = .travel) -> VocabEntry {
        VocabEntry(id: id, category: category, difficulty: .beginner,
                   terms: [.english: id, .turkish: id, .french: id, .spanish: id],
                   definitions: [.english: "d", .turkish: "d", .french: "d", .spanish: "d"], topic: topic)
    }

    func testSaveLoadRemoveRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PackStore(directory: dir)
        let pack = WordPack(id: WordPack.makeID(native: .turkish, target: .english, difficulty: .beginner,
                                                 category: .travel, topic: "Sailing  Boats", page: 1),
                            nativeLanguage: .turkish, targetLanguage: .english, difficulty: .beginner,
                            category: .travel, topic: "sailing boats", entries: [entry("ai-1", topic: "sailing boats")],
                            createdAt: Date(), version: 1)
        XCTAssertEqual(pack.id, "ai-tr-en-beginner-t_sailing_boats-1")
        try store.save(pack)
        XCTAssertEqual(PackStore(directory: dir).allPacks.map(\.id), [pack.id])
        XCTAssertEqual(store.allEntries().first?.topic, "sailing boats")
        store.remove(id: pack.id)
        XCTAssertTrue(store.allPacks.isEmpty)
    }

    func testPoolIncludesCustomTopicEntriesOnlyWhenSelected() {
        var entries = (0..<20).map { entry("seed-\($0)") }
        entries += (0..<15).map { entry("ai-s-\($0)", topic: "sailing") }
        entries += (0..<15).map { entry("ai-c-\($0)", topic: "cooking") }
        let repo = VocabularyRepository(entries: entries)
        var settings = UserSettings(difficulties: [.beginner], categories: [.travel])
        XCTAssertEqual(repo.pool(for: settings).count, 20)
        settings.customTopics = ["Sailing"]
        XCTAssertEqual(repo.pool(for: settings).count, 35)
    }

    func testOldSettingsWithoutNewFieldsStillDecode() throws {
        let json = #"{"nativeLanguage":"tr","targetLanguage":"en","frequency":"daily","difficulties":["beginner"],"categories":["food"],"nickname":"alp","hasCompletedOnboarding":true}"#
        let s = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.hasCompletedOnboarding)
        XCTAssertEqual(s.customTopics, [])
    }

    func testEntryTopicRoundTripsThroughJSON() throws {
        let e = entry("ai-x", topic: "sailing")
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(VocabEntry.self, from: data).topic, "sailing")
        XCTAssertTrue(e.isAIGenerated)
    }
}

final class PackLanguagePairTests: XCTestCase {
    func testAIEntriesWithoutCurrentPairAreExcluded() {
        func seed(_ i: Int) -> VocabEntry {
            VocabEntry(id: "seed-\(i)", category: .travel, difficulty: .beginner,
                       terms: [.english: "e\(i)", .turkish: "t\(i)", .french: "f\(i)", .spanish: "s\(i)"],
                       definitions: [.english: "d", .turkish: "d", .french: "d", .spanish: "d"])
        }
        // tr→en pack: only has en + tr terms.
        let ai = (0..<15).map { i in
            VocabEntry(id: "ai-tr-en-beginner-travel-1-\(i)", category: .travel, difficulty: .beginner,
                       terms: [.english: "ae\(i)", .turkish: "at\(i)"],
                       definitions: [.english: "d", .turkish: "d"])
        }
        let repo = VocabularyRepository(entries: (0..<20).map(seed) + ai)
        let trEn = UserSettings(nativeLanguage: .turkish, targetLanguage: .english, difficulties: [.beginner], categories: [.travel])
        XCTAssertEqual(repo.pool(for: trEn).count, 35)
        let trFr = UserSettings(nativeLanguage: .turkish, targetLanguage: .french, difficulties: [.beginner], categories: [.travel])
        XCTAssertEqual(repo.pool(for: trFr).count, 20)
    }
}
