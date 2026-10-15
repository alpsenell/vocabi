import Foundation

// MARK: - Model

/// The two question styles mixed in a quiz session.
public enum QuizQuestionStyle: String, Codable, CaseIterable, Sendable, Hashable {
    /// Prompt is the target-language word; options are native-language definitions.
    case wordToDefinition
    /// Prompt is the native-language definition; options are target-language words.
    case definitionToWord
}

/// One answer choice, already resolved for the user's language pair.
public struct QuizOption: Identifiable, Hashable, Sendable {
    /// Id of the vocabulary entry this option comes from.
    public let entryID: String
    public let text: String

    public var id: String { entryID }

    public init(entryID: String, text: String) {
        self.entryID = entryID
        self.text = text
    }
}

/// A multiple-choice question resolved for a language pair.
public struct QuizQuestion: Identifiable, Hashable, Sendable {
    public let id: Int                 // position in the session (0-based)
    public let entry: VocabEntry       // the entry being asked about
    public let style: QuizQuestionStyle
    public let targetLanguage: Language
    public let nativeLanguage: Language
    /// Text shown as the question (word or definition, depending on `style`).
    public let prompt: String
    /// Exactly `QuizEngine.optionCount` options when the vocabulary allows it; texts are unique.
    public let options: [QuizOption]
    public let correctIndex: Int

    public init(id: Int, entry: VocabEntry, style: QuizQuestionStyle, targetLanguage: Language,
                nativeLanguage: Language, prompt: String, options: [QuizOption], correctIndex: Int) {
        self.id = id
        self.entry = entry
        self.style = style
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
    }

    public var correctOption: QuizOption { options[correctIndex] }
    /// Language the prompt is written in.
    public var promptLanguage: Language { style == .wordToDefinition ? targetLanguage : nativeLanguage }
    /// Language the options are written in.
    public var optionLanguage: Language { style == .wordToDefinition ? nativeLanguage : targetLanguage }
}

/// What the player did for one question.
public struct QuizAnswer: Hashable, Sendable {
    public let questionID: Int
    /// `nil` when the timer ran out.
    public let selectedIndex: Int?
    public let elapsed: TimeInterval
    public let isCorrect: Bool
    public let points: Int

    public init(questionID: Int, selectedIndex: Int?, elapsed: TimeInterval, isCorrect: Bool, points: Int) {
        self.questionID = questionID
        self.selectedIndex = selectedIndex
        self.elapsed = elapsed
        self.isCorrect = isCorrect
        self.points = points
    }
}

// MARK: - Scoring

public enum QuizScoring {
    public static let pointsPerCorrectAnswer = 100
    public static let maxSpeedBonus = 50
    /// Time allowed per question; the speed bonus decays linearly to 0 over this window.
    public static let timeLimit: TimeInterval = 10

    /// Speed bonus for a correct answer given after `elapsed` seconds (50 at 0 s → 0 at 10 s).
    public static func speedBonus(elapsed: TimeInterval) -> Int {
        let clamped = min(max(elapsed, 0), timeLimit)
        return Int((Double(maxSpeedBonus) * (timeLimit - clamped) / timeLimit).rounded())
    }

    public static func points(isCorrect: Bool, elapsed: TimeInterval) -> Int {
        guard isCorrect, elapsed <= timeLimit else { return 0 }
        return pointsPerCorrectAnswer + speedBonus(elapsed: elapsed)
    }

    /// Highest score achievable in a session of `questionCount` questions.
    public static func maxScore(questionCount: Int) -> Int {
        questionCount * (pointsPerCorrectAnswer + maxSpeedBonus)
    }
}

// MARK: - Session

/// State of a running quiz. Value type; the UI owns one and records answers in order.
public struct QuizSession: Sendable, Hashable {
    public let questions: [QuizQuestion]
    public let targetLanguage: Language
    public private(set) var answers: [QuizAnswer] = []

    public init(questions: [QuizQuestion], targetLanguage: Language) {
        self.questions = questions
        self.targetLanguage = targetLanguage
    }

    public var currentIndex: Int { answers.count }
    public var currentQuestion: QuizQuestion? { questions.indices.contains(currentIndex) ? questions[currentIndex] : nil }
    public var isFinished: Bool { answers.count >= questions.count }
    public var score: Int { answers.reduce(0) { $0 + $1.points } }
    public var correctCount: Int { answers.filter(\.isCorrect).count }

    /// Records the answer to the current question. `selectedIndex == nil` means time ran out.
    @discardableResult
    public mutating func answer(selectedIndex: Int?, elapsed: TimeInterval) -> QuizAnswer? {
        guard let q = currentQuestion else { return nil }
        let correct = selectedIndex == q.correctIndex && elapsed <= QuizScoring.timeLimit
        let a = QuizAnswer(questionID: q.id, selectedIndex: selectedIndex, elapsed: elapsed,
                           isCorrect: correct, points: QuizScoring.points(isCorrect: correct, elapsed: elapsed))
        answers.append(a)
        return a
    }

    public func makeResult(id: UUID = UUID(), date: Date = Date()) -> QuizResult {
        QuizResult(id: id, date: date, score: score, correct: correctCount,
                   total: questions.count, targetLanguage: targetLanguage)
    }
}

// MARK: - Engine

/// Builds quiz sessions. Pure and deterministic for a given random number generator.
public struct QuizEngine: Sendable {
    public static let questionCount = 10
    public static let optionCount = 4

    public let settings: UserSettings
    /// Entries eligible for padding (the user's filtered pool).
    public let pool: [VocabEntry]
    /// Every known entry (used to resolve seen ids and as a distractor fallback).
    public let allEntries: [VocabEntry]

    public init(settings: UserSettings, pool: [VocabEntry], allEntries: [VocabEntry]) {
        self.settings = settings
        self.pool = pool.sorted { $0.id < $1.id }
        self.allEntries = allEntries.sorted { $0.id < $1.id }
    }

    public init(settings: UserSettings, repository: VocabularyRepository) {
        self.init(settings: settings, pool: repository.pool(for: settings), allEntries: repository.allEntries)
    }

    /// Builds a session of up to `questionCount` questions, preferring `seenEntryIDs`
    /// and padding from the pool when fewer than `questionCount` entries were seen.
    public func makeSession<R: RandomNumberGenerator>(seenEntryIDs: [String],
                                                      questionCount: Int = QuizEngine.questionCount,
                                                      using rng: inout R) -> QuizSession {
        let entries = selectEntries(seenEntryIDs: seenEntryIDs, count: questionCount, using: &rng)

        // Mix styles evenly, then shuffle their order.
        var styles = (0..<entries.count).map { $0 % 2 == 0 ? QuizQuestionStyle.wordToDefinition : .definitionToWord }
        styles.shuffle(using: &rng)

        let questions = entries.enumerated().map { i, entry in
            makeQuestion(id: i, entry: entry, style: styles[i], using: &rng)
        }
        return QuizSession(questions: questions, targetLanguage: settings.targetLanguage)
    }

    /// Picks the entries to ask about: seen first (random sample), then pool padding. No duplicates.
    func selectEntries<R: RandomNumberGenerator>(seenEntryIDs: [String], count: Int, using rng: inout R) -> [VocabEntry] {
        let byID = Dictionary(allEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seenUnique: [VocabEntry] = []
        var used = Set<String>()
        for id in seenEntryIDs where !used.contains(id) {
            if let e = byID[id] { seenUnique.append(e); used.insert(id) }
        }
        seenUnique.shuffle(using: &rng)
        var chosen = Array(seenUnique.prefix(count))
        let chosenIDs = Set(chosen.map(\.id))

        if chosen.count < count {
            var padding = pool.filter { !chosenIDs.contains($0.id) }
            padding.shuffle(using: &rng)
            chosen.append(contentsOf: padding.prefix(count - chosen.count))
        }
        chosen.shuffle(using: &rng)
        return chosen
    }

    func makeQuestion<R: RandomNumberGenerator>(id: Int, entry: VocabEntry, style: QuizQuestionStyle,
                                                using rng: inout R) -> QuizQuestion {
        let target = settings.targetLanguage
        let native = settings.nativeLanguage
        let promptText: String
        let optionText: (VocabEntry) -> String
        switch style {
        case .wordToDefinition:
            promptText = entry.term(in: target)
            optionText = { $0.definition(in: native) }
        case .definitionToWord:
            promptText = entry.definition(in: native)
            optionText = { $0.term(in: target) }
        }

        let correct = QuizOption(entryID: entry.id, text: optionText(entry))
        var usedTexts: Set<String> = [Self.normalized(correct.text)]
        var distractors: [QuizOption] = []

        // Same category first (pool, then whole vocabulary), then any category.
        var sameCategory = allEntries.filter { $0.category == entry.category && $0.id != entry.id }
        sameCategory.shuffle(using: &rng)
        var others = allEntries.filter { $0.category != entry.category }
        others.shuffle(using: &rng)

        for candidate in sameCategory + others {
            if distractors.count == Self.optionCount - 1 { break }
            let text = optionText(candidate)
            let key = Self.normalized(text)
            guard !key.isEmpty, !usedTexts.contains(key) else { continue }
            usedTexts.insert(key)
            distractors.append(QuizOption(entryID: candidate.id, text: text))
        }

        var options = distractors + [correct]
        options.shuffle(using: &rng)
        let correctIndex = options.firstIndex { $0.entryID == entry.id } ?? 0
        return QuizQuestion(id: id, entry: entry, style: style, targetLanguage: target, nativeLanguage: native,
                            prompt: promptText, options: options, correctIndex: correctIndex)
    }

    static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
