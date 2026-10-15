import AppIntents
import WidgetKit
import VocabCore

/// Kind string shared by the widget configuration and every reload call.
enum VocabiWidgetKind {
    static let word = "VocabiWordWidget"
}

/// Which of the `maxWidgetSlots` scheduler slots a widget instance uses.
/// Distinct slots are guaranteed to show distinct words at the same time.
enum WidgetSlot: Int, AppEnum, CaseIterable {
    case one = 1, two, three, four, five, six

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Widget slot"

    static var caseDisplayRepresentations: [WidgetSlot: DisplayRepresentation] = [
        .one: "Slot 1",
        .two: "Slot 2",
        .three: "Slot 3",
        .four: "Slot 4",
        .five: "Slot 5",
        .six: "Slot 6",
    ]

    /// 0-based index used by `WordScheduler`.
    var schedulerSlot: Int { rawValue - 1 }
}

/// Per-instance configuration of the word widget.
struct VocabiWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Word Widget"
    static var description = IntentDescription("Give each widget a different slot so they never show the same word.")

    @Parameter(title: "Widget slot", default: .one)
    var slot: WidgetSlot

    init() {}

    init(slot: WidgetSlot) {
        self.slot = slot
    }
}

/// Interactive "next word" action used by the widget in on-tap mode.
/// Runs inside the widget extension process; it never opens the app.
struct NextWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Word"
    static var description = IntentDescription("Shows the next word in this widget.")
    static var isDiscoverable = false

    /// 1-based widget slot (matches `WidgetSlot.rawValue`).
    @Parameter(title: "Slot", default: 1)
    var slot: Int

    init() {}

    init(slot: Int) {
        self.slot = slot
    }

    func perform() async throws -> some IntentResult {
        let store = SharedStore.shared
        let settings = store.settings
        let pool = VocabularyRepository.shared.pool(for: settings)
        let scheduler = WordScheduler(settings: settings, pool: pool, seed: store.deckSeed)
        let clamped = min(max(slot, 1), maxWidgetSlots)
        scheduler.advance(slot: clamped - 1, store: store)
        WidgetCenter.shared.reloadTimelines(ofKind: VocabiWidgetKind.word)
        return .result()
    }
}
