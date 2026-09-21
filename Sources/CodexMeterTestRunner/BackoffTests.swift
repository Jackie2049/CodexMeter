import Foundation
@testable import CodexMeterCore

private func testBackoffPolicy() throws {
    // No failures → no retry delay.
    try expectNil(BackoffPolicy.delay(afterConsecutiveFailures: 0), "zero failures")

    // 30s doubling, capped at 600s.
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 1)), 30.0, "1 failure")
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 2)), 60.0, "2 failures")
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 3)), 120.0, "3 failures")
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 5)), 480.0, "5 failures")
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 6)), 600.0, "capped at 600")
    try expectEqual(try expectNotNil(BackoffPolicy.delay(afterConsecutiveFailures: 50)), 600.0, "stays capped")
}

let backoffTests: [TestEntry] = [
    TestEntry(name: "BackoffPolicy.delay", run: sync(testBackoffPolicy)),
]
