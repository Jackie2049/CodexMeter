import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var monitor: UsageMonitor

    init() {
        let m = UsageMonitor()
        _monitor = StateObject(wrappedValue: m)
        Task { @MainActor in
            // MenuBarExtra window content is lazy — onAppear only fires on
            // first click, so kick the poll loop off here.
            m.start()
            NotificationManager.shared.requestAuthorizationIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(monitor: monitor)
        } label: {
            StatusBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
