import CodexMeterCore
import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item + popover are managed by AppDelegate's
        // StatusItemController; no window scenes needed (LSUIElement app).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: UsageMonitor?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.language = AppSettings.language
        // Language picker default before the user picks one.
        UserDefaults.standard.register(defaults: ["appLanguage": AppSettings.language.rawValue])
        let monitor = UsageMonitor()
        self.monitor = monitor
        statusItemController = StatusItemController(monitor: monitor)
        monitor.start()
        NotificationManager.shared.requestAuthorizationIfNeeded()
    }
}
