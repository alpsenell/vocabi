import SwiftUI
import WidgetKit
import VocabCore

// MARK: - Root

/// Entry view for every supported family. Handles interactivity, deep links and the container background.
struct WordWidgetEntryView: View {
    let entry: WordEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        interactiveContent
            .containerBackground(for: .widget) { WidgetBackdrop(category: entry.card?.entry.category, family: family) }
    }

    @ViewBuilder
    private var interactiveContent: some View {
        if entry.isInteractive {
            // On-tap mode: the whole widget advances to the next word without opening the app.
            Button(intent: NextWordIntent(slot: entry.slot)) {
                familyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            familyContent
                .widgetURL(entry.deepLink)
        }
    }

    @ViewBuilder
    private var familyContent: some View {
        switch entry.content {
        case .setup:
            SetupView(family: family)
        case .word(let card):
            switch family {
            case .systemSmall: SmallWordView(card: card, interactive: entry.isInteractive)
            case .systemMedium: MediumWordView(card: card, interactive: entry.isInteractive)
            case .systemLarge: LargeWordView(card: card, interactive: entry.isInteractive)
            case .accessoryRectangular: RectangularWordView(card: card)
            case .accessoryInline: InlineWordView(card: card)
            default: SmallWordView(card: card, interactive: entry.isInteractive)
            }
        }
    }
}

// MARK: - Background

private struct WidgetBackdrop: View {
    let category: VocabCore.Category?
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            Color.clear
        default:
            ZStack {
                Color(uiColor: .systemBackground)
                LinearGradient(
                    colors: [WidgetTheme.tint(for: category).opacity(0.22), WidgetTheme.tint(for: category).opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

// MARK: - System families

private struct SmallWordView: View {
    let card: WordCard
    let interactive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                CategoryGlyph(category: card.entry.category)
                Spacer(minLength: 4)
                LanguageBadge(language: card.targetLanguage)
            }
            Spacer(minLength: 2)
            WordTitle(word: card.word, size: 30)
                .id(card.id)
                .transition(.push(from: .trailing))
            Text(card.description)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if interactive { TapHint().padding(.top, 2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumWordView: View {
    let card: WordCard
    let interactive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                CategoryGlyph(category: card.entry.category)
                Text(WidgetTheme.name(for: card.entry.category))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 4)
                LanguageBadge(language: card.targetLanguage)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                WordTitle(word: card.word, size: 34)
                Text(card.translation)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .id(card.id)
            .transition(.push(from: .trailing))
            Text(card.description)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if interactive { TapHint() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LargeWordView: View {
    let card: WordCard
    let interactive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                CategoryGlyph(category: card.entry.category)
                Text("Word of the moment")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 4)
                LanguageBadge(language: card.targetLanguage)
            }

            VStack(alignment: .leading, spacing: 2) {
                WordTitle(word: card.word, size: 44)
                Text(card.translation)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .id(card.id)
            .transition(.push(from: .trailing))

            Text(card.description)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            if let example = card.example, !example.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(WidgetTheme.tint(for: card.entry.category))
                        .frame(width: 3)
                    Text("“\(example)”")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Chip(icon: Image(systemName: card.entry.category.symbolName),
                     text: WidgetTheme.name(for: card.entry.category),
                     tint: WidgetTheme.tint(for: card.entry.category))
                Chip(icon: Image(systemName: "cellularbars", variableValue: WidgetTheme.level(for: card.entry.difficulty)),
                     text: WidgetTheme.name(for: card.entry.difficulty),
                     tint: .secondary)
                Spacer(minLength: 0)
                if interactive { TapHint() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Accessory families

private struct RectangularWordView: View {
    let card: WordCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.word)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(card.description)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineWordView: View {
    let card: WordCard

    var body: some View {
        Label(card.word, systemImage: "character.book.closed")
    }
}

// MARK: - Setup state

private struct SetupView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Open Vocabi to set up", systemImage: "character.book.closed")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("Vocabi").font(.system(.headline, design: .rounded, weight: .bold)).widgetAccentable()
                Text("Open Vocabi to set up").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 8) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Open Vocabi to set up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if family != .systemSmall {
                    Text("Choose your languages to start learning new words.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Building blocks

private struct WordTitle: View {
    let word: String
    let size: CGFloat

    var body: some View {
        Text(word)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
            .widgetAccentable()
    }
}

/// Tiny flag + language code badge for the target language.
private struct LanguageBadge: View {
    let language: Language

    var body: some View {
        HStack(spacing: 3) {
            Text(language.flag).font(.system(size: 10))
            Text(language.rawValue.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.fill.tertiary, in: Capsule())
        .accessibilityLabel(Text(language.nativeName))
    }
}

private struct CategoryGlyph: View {
    let category: VocabCore.Category

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WidgetTheme.tint(for: category))
            .widgetAccentable()
            .accessibilityLabel(Text(WidgetTheme.name(for: category)))
    }
}

private struct Chip<S: ShapeStyle>: View {
    let icon: Image
    let text: String
    let tint: S

    var body: some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            icon
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: Capsule())
    }
}

private struct TapHint: View {
    var body: some View {
        Label("Tap for next", systemImage: "arrow.forward.circle.fill")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

// MARK: - Theme

enum WidgetTheme {
    static func tint(for category: VocabCore.Category?) -> Color {
        switch category {
        case .business: return .indigo
        case .school: return .orange
        case .dailyLife: return .teal
        case .travel: return .blue
        case .technology: return .purple
        case .health: return .pink
        case .food: return .green
        case nil: return .accentColor
        }
    }

    static func name(for category: VocabCore.Category) -> String {
        switch category {
        case .business: return String(localized: "Business")
        case .school: return String(localized: "School")
        case .dailyLife: return String(localized: "Daily life")
        case .travel: return String(localized: "Travel")
        case .technology: return String(localized: "Technology")
        case .health: return String(localized: "Health")
        case .food: return String(localized: "Food")
        }
    }

    static func name(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return String(localized: "Beginner")
        case .intermediate: return String(localized: "Intermediate")
        case .advanced: return String(localized: "Advanced")
        }
    }

    /// Fill level for the `cellularbars` symbol.
    static func level(for difficulty: Difficulty) -> Double {
        switch difficulty {
        case .beginner: return 0.34
        case .intermediate: return 0.67
        case .advanced: return 1.0
        }
    }
}
