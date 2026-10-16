import Foundation

/// One pack the client wants from the server. `id` is the deterministic `WordPack.makeID` value.
public struct PackRequest: Codable, Hashable, Sendable {
    public let native: Language
    public let target: Language
    public let difficulty: Difficulty
    public let category: Category
    /// Normalized custom topic, `nil` for a standard-category pack.
    public let topic: String?
    public let page: Int
    /// Target-language terms the user already has for this subject, so the server avoids repeats.
    public var knownTerms: [String]?

    public init(native: Language, target: Language, difficulty: Difficulty, category: Category,
                topic: String?, page: Int, knownTerms: [String]? = nil) {
        self.native = native
        self.target = target
        self.difficulty = difficulty
        self.category = category
        self.topic = topic.map(UserSettings.normalizeTopic)
        self.page = page
        self.knownTerms = knownTerms
    }

    public var id: String {
        WordPack.makeID(native: native, target: target, difficulty: difficulty, category: category, topic: topic, page: page)
    }

    private enum CodingKeys: String, CodingKey { case native, target, difficulty, category, topic, page, knownTerms }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(native.rawValue, forKey: .native)
        try c.encode(target.rawValue, forKey: .target)
        try c.encode(difficulty.rawValue, forKey: .difficulty)
        try c.encode(category.rawValue, forKey: .category)
        try c.encodeIfPresent(topic, forKey: .topic)
        try c.encode(page, forKey: .page)
        if let knownTerms, !knownTerms.isEmpty { try c.encode(knownTerms, forKey: .knownTerms) }
    }
}

/// `{error, message}` body returned by the pack server on non-200 responses.
public struct PackServerErrorBody: Codable, Equatable, Sendable {
    public let error: String
    public let message: String?
}

public enum PackClientError: Error, Equatable, Sendable, LocalizedError {
    /// No StoreKit transaction (and no dev token) to authenticate with.
    case missingToken
    /// 401: the subscription is not valid (expired, revoked, wrong product).
    case subscriptionInvalid(message: String?)
    /// 429: per-install rate limit; `retryAfter` from the `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?, message: String?)
    /// 502: the model failed to produce a valid pack.
    case generationFailed(message: String?)
    /// Any other non-200 status.
    case server(status: Int, message: String?)
    /// Transport failure (offline, DNS, timeout). Holds `URLError.Code.rawValue`.
    case network(code: Int)
    /// 200 with a body that does not decode as `WordPack`.
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingToken: return "No active subscription."
        case .subscriptionInvalid(let m): return m ?? "Subscription is not valid."
        case .rateLimited(_, let m): return m ?? "Too many requests. Try again later."
        case .generationFailed(let m): return m ?? "Word pack generation failed."
        case .server(let s, let m): return m ?? "Server error \(s)."
        case .network: return "The pack server can't be reached."
        case .invalidResponse: return "The pack server sent an invalid response."
        }
    }

    /// True for errors where continuing with the next request in the same sync is pointless.
    public var abortsSync: Bool {
        switch self {
        case .missingToken, .subscriptionInvalid, .rateLimited, .network: return true
        case .generationFailed, .server, .invalidResponse: return false
        }
    }
}

/// Fetches AI word packs. Abstracted for tests and previews.
public protocol PackClient: Sendable {
    func fetchPack(_ request: PackRequest) async throws -> WordPack
}

/// `POST {baseURL}/v1/packs` over URLSession.
public final class URLSessionPackClient: PackClient, @unchecked Sendable {
    public static let requestTimeout: TimeInterval = 120

    /// Returns the bearer token value (without the "Bearer " prefix), or `nil` when not subscribed.
    public typealias TokenProvider = @Sendable () async -> String?

    private let baseURL: URL
    private let installID: String
    private let tokenProvider: TokenProvider
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public init(baseURL: URL, installID: String, session: URLSession? = nil, tokenProvider: @escaping TokenProvider) {
        self.baseURL = baseURL
        self.installID = installID
        self.tokenProvider = tokenProvider
        self.session = session ?? URLSession(configuration: Self.defaultConfiguration())
    }

    /// Generation takes 30–90 s on the server, so allow 120 s per request.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout + 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }

    public func makeURLRequest(_ request: PackRequest, token: String) throws -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent("packs"))
        r.httpMethod = "POST"
        r.timeoutInterval = Self.requestTimeout
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(installID, forHTTPHeaderField: "X-Vocabi-Install")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = try encoder.encode(request)
        return r
    }

    public func fetchPack(_ request: PackRequest) async throws -> WordPack {
        guard let token = await tokenProvider(), !token.isEmpty else { throw PackClientError.missingToken }
        let urlRequest = try makeURLRequest(request, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw PackClientError.network(code: error.code.rawValue)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PackClientError.network(code: URLError.Code.unknown.rawValue)
        }
        guard let http = response as? HTTPURLResponse else { throw PackClientError.invalidResponse }
        let message = (try? decoder.decode(PackServerErrorBody.self, from: data))?.message
        switch http.statusCode {
        case 200:
            guard let pack = try? decoder.decode(WordPack.self, from: data) else { throw PackClientError.invalidResponse }
            return Self.normalized(pack, for: request)
        case 401, 403: throw PackClientError.subscriptionInvalid(message: message)
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw PackClientError.rateLimited(retryAfter: retry, message: message)
        case 502: throw PackClientError.generationFailed(message: message)
        default: throw PackClientError.server(status: http.statusCode, message: message)
        }
    }

    /// Stores the pack under the id the client asked for, so the planner's "already stored" check
    /// cannot loop on a server that formats ids differently.
    static func normalized(_ pack: WordPack, for request: PackRequest) -> WordPack {
        guard pack.id != request.id else { return pack }
        return WordPack(id: request.id, nativeLanguage: pack.nativeLanguage, targetLanguage: pack.targetLanguage,
                        difficulty: pack.difficulty, category: pack.category, topic: pack.topic,
                        entries: pack.entries, createdAt: pack.createdAt, version: pack.version)
    }
}

/// Stable random id per install, sent as `X-Vocabi-Install` for server-side rate limiting.
/// Lives in the App Group and deliberately survives "Reset progress".
public enum PackInstallID {
    public static let key = "pack.installID.v1"

    public static func current(defaults: UserDefaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard) -> String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: key)
        return id
    }
}
