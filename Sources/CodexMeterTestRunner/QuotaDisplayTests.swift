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
    try expectEqual(QuotaDisplay.shortLabel(seconds: 18000), "5小时", "5h short")
    try expectEqual(QuotaDisplay.shortLabel(seconds: 604800), "周度", "week short")
    try expectEqual(QuotaDisplay.shortLabel(seconds: 3600), "窗口", "unknown short")
    try expectEqual(QuotaDisplay.longLabel(seconds: 18000), "5小时", "5h long")
    try expectEqual(QuotaDisplay.longLabel(seconds: 604800), "周度", "week long")
    try expectEqual(QuotaDisplay.longLabel(seconds: 3600), "窗口", "unknown long")
}

// MARK: - status bar text

private func testStatusBarTextPlusShape() throws {
    // Classic plus-plan shape: 5h primary + weekly secondary.
    let snap = snapshot(
        primary: window(used: 33, seconds: 18000),
        secondary: window(used: 5, seconds: 604800))
    try expectEqual(QuotaDisplay.statusBarText(snap), "5小时 67% · 周度 95%", "plus shape")
}

private func testStatusBarTextProShapeSingleWindow() throws {
    // Live Pro shape (2026-09-21): primary IS the weekly window, secondary null.
    let snap = snapshot(
        primary: window(used: 0, seconds: 604800),
        secondary: nil)
    try expectEqual(QuotaDisplay.statusBarText(snap), "5小时 — · 周度 100%", "pro shape, missing 5h slot")
}

private func testStatusBarTextMissingWeeklySlot() throws {
    let snap = snapshot(
        primary: window(used: 33, seconds: 18000),
        secondary: nil)
    try expectEqual(QuotaDisplay.statusBarText(snap), "5小时 67% · 周度 —", "missing weekly slot")
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
    try expectEqual(QuotaDisplay.statusBarText(reached), "5小时 0% · 周度 50%", "limitReached keeps numbers")
}

// MARK: - natural-Chinese reset countdown

private func testResetTextNaturalChinese() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)

    try expectEqual(
        QuotaDisplay.resetText(resetAt: now.addingTimeInterval(6 * 86400 + 13 * 3600), now: now),
        "6 天 13 小时后重置", "days + hours")
    try expectEqual(
        QuotaDisplay.resetText(resetAt: now.addingTimeInterval(48 * 3600), now: now),
        "2 天后重置", "whole days drop hours")
    try expectEqual(
        QuotaDisplay.resetText(resetAt: now.addingTimeInterval(3 * 3600 + 5 * 60), now: now),
        "3 小时 5 分后重置", "hours + minutes")
    try expectEqual(
        QuotaDisplay.resetText(resetAt: now.addingTimeInterval(42 * 60), now: now),
        "42 分后重置", "minutes only")
    try expectEqual(
        QuotaDisplay.resetText(resetAt: now.addingTimeInterval(30), now: now),
        "1 分后重置", "under a minute rounds up, no seconds shown")
}

private func testResetTextZeroMeansWaitingNotRecovered() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    // Countdown at zero is NOT recovery — only a fresh snapshot confirms it.
    try expectEqual(QuotaDisplay.resetText(resetAt: now, now: now), "等待更新", "at zero")
    try expectEqual(QuotaDisplay.resetText(resetAt: now.addingTimeInterval(-60), now: now), "等待更新", "past zero")
}

// MARK: - composed menu bar title (NSStatusItem)

private func testMenuBarTitle() throws {
    let ok = snapshot(
        primary: window(used: 43, seconds: 18000),
        secondary: window(used: 16, seconds: 604800))

    try expectEqual(
        QuotaDisplay.menuBarTitle(snapshot: ok, notLoggedIn: false, loginExpired: false, dataWarning: false),
        "Codex ⚡ 5小时 57% · 周度 84%", "healthy state")

    try expectEqual(
        QuotaDisplay.menuBarTitle(snapshot: nil, notLoggedIn: true, loginExpired: false, dataWarning: false),
        "Codex ⚠️ 未登录", "no login")
    try expectEqual(
        QuotaDisplay.menuBarTitle(snapshot: ok, notLoggedIn: false, loginExpired: true, dataWarning: false),
        "Codex ⚠️ 过期", "expired login wins over data")

    try expectEqual(
        QuotaDisplay.menuBarTitle(snapshot: ok, notLoggedIn: false, loginExpired: false, dataWarning: true),
        "Codex ⚡ 5小时 57% · 周度 84% ⚠️", "stale/failed data appends warning marker")
    try expectEqual(
        QuotaDisplay.menuBarTitle(snapshot: nil, notLoggedIn: false, loginExpired: false, dataWarning: false),
        "Codex ⚡ –", "no data yet")
}

// MARK: - two-line menu bar title (quota row + reset row)

private func testResetLeadText() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)

    try expectEqual(
        QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(2 * 3600 + 48 * 60), now: now),
        "2 小时 48 分后", "hours + minutes, no 重置 suffix")
    try expectEqual(
        QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(6 * 86400 + 13 * 3600), now: now),
        "6 天 13 小时后", "days + hours")
    try expectEqual(
        QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(42 * 60), now: now),
        "42 分后", "minutes only")
    try expectEqual(
        QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(-30), now: now),
        "等待更新", "zero countdown waits for fresh data")
}

private func testMenuBarTitleComponentsTwoLines() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let healthy = snapshot(
        primary: window(used: 3, seconds: 18000,
                        resetAt: now.addingTimeInterval(2 * 3600 + 48 * 60)),
        secondary: window(used: 17, seconds: 604800,
                          resetAt: now.addingTimeInterval(6 * 86400 + 13 * 3600)))

    let components = QuotaDisplay.menuBarTitleComponents(
        snapshot: healthy, notLoggedIn: false, loginExpired: false, dataWarning: false, now: now)
    try expectEqual(components.brand, "Codex ⚡", "brand sits leftmost")
    try expectEqual(components.quota, "5小时 97% · 周度 83%", "top line: remaining quota")
    try expectEqual(components.symbolName, "bolt.fill", "bolt trails the quota line")
    try expectEqual(
        components.resets,
        "↻ 2 小时 48 分后 · 6 天 13 小时后",
        "bottom line: reset times, dot-separated, reset symbol prefix")

    // Limit reached → warning symbol replaces the bolt.
    let limited = snapshot(
        primary: window(used: 100, seconds: 18000,
                        resetAt: now.addingTimeInterval(2 * 3600)),
        secondary: window(used: 50, seconds: 604800,
                          resetAt: now.addingTimeInterval(6 * 86400)),
        limitReached: true)
    try expectEqual(
        QuotaDisplay.menuBarTitleComponents(
            snapshot: limited, notLoggedIn: false, loginExpired: false, dataWarning: false, now: now)
            .symbolName,
        "exclamationmark.triangle.fill", "limit reached swaps bolt for warning")

    // Auth problems keep a single line.
    let loggedOut = QuotaDisplay.menuBarTitleComponents(
        snapshot: healthy, notLoggedIn: true, loginExpired: false, dataWarning: false, now: now)
    try expectEqual(loggedOut.brand, "Codex ⚠️", "auth problem brand")
    try expectEqual(loggedOut.quota, "未登录", "auth problem quota text")
    try expectNil(loggedOut.symbolName, "no meter symbol without data")
    try expectNil(loggedOut.resets, "no reset row when logged out")

    // No data yet → single line.
    let noData = QuotaDisplay.menuBarTitleComponents(
        snapshot: nil, notLoggedIn: false, loginExpired: false, dataWarning: false, now: now)
    try expectEqual(noData.brand, "Codex ⚡", "no data brand")
    try expectEqual(noData.quota, "–", "no data quota text")
    try expectNil(noData.symbolName, "no meter symbol without data")
    try expectNil(noData.resets, "no reset row without windows")

    // Stale data keeps both rows (numbers + warning marker stay).
    let stale = QuotaDisplay.menuBarTitleComponents(
        snapshot: healthy, notLoggedIn: false, loginExpired: false, dataWarning: true, now: now)
    try expectEqual(stale.quota, "5小时 97% · 周度 83% ⚠️", "warning marker on quota line")
    try expectEqual(stale.symbolName, "bolt.fill", "bolt stays on stale data")
    try expectNotNil(stale.resets, "reset row survives data warning")
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
    TestEntry(name: "QuotaDisplay.resetTextNaturalChinese", run: sync(testResetTextNaturalChinese)),
    TestEntry(name: "QuotaDisplay.resetTextZeroMeansWaiting", run: sync(testResetTextZeroMeansWaitingNotRecovered)),
    TestEntry(name: "QuotaDisplay.menuBarTitle", run: sync(testMenuBarTitle)),
    TestEntry(name: "QuotaDisplay.resetLeadText", run: sync(testResetLeadText)),
    TestEntry(name: "QuotaDisplay.menuBarTitleComponents", run: sync(testMenuBarTitleComponentsTwoLines)),
]
