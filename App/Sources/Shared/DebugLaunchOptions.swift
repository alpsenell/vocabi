#if DEBUG
import Foundation
import VocabCore

/// Debug-only launch arguments for screenshots / manual QA:
///   -VocabiDemo          completes onboarding with demo settings and marks a few words as seen
///   -VocabiTab <name>    home | quiz | leaderboard | settings
///   -VocabiStartQuiz     starts a quiz immediately
///   -VocabiOpenURL <url> handles a deep link as if opened by the system
enum DebugLaunchOptions {
    static func apply(to model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-VocabiDemo") {
            var s = UserSettings(nativeLanguage: .turkish, targetLanguage: .english, frequency: .daily,
                                 difficulties: [.beginner, .intermediate], categories: Set(VocabCore.Category.allCases),
                                 nickname: "alp")
            s.hasCompletedOnboarding = true
            model.save(s)
            let ids = model.repository.pool(for: s).prefix(6).map(\.id)
            for (i, id) in ids.enumerated() {
                model.store.markSeen([id], at: Date().addingTimeInterval(Double(-i * 60)))
            }
            model.refresh()
        }
        if let i = args.firstIndex(of: "-VocabiTab"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "quiz": model.selectedTab = .quiz
            case "leaderboard": model.selectedTab = .leaderboard
            case "settings": model.selectedTab = .settings
            default: model.selectedTab = .home
            }
        }
        if let i = args.firstIndex(of: "-VocabiOpenURL"), args.indices.contains(i + 1), let url = URL(string: args[i + 1]) {
            model.handle(url)
        }
        if args.contains("-VocabiStartQuiz") {
            model.quizStartRequested = true
            model.selectedTab = .quiz
        }
    }
}
#endif
