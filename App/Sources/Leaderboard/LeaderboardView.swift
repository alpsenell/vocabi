import SwiftUI
import VocabCore

// OWNED BY THE LEADERBOARD TEAMMATE. The app shell only instantiates `LeaderboardView()`
// and calls `LeaderboardSubmitter.submit(_:)` after a quiz.

// MARK: - Shared backend

enum LeaderboardBackend {
    static let defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard

    static let cloudKit = CloudKitLeaderboardService(defaults: defaults)

    /// CloudKit service wrapped in the offline queue (App Group key "leaderboard.pendingResults.v1").
    static let shared = LeaderboardSyncCoordinator(service: cloudKit,
                                                   queue: PendingLeaderboardQueue(defaults: defaults))

    /// "Report nickname": CloudKit `NicknameReport` records; reported rows are hidden locally
    /// (App Group key "leaderboard.reportedRecords.v1").
    static let reporter = NicknameReporter(service: cloudKit, store: ReportedNicknameStore(defaults: defaults))

    /// Posted on the main queue after queued results reached the server.
    static let didSubmitNotification = Notification.Name("LeaderboardBackend.didSubmit")
    /// Posted on the main queue when a submission could not reach the server (it stays queued).
    static let didFailNotification = Notification.Name("LeaderboardBackend.didFail")
}

enum LeaderboardSubmitter {
    /// Fire-and-forget submission; never throws into the quiz flow.
    /// The result is persisted first, so failures are retried on the next submit or leaderboard fetch.
    static func submit(_ result: QuizResult) {
        let nickname = SharedStore.shared.settings.nickname
        Task.detached(priority: .utility) {
            do {
                try await LeaderboardBackend.shared.submit(result, nickname: nickname)
                await MainActor.run {
                    NotificationCenter.default.post(name: LeaderboardBackend.didSubmitNotification, object: nil)
                }
            } catch {
                // Swallowed on purpose: the submission stays queued for the next attempt.
                await MainActor.run {
                    NotificationCenter.default.post(name: LeaderboardBackend.didFailNotification, object: nil)
                }
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class LeaderboardViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([LeaderboardEntry])
        case failed(LeaderboardError)
    }

    /// Brief message shown after "Report nickname".
    enum ReportConfirmation: Equatable {
        case sent
        case hiddenNotSignedIn
        case hiddenNotSent
    }

    var period: LeaderboardPeriod = .weekly
    private(set) var states: [LeaderboardPeriod: LoadState] = [:]
    private(set) var targetLanguage: Language = SharedStore.shared.settings.targetLanguage
    private(set) var pendingCount = 0
    private(set) var reportConfirmation: ReportConfirmation?

    private let service: LeaderboardService
    private let reporter: NicknameReporter
    private let now: () -> Date
    private let pendingCounter: (@Sendable () async -> Int)?
    private var confirmationTask: Task<Void, Never>?

    init(service: LeaderboardService = LeaderboardBackend.shared,
         reporter: NicknameReporter = LeaderboardBackend.reporter,
         now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.reporter = reporter
        self.now = now
        if let coordinator = service as? LeaderboardSyncCoordinator {
            pendingCounter = { await coordinator.pendingCount }
        } else {
            pendingCounter = nil
        }
    }

    var state: LoadState { states[period] ?? .idle }

    var currentEntry: LeaderboardEntry? {
        if case .loaded(let entries) = state { return entries.first(where: \.isCurrentUser) }
        return nil
    }

    /// Loads the selected period (cached unless `force`); invalidates the cache when the target language changed.
    /// Keeps the previous rows visible while refreshing.
    func load(force: Bool = false) async {
        let language = SharedStore.shared.settings.targetLanguage
        if language != targetLanguage {
            targetLanguage = language
            states.removeAll()
        }
        let period = self.period
        if !force, case .loaded = states[period] { return }
        if case .loaded = states[period] {} else { states[period] = .loading }

        do {
            let entries = try await service.fetch(period: period, targetLanguage: language)
            states[period] = .loaded(reporter.filter(entries))
        } catch let error as LeaderboardError {
            states[period] = .failed(error)
        } catch {
            states[period] = .failed(.unknown(error.localizedDescription))
        }
        pendingCount = await pendingCounter?() ?? 0
    }

    func invalidateAll() { states.removeAll() }

    // MARK: Reporting

    /// Hides `entry` immediately (in every period), then sends a `NicknameReport`.
    /// Without iCloud or network the row stays hidden locally and the message says so.
    func report(_ entry: LeaderboardEntry) async {
        guard !entry.isCurrentUser else { return }
        let recordName = NicknameReporter.recordName(for: entry, period: period, date: now(),
                                                     targetLanguage: targetLanguage)
        for (key, state) in states {
            if case .loaded(let entries) = state {
                states[key] = .loaded(entries.filter { $0.id != entry.id })
            }
        }
        let outcome = await reporter.report(recordName: recordName, nickname: entry.nickname)
        switch outcome {
        case .sent: showConfirmation(.sent)
        case .hiddenOnly(.notSignedIn): showConfirmation(.hiddenNotSignedIn)
        case .hiddenOnly: showConfirmation(.hiddenNotSent)
        }
    }

    private func showConfirmation(_ confirmation: ReportConfirmation) {
        confirmationTask?.cancel()
        reportConfirmation = confirmation
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.reportConfirmation = nil
        }
    }
}

// MARK: - View

struct LeaderboardView: View {
    @State private var model = LeaderboardViewModel()
    @State private var pendingReport: LeaderboardEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                content
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Leaderboard"))
            .refreshable { await model.load(force: true) }
            .task(id: model.period) { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: LeaderboardBackend.didSubmitNotification)) { _ in
                model.invalidateAll()
                Task { await model.load(force: true) }
            }
            .animation(.default, value: model.state)
            .confirmationDialog(reportTitle, isPresented: isReportDialogPresented, titleVisibility: .visible,
                                presenting: pendingReport) { entry in
                Button("Report nickname", role: .destructive) {
                    Task { await model.report(entry) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This nickname will be hidden for you and sent to us for review.")
            }
            .overlay(alignment: .bottom) {
                if let confirmation = model.reportConfirmation {
                    ReportToast(confirmation: confirmation)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: model.reportConfirmation)
        }
    }

    private var reportTitle: Text {
        Text("Report “\(pendingReport?.nickname ?? "")”?")
    }

    private var isReportDialogPresented: Binding<Bool> {
        Binding(get: { pendingReport != nil }, set: { if !$0 { pendingReport = nil } })
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $model.period) {
                ForEach(LeaderboardPeriod.allCases) { p in
                    Text(p.localizedName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label(model.period.windowLabel(for: Date()), systemImage: "calendar")
                Spacer()
                Text("Learning \(model.targetLanguage.flag) \(model.targetLanguage.nativeName)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if case .loaded = model.state {
                OwnRankCard(entry: model.currentEntry)
            }
            if model.pendingCount > 0 {
                Label("Some scores will sync when you're back online.", systemImage: "icloud.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            Section {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
            }
        case .failed(.notSignedIn):
            Section {
                ContentUnavailableView {
                    Label("iCloud required", systemImage: "icloud.slash")
                } description: {
                    Text("Sign in to iCloud in Settings to join the global ranking.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        case .failed:
            Section {
                ContentUnavailableView {
                    Label("Couldn't load the leaderboard", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await model.load(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        case .loaded(let entries) where entries.isEmpty:
            Section {
                ContentUnavailableView("No scores yet", systemImage: "trophy",
                                       description: Text("Be the first to finish a quiz this period!"))
                    .listRowBackground(Color.clear)
            }
        case .loaded(let entries):
            Section {
                ForEach(entries) { entry in
                    LeaderboardRow(entry: entry)
                        .listRowBackground(entry.isCurrentUser ? Color.accentColor.opacity(0.15) : nil)
                        .modifier(ReportActions(entry: entry) { pendingReport = $0 })
                }
            }
        }
    }
}

// MARK: - Reporting

/// Context menu + trailing swipe "Report nickname" on other players' rows.
private struct ReportActions: ViewModifier {
    let entry: LeaderboardEntry
    let onReport: (LeaderboardEntry) -> Void

    func body(content: Content) -> some View {
        if entry.isCurrentUser {
            content
        } else {
            content
                .contextMenu {
                    Button(role: .destructive) { onReport(entry) } label: {
                        Label("Report nickname", systemImage: "exclamationmark.bubble")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { onReport(entry) } label: {
                        Label("Report nickname", systemImage: "exclamationmark.bubble")
                    }
                    .tint(.orange)
                }
        }
    }
}

private struct ReportToast: View {
    let confirmation: LeaderboardViewModel.ReportConfirmation

    var body: some View {
        Label(message, systemImage: confirmation == .sent ? "checkmark.circle.fill" : "eye.slash.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isStaticText)
    }

    private var message: LocalizedStringKey {
        switch confirmation {
        case .sent: return "Thanks! The nickname was reported and hidden."
        case .hiddenNotSignedIn: return "Nickname hidden. Sign in to iCloud to send reports."
        case .hiddenNotSent: return "Nickname hidden. The report couldn't be sent."
        }
    }
}

// MARK: - Rows

private struct OwnRankCard: View {
    let entry: LeaderboardEntry?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your rank").font(.caption).foregroundStyle(.secondary)
                if let entry {
                    Text("#\(LeaderboardRanking.rankLabel(entry.rank))")
                        .font(.title2.bold())
                        .monospacedDigit()
                } else {
                    Text("Not ranked yet").font(.headline)
                    Text("Finish a quiz to get on the board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let entry {
                Text("\(entry.total) pts")
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            Text(entry.nickname)
                .font(entry.isCurrentUser ? .body.bold() : .body)
                .lineLimit(1)
            if entry.isCurrentUser {
                Text("You")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
            Spacer()
            Text("\(entry.total) pts")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rankBadge: some View {
        let label = LeaderboardRanking.rankLabel(entry.rank)
        if let medal = medalColor {
            Image(systemName: "medal.fill")
                .foregroundStyle(medal)
                .frame(width: 40)
                .accessibilityLabel(Text(label))
        } else {
            Text(label)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 40)
                .foregroundStyle(.secondary)
        }
    }

    private var medalColor: Color? {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return nil
        }
    }
}

// MARK: - Labels

extension LeaderboardPeriod {
    var localizedName: String {
        switch self {
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }

    /// "Oct 15", "Week 42", "October 2026" — computed in UTC like the period keys.
    func windowLabel(for date: Date) -> String {
        let utc = TimeZone(identifier: "UTC")!
        switch self {
        case .daily:
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.timeZone = utc
            return date.formatted(style)
        case .weekly:
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = utc
            let week = cal.component(.weekOfYear, from: date)
            return String(localized: "Week \(week)")
        case .monthly:
            var style = Date.FormatStyle.dateTime.month(.wide).year()
            style.timeZone = utc
            return date.formatted(style)
        }
    }
}

#Preview {
    LeaderboardView()
}
