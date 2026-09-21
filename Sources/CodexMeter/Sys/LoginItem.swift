import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Only meaningful for the
/// bundled, signed app produced by Scripts/make_app.sh.
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("CodexMeter login item error: \(error)")
            return false
        }
    }
}
