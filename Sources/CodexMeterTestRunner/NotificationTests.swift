import Foundation
import CodexMeterCore

private func snapshot(
    primaryPercent: Int = 10,
    secondaryPercent: Int = 5,
    primaryResetAt: Date = Date(timeIntervalSince1970: 1_789_972_673),
    secondaryResetAt: Date = Date(timeIntervalSince1970: 1_790_559_473),
    limitReached: Bool = false
) -> UsageSnapshot {
    UsageSnapshot(
        planType: "plus",
        limitReached: limitReached,
        primary: UsageWindow(usedPercent: primaryPercent, windowSeconds: 18000, resetAt: primaryResetAt),
        secondary: UsageWindow(usedPercent: secondaryPercent, windowSeconds: 604800, resetAt: secondaryResetAt),
        resetCreditsAvailable: 0,
        hasCredits: false,
        creditBalance: "")
}

private func makeGate() -> NotificationGate {
    let suite = "test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return NotificationGate(defaults: defaults)
}

private func testGateFiresPrimaryAtEightyPercentOnce() throws {
    let gate = makeGate()

    let first = gate.evaluate(snapshot: snapshot(primaryPercent: 80))
    try expectEqual(first.count, 1, "first crossing fires")
    try expectTrue(first[0].message.contains("5 小时"), "message mentions 5h window")

    // Still above threshold within the same window → silent.
    let second = gate.evaluate(snapshot: snapshot(primaryPercent: 85))
    try expectEqual(second.count, 0, "repeat within same window is silent")
}

private func testGateRefiresAfterWindowReset() throws {
    let gate = makeGate()
    _ = gate.evaluate(snapshot: snapshot(primaryPercent: 90))

    // New window = new reset_at → allowed to fire again.
    let next = gate.evaluate(snapshot: snapshot(
        primaryPercent: 95,
        primaryResetAt: Date(timeIntervalSince1970: 1_900_000_000)))
    try expectEqual(next.count, 1, "new window fires again")
}

private func testGateSilentBelowThreshold() throws {
    let gate = makeGate()
    let fired = gate.evaluate(snapshot: snapshot(primaryPercent: 79, secondaryPercent: 89))
    try expectEqual(fired.count, 0, "below thresholds")
}

private func testGateFiresWeeklyAtNinetyPercent() throws {
    let gate = makeGate()
    let fired = gate.evaluate(snapshot: snapshot(secondaryPercent: 90))
    try expectEqual(fired.count, 1, "weekly crossing fires")
    try expectTrue(fired[0].message.contains("1 周"), "message mentions weekly window")
}

private func testGateFiresOnLimitReached() throws {
    let gate = makeGate()
    let fired = gate.evaluate(snapshot: snapshot(limitReached: true))
    try expectEqual(fired.count, 1, "limit reached fires")
    try expectTrue(fired[0].message.contains("已触顶"), "message mentions limit reached")

    // Deduped like the others.
    let again = gate.evaluate(snapshot: snapshot(limitReached: true))
    try expectEqual(again.count, 0, "limit-reached deduped")
}

private func testGateFiresBothWindowsIndependently() throws {
    let gate = makeGate()
    let fired = gate.evaluate(snapshot: snapshot(primaryPercent: 85, secondaryPercent: 95))
    try expectEqual(fired.count, 2, "both windows fire together")
}

private func testGateDedupSurvivesRestart() throws {
    // Same UserDefaults suite simulates an app restart.
    let suite = "test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let first = NotificationGate(defaults: defaults)
    try expectEqual(first.evaluate(snapshot: snapshot(primaryPercent: 80)).count, 1, "fires before restart")

    let second = NotificationGate(defaults: defaults)
    try expectEqual(second.evaluate(snapshot: snapshot(primaryPercent: 80)).count, 0, "silent after restart")
}

let notificationTests: [TestEntry] = [
    TestEntry(name: "NotificationGate.firesPrimaryAtEightyOnce", run: sync(testGateFiresPrimaryAtEightyPercentOnce)),
    TestEntry(name: "NotificationGate.refiresAfterWindowReset", run: sync(testGateRefiresAfterWindowReset)),
    TestEntry(name: "NotificationGate.silentBelowThreshold", run: sync(testGateSilentBelowThreshold)),
    TestEntry(name: "NotificationGate.firesWeeklyAtNinety", run: sync(testGateFiresWeeklyAtNinetyPercent)),
    TestEntry(name: "NotificationGate.firesOnLimitReached", run: sync(testGateFiresOnLimitReached)),
    TestEntry(name: "NotificationGate.firesBothWindowsIndependently", run: sync(testGateFiresBothWindowsIndependently)),
    TestEntry(name: "NotificationGate.dedupSurvivesRestart", run: sync(testGateDedupSurvivesRestart)),
]
