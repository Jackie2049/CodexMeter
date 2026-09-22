import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"
    case zhHant = "zh-Hant"

    /// Shown in its own script in the language picker.
    public var displayName: String {
        switch self {
        case .zhHans: "简体中文"
        case .en: "English"
        case .zhHant: "繁體中文"
        }
    }
}

extension Notification.Name {
    public static let codexMeterLanguageChanged = Notification.Name("codexMeterLanguageChanged")
}

/// All user-visible strings, resolved per `L10n.language`. The app syncs
/// this from its persisted language setting at launch and on change.
public enum L10n {
    /// Language used until the user picks one: follow the system, mapping
    /// Chinese variants, everything else to English.
    public static let systemDefault: AppLanguage = {
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return .zhHant
        }
        if preferred.hasPrefix("zh") { return .zhHans }
        if preferred.hasPrefix("en") { return .en }
        return .zhHans
    }()

    public static var language: AppLanguage = .zhHans

    static func str(_ zhHans: String, _ en: String, _ zhHant: String) -> String {
        switch language {
        case .zhHans: zhHans
        case .en: en
        case .zhHant: zhHant
        }
    }

    // MARK: - Windows

    public enum Window {
        public static func short(seconds: Int) -> String {
            switch seconds {
            case QuotaDisplay.fiveHoursSeconds: str("5小时", "5h", "5小時")
            case QuotaDisplay.weekSeconds: str("周度", "Weekly", "週度")
            default: str("窗口", "Window", "視窗")
            }
        }

        public static func long(seconds: Int) -> String { short(seconds: seconds) }
    }

    // MARK: - Reset countdowns

    public enum Reset {
        static func unit(days: Int, hours: Int, minutes: Int) -> String {
            if days >= 1 {
                return hours > 0
                    ? str("\(days) 天 \(hours) 小时后", "in \(days)d \(hours)h", "\(days) 天 \(hours) 小時後")
                    : str("\(days) 天后", "in \(days)d", "\(days) 天後")
            }
            if hours >= 1 {
                return minutes > 0
                    ? str("\(hours) 小时 \(minutes) 分后", "in \(hours)h \(minutes)m", "\(hours) 小時 \(minutes) 分後")
                    : str("\(hours) 小时后", "in \(hours)h", "\(hours) 小時後")
            }
            return str("\(max(1, minutes)) 分后", "in \(max(1, minutes))m", "\(max(1, minutes)) 分後")
        }

        public static var waiting: String { str("等待更新", "Waiting for update", "等待更新") }
        public static var suffix: String { str("重置", "", "重置") }
    }

    // MARK: - Status item

    public enum Status {
        public static var notLoggedIn: String { str("未登录", "Not logged in", "未登入") }
        public static var expired: String { str("过期", "Expired", "已過期") }
        public static var noData: String { "–" }
        public static var separator: String { "·" }
        public static var resetMarkAccessibility: String { str("重置", "Reset", "重置") }
    }

    // MARK: - Panel

    public enum Panel {
        public static var notLoggedIn: String { str("未登录 · 请在终端运行 codex login", "Not logged in · run `codex login` in Terminal", "未登入 · 請在終端機執行 codex login") }
        public static var loginExpired: String { str("登录已过期 · 请重新运行 codex login", "Login expired · run `codex login` again", "登入已過期 · 請重新執行 codex login") }
        public static var limitReached: String { str("额度已触顶，等待窗口重置", "Limit reached — waiting for the window to reset", "額度已觸頂，等待視窗重置") }
        public static func updateFailed(dataAge: String) -> String {
            str("更新失败 · 数据来自 \(dataAge)", "Update failed · data from \(dataAge)", "更新失敗 · 資料來自 \(dataAge)")
        }
        public static var stale: String { str("数据待更新", "Data may be stale", "資料待更新") }
        public static var remaining: String { str("剩余", "Left", "剩餘") }
        public static func resetAt(_ time: String) -> String {
            str("重置于 \(time)", "Resets at \(time)", "重置於 \(time)")
        }
        public static var fetching: String { str("获取用量中…", "Fetching usage…", "取得用量中…") }
        public static var noData: String { str("暂无数据", "No data yet", "暫無資料") }
        public static func resetCredits(_ count: Int) -> String {
            str("\(count) 次可用重置", "\(count) reset credits available", "\(count) 次可用重置")
        }
        public static var justUpdated: String { str("刚刚更新", "Updated just now", "剛剛更新") }
        public static func updatedAgo(_ ago: String) -> String {
            str("\(ago)更新", "Updated \(ago)", "\(ago)更新")
        }
        public static func lastSuccessfulUpdate(_ ago: String) -> String {
            str("上次成功更新 \(ago)", "Last success \(ago)", "上次成功更新 \(ago)")
        }
        public static var notUpdatedYet: String { str("尚未更新", "Not updated yet", "尚未更新") }
        public static var refreshNow: String { str("立即刷新", "Refresh now", "立即重新整理") }
        public static var openCodex: String { str("打开 Codex", "Open Codex", "開啟 Codex") }
        public static var retry: String { str("重试", "Retry", "重試") }
        public static var settings: String { str("设置", "Settings", "設定") }
        public static var moreActions: String { str("更多操作", "More actions", "更多動作") }
        public static var remainingCaption: String { str("剩余", "Left", "剩餘") }
    }

    // MARK: - Gear menu

    public enum Menu {
        public static var pollInterval: String { str("轮询间隔", "Poll interval", "輪詢間隔") }
        public static func interval(_ seconds: Int) -> String {
            switch seconds {
            case 30: str("30 秒", "30s", "30 秒")
            case 60: str("1 分钟", "1m", "1 分鐘")
            case 300: str("5 分钟", "5m", "5 分鐘")
            default: str("\(seconds) 秒", "\(seconds)s", "\(seconds) 秒")
            }
        }
        public static var thresholdAlerts: String { str("用量阈值通知", "Usage threshold alerts", "用量閾值通知") }
        public static var resetReminder: String { str("重置提醒", "Recovery reminder", "重置提醒") }
        public static var launchAtLogin: String { str("开机自启", "Launch at login", "開機自動啟動") }
        public static var language: String { str("语言", "Language", "語言") }
        public static var quit: String { str("退出 CodexMeter", "Quit CodexMeter", "結束 CodexMeter") }
    }

    // MARK: - Notifications

    public enum Notif {
        public static func quotaAlert(window: String, percent: Int, resetTime: String) -> String {
            str("Codex \(window) 额度剩余 \(percent)%，\(resetTime)重置",
                "Codex \(window) quota at \(percent)% left, resets at \(resetTime)",
                "Codex \(window) 額度剩餘 \(percent)%，\(resetTime)重置")
        }
        public static var limitReached: String {
            str("Codex 用量已触顶，等待窗口重置", "Codex limit reached — waiting for the window to reset", "Codex 用量已觸頂，等待視窗重置")
        }
        public static var recoveredTitle: String {
            str("Codex 额度已恢复", "Codex quota recovered", "Codex 額度已恢復")
        }
        public static var recoveredBody: String {
            str("可以继续使用 Codex 了。", "You can use Codex again.", "可以繼續使用 Codex 了。")
        }
    }

    // MARK: - Errors

    public enum Errors {
        public static func http(_ status: Int) -> String {
            str("服务返回错误 (HTTP \(status))", "Service error (HTTP \(status))", "服務返回錯誤 (HTTP \(status))")
        }
        public static var timeout: String { str("请求超时", "Request timed out", "請求逾時") }
        public static var noNetwork: String { str("无网络连接", "No network connection", "無網路連線") }
        public static var cannotResolveHost: String { str("无法解析 chatgpt.com", "Cannot resolve chatgpt.com", "無法解析 chatgpt.com") }
        public static var parseFailed: String { str("响应解析失败", "Failed to parse the response", "回應解析失敗") }
        public static func network(_ reason: String) -> String {
            str("网络错误: \(reason)", "Network error: \(reason)", "網路錯誤: \(reason)")
        }
    }

    // MARK: - Relative update age

    public enum Age {
        public static var justNow: String { str("刚刚", "just now", "剛剛") }
        public static func seconds(_ n: Int) -> String { str("\(n) 秒前", "\(n)s ago", "\(n) 秒前") }
        public static func minutes(_ n: Int) -> String { str("\(n) 分钟前", "\(n)m ago", "\(n) 分鐘前") }
        public static func hoursMinutes(_ h: Int, _ m: Int) -> String {
            str("\(h) 小时 \(m) 分前", "\(h)h \(m)m ago", "\(h) 小時 \(m) 分前")
        }
        public static func daysHours(_ d: Int, _ h: Int) -> String {
            str("\(d) 天 \(h) 小时前", "\(d)d \(h)h ago", "\(d) 天 \(h) 小時前")
        }
    }
}
