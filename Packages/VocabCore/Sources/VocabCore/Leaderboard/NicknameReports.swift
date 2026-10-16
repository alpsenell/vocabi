import Foundation

/// Sends "Report nickname" requests to the backend (CloudKit `NicknameReport` records in the app).
public protocol NicknameReportService: Sendable {
    /// Saves a report for the `PeriodScore` record `recordName` showing `nickname`.
    /// Throws `LeaderboardError.notSignedIn` without an iCloud account.
    func reportNickname(recordName: String, nickname: String) async throws
}

/// Record names the current user reported, persisted in the App Group so the rows stay hidden for them.
///
/// Record names have the form "<playerId>|<period>|<periodKey>|<targetLanguage>"; a report hides that
/// player in every period and language.
public final class ReportedNicknameStore: @unchecked Sendable {
    public static let defaultsKey = "leaderboard.reportedRecords.v1"
    /// Oldest reports are forgotten beyond this many.
    public static let limit = 500

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var recordNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    public func add(_ recordName: String) {
        lock.lock(); defer { lock.unlock() }
        var names = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        guard !names.contains(recordName) else { return }
        names.append(recordName)
        if names.count > Self.limit { names.removeFirst(names.count - Self.limit) }
        defaults.set(names, forKey: Self.defaultsKey)
    }

    /// Player ids of reported records.
    public var hiddenPlayerIds: Set<String> {
        Set(recordNames.compactMap { name in
            let id = name.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
            return (id?.isEmpty ?? true) ? nil : id
        })
    }

    /// Removes reported players. The current user's own row is never hidden.
    public func filter(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        let hidden = hiddenPlayerIds
        guard !hidden.isEmpty else { return entries }
        return entries.filter { $0.isCurrentUser || !hidden.contains($0.id) }
    }
}

/// Hides a reported row locally first, then tries to send the report.
public struct NicknameReporter: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Report saved on the server and row hidden locally.
        case sent
        /// Row hidden locally, but the report could not be sent (e.g. `.notSignedIn`, `.network`).
        case hiddenOnly(LeaderboardError)
    }

    private let service: NicknameReportService
    private let store: ReportedNicknameStore

    public init(service: NicknameReportService, store: ReportedNicknameStore) {
        self.service = service
        self.store = store
    }

    /// The `PeriodScore` record name shown by `entry` in the given window.
    public static func recordName(for entry: LeaderboardEntry, period: LeaderboardPeriod, date: Date,
                                  targetLanguage: Language) -> String {
        LeaderboardRanking.recordName(playerId: entry.id, period: period, periodKey: period.key(for: date),
                                      targetLanguage: targetLanguage)
    }

    public func report(recordName: String, nickname: String) async -> Outcome {
        store.add(recordName)
        do {
            try await service.reportNickname(recordName: recordName, nickname: nickname)
            return .sent
        } catch let error as LeaderboardError {
            return .hiddenOnly(error)
        } catch {
            return .hiddenOnly(.unknown(error.localizedDescription))
        }
    }

    public func filter(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        store.filter(entries)
    }
}
