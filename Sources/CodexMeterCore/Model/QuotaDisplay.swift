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

    public static func shortLabel(seconds: Int) -> String {
        switch seconds {
        case fiveHoursSeconds: "5h"
        case weekSeconds: "Weekly"
        default: "窗口"
        }
    }

    public static func longLabel(seconds: Int) -> String {
        switch seconds {
        case fiveHoursSeconds: "5 小时"
        case weekSeconds: "Weekly"
        default: "窗口"
        }
    }

    /// Menu bar text: `5h 67% · 周 95%`. Slots are duration-based; a missing
    /// slot shows `—`. limitReached never replaces the numbers — it is
    /// surfaced separately (icon / badge / card). nil = nothing to show.
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
}
