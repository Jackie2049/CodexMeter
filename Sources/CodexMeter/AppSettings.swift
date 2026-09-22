import Foundation
import CodexMeterCore
import SwiftUI

/// UserDefaults-backed settings. The monitor reads values at poll
/// scheduling time, so changes apply from the next cycle on.
enum AppSettings {
    static let pollIntervalOptions: [Int] = [30, 60, 300]

    static func label(forInterval seconds: Int) -> String {
        L10n.Menu.interval(seconds)
    }

    // MARK: - Interface language

    /// Persisted interface language; defaults to the system language on
    /// first launch. Setting this also syncs L10n and posts a change note.
    static var language: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: "appLanguage")
                .flatMap(AppLanguage.init(rawValue:)) ?? L10n.systemDefault
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
            L10n.language = newValue
            NotificationCenter.default.post(name: .codexMeterLanguageChanged, object: nil)
        }
    }

    static var pollInterval: Int {
        let value = UserDefaults.standard.integer(forKey: "pollIntervalSeconds")
        return pollIntervalOptions.contains(value) ? value : 60
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    /// 独立于阈值通知的“重置提醒”开关，只控制额度恢复通知。
    static var resetReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: "resetReminderEnabled") as? Bool ?? true
    }

    /// 任一通知开关开启即需要系统通知权限；两者都关闭则不请求。
    static var shouldRequestNotificationPermission: Bool {
        notificationsEnabled || resetReminderEnabled
    }

    // MARK: - Menu bar layout

    /// Vertical offset (pt) of the status item's two-line block relative to
    /// the button's vertical center (positive = down). The block is centered
    /// by an explicit constraint, so 0 is the balanced position; overridable
    /// via `defaults write com.jackie.CodexMeter menuBarBaselineOffset -float <pt>`.
    static let menuBarBaselineOffsetDefault = 0.0

    static var menuBarBaselineOffset: Double {
        UserDefaults.standard.object(forKey: "menuBarBaselineOffset") as? Double
            ?? menuBarBaselineOffsetDefault
    }
}
