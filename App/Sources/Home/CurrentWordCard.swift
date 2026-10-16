import SwiftUI
import VocabCore

/// The word currently shown by widget slot 1.
struct CurrentWordCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let entry = model.currentSlotOneEntry() {
            let card = model.card(for: entry)
            NavigationLink(value: WordLink(id: entry.id)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Word of the moment", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                        if entry.isAIGenerated { AIBadge(onAccent: true) }
                        Spacer()
                        Text(model.settings.frequency.localizedName)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    Text(card.word)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                    Text(card.description)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text("\(model.settings.targetLanguage.flag) → \(model.settings.nativeLanguage.flag)")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .task(id: entry.id) {
                // Seeing the word in the app counts as seen, just like in a widget.
                model.markSeen(entry.id)
            }
        } else {
            ContentUnavailableView("No words available", systemImage: "text.book.closed",
                                   description: Text("Try selecting more levels or topics in Settings."))
                .card()
        }
    }
}
