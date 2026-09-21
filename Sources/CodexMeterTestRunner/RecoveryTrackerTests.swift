import Foundation
import CodexMeterCore

private func makeTracker(_ suite: String) -> RecoveryTracker {
    RecoveryTracker(defaults: UserDefaults(suiteName: suite)!)
}

private func testNoEventOnHealthyStart() throws {
    let tracker = makeTracker("rec-\(UUID().uuidString)")
    try expectNil(tracker.record(limitReached: false), "healthy from the start → no event")
}

private func testEnteredThenRecoveredTransitions() throws {
    let tracker = makeTracker("rec-\(UUID().uuidString)")

    try expectNil(tracker.record(limitReached: false), "healthy → nil")
    try expectEqual(tracker.record(limitReached: true), RecoveryEvent.entered, "limit hit → entered")
    try expectNil(tracker.record(limitReached: true), "still limited → nil")
    try expectEqual(tracker.record(limitReached: false), RecoveryEvent.recovered, "confirmed recovery → recovered")
    try expectNil(tracker.record(limitReached: false), "still healthy → nil")
}

private func testRecoveryRequiresConfirmedNewData() throws {
    // The tracker only ever reacts to fresh snapshots; there is no
    // timer-based recovery path. Feed the sequence a UI countdown would see:
    // reset time passing does NOT produce a snapshot → no recovery event.
    let tracker = makeTracker("rec-\(UUID().uuidString)")
    _ = tracker.record(limitReached: true)
    try expectNil(tracker.record(limitReached: true), "no new data → no recovery, even after reset passes")
}

private func testSurvivesRestart() throws {
    let suite = "rec-\(UUID().uuidString)"
    let first = makeTracker(suite)
    _ = first.record(limitReached: true)

    // App restarts (new instance, same defaults) while still limited.
    let second = makeTracker(suite)
    try expectEqual(second.record(limitReached: false), RecoveryEvent.recovered, "restart keeps was-limit-reached state")
}

private func testReentryAfterRecovery() throws {
    let tracker = makeTracker("rec-\(UUID().uuidString)")
    _ = tracker.record(limitReached: true)
    _ = tracker.record(limitReached: false)
    try expectEqual(tracker.record(limitReached: true), RecoveryEvent.entered, "second limit episode re-arms")
    try expectEqual(tracker.record(limitReached: false), RecoveryEvent.recovered, "second recovery fires once")
}

let recoveryTrackerTests: [TestEntry] = [
    TestEntry(name: "RecoveryTracker.noEventOnHealthyStart", run: sync(testNoEventOnHealthyStart)),
    TestEntry(name: "RecoveryTracker.transitions", run: sync(testEnteredThenRecoveredTransitions)),
    TestEntry(name: "RecoveryTracker.recoveryNeedsNewData", run: sync(testRecoveryRequiresConfirmedNewData)),
    TestEntry(name: "RecoveryTracker.survivesRestart", run: sync(testSurvivesRestart)),
    TestEntry(name: "RecoveryTracker.reentry", run: sync(testReentryAfterRecovery)),
]
