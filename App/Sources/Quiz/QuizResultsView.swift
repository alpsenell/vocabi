import SwiftUI
import VocabCore

struct QuizResultsView: View {
    let result: QuizResult
    let bestScore: Int
    let isNewBest: Bool
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private enum Submission { case pending, submitted, queued }
    @State private var submission: Submission = .pending

    private var submissionMessage: LocalizedStringKey {
        guard result.score > 0 else { return "Score at least one point to join the leaderboard." }
        switch submission {
        case .pending: return "Submitting your score to the leaderboard…"
        case .submitted: return "Your score was added to the leaderboard."
        case .queued: return "Score saved. It will join the leaderboard once iCloud is available."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: isNewBest ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 60))
                    .foregroundStyle(isNewBest ? Color.yellow.gradient : Color.accentColor.gradient)
                    .padding(.top, 24)
                Text(isNewBest ? "New best score!" : "Quiz complete")
                    .font(.largeTitle.bold())

                VStack(spacing: 4) {
                    Text(result.score, format: .number)
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("points").font(.headline).foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    stat(symbol: "checkmark.circle.fill", tint: .green, title: "Correct",
                         value: Text(verbatim: "\(result.correct)/\(result.total)"))
                    stat(symbol: "star.fill", tint: .orange, title: "Best score",
                         value: Text(bestScore, format: .number))
                }

                Text(submissionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .onReceive(NotificationCenter.default.publisher(for: LeaderboardBackend.didSubmitNotification)) { _ in
                        submission = .submitted
                    }
                    .onReceive(NotificationCenter.default.publisher(for: LeaderboardBackend.didFailNotification)) { _ in
                        submission = .queued
                    }

                Button(action: onPlayAgain) {
                    Label("Play again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.primary)
                Button("Done", action: onDone)
                    .font(.headline)
            }
            .padding()
        }
    }

    private func stat(symbol: String, tint: Color, title: LocalizedStringKey, value: Text) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            value.font(.system(.title2, design: .rounded).bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
