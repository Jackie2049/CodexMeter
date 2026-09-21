import Foundation

public extension UsageWindow {
    /// "剩余额度" semantics — the number users actually care about.
    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

public enum QuotaTier: Equatable {
    case normal
    case warning
    case critical
}

public enum QuotaThresholds {
    public static func tier(forRemaining remaining: Int) -> QuotaTier {
        if remaining <= 10 { return .critical }
        if remaining <= 30 { return .warning }
        return .normal
    }
}

/// Window identity comes from `limit_window_seconds`, never from the API's
/// primary/secondary field positions — OpenAI reshuffled the fields when the
/// account moved to Pro (primary became the weekly window, secondary null).
public enum QuotaDisplay {
    static let fiveHoursSeconds = 18000
    static let weekSeconds = 604800

    /// Canonical window names, used everywhere (status bar, panel, alerts):
    /// 18000 → "5小时", 604800 → "周度".
    public static func shortLabel(seconds: Int) -> String {
        switch seconds {
        case fiveHoursSeconds: "5小时"
        case weekSeconds: "周度"
        default: "窗口"
        }
    }

    public static func longLabel(seconds: Int) -> String {
        shortLabel(seconds: seconds)
    }

    /// Menu bar text: `5小时 67% · 周度 95%`. Slots are duration-based; a
    /// missing slot shows `—`. limitReached never replaces the numbers — it
    /// is surfaced separately (icon / banner). nil = nothing to show.
    public static func statusBarText(_ snapshot: UsageSnapshot) -> String? {
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        guard !windows.isEmpty else { return nil }

        func slot(_ seconds: Int) -> String {
            if let match = windows.first(where: { $0.windowSeconds == seconds }) {
                return "\(shortLabel(seconds: seconds)) \(match.remainingPercent)%"
            }
            // Standard slots always render; a plan without that window
            // shows an em dash in its place.
            return "\(shortLabel(seconds: seconds)) —"
        }

        var parts: [String] = [slot(fiveHoursSeconds), slot(weekSeconds)]
        for extra in windows where extra.windowSeconds != fiveHoursSeconds && extra.windowSeconds != weekSeconds {
            parts.append("\(shortLabel(seconds: extra.windowSeconds)) \(extra.remainingPercent)%")
        }
        return parts.joined(separator: " · ")
    }

    /// Natural-Chinese reset countdown: "6 天 13 小时后重置", "3 小时后重置",
    /// "42 分后重置" — no seconds, no "157h46m". A countdown that has reached
    /// zero shows "等待更新": passing zero does NOT mean the quota recovered,
    /// only a fresh snapshot can confirm that.
    public static func resetText(resetAt: Date, now: Date) -> String {
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "等待更新" }

        let total = Int(remaining.rounded(.up))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days >= 1 {
            return hours > 0 ? "\(days) 天 \(hours) 小时后重置" : "\(days) 天后重置"
        }
        if hours >= 1 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分后重置" : "\(hours) 小时后重置"
        }
        return "\(max(1, minutes)) 分后重置"
    }
}
