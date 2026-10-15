import Foundation
import Observation
import VocabCore

/// Drives one quiz run: per-question timer, answer feedback and completion.
@MainActor
@Observable
final class QuizViewModel {
    enum Phase: Equatable {
        case start
        case playing
        case finished(QuizResult, isNewBest: Bool)
    }

    private(set) var phase: Phase = .start
    private(set) var session: QuizSession?
    /// Seconds left for the current question.
    private(set) var remaining: TimeInterval = QuizScoring.timeLimit
    /// Answer for the current question once given (drives correct/incorrect highlight).
    private(set) var lastAnswer: QuizAnswer?

    @ObservationIgnored private var questionStart = Date()
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    @ObservationIgnored private weak var model: AppModel?

    static let feedbackDuration: Duration = .milliseconds(1100)

    var currentQuestion: QuizQuestion? { session?.currentQuestion }
    var isRevealing: Bool { lastAnswer != nil }
    var progress: Double {
        guard let session, !session.questions.isEmpty else { return 0 }
        return Double(session.answers.count) / Double(session.questions.count)
    }

    func start(model: AppModel) {
        self.model = model
        cancelTasks()
        var rng = SystemRandomNumberGenerator()
        let engine = QuizEngine(settings: model.settings, repository: model.repository)
        let newSession = engine.makeSession(seenEntryIDs: model.store.seenEntryIDs, using: &rng)
        guard !newSession.questions.isEmpty else { return }
        session = newSession
        phase = .playing
        beginQuestion()
    }

    func select(_ index: Int) {
        guard !isRevealing else { return }
        submit(index)
    }

    func reset() {
        cancelTasks()
        session = nil
        lastAnswer = nil
        phase = .start
    }

    // MARK: Private

    private func beginQuestion() {
        lastAnswer = nil
        remaining = QuizScoring.timeLimit
        questionStart = Date()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let left = max(0, QuizScoring.timeLimit - Date().timeIntervalSince(self.questionStart))
                self.remaining = left
                if left == 0 {
                    self.submit(nil)
                    return
                }
            }
        }
    }

    private func submit(_ index: Int?) {
        guard lastAnswer == nil, var session else { return }
        timerTask?.cancel()
        let elapsed = index == nil ? QuizScoring.timeLimit : Date().timeIntervalSince(questionStart)
        lastAnswer = session.answer(selectedIndex: index, elapsed: elapsed)
        self.session = session
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDuration)
            guard let self, !Task.isCancelled else { return }
            self.advance()
        }
    }

    private func advance() {
        guard let session else { return }
        if session.isFinished {
            finish(session)
        } else {
            beginQuestion()
        }
    }

    private func finish(_ session: QuizSession) {
        let result = session.makeResult()
        let previousBest = model?.bestScore ?? 0
        model?.record(result)
        lastAnswer = nil
        phase = .finished(result, isNewBest: result.score > previousBest)
    }

    private func cancelTasks() {
        timerTask?.cancel()
        advanceTask?.cancel()
    }
}
