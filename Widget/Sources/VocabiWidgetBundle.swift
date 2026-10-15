import WidgetKit
import SwiftUI
import VocabCore

@main
struct VocabiWidgetBundle: WidgetBundle {
    var body: some Widget {
        VocabiWordWidget()
    }
}

/// The single Vocabi widget. Each instance is configured with a slot so several
/// widgets on the same screen never show the same word.
struct VocabiWordWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: VocabiWidgetKind.word,
            intent: VocabiWidgetConfigurationIntent.self,
            provider: WordTimelineProvider()
        ) { entry in
            WordWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Vocabi Word")
        .description("Learn a new word right from your Home Screen. Give each widget a different slot so they never show the same word.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    VocabiWordWidget()
} timeline: {
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: false)
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: true)
    WordEntry(date: .now, content: .setup, slot: 1, isInteractive: false)
}

#Preview("Medium", as: .systemMedium) {
    VocabiWordWidget()
} timeline: {
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: false)
    WordEntry(date: .now, content: .setup, slot: 1, isInteractive: false)
}

#Preview("Large", as: .systemLarge) {
    VocabiWordWidget()
} timeline: {
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: true)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    VocabiWordWidget()
} timeline: {
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: false)
}

#Preview("Inline", as: .accessoryInline) {
    VocabiWordWidget()
} timeline: {
    WordEntry(date: .now, content: .word(SampleWord.card), slot: 1, isInteractive: false)
}
