import Foundation

let allTests: [TestEntry] = snapshotTests + authDecisionTests + backoffTests
    + usageClientTests + authStoreTests + notificationTests
    + quotaDisplayTests + stalenessTests + recoveryTrackerTests
    + localizationTests

var failures = 0

for test in allTests {
    do {
        try await test.run()
        print("✅ PASS  \(test.name)")
    } catch {
        failures += 1
        print("❌ FAIL  \(test.name): \(error)")
    }
}

print("----")
print("\(allTests.count - failures)/\(allTests.count) passed")
exit(failures == 0 ? 0 : 1)
