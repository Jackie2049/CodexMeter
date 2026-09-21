import Foundation

public struct UsageAlert {
    public let message: String
    public let dedupKey: String
}

/// Decides when a snapshot should produce a notification. Windows are
/// identified by duration (not API field position); thresholds apply to
/// REMAINING quota: ≤20% for short (≤6h) windows, ≤10% for longer ones.
/// Dedup keys are persisted (per duration + reset_at + kind) so each
/// threshold fires once per rate-limit window, surviving app restarts.
/// Pure logic — delivery and merging live in the app layer.
public final class NotificationGate {
    public static let shortWindowRemainingThreshold = 20
    public static let longWindowRemainingThreshold = 10
    static let shortWindowMaxSeconds = 6 * 3600

    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults, prefix: String = "codexmeter.alerts") {
        self.defaults = defaults
        self.keyPrefix = prefix
    }

    public func evaluate(snapshot: UsageSnapshot, now: Date = Date()) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        for window in [snapshot.primary, snapshot.secondary].compactMap({ $0 }) {
            let threshold = window.windowSeconds <= Self.shortWindowMaxSeconds
                ? Self.shortWindowRemainingThreshold
                : Self.longWindowRemainingThreshold
            if window.remainingPercent <= threshold,
               let alert = quotaAlert(window: window, threshold: threshold) {
                alerts.append(alert)
            }
        }

        if snapshot.limitReached,
           let alert = limitReachedAlert(snapshot: snapshot, now: now) {
            alerts.append(alert)
        }

        return alerts
    }

    private func quotaAlert(window: UsageWindow, threshold: Int) -> UsageAlert? {
        let key = "\(keyPrefix).window.\(window.windowSeconds).\(Int(window.resetAt.timeIntervalSince1970))"
        guard !defaults.bool(forKey: key) else { return nil }
        defaults.set(true, forKey: key)

        let label = QuotaDisplay.longLabel(seconds: window.windowSeconds)
        let resetText = Self.resetText(resetAt: window.resetAt, windowSeconds: window.windowSeconds)
        return UsageAlert(
            message: "Codex \(label) 额度剩余 \(window.remainingPercent)%，\(resetText)重置",
            dedupKey: key)
    }

    private func limitReachedAlert(snapshot: UsageSnapshot, now: Date) -> UsageAlert? {
        // Global flag — no window attribution or exact recovery time.
        let anchor = snapshot.primary?.resetAt ?? snapshot.secondary?.resetAt ?? now
        let key = "\(keyPrefix).limit.\(Int(anchor.timeIntervalSince1970))"
        guard !defaults.bool(forKey: key) else { return nil }
        defaults.set(true, forKey: key)
        return UsageAlert(message: "Codex 用量已触顶，等待窗口重置", dedupKey: key)
    }

    static func resetText(resetAt: Date, windowSeconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(windowSeconds <= shortWindowMaxSeconds ? "HH:mm" : "MMMd")
        return formatter.string(from: resetAt)
    }
}
