import Foundation
import Observation
import VocabCore
import WidgetKit

enum AppTab: Hashable {
    case home, quiz, leaderboard, settings
}

/// Identifiable wrapper so a deep-linked word can drive `.sheet(item:)`.
struct WordLink: Identifiable, Hashable {
    let id: String
}

/// App-wide state. Every write to shared settings goes through `save(_:)` so widgets reload.
@Observable
final class AppModel {
    let store: SharedStore
    let repository: VocabularyRepository

    private(set) var settings: UserSettings
    /// Most recently seen entry ids (refreshed on `refresh()`).
    private(set) var seenIDs: [String] = []
    private(set) var bestScore: Int = 0

    var selectedTab: AppTab = .home
    var presentedWord: WordLink?
    /// Set by Home's "Start quiz" button; the quiz tab consumes it.
    var quizStartRequested = false

    init(store: SharedStore = .shared, repository: VocabularyRepository = .shared) {
        self.store = store
        self.repository = repository
        self.settings = store.settings
        refresh()
        #if DEBUG
        DebugLaunchOptions.apply(to: self)
        #endif
    }

    // MARK: Settings

    func save(_ newSettings: UserSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        store.settings = newSettings
        WidgetCenter.shared.reloadAllTimelines()
    }

    func completeOnboarding(with draft: UserSettings) {
        var s = draft
        s.nickname = Nickname.clean(s.nickname)
        s.hasCompletedOnboarding = true
        save(s)
        refresh()
    }

    /// Clears seen words, quiz history and widget state while keeping the user's settings.
    func resetProgress() {
        let kept = settings
        store.resetAll()
        store.settings = kept
        WidgetCenter.shared.reloadAllTimelines()
        refresh()
    }

    // MARK: Derived data

    func refresh() {
        settings = store.settings
        seenIDs = store.seenEntryIDs
        bestScore = store.quizHistory.map(\.score).max() ?? 0
    }

    var seenCount: Int { seenIDs.count }

    func markSeen(_ entryID: String) {
        guard seenIDs.first != entryID else { return }
        store.markSeen([entryID])
        seenIDs = store.seenEntryIDs
    }

    func recentlySeen(limit: Int = 8) -> [VocabEntry] {
        seenIDs.prefix(limit).compactMap(repository.entry(id:))
    }

    func card(for entry: VocabEntry) -> WordCard {
        WordCard(entry: entry, targetLanguage: settings.targetLanguage, nativeLanguage: settings.nativeLanguage)
    }

    /// Word currently shown by widget slot 1 — computed exactly as the widget does.
    func currentSlotOneEntry(at date: Date = Date()) -> VocabEntry? {
        let scheduler = WordScheduler(settings: settings, pool: repository.pool(for: settings), seed: store.deckSeed)
        if settings.frequency == .onTap {
            return scheduler.currentTapEntry(slot: 0, store: store)
        }
        return scheduler.entry(slot: 0, at: date)
    }

    // MARK: Quiz

    func record(_ result: QuizResult) {
        store.appendQuizResult(result)
        LeaderboardSubmitter.submit(result)
        refresh()
    }

    // MARK: Deep links

    func handle(_ url: URL) {
        switch DeepLink(url: url) {
        case .word(let id):
            selectedTab = .home
            presentedWord = WordLink(id: id)
        case .quiz:
            presentedWord = nil
            selectedTab = .quiz
        case nil:
            break
        }
    }
}
