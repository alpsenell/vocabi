import XCTest
@testable import VocabCore

final class WordSchedulerTests: XCTestCase {
    private func makeEntries(_ n: Int) -> [VocabEntry] {
        (0..<n).map { i in
            VocabEntry(id: String(format: "t-%04d", i), category: .dailyLife, difficulty: .beginner,
                       terms: [.english: "w\(i)", .turkish: "k\(i)", .french: "m\(i)", .spanish: "p\(i)"],
                       definitions: [.english: "d\(i)", .turkish: "t\(i)", .french: "f\(i)", .spanish: "s\(i)"])
        }
    }

    private func makeStore() -> SharedStore {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return SharedStore(defaults: d)
    }

    func testTimedSlotsAreDistinctInEveryBucket() {
        for n in [6, 7, 13, 50, 101] {
            let s = WordScheduler(settings: UserSettings(frequency: .daily), pool: makeEntries(n), seed: 42)
            for b in 0..<(n * 2) {
                let ids = (0..<maxWidgetSlots).compactMap { s.entry(slot: $0, bucket: b)?.id }
                XCTAssertEqual(Set(ids).count, maxWidgetSlots, "collision in bucket \(b) for n=\(n)")
            }
        }
    }

    func testEverySlotWalksTheWholeDeck() {
        let s = WordScheduler(settings: UserSettings(frequency: .hourly), pool: makeEntries(30), seed: 7)
        let seen = Set((0..<s.deck.count).compactMap { s.entry(slot: 3, bucket: $0)?.id })
        XCTAssertEqual(seen.count, s.deck.count)
    }

    func testDeterministicForSeed() {
        let a = WordScheduler(settings: .default, pool: makeEntries(40), seed: 99)
        let b = WordScheduler(settings: .default, pool: makeEntries(40), seed: 99)
        XCTAssertEqual(a.deck.map(\.id), b.deck.map(\.id))
    }

    func testOnTapAdvanceNeverCollidesWithOtherSlots() {
        let store = makeStore()
        let s = WordScheduler(settings: UserSettings(frequency: .onTap), pool: makeEntries(7), seed: 1)
        for _ in 0..<3 { for k in 0..<maxWidgetSlots { _ = s.currentTapEntry(slot: k, store: store) } }
        for _ in 0..<50 {
            let slot = Int.random(in: 0..<maxWidgetSlots)
            let before = store.slotAssignments[slot]
            let next = s.advance(slot: slot, store: store)
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next?.id, before)
            let ids = Array(store.slotAssignments.values)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate assignment after tap")
        }
    }

    func testTimelineStartsAtRequestedDateThenBucketBoundaries() {
        let s = WordScheduler(settings: UserSettings(frequency: .hourly), pool: makeEntries(12), seed: 3)
        let from = Date(timeIntervalSince1970: 3600 * 10 + 100)
        let tl = s.timeline(slot: 0, from: from, count: 3)
        XCTAssertEqual(tl.count, 3)
        XCTAssertEqual(tl[0].date, from)
        XCTAssertEqual(tl[1].date, Date(timeIntervalSince1970: 3600 * 11))
        XCTAssertEqual(tl[2].date, Date(timeIntervalSince1970: 3600 * 12))
    }

    func testBundledVocabularyDecodes() {
        let repo = VocabularyRepository()
        XCTAssertFalse(repo.allEntries.isEmpty)
        for e in repo.allEntries {
            for l in Language.allCases {
                XCTAssertNotNil(e.terms[l], "\(e.id) missing term \(l)")
                XCTAssertNotNil(e.definitions[l], "\(e.id) missing definition \(l)")
            }
        }
    }
}

final class SharedStoreSeenTests: XCTestCase {
    func testFutureSeenEntriesAreHiddenUntilTheirDate() {
        let suite = "test.\(UUID().uuidString)"
        let store = SharedStore(defaults: UserDefaults(suiteName: suite)!)
        let now = Date()
        store.markSeen(["past"], at: now.addingTimeInterval(-10))
        store.markSeen(["future"], at: now.addingTimeInterval(3600))
        XCTAssertEqual(store.seenEntryIDs(asOf: now), ["past"])
        XCTAssertEqual(store.seenCount, 1)
        XCTAssertEqual(Set(store.seenEntryIDs(asOf: now.addingTimeInterval(7200))), ["past", "future"])
    }
}
