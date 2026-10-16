import CloudKit
import Foundation
import VocabCore

/// `LeaderboardService` backed by the CloudKit public database.
///
/// Schema (record type `PeriodScore`, see docs/CLOUDKIT_SETUP.md):
/// recordName = "<playerId>|<period>|<periodKey>|<targetLanguage>"
/// fields: playerId, nickname, period, periodKey, targetLanguage (String), total (Int64), updatedAt (Date),
///         recentResultIds (String list — last applied quiz ids, makes retries idempotent).
///
/// Reports (record type `NicknameReport`): recordName = "<reporterId>|<reportedRecordName>" so repeated reports
/// by the same player are deduplicated; fields reportedRecordName, reportedNickname, reporterId (String),
/// createdAt (Date). Not world-readable — reviewed in the CloudKit Dashboard.
final class CloudKitLeaderboardService: LeaderboardService, NicknameReportService, @unchecked Sendable {
    static let containerIdentifier = "iCloud.com.alpsenel.wordwidget"
    static let playerIdDefaultsKey = "leaderboard.playerId.v1"

    enum Field {
        static let recordType = "PeriodScore"
        static let playerId = "playerId"
        static let nickname = "nickname"
        static let period = "period"
        static let periodKey = "periodKey"
        static let targetLanguage = "targetLanguage"
        static let total = "total"
        static let updatedAt = "updatedAt"
        static let recentResultIds = "recentResultIds"
    }

    enum ReportField {
        static let recordType = "NicknameReport"
        static let reportedRecordName = "reportedRecordName"
        static let reportedNickname = "reportedNickname"
        static let reporterId = "reporterId"
        static let createdAt = "createdAt"
    }

    private static let maxConflictRetries = 3
    private static let recentResultIdLimit = 30

    // CKContainer(identifier:) traps when the binary lacks the iCloud entitlement (e.g. simulator builds
    // made with CODE_SIGNING_ALLOWED=NO), so it is created lazily, off the launch path, and never at init.
    private let containerFactory: @Sendable () -> CKContainer
    private let containerLock = NSLock()
    private var cachedContainer: CKContainer?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    init(container: (@Sendable () -> CKContainer)? = nil,
         defaults: UserDefaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.containerFactory = container ?? { CKContainer(identifier: CloudKitLeaderboardService.containerIdentifier) }
        self.defaults = defaults
        self.now = now
    }

    private var container: CKContainer {
        containerLock.lock(); defer { containerLock.unlock() }
        if let cachedContainer { return cachedContainer }
        let c = containerFactory()
        cachedContainer = c
        return c
    }

    private var database: CKDatabase { container.publicCloudDatabase }

    // MARK: Identity

    /// The iCloud user record name, cached in the App Group. Throws `.notSignedIn` without an iCloud account.
    func playerId() async throws -> String {
        let status: CKAccountStatus
        do { status = try await container.accountStatus() } catch { throw Self.map(error) }
        guard status == .available else {
            // Account removed or restricted: forget the cached id so a different account never inherits it.
            defaults.removeObject(forKey: Self.playerIdDefaultsKey)
            throw LeaderboardError.notSignedIn
        }
        if let cached = defaults.string(forKey: Self.playerIdDefaultsKey), !cached.isEmpty { return cached }
        do {
            let id = try await container.userRecordID().recordName
            defaults.set(id, forKey: Self.playerIdDefaultsKey)
            return id
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Submit

    func submit(_ result: QuizResult, nickname: String) async throws {
        guard result.score > 0 else { return }
        let player = try await playerId()
        let name = LeaderboardRanking.displayNickname(nickname, playerId: player)
        for period in LeaderboardPeriod.allCases {
            try await add(result, to: period, playerId: player, nickname: name)
        }
    }

    private func add(_ result: QuizResult, to period: LeaderboardPeriod, playerId: String, nickname: String) async throws {
        let periodKey = period.key(for: result.date)
        let recordID = CKRecord.ID(recordName: LeaderboardRanking.recordName(
            playerId: playerId, period: period, periodKey: periodKey, targetLanguage: result.targetLanguage))
        let resultId = result.id.uuidString

        for _ in 0..<Self.maxConflictRetries {
            let record = try await fetchOrCreate(recordID) { record in
                record[Field.playerId] = playerId as CKRecordValue
                record[Field.period] = period.rawValue as CKRecordValue
                record[Field.periodKey] = periodKey as CKRecordValue
                record[Field.targetLanguage] = result.targetLanguage.rawValue as CKRecordValue
                record[Field.total] = Int64(0) as CKRecordValue
            }

            var recent = record[Field.recentResultIds] as? [String] ?? []
            if recent.contains(resultId) { return } // already applied by an earlier, partially failed attempt
            recent.append(resultId)
            if recent.count > Self.recentResultIdLimit { recent.removeFirst(recent.count - Self.recentResultIdLimit) }

            let oldTotal = (record[Field.total] as? Int64) ?? 0
            record[Field.total] = (oldTotal + Int64(result.score)) as CKRecordValue
            record[Field.nickname] = nickname as CKRecordValue
            record[Field.updatedAt] = now() as CKRecordValue
            record[Field.recentResultIds] = recent as CKRecordValue

            do {
                let (saveResults, _) = try await database.modifyRecords(saving: [record], deleting: [],
                                                                        savePolicy: .ifServerRecordUnchanged,
                                                                        atomically: false)
                if let outcome = saveResults[recordID] { _ = try outcome.get() }
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue // someone else (another device) updated it — re-fetch and re-apply
            } catch {
                throw Self.map(error)
            }
        }
        throw LeaderboardError.unknown("Conflict retry limit reached")
    }

    private func fetchOrCreate(_ id: CKRecord.ID, initialize: (CKRecord) -> Void) async throws -> CKRecord {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: Field.recordType, recordID: id)
            initialize(record)
            return record
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Report

    func reportNickname(recordName: String, nickname: String) async throws {
        let reporter = try await playerId()
        let id = CKRecord.ID(recordName: String("\(reporter)|\(recordName)".prefix(255)))
        let record = CKRecord(recordType: ReportField.recordType, recordID: id)
        record[ReportField.reportedRecordName] = recordName as CKRecordValue
        record[ReportField.reportedNickname] = String(nickname.prefix(LeaderboardRanking.maxNicknameLength * 2)) as CKRecordValue
        record[ReportField.reporterId] = reporter as CKRecordValue
        record[ReportField.createdAt] = now() as CKRecordValue
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return // this player already reported that record
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Fetch

    func fetch(period: LeaderboardPeriod, targetLanguage: Language) async throws -> [LeaderboardEntry] {
        let player = try await playerId()
        let periodKey = period.key(for: now())
        let base = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                               Field.period, period.rawValue,
                               Field.periodKey, periodKey,
                               Field.targetLanguage, targetLanguage.rawValue)

        let top: [LeaderboardScoreRow]
        do {
            let query = CKQuery(recordType: Field.recordType, predicate: base)
            query.sortDescriptors = [NSSortDescriptor(key: Field.total, ascending: false)]
            let (matches, _) = try await database.records(matching: query,
                                                          desiredKeys: [Field.playerId, Field.nickname, Field.total],
                                                          resultsLimit: LeaderboardRanking.topLimit)
            top = matches.compactMap { _, outcome in (try? outcome.get()).flatMap(Self.row(from:)) }
        } catch let error as CKError where error.code == .unknownItem {
            return [] // record type not created yet (fresh Development environment)
        } catch {
            throw Self.map(error)
        }

        // Own row for this period.
        let myID = CKRecord.ID(recordName: LeaderboardRanking.recordName(
            playerId: player, period: period, periodKey: periodKey, targetLanguage: targetLanguage))
        var mine: LeaderboardScoreRow?
        do {
            mine = Self.row(from: try await database.record(for: myID))
        } catch let error as CKError where error.code == .unknownItem {
            mine = nil
        } catch {
            mine = nil // non-fatal: show the board without the personal row
        }

        var ahead: Int?
        if let mine, !top.contains(where: { $0.playerId == mine.playerId }) {
            ahead = await countPlayers(above: mine.total, base: base)
        }

        return LeaderboardRanking.entries(top: top, currentPlayerId: player, currentRow: mine, playersAhead: ahead)
    }

    /// Counts records with a higher total (CloudKit has no COUNT; page through ids only), capped.
    private func countPlayers(above total: Int, base: NSPredicate) async -> Int? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            base, NSPredicate(format: "%K > %@", Field.total, NSNumber(value: Int64(total)))
        ])
        let cap = LeaderboardRanking.rankCountCap
        do {
            var (matches, cursor) = try await database.records(matching: CKQuery(recordType: Field.recordType,
                                                                                 predicate: predicate),
                                                               desiredKeys: [],
                                                               resultsLimit: CKQueryOperation.maximumResults)
            var count = matches.count
            while count < cap, let next = cursor {
                (matches, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: [],
                                                               resultsLimit: CKQueryOperation.maximumResults)
                count += matches.count
            }
            return min(count, cap)
        } catch {
            return nil
        }
    }

    private static func row(from record: CKRecord) -> LeaderboardScoreRow? {
        guard let playerId = record[Field.playerId] as? String else { return nil }
        let total = (record[Field.total] as? Int64).map(Int.init) ?? 0
        return LeaderboardScoreRow(playerId: playerId,
                                   nickname: record[Field.nickname] as? String ?? "",
                                   total: total)
    }

    // MARK: Errors

    static func map(_ error: Error) -> LeaderboardError {
        if let error = error as? LeaderboardError { return error }
        guard let ck = error as? CKError else {
            if (error as NSError).domain == NSURLErrorDomain { return .network }
            return .unknown(error.localizedDescription)
        }
        switch ck.code {
        case .notAuthenticated:
            return .notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .operationCancelled:
            return .network
        case .partialFailure:
            if let first = ck.partialErrorsByItemID?.values.first { return map(first) }
            return .unknown(ck.localizedDescription)
        default:
            return .unknown(ck.localizedDescription)
        }
    }
}
