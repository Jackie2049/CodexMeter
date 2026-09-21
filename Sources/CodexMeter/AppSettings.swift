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
}
