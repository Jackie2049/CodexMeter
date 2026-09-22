import Foundation
import CodexMeterCore

/// Fixture based on a real (sanitized) wham/usage response captured 2026-09-21.
private let realFixture = """
{
  "user_id": "user-***", "account_id": "***", "email": "***", "plan_type": "plus",
  "rate_limit": {
    "allowed": true, "limit_reached": false,
    "primary_window":   {"used_percent": 33, "limit_window_seconds": 18000, "reset_after_seconds": 16481, "reset_at": 1789972673},
    "secondary_window": {"used_percent": 5,  "limit_window_seconds": 604800, "reset_after_seconds": 603281, "reset_at": 1790559473}
  },
  "code_review_rate_limit": null, "additional_rate_limits": null,
  "model_usage": {"gpt-6-astra": {"available": true, "available_at": null, "credits_would_enable": false}},
  "credits": {"has_credits": false, "unlimited": false, "overage_limit_reached": false, "balance": "0", "approx_local_messages": [0,0], "approx_cloud_messages": [0,0]},
  "spend_control": {"reached": false, "individual_limit": null},
  "rate_limit_reached_type": null, "promo": null,
  "rate_limit_reset_credits": {"available_count": 1, "applicable_available_count": 0}
}
"""

private func testParsesRealResponseFixture() throws {
    let snapshot = try UsageSnapshot.parse(Data(realFixture.utf8))

    try expectEqual(snapshot.planType, "plus", "planType")
    try expectTrue(snapshot.limitReached == false, "limitReached should be false")

    let primary = try expectNotNil(snapshot.primary, "primary window")
    try expectEqual(primary.usedPercent, 33, "primary.usedPercent")
    try expectEqual(primary.windowSeconds, 18000, "primary.windowSeconds")
    try expectEqual(primary.resetAt, Date(timeIntervalSince1970: 1_789_972_673), "primary.resetAt")

    let secondary = try expectNotNil(snapshot.secondary, "secondary window")
    try expectEqual(secondary.usedPercent, 5, "secondary.usedPercent")
    try expectEqual(secondary.windowSeconds, 604800, "secondary.windowSeconds")
    try expectEqual(secondary.resetAt, Date(timeIntervalSince1970: 1_790_559_473), "secondary.resetAt")

    try expectEqual(snapshot.resetCreditsAvailable, 1, "resetCreditsAvailable")
    try expectTrue(snapshot.hasCredits == false, "hasCredits")
    try expectEqual(snapshot.creditBalance, "0", "creditBalance")
}

private func testParsesLimitReachedAndCredits() throws {
    let json = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": false, "limit_reached": true,
        "primary_window":   {"used_percent": 100, "limit_window_seconds": 18000, "reset_after_seconds": 60, "reset_at": 1789972673},
        "secondary_window": {"used_percent": 91,  "limit_window_seconds": 604800, "reset_after_seconds": 600, "reset_at": 1790559473}
      },
      "credits": {"has_credits": true, "unlimited": false, "overage_limit_reached": false, "balance": "12.34", "approx_local_messages": [0,0], "approx_cloud_messages": [0,0]},
      "rate_limit_reset_credits": {"available_count": 0, "applicable_available_count": 0}
    }
    """
    let snapshot = try UsageSnapshot.parse(Data(json.utf8))

    try expectEqual(snapshot.planType, "pro", "planType")
    try expectTrue(snapshot.limitReached, "limitReached")
    try expectEqual(snapshot.primary?.usedPercent, 100, "primary.usedPercent")
    try expectEqual(snapshot.secondary?.usedPercent, 91, "secondary.usedPercent")
    try expectTrue(snapshot.hasCredits, "hasCredits")
    try expectEqual(snapshot.creditBalance, "12.34", "creditBalance")
    try expectEqual(snapshot.resetCreditsAvailable, 0, "resetCreditsAvailable")
}

private func testToleratesMissingOptionalFields() throws {
    let json = """
    { "rate_limit": { "allowed": true, "limit_reached": false } }
    """
    let snapshot = try UsageSnapshot.parse(Data(json.utf8))

    try expectNil(snapshot.planType, "planType")
    try expectNil(snapshot.primary, "primary")
    try expectNil(snapshot.secondary, "secondary")
    try expectTrue(snapshot.limitReached == false, "limitReached")
    try expectEqual(snapshot.resetCreditsAvailable, 0, "resetCreditsAvailable")
    try expectTrue(snapshot.hasCredits == false, "hasCredits")
    try expectTrue(snapshot.creditBalance.isEmpty, "creditBalance")
}

private func testLimitReachedKnownFlag() throws {
    // Field present (even when false) → known.
    let known = try UsageSnapshot.parse(
        Data(#"{"rate_limit": {"allowed": true, "limit_reached": false}}"#.utf8))
    try expectTrue(known.limitReachedKnown, "present limit_reached is known")

    // rate_limit object missing entirely → unknown; display still defaults
    // to false, but the recovery tracker must not read it as confirmed.
    let unknown = try UsageSnapshot.parse(Data(#"{"plan_type": "plus"}"#.utf8))
    try expectTrue(unknown.limitReachedKnown == false, "missing field is unknown")
    try expectTrue(unknown.limitReached == false, "display default stays false")
}

let snapshotTests: [TestEntry] = [
    TestEntry(name: "UsageSnapshot.parsesRealResponseFixture", run: sync(testParsesRealResponseFixture)),
    TestEntry(name: "UsageSnapshot.parsesLimitReachedAndCredits", run: sync(testParsesLimitReachedAndCredits)),
    TestEntry(name: "UsageSnapshot.toleratesMissingOptionalFields", run: sync(testToleratesMissingOptionalFields)),
    TestEntry(name: "UsageSnapshot.limitReachedKnownFlag", run: sync(testLimitReachedKnownFlag)),
]
