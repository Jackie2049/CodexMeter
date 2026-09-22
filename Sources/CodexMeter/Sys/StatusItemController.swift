import AppKit
import Combine
import CodexMeterCore
import SwiftUI

/// Content view for the status item button: two stacked labels (quota row on
/// top, reset row below) whose vertical position is an explicit constraint.
/// This replaces the attributed-string "\n" approach, where baseline offsets
/// moved the two rows unpredictably (TextKit line-box metrics).
final class StatusItemContentView: NSView {
    private let quotaLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private var verticalOffset: NSLayoutConstraint!

    /// This view is transparent to clicks (hitTest nil) so the underlying
    /// NSStatusBarButton receives them and its toggle action keeps working.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        quotaLabel.font = .systemFont(ofSize: 9.5)
        quotaLabel.textColor = .labelColor
        resetLabel.font = .systemFont(ofSize: 8)
        resetLabel.textColor = .labelColor

        let stack = NSStackView(views: [quotaLabel, resetLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        verticalOffset = stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 5),
            verticalOffset,
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(quota: String, resets: String?, offset: Double) {
        quotaLabel.stringValue = quota
        if let resets {
            resetLabel.stringValue = resets
            resetLabel.isHidden = false
        } else {
            resetLabel.stringValue = ""
            resetLabel.isHidden = true
        }
        verticalOffset.constant = offset
    }

    /// Width the status item should reserve for the content plus padding.
    var preferredWidth: CGFloat {
        var width = quotaLabel.intrinsicContentSize.width
        if !resetLabel.isHidden {
            width = max(width, resetLabel.intrinsicContentSize.width)
        }
        return width + 10
    }
}

/// Owns the NSStatusItem (menu bar) and the NSPopover (panel).
///
/// Replaces SwiftUI's MenuBarExtra: its label view does not reliably
/// re-render on observed-object changes, which froze the menu bar title
/// at whatever state it had at launch ("未登录" forever).
@MainActor
final class StatusItemController: NSObject {
    private let monitor: UsageMonitor
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var contentView: StatusItemContentView!
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
            button.title = "" // content drawn by StatusItemContentView
            button.target = self
            button.action = #selector(togglePopover(_:))

            let view = StatusItemContentView()
            contentView = view
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
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

        contentView.update(
            quota: components.main,
            resets: components.resets,
            offset: AppSettings.menuBarBaselineOffset)
        statusItem.length = contentView.preferredWidth
    }
}
