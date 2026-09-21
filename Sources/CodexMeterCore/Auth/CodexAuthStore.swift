import Foundation

public enum AuthStoreError: Error, Equatable {
    case notChatGPTAuth
    case noRefreshToken
    case refreshRejected
    case missingNewAccessToken
}

/// Reads (and silently refreshes) the ChatGPT OAuth credentials the Codex
/// client keeps in `~/.codex/auth.json`. Write-backs preserve every unknown
/// top-level key and the file's 0600 permissions, and go through an atomic
/// tmp+rename so a concurrent Codex client never sees a partial file.
public final class CodexAuthStore {
    public static let defaultAuthFileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")

    static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let authFileURL: URL
    private let session: URLSessioning

    public init(authFileURL: URL = CodexAuthStore.defaultAuthFileURL,
                session: URLSessioning = URLSession.shared) {
        self.authFileURL = authFileURL
        self.session = session
    }

    /// nil when the file is missing or the user is in API-key mode —
    /// the caller should surface "run codex login" instead of an error.
    public func readCredentials() throws -> CodexCredentials? {
        guard let tokens = try readTokens() else { return nil }
        guard let accessToken = tokens["access_token"] as? String,
              let accountID = tokens["account_id"] as? String
        else { return nil }
        return CodexCredentials(accessToken: accessToken, accountID: accountID)
    }

    public func tokenExpiry() throws -> Date? {
        guard let tokens = try readTokens(),
              let accessToken = tokens["access_token"] as? String
        else { return nil }
        return JWT.expiry(of: accessToken)
    }

    /// POSTs the refresh grant and atomically persists the rotated tokens.
    public func refresh() async throws -> CodexCredentials {
        guard let tokens = try readTokens(),
              let refreshToken = tokens["refresh_token"] as? String
        else { throw AuthStoreError.noRefreshToken }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthStoreError.refreshRejected
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthStoreError.refreshRejected
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = payload["access_token"] as? String
        else { throw AuthStoreError.missingNewAccessToken }
        let newRefreshToken = payload["refresh_token"] as? String ?? refreshToken

        try persistTokens(accessToken: newAccessToken, refreshToken: newRefreshToken)
        return CodexCredentials(accessToken: newAccessToken, accountID: tokens["account_id"] as? String ?? "")
    }

    // MARK: - File handling

    private func readTokens() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: authFileURL),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AuthStoreError.notChatGPTAuth }
        return document["tokens"] as? [String: Any]
    }

    private func persistTokens(accessToken: String, refreshToken: String) throws {
        guard let data = try? Data(contentsOf: authFileURL),
              var document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AuthStoreError.notChatGPTAuth }

        var tokens = document["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = refreshToken
        document["tokens"] = tokens
        document["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let newData = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys])

        let tmpURL = authFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".auth.json.codexmeter-\(UUID().uuidString).tmp")
        try newData.write(to: tmpURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        _ = try FileManager.default.replaceItemAt(authFileURL, withItemAt: tmpURL)
    }
}
