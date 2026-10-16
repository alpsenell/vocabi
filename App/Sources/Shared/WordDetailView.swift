import SwiftUI
import VocabCore

/// Word, translation, definition, example, category and difficulty for one entry.
struct WordDetailView: View {
    @Environment(AppModel.self) private var model
    let entryID: String

    var body: some View {
        Group {
            if let entry = model.repository.entry(id: entryID) {
                content(model.card(for: entry))
            } else {
                ContentUnavailableView("Word not found", systemImage: "questionmark.text.page",
                                       description: Text("This word is no longer available."))
            }
        }
        .navigationTitle("Word")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private func content(_ card: WordCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TagView(text: card.entry.category.localizedName, systemImage: card.entry.category.symbolName)
                        TagView(text: card.entry.difficulty.localizedName, systemImage: card.entry.difficulty.symbolName,
                                tint: card.entry.difficulty.tint)
                        Spacer(minLength: 0)
                        if card.entry.isAIGenerated { AIBadge() }
                    }
                    if let topic = card.entry.topic, !topic.isEmpty {
                        TagView(text: topic.capitalized, systemImage: "tag.fill", tint: .purple)
                    }
                    Text(card.word)
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .textSelection(.enabled)
                    Label(card.translation, systemImage: "character.book.closed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .card(padding: 20)

                section("Definition", systemImage: "text.alignleft", text: card.description)
                if let example = card.example {
                    section("Example", systemImage: "quote.opening", text: example, italic: true)
                }
            }
            .padding()
        }
    }

    private func section(_ title: LocalizedStringKey, systemImage: String, text: String, italic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .italic(italic)
                .textSelection(.enabled)
        }
        .card()
    }
}
