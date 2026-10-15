import SwiftUI
import VocabCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CurrentWordCard()
                    StatsRow()
                    Button {
                        model.quizStartRequested = true
                        model.selectedTab = .quiz
                    } label: {
                        Label("Start quiz", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                    WidgetHelpCard()
                    RecentWordsSection()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vocabi")
            .navigationDestination(for: WordLink.self) { WordDetailView(entryID: $0.id) }
            .refreshable { model.refresh() }
            .onAppear { model.refresh() }
        }
    }
}

private struct StatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            stat(value: model.seenCount, title: "Words seen", symbol: "eye.fill", tint: .blue)
            stat(value: model.bestScore, title: "Best score", symbol: "star.fill", tint: .orange)
        }
    }

    private func stat(value: Int, title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value, format: .number)
                .font(.system(.title, design: .rounded).bold())
                .contentTransition(.numericText())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .card()
    }
}
