import Foundation

/// Decides which word each widget slot shows at a given time.
///
/// Guarantees: for a fixed settings/pool, the words shown by different slots at the same instant
/// are always distinct, and every slot walks the whole deck over time.
///
/// * Timed modes (`hourly`/`daily`/`weekly`): deck = pool shuffled by the per-install seed and
///   truncated to a multiple of `maxWidgetSlots`. At bucket `b`, slot `k` (0-based) shows
///   `deck[(b + k * stride) mod deck.count]` with `stride = deck.count / maxWidgetSlots`.
///   Slots are offset by a constant, so they never collide for the same `b`.
/// * `onTap` mode: assignments live in `SharedStore.slotAssignments`; `advance(slot:)` walks a
///   shared cursor through the deck, skipping any entry currently shown by another slot.
public struct WordScheduler: Sendable {
    public let settings: UserSettings
    public let deck: [VocabEntry]

    public init(settings: UserSettings, pool: [VocabEntry], seed: UInt64) {
        self.settings = settings
        var rng = SplitMix64(seed: seed)
        var shuffled = pool
        shuffled.shuffle(using: &rng)
        if settings.frequency == .onTap {
            // On-tap mode walks the deck with a cursor; no truncation needed.
            self.deck = shuffled
        } else {
            // Timed modes rely on deck.count being a multiple of maxWidgetSlots for the stride proof.
            let usable = shuffled.count - (shuffled.count % maxWidgetSlots)
            self.deck = Array(shuffled.prefix(max(usable, 0)))
        }
    }

    public var stride: Int { max(deck.count / maxWidgetSlots, 1) }

    // MARK: Timed modes

    /// Index of the bucket that contains `date` for the current frequency (0 for `onTap`).
    public func bucketIndex(at date: Date) -> Int {
        guard let length = settings.frequency.bucketLength else { return 0 }
        return Int((date.timeIntervalSince1970 / length).rounded(.down))
    }

    /// Start date of bucket `index`.
    public func bucketStart(_ index: Int) -> Date {
        let length = settings.frequency.bucketLength ?? 0
        return Date(timeIntervalSince1970: Double(index) * length)
    }

    /// Entry for `slot` (0-based) in bucket `bucket`. `nil` only if the deck is empty.
    public func entry(slot: Int, bucket: Int) -> VocabEntry? {
        guard !deck.isEmpty else { return nil }
        let k = ((slot % maxWidgetSlots) + maxWidgetSlots) % maxWidgetSlots
        let idx = ((bucket + k * stride) % deck.count + deck.count) % deck.count
        return deck[idx]
    }

    public func entry(slot: Int, at date: Date) -> VocabEntry? {
        entry(slot: slot, bucket: bucketIndex(at: date))
    }

    /// Timeline of `(start, entry)` pairs starting at the bucket containing `from`.
    public func timeline(slot: Int, from: Date, count: Int) -> [(date: Date, entry: VocabEntry)] {
        guard settings.frequency != .onTap else {
            return entry(slot: slot, at: from).map { [(from, $0)] } ?? []
        }
        let first = bucketIndex(at: from)
        return (0..<count).compactMap { i in
            entry(slot: slot, bucket: first + i).map { (i == 0 ? from : bucketStart(first + i), $0) }
        }
    }

    // MARK: On-tap mode

    /// Current entry for `slot` in `onTap` mode; assigns one if none exists yet.
    public func currentTapEntry(slot: Int, store: SharedStore) -> VocabEntry? {
        guard !deck.isEmpty else { return nil }
        if let id = store.slotAssignments[slot], let e = deck.first(where: { $0.id == id }) { return e }
        return advance(slot: slot, store: store)
    }

    /// Moves `slot` to the next unused word and persists the assignment. Returns the new entry.
    @discardableResult
    public func advance(slot: Int, store: SharedStore) -> VocabEntry? {
        guard !deck.isEmpty else { return nil }
        var assignments = store.slotAssignments
        let taken = Set(assignments.filter { $0.key != slot }.values)
        var cursor = store.tapCursor
        var chosen: VocabEntry?
        for _ in 0..<deck.count {
            let candidate = deck[((cursor % deck.count) + deck.count) % deck.count]
            cursor += 1
            if !taken.contains(candidate.id) && candidate.id != assignments[slot] {
                chosen = candidate
                break
            }
        }
        store.tapCursor = cursor
        if let chosen {
            assignments[slot] = chosen.id
            store.slotAssignments = assignments
        }
        return chosen
    }
}

/// Small deterministic RNG so the deck order is stable for a given seed.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
