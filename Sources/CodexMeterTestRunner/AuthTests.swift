import Foundation
import CodexMeterCore

func makeJWT(payload: [String: Any]) -> String {
    func b64(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = b64(["alg": "RS256", "typ": "JWT"])
    let body = b64(payload)
    return "\(header).\(body).signature"
}

private func testJWTExtractsExpiry() throws {
    let token = makeJWT(payload: [
        "exp": 1_900_000_000,
        "aud": ["https://api.openai.com/v1"],
    ])
    try expectEqual(JWT.expiry(of: token), Date(timeIntervalSince1970: 1_900_000_000), "exp")
}

private func testJWTReturnsNilForMalformedToken() throws {
    try expectNil(JWT.expiry(of: "garbage"), "single segment")
    try expectNil(JWT.expiry(of: "a.b"), "two segments")
    try expectNil(JWT.expiry(of: "not.json!.sig"), "three garbage segments")
}

private func testJWTReturnsNilWithoutExpClaim() throws {
    let token = makeJWT(payload: ["aud": ["https://api.openai.com/v1"]])
    try expectNil(JWT.expiry(of: token), "no exp claim")
}

private func testRefreshDecision() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)

    // Token valid for 10 days, lead 24h → no refresh needed.
    try expectTrue(
        RefreshDecision.shouldRefresh(tokenExp: now.addingTimeInterval(10 * 86400), now: now, leadTime: 86400) == false,
        "fresh token should not refresh")

    // Token expires in 2h (within 24h lead) → refresh.
    try expectTrue(
        RefreshDecision.shouldRefresh(tokenExp: now.addingTimeInterval(2 * 3600), now: now, leadTime: 86400),
        "token inside lead window should refresh")

    // Already expired → refresh.
    try expectTrue(
        RefreshDecision.shouldRefresh(tokenExp: now.addingTimeInterval(-60), now: now, leadTime: 86400),
        "expired token should refresh")

    // Unparsable exp → defer to the 401 path, don't burn refresh tokens.
    try expectTrue(
        RefreshDecision.shouldRefresh(tokenExp: nil, now: now, leadTime: 86400) == false,
        "nil exp should not proactively refresh")
}

let authDecisionTests: [TestEntry] = [
    TestEntry(name: "JWT.extractsExpiry", run: sync(testJWTExtractsExpiry)),
    TestEntry(name: "JWT.returnsNilForMalformedToken", run: sync(testJWTReturnsNilForMalformedToken)),
    TestEntry(name: "JWT.returnsNilWithoutExpClaim", run: sync(testJWTReturnsNilWithoutExpClaim)),
    TestEntry(name: "RefreshDecision.shouldRefresh", run: sync(testRefreshDecision)),
]
