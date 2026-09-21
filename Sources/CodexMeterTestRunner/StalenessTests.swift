import Foundation
import CodexMeterCore

private func testStalenessBoundaries() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let interval: TimeInterval = 60

    try expectTrue(Staleness.isStale(lastRefresh: nil, now: now, interval: interval), "no data yet → stale")
    try expectTrue(Staleness.isStale(lastRefresh: now.addingTimeInterval(-119), now: now, interval: interval) == false, "just under 2× → fresh")
    try expectTrue(Staleness.isStale(lastRefresh: now.addingTimeInterval(-120), now: now, interval: interval) == false, "exactly 2× → still fresh (must exceed)")
    try expectTrue(Staleness.isStale(lastRefresh: now.addingTimeInterval(-121), now: now, interval: interval), "just over 2× → stale")
}

let stalenessTests: [TestEntry] = [
    TestEntry(name: "Staleness.boundaries", run: sync(testStalenessBoundaries)),
]
