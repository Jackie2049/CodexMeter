import AppKit
import Combine
import CodexMeterCore
import SwiftUI

/// Owns the NSStatusItem (menu bar) and the NSPopover (panel).
///
/// Replaces SwiftUI's MenuBarExtra: its label view does not reliably
/// re-render on observed-object changes, which froze the menu bar title
/// at whatever state it had at launch ("未登录" forever). NSStatusItem
/// gives a plain `button.title` we can set on every change.
@MainActor
final class StatusItemController: NSObject {
    private let monitor: UsageMonitor
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(rootView: MenuPanelView(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // objectWillChange fires before values change; hopping to the next
        // runloop pass means render() sees the already-updated state.
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        render()

        // Auto-dismiss: .transient alone misses outside clicks in some
        // window configurations (desktop, other apps' status items), so
        // watch both event streams explicitly. Clicks on the popover or
        // the status button itself are left to the normal toggle path.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismissPopoverIfShown()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            if event.window !== popoverWindow, event.window !== self.statusItem.button?.window {
                self.popover.performClose(nil)
            }
            return event
        }
    }

    private func dismissPopoverIfShown() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refreshIfStale(maxAge: 20)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func render() {
        let components = QuotaDisplay.menuBarTitleComponents(
            snapshot: monitor.snapshot,
            notLoggedIn: monitor.authState == .noAuth,
            loginExpired: monitor.authState == .loginExpired,
            dataWarning: monitor.lastError != nil || monitor.isStale,
            now: Date())

        // Two stacked lines (iStat-style): quota row on top, reset row below.
        // Sizes are budgeted so both rows fit the ~24pt menu bar. NSStatusBar
        // centers single-line metrics, so multi-line blocks ride high — a
        // negative baselineOffset nudges the whole block down. Both rows use
        // labelColor: secondaryLabelColor resolves near-invisible on the dark
        // menu bar.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0.5

        let attributed = NSMutableAttributedString(
            string: components.main,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: -2.5,
            ])

        if let resets = components.resets {
            attributed.append(NSAttributedString(
                string: "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .paragraphStyle: paragraph,
                    .baselineOffset: -2.5,
                ]))
            attributed.append(NSAttributedString(
                string: resets,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .paragraphStyle: paragraph,
                    .foregroundColor: NSColor.labelColor,
                    .baselineOffset: -2.5,
                ]))
        }
        statusItem.button?.attributedTitle = attributed
    }
}
