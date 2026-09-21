import Foundation

/// Minimal JWT payload reader — we only need the `exp` claim to decide
/// when to proactively refresh the Codex access token. No signature
/// verification: the token came from the local Codex client's own store.
public enum JWT {
    public static func expiry(of token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        guard let payloadData = base64URLDecode(String(segments[1])) else { return nil }
        guard let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = claims["exp"] as? Double ?? (claims["exp"] as? Int).map(Double.init)
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }
}

public enum RefreshDecision {
    /// Refresh when the token expires within `leadTime` (or already expired).
    /// A nil `tokenExp` means we couldn't parse it — defer to the 401 path
    /// rather than burning a refresh token proactively.
    public static func shouldRefresh(tokenExp: Date?, now: Date, leadTime: TimeInterval) -> Bool {
        guard let tokenExp else { return false }
        return tokenExp.timeIntervalSince(now) <= leadTime
    }
}
