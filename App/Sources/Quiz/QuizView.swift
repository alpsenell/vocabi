import SwiftUI
import VocabCore

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @State private var quiz = QuizViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch quiz.phase {
                case .start:
                    QuizStartView { quiz.start(model: model) }
                case .playing:
                    if let question = quiz.currentQuestion {
                        QuizQuestionView(quiz: quiz, question: question)
                    }
                case let .finished(result, isNewBest):
                    QuizResultsView(result: result, bestScore: model.bestScore, isNewBest: isNewBest,
                                    onPlayAgain: { quiz.start(model: model) },
                                    onDone: { quiz.reset() })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if quiz.phase == .playing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Quit", role: .cancel) { quiz.reset() }
                    }
                }
            }
            .animation(.snappy, value: quiz.phase)
        }
        .onAppear(perform: consumeStartRequest)
        .onChange(of: model.quizStartRequested) { _, _ in consumeStartRequest() }
    }

    private func consumeStartRequest() {
        guard model.quizStartRequested else { return }
        model.quizStartRequested = false
        if quiz.phase != .playing { quiz.start(model: model) }
    }
}
