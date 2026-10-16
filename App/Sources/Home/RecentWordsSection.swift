import SwiftUI
import VocabCore

struct RecentWordsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recent = model.recentlySeen()
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently seen")
                .font(.title3.bold())
                .padding(.horizontal, 4)
            if recent.isEmpty {
                Text("Words you see in your widgets will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 52) }
                        NavigationLink(value: WordLink(id: entry.id)) {
                            RecentWordRow(card: model.card(for: entry))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

private struct RecentWordRow: View {
    let card: WordCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.entry.category.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.word).font(.body.weight(.semibold))
                    if card.entry.isAIGenerated { AIBadge() }
                }
                Text(card.translation).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
