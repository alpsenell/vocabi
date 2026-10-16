import XCTest
@testable import VocabCore

/// Local stub "server": answers every request on a stubbed URLSession from a handler.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        do {
            guard let handler = Self.handler else { throw URLError(.cannotConnectToHost) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class PackClientTests: XCTestCase {
    private let request = PackRequest(native: .turkish, target: .english, difficulty: .beginner,
                                      category: .dailyLife, topic: "Sailing", page: 2, knownTerms: ["boat"])

    private func makeClient(token: String? = "jws.token") -> URLSessionPackClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionPackClient(baseURL: URL(string: "https://packs.test")!, installID: "install-1",
                                    session: URLSession(configuration: config), tokenProvider: { token })
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    private let packJSON = """
    {"id":"ai-tr-en-beginner-t_sailing-2","nativeLanguage":"tr","targetLanguage":"en","difficulty":"beginner",
     "category":"dailyLife","topic":"sailing","createdAt":"2026-10-16T10:00:00Z","version":3,
     "entries":[{"id":"ai-tr-en-beginner-t_sailing-2-001","category":"dailyLife","difficulty":"beginner","topic":"sailing",
       "terms":{"en":"mast","tr":"direk"},"definitions":{"en":"A tall pole on a boat.","tr":"Teknedeki uzun direk."},
       "examples":{"en":"The mast is tall."}}]}
    """

    func testSuccessSendsContractAndDecodesPack() async throws {
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data(self.packJSON.utf8)) }
        let pack = try await makeClient().fetchPack(request)
        XCTAssertEqual(pack.id, "ai-tr-en-beginner-t_sailing-2")
        XCTAssertEqual(pack.version, 3)
        XCTAssertEqual(pack.entries.first?.term(in: .english), "mast")
        XCTAssertTrue(pack.entries.first?.isAIGenerated ?? false)
        XCTAssertEqual(pack.createdAt, ISO8601DateFormatter().date(from: "2026-10-16T10:00:00Z"))

        let sent = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://packs.test/v1/packs")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer jws.token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Vocabi-Install"), "install-1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.timeoutInterval, 120)

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body["native"] as? String, "tr")
        XCTAssertEqual(body["target"] as? String, "en")
        XCTAssertEqual(body["difficulty"] as? String, "beginner")
        XCTAssertEqual(body["category"] as? String, "dailyLife")
        XCTAssertEqual(body["topic"] as? String, "sailing")
        XCTAssertEqual(body["page"] as? Int, 2)
        XCTAssertEqual(body["knownTerms"] as? [String], ["boat"])
    }

    func testStandardRequestOmitsTopicAndEmptyKnownTerms() throws {
        let r = PackRequest(native: .english, target: .french, difficulty: .advanced, category: .health, topic: nil, page: 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["native", "target", "difficulty", "category", "page"])
        XCTAssertEqual(r.id, "ai-en-fr-advanced-health-1")
    }

    func testMismatchedServerIDIsStoredUnderRequestedID() async throws {
        let json = packJSON.replacingOccurrences(of: "\"id\":\"ai-tr-en-beginner-t_sailing-2\"", with: "\"id\":\"something-else\"")
        StubURLProtocol.handler = { _ in (200, [:], Data(json.utf8)) }
        let pack = try await makeClient().fetchPack(request)
        XCTAssertEqual(pack.id, request.id)
    }

    func testErrorMapping() async {
        let cases: [(Int, [String: String], PackClientError)] = [
            (401, [:], .subscriptionInvalid(message: "nope")),
            (429, ["Retry-After": "30"], .rateLimited(retryAfter: 30, message: "nope")),
            (502, [:], .generationFailed(message: "nope")),
            (500, [:], .server(status: 500, message: "nope")),
        ]
        for (status, headers, expected) in cases {
            StubURLProtocol.handler = { _ in (status, headers, Data(#"{"error":"x","message":"nope"}"#.utf8)) }
            do {
                _ = try await makeClient().fetchPack(request)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? PackClientError, expected)
            }
        }
    }

    func testInvalidBodyAndNetworkFailureAndMissingToken() async {
        StubURLProtocol.handler = { _ in (200, [:], Data("{}".utf8)) }
        await assertThrows(.invalidResponse) { try await self.makeClient().fetchPack(self.request) }

        StubURLProtocol.handler = { _ in throw URLError(.cannotFindHost) }
        await assertThrows(.network(code: URLError.Code.cannotFindHost.rawValue)) {
            try await self.makeClient().fetchPack(self.request)
        }

        StubURLProtocol.handler = { _ in XCTFail("must not hit network without a token"); return (200, [:], Data()) }
        await assertThrows(.missingToken) { try await self.makeClient(token: nil).fetchPack(self.request) }
    }

    func testDefaultConfigurationTimeouts() {
        let c = URLSessionPackClient.defaultConfiguration()
        XCTAssertEqual(c.timeoutIntervalForRequest, 120)
        XCTAssertGreaterThanOrEqual(c.timeoutIntervalForResource, 120)
    }

    func testAbortsSync() {
        XCTAssertTrue(PackClientError.network(code: -1).abortsSync)
        XCTAssertTrue(PackClientError.subscriptionInvalid(message: nil).abortsSync)
        XCTAssertFalse(PackClientError.generationFailed(message: nil).abortsSync)
    }

    func testInstallIDIsStable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let a = PackInstallID.current(defaults: defaults)
        XCTAssertEqual(PackInstallID.current(defaults: defaults), a)
        XCTAssertNotNil(UUID(uuidString: a))
    }

    private func assertThrows(_ expected: PackClientError, _ body: () async throws -> WordPack,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PackClientError, expected, file: file, line: line)
        }
    }
}
