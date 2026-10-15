import SwiftUI
import VocabCore

struct QuizQuestionView: View {
    let quiz: QuizViewModel
    let question: QuizQuestion

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                promptCard
                VStack(spacing: 12) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                        AnswerButton(text: option.text, state: state(for: index)) { quiz.select(index) }
                    }
                }
                feedback
            }
            .padding()
        }
        .sensoryFeedback(trigger: quiz.lastAnswer) { _, answer in
            guard let answer else { return nil }
            return answer.isCorrect ? .success : .error
        }
    }

    private var header: some View {
        let total = quiz.session?.questions.count ?? QuizEngine.questionCount
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Question \(question.id + 1) of \(total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView(value: quiz.progress)
                    .tint(.accentColor)
                Text("Score: \(quiz.session?.score ?? 0)")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
            }
            TimerRing(remaining: quiz.remaining, total: QuizScoring.timeLimit)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 12) {
            Text(question.style == .wordToDefinition ? "What does this word mean?" : "Which word matches this definition?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(question.prompt)
                .font(question.style == .wordToDefinition
                      ? .system(size: 34, weight: .bold, design: .rounded)
                      : .title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            Text(question.promptLanguage.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var feedback: some View {
        if let answer = quiz.lastAnswer {
            Group {
                if answer.isCorrect {
                    Label("Correct! +\(answer.points)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if answer.selectedIndex == nil {
                    Label("Time's up!", systemImage: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("Not quite", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.headline)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func state(for index: Int) -> AnswerButton.State {
        guard let answer = quiz.lastAnswer else { return .idle }
        if index == question.correctIndex { return .correct }
        if index == answer.selectedIndex { return .wrong }
        return .dimmed
    }
}

struct AnswerButton: View {
    enum State { case idle, correct, wrong, dimmed }

    let text: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let symbol {
                    Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint, lineWidth: state == .idle || state == .dimmed ? 0 : 2))
            .opacity(state == .dimmed ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
        .animation(.easeOut(duration: 0.2), value: state)
    }

    private var tint: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        default: return .clear
        }
    }

    private var symbol: String? {
        switch state {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        default: return nil
        }
    }

    private var background: Color {
        switch state {
        case .correct: return Color.green.opacity(0.15)
        case .wrong: return Color.red.opacity(0.15)
        default: return Color(.secondarySystemGroupedBackground)
        }
    }
}

/// Circular countdown for the per-question timer.
struct TimerRing: View {
    let remaining: TimeInterval
    let total: TimeInterval

    private var fraction: Double { total > 0 ? remaining / total : 0 }
    private var color: Color { fraction > 0.5 ? .accentColor : (fraction > 0.2 ? .orange : .red) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: fraction)
            Text(Int(remaining.rounded(.up)), format: .number)
                .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Int(remaining.rounded(.up))) seconds left"))
    }
}
