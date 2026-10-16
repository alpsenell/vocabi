import XCTest
@testable import VocabCore

final class PackPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func settings(difficulties: Set<Difficulty> = [.beginner], categories: Set<VocabCore.Category> = [.travel, .food],
                          topics: [String] = []) -> UserSettings {
        UserSettings(nativeLanguage: .turkish, targetLanguage: .english, difficulties: difficulties,
                     categories: categories, customTopics: topics)
    }

    private func pack(for r: PackRequest, age: TimeInterval = 0, terms: [String] = ["a"]) -> WordPack {
        let entries = terms.enumerated().map { i, t in
            VocabEntry(id: "\(r.id)-\(i)", category: r.category, difficulty: r.difficulty,
                       terms: [.english: t, .turkish: t], definitions: [.english: "d", .turkish: "d"], topic: r.topic)
        }
        return WordPack(id: r.id, nativeLanguage: r.native, targetLanguage: r.target, difficulty: r.difficulty,
                        category: r.category, topic: r.topic, entries: entries, createdAt: now.addingTimeInterval(-age), version: 1)
    }

    func testOrderingTopicsFirstThenStandardPage1ThenPage2() {
        let s = settings(difficulties: [.intermediate, .beginner], categories: [.food, .travel], topics: ["Sailing"])
        let ids = PackPlanner(maxRequests: 100).plan(settings: s, stored: [], now: now).map(\.id)
        XCTAssertEqual(ids, [
            "ai-tr-en-beginner-t_sailing-1",
            "ai-tr-en-beginner-travel-1", "ai-tr-en-beginner-food-1",
            "ai-tr-en-intermediate-travel-1", "ai-tr-en-intermediate-food-1",
            "ai-tr-en-beginner-t_sailing-2",
            "ai-tr-en-beginner-travel-2", "ai-tr-en-beginner-food-2",
            "ai-tr-en-intermediate-travel-2", "ai-tr-en-intermediate-food-2",
        ])
    }

    func testCapPerSync() {
        let s = settings(difficulties: Set(Difficulty.allCases), categories: Set(VocabCore.Category.allCases))
        XCTAssertEqual(PackPlanner().candidates(for: s).count, 3 * 7 * 2)
        XCTAssertEqual(PackPlanner().plan(settings: s, stored: [], now: now).count, PackPlanner.maxRequestsPerSync)
        XCTAssertEqual(PackPlanner.maxRequestsPerSync, 6)
    }

    func testSkipsStoredAndAdvances() {
        let s = settings()
        let planner = PackPlanner()
        let first = planner.plan(settings: s, stored: [], now: now)
        XCTAssertEqual(first.map(\.page), [1, 1, 2, 2])
        let stored = first.prefix(2).map { pack(for: $0) }
        let next = planner.plan(settings: s, stored: stored, now: now)
        XCTAssertEqual(next.map(\.id), ["ai-tr-en-beginner-travel-2", "ai-tr-en-beginner-food-2"])
        // Page 2 carries page 1's terms so the server avoids repeats.
        XCTAssertEqual(next.first?.knownTerms, ["a"])
        let all = first.map { pack(for: $0) }
        XCTAssertTrue(planner.plan(settings: s, stored: all, now: now).isEmpty)
    }

    func testStaleStandardPackIsRefetchedButTopicPackIsNot() {
        let s = settings(categories: [.travel], topics: ["cooking"])
        let planner = PackPlanner()
        let old: TimeInterval = 91 * 86_400
        let stored = planner.candidates(for: s).map { pack(for: $0, age: old) }
        let ids = planner.plan(settings: s, stored: stored, now: now).map(\.id)
        XCTAssertEqual(ids, ["ai-tr-en-beginner-travel-1", "ai-tr-en-beginner-travel-2"])
        let fresh = planner.candidates(for: s).map { pack(for: $0, age: 89 * 86_400) }
        XCTAssertTrue(planner.plan(settings: s, stored: fresh, now: now).isEmpty)
    }

    func testCustomTopicsNormalizedDedupedAndCapped() {
        let s = settings(categories: [.travel],
                         topics: ["  Job   Interviews ", "job interviews", "", "a", "b", "c", "d", "e"])
        XCTAssertEqual(PackPlanner.topics(from: s), ["job interviews", "a", "b", "c", "d"])
        let page1Topics = PackPlanner(maxRequests: 100).plan(settings: s, stored: [], now: now)
            .filter { $0.page == 1 && $0.topic != nil }
        XCTAssertEqual(page1Topics.first?.id, "ai-tr-en-beginner-t_job_interviews-1")
        XCTAssertEqual(page1Topics.count, 5)
        XCTAssertTrue(page1Topics.allSatisfy { $0.category == PackPlanner.topicCategory })
    }

    func testTopicUsesLowestSelectedDifficulty() {
        let s = settings(difficulties: [.advanced, .intermediate], categories: [.travel], topics: ["sailing"])
        XCTAssertEqual(PackPlanner().plan(settings: s, stored: [], now: now).first?.difficulty, .intermediate)
    }

    func testOtherLanguagePairPacksDoNotCount() {
        let s = settings(categories: [.travel])
        let otherPair = PackRequest(native: .french, target: .english, difficulty: .beginner, category: .travel, topic: nil, page: 1)
        XCTAssertEqual(PackPlanner().plan(settings: s, stored: [pack(for: otherPair)], now: now).count, 2)
    }

    func testInvalidLanguagePairPlansNothing() {
        var s = settings()
        s.targetLanguage = s.nativeLanguage
        XCTAssertTrue(PackPlanner().plan(settings: s, stored: [], now: now).isEmpty)
    }

    func testLibrarySummary() {
        let r = PackRequest(native: .turkish, target: .english, difficulty: .beginner, category: .travel, topic: nil, page: 1)
        let summary = PackLibrarySummary(packs: [pack(for: r, age: 10, terms: ["a", "b", "c"])])
        XCTAssertEqual(summary.packCount, 1)
        XCTAssertEqual(summary.wordCount, 3)
        XCTAssertEqual(summary.newestPackDate, now.addingTimeInterval(-10))
    }

    /// End-to-end sync loop with a mock client: plan → fetch → store, until nothing is left.
    func testSyncLoopWithMockClient() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PackStore(directory: dir)
        let client = MockPackClient(createdAt: now)
        let s = settings(categories: [.travel, .food, .health], topics: ["sailing"])
        var rounds = 0
        while case let plan = PackPlanner().plan(settings: s, stored: store.allPacks, now: now), !plan.isEmpty {
            for r in plan { try store.save(try await client.fetchPack(r)) }
            rounds += 1
            if rounds > 10 { XCTFail("sync loop does not converge"); break }
        }
        XCTAssertEqual(rounds, 2) // 8 packs at 6 per sync
        XCTAssertEqual(store.allPacks.count, 8)
        let requested = await client.requested
        XCTAssertEqual(Set(requested.map(\.id)).count, 8)
    }
}

actor MockPackClient: PackClient {
    private(set) var requested: [PackRequest] = []
    var failure: PackClientError?
    let createdAt: Date

    init(createdAt: Date = Date()) { self.createdAt = createdAt }

    func setFailure(_ f: PackClientError?) { failure = f }

    func fetchPack(_ request: PackRequest) async throws -> WordPack {
        requested.append(request)
        if let failure { throw failure }
        let entry = VocabEntry(id: "\(request.id)-0", category: request.category, difficulty: request.difficulty,
                               terms: [request.target: "w", request.native: "w"],
                               definitions: [request.target: "d", request.native: "d"], topic: request.topic)
        return WordPack(id: request.id, nativeLanguage: request.native, targetLanguage: request.target,
                        difficulty: request.difficulty, category: request.category, topic: request.topic,
                        entries: [entry], createdAt: createdAt, version: 1)
    }
}
