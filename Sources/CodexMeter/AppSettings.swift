import Foundation
import SwiftUI

/// UserDefaults-backed settings. The monitor reads values at poll
/// scheduling time, so changes apply from the next cycle on.
enum AppSettings {
    static let pollIntervalOptions: [Int] = [30, 60, 300]

    static func label(forInterval seconds: Int) -> String {
        switch seconds {
        case 30: "30 秒"
        case 60: "1 分钟"
        case 300: "5 分钟"
        default: "\(seconds) 秒"
        }
    }

    static var pollInterval: Int {
        let value = UserDefaults.standard.integer(forKey: "pollIntervalSeconds")
        return pollIntervalOptions.contains(value) ? value : 60
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    // MARK: - Menu bar layout

    /// Vertical baseline offset (pt) for the two-line status item. NSStatusBar
    /// centers single-line metrics, so multi-line blocks ride high; this lets
    /// the user dial the position in for their display instead of us guessing.
    static let menuBarBaselineOffsetDefault = -6.5

    static var menuBarBaselineOffset: Double {
        get {
            UserDefaults.standard.object(forKey: "menuBarBaselineOffset") as? Double
                ?? menuBarBaselineOffsetDefault
        }
        set { UserDefaults.standard.set(newValue, forKey: "menuBarBaselineOffset") }
    }

    static let menuBarOffsetChanged = Notification.Name("codexMeterMenuBarOffsetChanged")

    static func adjustMenuBarBaselineOffset(_ delta: Double) {
        menuBarBaselineOffset += delta
        NotificationCenter.default.post(name: menuBarOffsetChanged, object: nil)
    }

    static func resetMenuBarBaselineOffset() {
        menuBarBaselineOffset = menuBarBaselineOffsetDefault
        NotificationCenter.default.post(name: menuBarOffsetChanged, object: nil)
    }
}
