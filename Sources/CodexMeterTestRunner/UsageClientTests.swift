import Foundation
@testable import CodexMeterCore

// MARK: - Mock URLProtocol (test-only)

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: TestFailure("no mock handler set"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func httpResponse(_ status: Int, _ url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
}

private func okBody() -> Data {
    let json = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true, "limit_reached": false,
        "primary_window":   {"used_percent": 33, "limit_window_seconds": 18000, "reset_after_seconds": 16481, "reset_at": 1789972673},
        "secondary_window": {"used_percent": 5,  "limit_window_seconds": 604800, "reset_after_seconds": 603281, "reset_at": 1790559473}
      },
      "credits": {"has_credits": false, "balance": "0"},
      "rate_limit_reset_credits": {"available_count": 1}
    }
    """
    return Data(json.utf8)
}

private let credentials = CodexCredentials(accessToken: "tok-abc", accountID: "acct-123")

// MARK: - Tests

private func testClientBuildsRequestWithAuthHeadersAndParses() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.handler = { request in
        capturedRequest = request
        return (httpResponse(200, request.url!), okBody())
    }
    let client = CodexUsageClient(session: makeMockSession())

    let snapshot = try await client.fetchUsage(credentials: credentials)

    let request = try expectNotNil(capturedRequest, "request captured")
    try expectEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage", "url")
    try expectEqual(request.httpMethod, "GET", "method")
    try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abc", "auth header")
    try expectEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "acct-123", "account header")
    try expectEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", "accept header")

    try expectEqual(snapshot.primary?.usedPercent, 33, "parsed primary")
    try expectEqual(snapshot.planType, "plus", "parsed plan")
}

private func testClientThrowsUnauthorizedOn401() async throws {
    MockURLProtocol.handler = { request in
        (httpResponse(401, request.url!), Data("unauthorized".utf8))
    }
    let client = CodexUsageClient(session: makeMockSession())

    do {
        _ = try await client.fetchUsage(credentials: credentials)
        throw TestFailure("expected unauthorized error")
    } catch let error as UsageClientError {
        try expectEqual(error, UsageClientError.unauthorized, "should be unauthorized")
    }
}

private func testClientThrowsHTTPErrorOn500() async throws {
    MockURLProtocol.handler = { request in
        (httpResponse(500, request.url!), Data("boom".utf8))
    }
    let client = CodexUsageClient(session: makeMockSession())

    do {
        _ = try await client.fetchUsage(credentials: credentials)
        throw TestFailure("expected http error")
    } catch let error as UsageClientError {
        try expectEqual(error, UsageClientError.http(status: 500), "should carry status")
    }
}

let usageClientTests: [TestEntry] = [
    TestEntry(name: "CodexUsageClient.buildsRequestAndParses", run: testClientBuildsRequestWithAuthHeadersAndParses),
    TestEntry(name: "CodexUsageClient.throwsUnauthorizedOn401", run: testClientThrowsUnauthorizedOn401),
    TestEntry(name: "CodexUsageClient.throwsHTTPErrorOn500", run: testClientThrowsHTTPErrorOn500),
]
