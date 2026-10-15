import SwiftUI
import VocabCore

struct QuizStartView: View {
    @Environment(AppModel.self) private var model
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(24)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .padding(.top, 24)
                Text("Ready for a quiz?")
                    .font(.largeTitle.bold())
                Text(model.seenCount >= QuizEngine.questionCount
                     ? "Questions use words you've seen in your widgets."
                     : "We'll mix the words you've seen with new ones from your topics.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    rule("list.number", "10 questions")
                    rule("timer", "10 seconds per question")
                    rule("bolt.fill", "100 points per correct answer + up to 50 for speed")
                    rule("star.fill", "Best score: \(model.bestScore)")
                }
                .card(padding: 20)

                Button(action: onStart) {
                    Label("Start quiz", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
            .padding()
        }
    }

    private func rule(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.body)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24)
        }
    }
}
