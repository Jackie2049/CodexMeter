import Foundation
@testable import CodexMeterCore

private func readBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufSize = 4096
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    defer { buf.deallocate() }
    while stream.hasBytesAvailable {
        let n = stream.read(buf, maxLength: bufSize)
        if n <= 0 { break }
        data.append(buf, count: n)
    }
    return data
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func httpResponse(_ status: Int, _ url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
}

private struct TempAuthFile {
    let url: URL

    init(content: String?) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("auth.json")
        if let content {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    var currentContent: String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}

private let fixtureAccessToken = makeJWT(payload: ["exp": 1_900_000_000, "aud": ["https://api.openai.com/v1"]])

private let authFixture: String = """
{
  "auth_mode": "chatgpt",
  "note": "extra top-level keys must survive refresh write-back",
  "tokens": {
    "id_token": "header.payload.sig",
    "access_token": "\(fixtureAccessToken)",
    "refresh_token": "rt-old",
    "account_id": "acct-123"
  },
  "last_refresh": "2026-09-01T00:00:00Z"
}
"""

// MARK: - Tests

private func testStoreReadsCredentials() throws {
    let file = try TempAuthFile(content: authFixture)
    let store = CodexAuthStore(authFileURL: file.url)

    let credentials = try expectNotNil(try store.readCredentials(), "credentials")
    try expectEqual(credentials, CodexCredentials(accessToken: fixtureAccessToken, accountID: "acct-123"), "credentials")
    try expectEqual(try expectNotNil(store.tokenExpiry()), Date(timeIntervalSince1970: 1_900_000_000), "exp")
}

private func testStoreReturnsNilWhenFileMissing() throws {
    let file = try TempAuthFile(content: nil)
    let store = CodexAuthStore(authFileURL: file.url)
    try expectNil(try store.readCredentials(), "missing file")
}

private func testStoreReturnsNilForAPIKeyMode() throws {
    let file = try TempAuthFile(content: #"{"OPENAI_API_KEY": "sk-xyz"}"#)
    let store = CodexAuthStore(authFileURL: file.url)
    try expectNil(try store.readCredentials(), "api-key mode")
}

private func testStoreRefreshPersistsNewTokensAndPreservesOtherKeys() async throws {
    let file = try TempAuthFile(content: authFixture)
    var capturedRequest: URLRequest?
    MockURLProtocol.handler = { request in
        capturedRequest = request
        let body = """
        {"access_token": "at-new", "refresh_token": "rt-new", "id_token": "new-id"}
        """
        return (httpResponse(200, request.url!), Data(body.utf8))
    }
    let store = CodexAuthStore(authFileURL: file.url, session: makeMockSession())

    let credentials = try await store.refresh()

    try expectEqual(credentials.accessToken, "at-new", "refreshed access token")

    // Request shape: official refresh endpoint, JSON grant.
    let request = try expectNotNil(capturedRequest, "request captured")
    try expectEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token", "refresh url")
    try expectEqual(request.httpMethod, "POST", "method")
    try expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", "content type")
    let bodyJSON = try expectNotNil(
        try JSONSerialization.jsonObject(with: readBody(request)) as? [String: String], "body json")
    try expectEqual(bodyJSON["grant_type"], "refresh_token", "grant_type")
    try expectEqual(bodyJSON["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann", "client_id")
    try expectEqual(bodyJSON["refresh_token"], "rt-old", "refresh_token")
    try expectEqual(bodyJSON["scope"], "openid profile email", "scope")

    // Persisted: new tokens visible on next read.
    let reread = try expectNotNil(try store.readCredentials(), "reread")
    try expectEqual(reread.accessToken, "at-new", "reread access token")

    // Unrelated top-level keys survive the write-back.
    let persisted = try expectNotNil(try JSONSerialization.jsonObject(
        with: Data(try expectNotNil(file.currentContent, "file content").utf8)) as? [String: Any], "persisted json")
    try expectEqual(persisted["note"] as? String, "extra top-level keys must survive refresh write-back", "note key")
    try expectEqual(persisted["auth_mode"] as? String, "chatgpt", "auth_mode")

    // File stays private (0600).
    let attrs = try FileManager.default.attributesOfItem(atPath: file.url.path)
    try expectEqual(attrs[.posixPermissions] as? Int, 0o600, "permissions")
}

private func testStoreRefreshRejectionLeavesFileUntouched() async throws {
    let file = try TempAuthFile(content: authFixture)
    MockURLProtocol.handler = { request in
        let body = #"{"error": "invalid_grant"}"#
        return (httpResponse(400, request.url!), Data(body.utf8))
    }
    let store = CodexAuthStore(authFileURL: file.url, session: makeMockSession())

    do {
        _ = try await store.refresh()
        throw TestFailure("expected refreshRejected")
    } catch let error as AuthStoreError {
        try expectEqual(error, AuthStoreError.refreshRejected, "error type")
    }

    // File unchanged — old token still there.
    let reread = try expectNotNil(try store.readCredentials(), "reread")
    try expectEqual(reread.accessToken, fixtureAccessToken, "file untouched")
}

private func testStoreRefreshRequiresRefreshToken() async throws {
    let file = try TempAuthFile(content: #"{"auth_mode": "chatgpt", "tokens": {"access_token": "at", "account_id": "a"}}"#)
    MockURLProtocol.handler = { request in
        (httpResponse(200, request.url!), Data("{}".utf8))
    }
    let store = CodexAuthStore(authFileURL: file.url, session: makeMockSession())

    do {
        _ = try await store.refresh()
        throw TestFailure("expected noRefreshToken")
    } catch let error as AuthStoreError {
        try expectEqual(error, AuthStoreError.noRefreshToken, "error type")
    }
}

let authStoreTests: [TestEntry] = [
    TestEntry(name: "CodexAuthStore.readsCredentials", run: sync(testStoreReadsCredentials)),
    TestEntry(name: "CodexAuthStore.returnsNilWhenFileMissing", run: sync(testStoreReturnsNilWhenFileMissing)),
    TestEntry(name: "CodexAuthStore.returnsNilForAPIKeyMode", run: sync(testStoreReturnsNilForAPIKeyMode)),
    TestEntry(name: "CodexAuthStore.refreshPersistsAndPreserves", run: testStoreRefreshPersistsNewTokensAndPreservesOtherKeys),
    TestEntry(name: "CodexAuthStore.refreshRejectionLeavesFileUntouched", run: testStoreRefreshRejectionLeavesFileUntouched),
    TestEntry(name: "CodexAuthStore.refreshRequiresRefreshToken", run: testStoreRefreshRequiresRefreshToken),
]
