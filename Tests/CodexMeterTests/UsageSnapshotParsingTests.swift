import Foundation
import Testing
@testable import CodexMeter

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

@Suite struct UsageSnapshotParsingTests {

    @Test func parsesRealResponseFixture() throws {
        let snapshot = try UsageSnapshot.parse(Data(realFixture.utf8))

        #expect(snapshot.planType == "plus")
        #expect(snapshot.limitReached == false)

        let primary = try #require(snapshot.primary)
        #expect(primary.usedPercent == 33)
        #expect(primary.windowSeconds == 18000)
        #expect(primary.resetAt == Date(timeIntervalSince1970: 1_789_972_673))

        let secondary = try #require(snapshot.secondary)
        #expect(secondary.usedPercent == 5)
        #expect(secondary.windowSeconds == 604800)
        #expect(secondary.resetAt == Date(timeIntervalSince1970: 1_790_559_473))

        #expect(snapshot.resetCreditsAvailable == 1)
        #expect(snapshot.hasCredits == false)
        #expect(snapshot.creditBalance == "0")
    }

    @Test func parsesLimitReachedAndCredits() throws {
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

        #expect(snapshot.planType == "pro")
        #expect(snapshot.limitReached == true)
        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.secondary?.usedPercent == 91)
        #expect(snapshot.hasCredits == true)
        #expect(snapshot.creditBalance == "12.34")
        #expect(snapshot.resetCreditsAvailable == 0)
    }

    @Test func toleratesMissingOptionalFields() throws {
        let json = """
        { "rate_limit": { "allowed": true, "limit_reached": false } }
        """
        let snapshot = try UsageSnapshot.parse(Data(json.utf8))

        #expect(snapshot.planType == nil)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.limitReached == false)
        #expect(snapshot.resetCreditsAvailable == 0)
        #expect(snapshot.hasCredits == false)
        #expect(snapshot.creditBalance.isEmpty)
    }
}
