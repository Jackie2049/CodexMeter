import Foundation

public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String
    public let accountID: String

    public init(accessToken: String, accountID: String) {
        self.accessToken = accessToken
        self.accountID = accountID
    }
}

public enum UsageClientError: Error, Equatable {
    case unauthorized
    case http(status: Int)
}

public protocol URLSessioning {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

/// Talks to the ChatGPT backend endpoint the Codex client itself uses
/// for the "剩余用量" panel.
public final class CodexUsageClient {
    private let baseURL: URL
    private let session: URLSessioning

    public init(baseURL: URL = URL(string: "https://chatgpt.com/backend-api")!,
                session: URLSessioning = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchUsage(credentials: CodexCredentials) async throws -> UsageSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("wham/usage"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.http(status: -1)
        }
        switch http.statusCode {
        case 200:
            return try UsageSnapshot.parse(data)
        case 401:
            throw UsageClientError.unauthorized
        case let status:
            throw UsageClientError.http(status: status)
        }
    }
}
