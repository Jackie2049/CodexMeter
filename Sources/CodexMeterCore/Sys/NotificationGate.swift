import Foundation

public struct UsageAlert {
    public let message: String
    public let dedupKey: String
}

/// Decides when a snapshot should produce a notification. Dedup keys are
/// persisted (per window + reset_at + kind) so each threshold fires once
/// per rate-limit window, surviving app restarts. Pure logic — delivery
/// (UNUserNotificationCenter) lives in the app layer.
public final class NotificationGate {
    public static let primaryThreshold = 80
    public static let weeklyThreshold = 90

    private let defaults: UserDefaults

    public init(defaults: UserDefaults, prefix: String = "codexmeter.alerts") {
        self.defaults = defaults
        self.keyPrefix = prefix
    }

    private let keyPrefix: String

    public func evaluate(snapshot: UsageSnapshot, now: Date = Date()) -> [UsageAlert] {
        var alerts: [UsageAlert] = []

        if let primary = snapshot.primary,
           primary.usedPercent >= Self.primaryThreshold,
           let alert = alert(kind: "primary", windowLabel: "5 小时",
                            usedPercent: primary.usedPercent, resetAt: primary.resetAt)
        {
            alerts.append(alert)
        }

        if let secondary = snapshot.secondary,
           secondary.usedPercent >= Self.weeklyThreshold,
           let alert = alert(kind: "weekly", windowLabel: "1 周",
                            usedPercent: secondary.usedPercent, resetAt: secondary.resetAt)
        {
            alerts.append(alert)
        }

        if snapshot.limitReached,
           let alert = alert(kind: "limit", windowLabel: "用量",
                            usedPercent: nil, resetAt: snapshot.primary?.resetAt ?? now)
        {
            alerts.append(alert)
        }

        return alerts
    }

    private func alert(kind: String, windowLabel: String,
                       usedPercent: Int?, resetAt: Date) -> UsageAlert? {
        let key = "\(keyPrefix).\(kind).\(Int(resetAt.timeIntervalSince1970))"
        guard !defaults.bool(forKey: key) else { return nil }
        defaults.set(true, forKey: key)

        let message: String
        switch (kind, usedPercent) {
        case ("limit", _):
            message = "Codex 用量已触顶，等待窗口重置"
        case (_, .some(let percent)):
            message = "Codex \(windowLabel)窗口用量已达 \(percent)%"
        default:
            message = "Codex \(windowLabel)窗口用量告警"
        }
        return UsageAlert(message: message, dedupKey: key)
    }
}
