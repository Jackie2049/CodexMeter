import Foundation
import CodexMeterCore

private func window(used: Int, seconds: Int, resetAt: Date = Date(timeIntervalSince1970: 1_789_972_673)) -> UsageWindow {
    UsageWindow(usedPercent: used, windowSeconds: seconds, resetAt: resetAt)
}

private func snapshot(
    primary: UsageWindow?, secondary: UsageWindow?, limitReached: Bool = false
) -> UsageSnapshot {
    UsageSnapshot(
        planType: "pro", limitReached: limitReached,
        primary: primary, secondary: secondary,
        resetCreditsAvailable: 0, hasCredits: false, creditBalance: "")
}

// MARK: - remainingPercent

private func testRemainingPercent() throws {
    try expectEqual(window(used: 0, seconds: 18000).remainingPercent, 100, "fresh window")
    try expectEqual(window(used: 33, seconds: 18000).remainingPercent, 67, "partial usage")
    try expectEqual(window(used: 100, seconds: 18000).remainingPercent, 0, "exhausted")
    try expectEqual(window(used: 130, seconds: 18000).remainingPercent, 0, "clamped low")
    try expectEqual(window(used: -5, seconds: 18000).remainingPercent, 100, "clamped high")
}

// MARK: - tier thresholds (on remaining)

private func testQuotaTierBoundaries() throws {
    try expectEqual(QuotaThresholds.tier(forRemaining: 31), QuotaTier.normal, "31 → normal")
    try expectEqual(QuotaThresholds.tier(forRemaining: 30), QuotaTier.warning, "30 → warning")
    try expectEqual(QuotaThresholds.tier(forRemaining: 11), QuotaTier.warning, "11 → warning")
    try expectEqual(QuotaThresholds.tier(forRemaining: 10), QuotaTier.critical, "10 → critical")
    try expectEqual(QuotaThresholds.tier(forRemaining: 0), QuotaTier.critical, "0 → critical")
}

// MARK: - dynamic window labels

private func testWindowLabels() throws {
    try expectEqual(QuotaDisplay.shortLabel(seconds: 18000), "5h", "5h short")
    try expectEqual(QuotaDisplay.shortLabel(seconds: 604800), "Weekly", "week short")
    try expectEqual(QuotaDisplay.shortLabel(seconds: 3600), "窗口", "unknown short")
    try expectEqual(QuotaDisplay.longLabel(seconds: 18000), "5 小时", "5h long")
    try expectEqual(QuotaDisplay.longLabel(seconds: 604800), "Weekly", "week long")
    try expectEqual(QuotaDisplay.longLabel(seconds: 3600), "窗口", "unknown long")
}

// MARK: - status bar text

private func testStatusBarTextPlusShape() throws {
    // Classic plus-plan shape: 5h primary + weekly secondary.
    let snap = snapshot(
        primary: window(used: 33, seconds: 18000),
        secondary: window(used: 5, seconds: 604800))
    try expectEqual(QuotaDisplay.statusBarText(snap), "5h 67% · Weekly 95%", "plus shape")
}

private func testStatusBarTextProShapeSingleWindow() throws {
    // Live Pro shape (2026-09-21): primary IS the weekly window, secondary null.
    let snap = snapshot(
        primary: window(used: 0, seconds: 604800),
        secondary: nil)
    try expectEqual(QuotaDisplay.statusBarText(snap), "5h — · Weekly 100%", "pro shape, missing 5h slot")
}

private func testStatusBarTextMissingWeeklySlot() throws {
    let snap = snapshot(
        primary: window(used: 33, seconds: 18000),
        secondary: nil)
    try expectEqual(QuotaDisplay.statusBarText(snap), "5h 67% · Weekly —", "missing weekly slot")
}

private func testStatusBarTextNoWindows() throws {
    try expectNil(QuotaDisplay.statusBarText(snapshot(primary: nil, secondary: nil)), "no windows")
}

private func testStatusBarTextIgnoresLimitReached() throws {
    // limitReached must NOT replace the numbers with "顶" (v1 bug).
    let reached = snapshot(
        primary: window(used: 100, seconds: 18000),
        secondary: window(used: 50, seconds: 604800),
        limitReached: true)
    try expectEqual(QuotaDisplay.statusBarText(reached), "5h 0% · Weekly 50%", "limitReached keeps numbers")
}

let quotaDisplayTests: [TestEntry] = [
    TestEntry(name: "UsageWindow.remainingPercent", run: sync(testRemainingPercent)),
    TestEntry(name: "QuotaThresholds.tierBoundaries", run: sync(testQuotaTierBoundaries)),
    TestEntry(name: "QuotaDisplay.windowLabels", run: sync(testWindowLabels)),
    TestEntry(name: "QuotaDisplay.statusBarPlusShape", run: sync(testStatusBarTextPlusShape)),
    TestEntry(name: "QuotaDisplay.statusBarProShape", run: sync(testStatusBarTextProShapeSingleWindow)),
    TestEntry(name: "QuotaDisplay.statusBarMissingWeekly", run: sync(testStatusBarTextMissingWeeklySlot)),
    TestEntry(name: "QuotaDisplay.statusBarNoWindows", run: sync(testStatusBarTextNoWindows)),
    TestEntry(name: "QuotaDisplay.statusBarIgnoresLimitReached", run: sync(testStatusBarTextIgnoresLimitReached)),
]
