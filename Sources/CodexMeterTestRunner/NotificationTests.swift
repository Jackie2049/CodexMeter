import Foundation
import CodexMeterCore

private func snapshot(
    primaryPercent: Int? = nil,
    secondaryPercent: Int? = nil,
    primarySeconds: Int = 18000,
    secondarySeconds: Int = 604800,
    primaryResetAt: Date = Date(timeIntervalSince1970: 1_789_972_673),
    secondaryResetAt: Date = Date(timeIntervalSince1970: 1_790_559_473),
    limitReached: Bool = false
) -> UsageSnapshot {
    UsageSnapshot(
        planType: "plus",
        limitReached: limitReached,
        primary: primaryPercent.map {
            UsageWindow(usedPercent: $0, windowSeconds: primarySeconds, resetAt: primaryResetAt)
        },
        secondary: secondaryPercent.map {
            UsageWindow(usedPercent: $0, windowSeconds: secondarySeconds, resetAt: secondaryResetAt)
        },
        resetCreditsAvailable: 0,
        hasCredits: false,
        creditBalance: "")
}

private func makeGate() -> NotificationGate {
    let suite = "gate-\(UUID().uuidString)"
    return NotificationGate(defaults: UserDefaults(suiteName: suite)!)
}

private func testShortWindowFiresAtRemaining20Once() throws {
    let gate = makeGate()

    // used 80 → remaining 20 → at threshold → fires.
    let first = gate.evaluate(snapshot: snapshot(primaryPercent: 80))
    try expectEqual(first.count, 1, "first crossing fires")
    try expectTrue(first[0].message.contains("5 小时"), "message names the window")
    try expectTrue(first[0].message.contains("剩余 20%"), "message carries remaining quota")

    // Still at/below threshold within the same window → silent.
    let second = gate.evaluate(snapshot: snapshot(primaryPercent: 90))
    try expectEqual(second.count, 0, "repeat within same window is silent")

    // used 79 → remaining 21 → above threshold → silent.
    let fresh = makeGate()
    try expectEqual(fresh.evaluate(snapshot: snapshot(primaryPercent: 79)).count, 0, "above threshold silent")
}

private func testLongWindowFiresAtRemaining10() throws {
    let gate = makeGate()

    // used 90 → remaining 10 → fires; used 89 → remaining 11 → silent.
    let fired = gate.evaluate(snapshot: snapshot(secondaryPercent: 90))
    try expectEqual(fired.count, 1, "weekly crossing fires")
    try expectTrue(fired[0].message.contains("1 周"), "message names weekly window")
    try expectTrue(fired[0].message.contains("剩余 10%"), "message carries remaining quota")

    let fresh = makeGate()
    try expectEqual(fresh.evaluate(snapshot: snapshot(secondaryPercent: 89)).count, 0, "remaining 11 silent")
}

private func testProShapeSingleWeeklyWindow() throws {
    // Live Pro shape: weekly window sits in the primary slot, no 5h window.
    let gate = makeGate()
    let fired = gate.evaluate(snapshot: snapshot(
        primaryPercent: 95, secondaryPercent: nil, primarySeconds: 604800))
    try expectEqual(fired.count, 1, "long-window threshold fires regardless of field position")
    try expectTrue(fired[0].message.contains("1 周"), "label derived from duration")
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
    let suite = "gate-\(UUID().uuidString)"
    let first = NotificationGate(defaults: UserDefaults(suiteName: suite)!)
    try expectEqual(first.evaluate(snapshot: snapshot(primaryPercent: 80)).count, 1, "fires before restart")

    let second = NotificationGate(defaults: UserDefaults(suiteName: suite)!)
    try expectEqual(second.evaluate(snapshot: snapshot(primaryPercent: 80)).count, 0, "silent after restart")
}

let notificationTests: [TestEntry] = [
    TestEntry(name: "NotificationGate.shortWindowAtRemaining20", run: sync(testShortWindowFiresAtRemaining20Once)),
    TestEntry(name: "NotificationGate.longWindowAtRemaining10", run: sync(testLongWindowFiresAtRemaining10)),
    TestEntry(name: "NotificationGate.proShapeSingleWindow", run: sync(testProShapeSingleWeeklyWindow)),
    TestEntry(name: "NotificationGate.refiresAfterWindowReset", run: sync(testGateRefiresAfterWindowReset)),
    TestEntry(name: "NotificationGate.firesOnLimitReached", run: sync(testGateFiresOnLimitReached)),
    TestEntry(name: "NotificationGate.bothWindowsIndependent", run: sync(testGateFiresBothWindowsIndependently)),
    TestEntry(name: "NotificationGate.dedupSurvivesRestart", run: sync(testGateDedupSurvivesRestart)),
]
