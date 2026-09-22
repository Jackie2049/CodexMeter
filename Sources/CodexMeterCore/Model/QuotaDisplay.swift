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
    /// Windows this short show a clock time instead of a countdown.
    static let statusClockWindowSeconds = 6 * 3600

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

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
        statusSlots(windows: [snapshot.primary, snapshot.secondary].compactMap { $0 })
    }

    private static func statusSlots(windows: [UsageWindow]) -> String? {
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

    /// Full NSStatusItem title: "Codex ⚡ 5小时 57% · 周度 84%".
    /// Auth problems win over data; stale/failed data keeps numbers but
    /// appends a warning marker so old values are never mistaken for live.
    public static func menuBarTitle(snapshot: UsageSnapshot?,
                                    notLoggedIn: Bool,
                                    loginExpired: Bool,
                                    dataWarning: Bool) -> String {
        let components = menuBarTitleComponents(
            snapshot: snapshot,
            notLoggedIn: notLoggedIn,
            loginExpired: loginExpired,
            dataWarning: dataWarning)
        return "\(components.brand) \(components.quota)"
    }

    public struct MenuBarWindowLine: Equatable, Sendable {
        /// Window name: "5小时" / "周度".
        public let label: String
        /// Remaining quota text: "84%" (+" ⚠️" on stale data).
        public let quota: String
        /// Reset countdown: "3 小时 12 分后" / "等待更新".
        public let reset: String
    }

    public struct MenuBarTitleComponents: Equatable, Sendable {
        /// Leftmost element: "Codex ⚡" (or "Codex ⚠️" on auth problems).
        public let brand: String
        /// Legacy combined quota text: "5小时 97% · 周度 83%" (menuBarTitle).
        public let quota: String
        /// One row per present window, shortest window first.
        public let lines: [MenuBarWindowLine]
        /// SF Symbol leading each quota row: bolt normally, warning triangle
        /// when the limit is reached; nil without live data.
        public let symbolName: String?
        /// Legacy combined reset text (menuBarTitle).
        public let resets: String?
    }

    /// Status item content: logo leftmost, one row per window (quota + its
    /// own reset). Auth problems collapse to a single quota line — there
    /// are no windows to count down.
    public static func menuBarTitleComponents(snapshot: UsageSnapshot?,
                                              notLoggedIn: Bool,
                                              loginExpired: Bool,
                                              dataWarning: Bool,
                                              now: Date = Date()) -> MenuBarTitleComponents {
        if notLoggedIn {
            return MenuBarTitleComponents(brand: "Codex ⚠️", quota: "未登录",
                                          lines: [], symbolName: nil, resets: nil)
        }
        if loginExpired {
            return MenuBarTitleComponents(brand: "Codex ⚠️", quota: "过期",
                                          lines: [], symbolName: nil, resets: nil)
        }

        let windows = [snapshot?.primary, snapshot?.secondary].compactMap { $0 }
        var quota = statusSlots(windows: windows) ?? "–"
        if dataWarning && snapshot != nil { quota += " ⚠️" }

        let lines = windows.map { window -> MenuBarWindowLine in
            var lineQuota = "\(window.remainingPercent)%"
            if dataWarning { lineQuota += " ⚠️" }
            // Short windows (≤6h): a clock time beats a countdown. Longer
            // windows keep the natural-Chinese lead; a passed reset waits
            // for fresh data instead of showing a stale clock.
            let remaining = window.resetAt.timeIntervalSince(now)
            let reset: String
            if remaining <= 0 {
                reset = "等待更新"
            } else if window.windowSeconds <= statusClockWindowSeconds {
                reset = clockFormatter.string(from: window.resetAt)
            } else {
                reset = resetLeadText(resetAt: window.resetAt, now: now)
            }
            return MenuBarWindowLine(
                label: longLabel(seconds: window.windowSeconds),
                quota: lineQuota,
                reset: reset)
        }

        let symbolName: String?
        if snapshot == nil {
            symbolName = nil
        } else {
            symbolName = (snapshot?.limitReached ?? false)
                ? "exclamationmark.triangle.fill"
                : "bolt.fill"
        }

        let resets: String? = windows.isEmpty
            ? nil
            : "↻ " + windows.map { resetLeadText(resetAt: $0.resetAt, now: now) }
                .joined(separator: " · ")
        return MenuBarTitleComponents(brand: "Codex ⚡", quota: quota,
                                      lines: lines, symbolName: symbolName, resets: resets)
    }

    /// Natural-Chinese reset countdown WITHOUT the "重置" suffix — used in
    /// the status item's second row where the ↻ prefix carries the meaning.
    /// "2 小时 48 分后" / "6 天 13 小时后" / "等待更新"; no seconds.
    public static func resetLeadText(resetAt: Date, now: Date) -> String {
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "等待更新" }

        let total = Int(remaining.rounded(.up))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days >= 1 {
            return hours > 0 ? "\(days) 天 \(hours) 小时后" : "\(days) 天后"
        }
        if hours >= 1 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分后" : "\(hours) 小时后"
        }
        return "\(max(1, minutes)) 分后"
    }

    /// Natural-Chinese reset countdown: "6 天 13 小时后重置", "3 小时后重置",
    /// "42 分后重置" — no seconds, no "157h46m". A countdown that has reached
    /// zero shows "等待更新": passing zero does NOT mean the quota recovered,
    /// only a fresh snapshot can confirm that.
    public static func resetText(resetAt: Date, now: Date) -> String {
        let lead = resetLeadText(resetAt: resetAt, now: now)
        return lead == "等待更新" ? lead : lead + "重置"
    }
}
