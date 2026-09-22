import Foundation
import CodexMeterCore

/// Localization: the three languages must produce their own strings for
/// window labels, reset leads, and notification text.
private func testWindowLabelsPerLanguage() throws {
    L10n.language = .zhHans
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.fiveHoursSeconds), "5小时", "zh-Hans 5h")
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.weekSeconds), "周度", "zh-Hans weekly")

    L10n.language = .en
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.fiveHoursSeconds), "5h", "en 5h")
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.weekSeconds), "Weekly", "en weekly")

    L10n.language = .zhHant
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.fiveHoursSeconds), "5小時", "zh-Hant 5h")
    try expectEqual(QuotaDisplay.shortLabel(seconds: QuotaDisplay.weekSeconds), "週度", "zh-Hant weekly")

    L10n.language = .zhHans
}

private func testResetLeadPerLanguage() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let sixDays13h = now.addingTimeInterval(6 * 86400 + 13 * 3600)

    L10n.language = .zhHans
    try expectEqual(QuotaDisplay.resetLeadText(resetAt: sixDays13h, now: now), "6 天 13 小时后", "zh-Hans lead")
    try expectEqual(QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(42 * 60), now: now), "42 分后", "zh-Hans minutes")

    L10n.language = .en
    try expectEqual(QuotaDisplay.resetLeadText(resetAt: sixDays13h, now: now), "in 6d 13h", "en lead")
    try expectEqual(QuotaDisplay.resetLeadText(resetAt: now.addingTimeInterval(42 * 60), now: now), "in 42m", "en minutes")

    L10n.language = .zhHant
    try expectEqual(QuotaDisplay.resetLeadText(resetAt: sixDays13h, now: now), "6 天 13 小時後", "zh-Hant lead")

    L10n.language = .zhHans
}

private func testGateMessagePerLanguage() throws {
    let snapshot = UsageSnapshot(
        planType: "plus", limitReached: false, limitReachedKnown: true,
        primary: UsageWindow(usedPercent: 80, windowSeconds: 18000,
                             resetAt: Date(timeIntervalSince1970: 1_789_972_673)),
        secondary: nil, resetCreditsAvailable: 0, hasCredits: false, creditBalance: "")

    L10n.language = .zhHans
    let zh = NotificationGate(defaults: UserDefaults(suiteName: "l10n-\(UUID().uuidString)")!)
        .evaluate(snapshot: snapshot)
    try expectEqual(zh.count, 1, "zh alert count")
    try expectTrue(zh[0].message.contains("5小时"), "zh names window")
    try expectTrue(zh[0].message.contains("额度剩余"), "zh quota phrasing")

    L10n.language = .en
    let en = NotificationGate(defaults: UserDefaults(suiteName: "l10n-\(UUID().uuidString)")!)
        .evaluate(snapshot: snapshot)
    try expectEqual(en.count, 1, "en alert count")
    try expectTrue(en[0].message.contains("5h"), "en names window")
    try expectTrue(en[0].message.contains("left"), "en quota phrasing")

    L10n.language = .zhHans
}

let localizationTests: [TestEntry] = [
    TestEntry(name: "L10n.windowLabels", run: sync(testWindowLabelsPerLanguage)),
    TestEntry(name: "L10n.resetLead", run: sync(testResetLeadPerLanguage)),
    TestEntry(name: "L10n.gateMessage", run: sync(testGateMessagePerLanguage)),
]
