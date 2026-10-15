import WidgetKit
import Foundation
import VocabCore

/// One rendered state of the word widget.
struct WordEntry: TimelineEntry {
    enum Content {
        case word(WordCard)
        /// Settings invalid or nothing to show: ask the user to open the app.
        case setup
    }

    let date: Date
    let content: Content
    /// 1-based widget slot this entry was produced for.
    let slot: Int
    /// `true` in on-tap mode: the whole widget is a "next word" button.
    let isInteractive: Bool

    var card: WordCard? {
        if case .word(let card) = content { return card }
        return nil
    }

    /// Deep link opened by tapping a widget in timed modes.
    var deepLink: URL? {
        guard let card else { return nil }
        return URL(string: "vocabi://word/\(card.id)")
    }
}

/// Builds widget timelines from the shared `WordScheduler` contract.
struct WordTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = WordEntry
    typealias Intent = VocabiWidgetConfigurationIntent

    var store: SharedStore = .shared
    var repository: VocabularyRepository = .shared

    func placeholder(in context: Context) -> WordEntry {
        sampleEntry(slot: 1)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> WordEntry {
        let slot = configuration.slot.rawValue
        if context.isPreview { return sampleEntry(slot: slot) }
        // A real snapshot shows the current word but does not record it as seen.
        let entries = makeEntries(slot: slot, now: Date(), recordSeen: false).entries
        return entries.first ?? sampleEntry(slot: slot)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<WordEntry> {
        let slot = configuration.slot.rawValue
        if context.isPreview {
            return Timeline(entries: [sampleEntry(slot: slot)], policy: .never)
        }
        let result = makeEntries(slot: slot, now: Date(), recordSeen: true)
        return Timeline(entries: result.entries, policy: result.policy)
    }

    // MARK: Core

    /// Produces the entries for `slot` (1-based). Exposed for previews/tests.
    func makeEntries(slot: Int, now: Date, recordSeen: Bool) -> (entries: [WordEntry], policy: TimelineReloadPolicy) {
        let settings = store.settings
        let setup = WordEntry(date: now, content: .setup, slot: slot, isInteractive: false)
        guard settings.isValid else { return ([setup], .never) }

        let pool = repository.pool(for: settings)
        guard !pool.isEmpty else { return ([setup], .never) }

        let scheduler = WordScheduler(settings: settings, pool: pool, seed: store.deckSeed)
        let schedulerSlot = min(max(slot, 1), maxWidgetSlots) - 1

        func card(_ entry: VocabEntry) -> WordCard {
            WordCard(entry: entry, targetLanguage: settings.targetLanguage, nativeLanguage: settings.nativeLanguage)
        }

        if settings.frequency == .onTap {
            guard let current = scheduler.currentTapEntry(slot: schedulerSlot, store: store) else {
                return ([setup], .never)
            }
            if recordSeen { store.markSeen([current.id], at: now) }
            let entry = WordEntry(date: now, content: .word(card(current)), slot: slot, isInteractive: true)
            return ([entry], .never)
        }

        let count: Int
        switch settings.frequency {
        case .hourly: count = 24
        case .daily: count = 7
        case .weekly: count = 4
        case .onTap: count = 1
        }

        let items = scheduler.timeline(slot: schedulerSlot, from: now, count: count)
        guard !items.isEmpty else { return ([setup], .never) }

        if recordSeen {
            // Record every scheduled entry with its display date. Later entries become visible without
            // the provider running again, so `SharedStore.seenEntryIDs` filters by date when read.
            for item in items { store.markSeen([item.entry.id], at: max(item.date, now)) }
        }

        let entries = items.map {
            WordEntry(date: $0.date, content: .word(card($0.entry)), slot: slot, isInteractive: false)
        }
        return (entries, .atEnd)
    }

    // MARK: Samples

    /// Realistic word for the gallery / placeholder, rendered in the user's language pair when valid.
    func sampleEntry(slot: Int) -> WordEntry {
        let settings = store.settings
        let languages = settings.isValid
            ? (target: settings.targetLanguage, native: settings.nativeLanguage)
            : (target: Language.english, native: Language.turkish)
        let entry = repository.allEntries.first ?? SampleWord.entry
        let card = WordCard(entry: entry, targetLanguage: languages.target, nativeLanguage: languages.native)
        return WordEntry(date: Date(), content: .word(card), slot: slot, isInteractive: false)
    }
}

/// Hardcoded fallback sample used when the bundled vocabulary cannot be loaded.
enum SampleWord {
    static let entry = VocabEntry(
        id: "business-0001",
        category: .business,
        difficulty: .intermediate,
        terms: [.english: "invoice", .turkish: "fatura", .french: "facture", .spanish: "factura"],
        definitions: [
            .english: "A document listing goods or services provided and the amount owed.",
            .turkish: "Sağlanan mal veya hizmetleri ve ödenecek tutarı listeleyen belge.",
            .french: "Document listant les biens ou services fournis et le montant dû.",
            .spanish: "Documento que enumera los bienes o servicios prestados y el importe adeudado.",
        ],
        examples: [
            .english: "Please pay the invoice within 30 days.",
            .turkish: "Lütfen faturayı 30 gün içinde ödeyin.",
            .french: "Veuillez régler la facture sous 30 jours.",
            .spanish: "Por favor, pague la factura en un plazo de 30 días.",
        ]
    )

    static let card = WordCard(entry: entry, targetLanguage: .english, nativeLanguage: .turkish)
}
