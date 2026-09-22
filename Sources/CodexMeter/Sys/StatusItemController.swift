import AppKit
import Combine
import CodexMeterCore
import SwiftUI

/// Content view for the status item button: two stacked labels (quota row on
/// top, reset row below) whose vertical position is an explicit constraint.
/// This replaces the attributed-string "\n" approach, where baseline offsets
/// moved the two rows unpredictably (TextKit line-box metrics).
final class StatusItemContentView: NSView {
    private let logoView: NSImageView = {
        let view = NSImageView()
        view.image = CodexMark.templateImage
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .labelColor
        return view
    }()

    /// One row per window: [bolt] [label] [quota] · [↻] [reset]
    private struct WindowRow {
        let stack: NSStackView
        let bolt: NSImageView
        let label: NSTextField
        let quota: NSTextField
        let dot: NSTextField
        let refresh: NSImageView
        let reset: NSTextField
    }

    private var windowRows: [WindowRow] = []
    private var verticalOffset: NSLayoutConstraint!

    var onHover: ((Bool) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil))

        let row0 = makeWindowRow()
        let row1 = makeWindowRow()
        windowRows = [row0, row1]

        let rows = NSStackView(views: [row0.stack, row1.stack])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2

        let content = NSStackView(views: [logoView, rows])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        verticalOffset = content.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            trailingAnchor.constraint(greaterThanOrEqualTo: content.trailingAnchor, constant: 5),
            verticalOffset,
            logoView.widthAnchor.constraint(equalToConstant: 23.4),
            logoView.heightAnchor.constraint(equalToConstant: 23.4),
        ])
        row1.stack.isHidden = true // single-window plans show one row
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeWindowRow() -> WindowRow {
        let bolt = NSImageView()
        bolt.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9.5)
        label.textColor = .labelColor

        let quota = NSTextField(labelWithString: "")
        quota.font = .systemFont(ofSize: 9.5)
        quota.textColor = .labelColor

        let dot = NSTextField(labelWithString: "·")
        dot.font = .systemFont(ofSize: 9.5)
        dot.textColor = .labelColor

        let refresh = NSImageView()
        refresh.contentTintColor = .labelColor
        refresh.image = NSImage(systemSymbolName: "arrow.counterclockwise",
                                accessibilityDescription: "重置")?
            .withSymbolConfiguration(.init(pointSize: 7.5, weight: .medium))

        let reset = NSTextField(labelWithString: "")
        reset.font = .systemFont(ofSize: 9.5)
        reset.textColor = .labelColor

        let stack = NSStackView(views: [bolt, label, quota, dot, refresh, reset])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        return WindowRow(stack: stack, bolt: bolt, label: label,
                         quota: quota, dot: dot, refresh: refresh, reset: reset)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    /// rows: per-window (label, quota, reset). When empty, `fallback` renders
    /// as a single plain line (未登录 / –).
    func update(rows: [(label: String, quota: String, reset: String)],
                fallback: String?, symbolName: String?, offset: Double) {
        let symbolImage = symbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .medium))
        }

        for (index, row) in windowRows.enumerated() {
            if index < rows.count {
                let line = rows[index]
                row.bolt.image = symbolImage
                row.bolt.isHidden = symbolImage == nil
                row.label.stringValue = line.label
                row.label.isHidden = false
                row.quota.stringValue = line.quota
                row.quota.isHidden = false
                row.dot.isHidden = false
                row.refresh.isHidden = false
                row.reset.stringValue = line.reset
                row.reset.isHidden = false
            } else {
                row.bolt.isHidden = true
                row.label.isHidden = true
                row.quota.isHidden = true
                row.dot.isHidden = true
                row.refresh.isHidden = true
                row.reset.isHidden = true
            }
        }

        if rows.isEmpty, let fallback {
            let row = windowRows[0]
            row.quota.stringValue = fallback
            row.quota.isHidden = false
        }

        verticalOffset.constant = offset
    }

    /// Width the status item should reserve for the content plus padding.
    var preferredWidth: CGFloat {
        var rowsWidth: CGFloat = 0
        for row in windowRows where !row.stack.isHidden {
            rowsWidth = max(rowsWidth, row.stack.fittingSize.width)
        }
        return 23.4 + 5 + rowsWidth + 10
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
    private let hosting: NSHostingController<MenuPanelView>
    private var contentView: StatusItemContentView!
    private var cancellables: Set<AnyCancellable> = []
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?

    // Hover/click presentation state.
    private var isPinned = false
    private var hoverShowTimer: Timer?
    private var hoverHideTimer: Timer?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        hosting = NSHostingController(rootView: MenuPanelView(monitor: monitor))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        super.init()

        if let button = statusItem.button {
            button.title = "" // content drawn by StatusItemContentView
            button.target = self
            button.action = #selector(togglePopover(_:))
            // An empty-title status button collapses to zero height — the
            // content then draws as overflow and real mouse clicks fall
            // through the hit test (AXPress bypasses it, which is why the
            // simulated clicks "worked"). Pin the bar thickness explicitly.
            button.heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness).isActive = true

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
            view.onHover = { [weak self] entered in
                self?.handleHover(entered: entered)
            }
        }

        // Any close path (including AppKit's transient dismissal) resets
        // the presentation state.
        NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.presentationDidClose() }
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
            Task { @MainActor in self?.closePopover() }
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

    // MARK: - Presentation (hover shows, click pins)

    /// Hovering the item for a beat shows the panel unpinned; leaving both
    /// the item and the panel hides it again. Clicking shows it pinned —
    /// it then stays until the item or an outside click closes it.
    private func handleHover(entered: Bool) {
        if entered {
            hoverHideTimer?.invalidate()
            hoverHideTimer = nil
            guard hoverShowTimer == nil else { return }
            hoverShowTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.showPopover(pinned: false) }
            }
        } else {
            hoverShowTimer?.invalidate()
            hoverShowTimer = nil
            // Moving off the item: the mouse-move tracker decides whether
            // the pointer landed in the panel (keep) or elsewhere (hide).
        }
    }

    private func evaluateHover() {
        guard popover.isShown, !isPinned else { return }
        let point = NSEvent.mouseLocation

        var inItem = false
        if let button = statusItem.button, let window = button.window {
            inItem = window.convertToScreen(button.bounds).contains(point)
        }
        let inPopover = popover.contentViewController?.view.window?.frame.contains(point) ?? false

        if inItem || inPopover {
            hoverHideTimer?.invalidate()
            hoverHideTimer = nil
        } else if hoverHideTimer == nil {
            hoverHideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.closePopover() }
            }
        }
    }

    private func startMouseMoveTracking() {
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.evaluateHover() }
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            self.evaluateHover()
            return event
        }
    }

    private func stopMouseMoveTracking() {
        globalMouseMoveMonitor.map(NSEvent.removeMonitor)
        globalMouseMoveMonitor = nil
        localMouseMoveMonitor.map(NSEvent.removeMonitor)
        localMouseMoveMonitor = nil
    }

    private func showPopover(pinned: Bool) {
        hoverShowTimer?.invalidate()
        hoverShowTimer = nil
        if popover.isShown {
            if pinned { isPinned = true }
            return
        }
        isPinned = pinned

        // NSPopover sizes from the hosting view's fittingSize; SwiftUI
        // height only resolves after layout, so pin an explicit size
        // (a zero-height popover is invisible — looks like "won't open").
        hosting.view.layoutSubtreeIfNeeded()
        let fitted = hosting.view.fittingSize
        popover.contentSize = NSSize(
            width: max(330, fitted.width),
            height: fitted.height > 1 ? fitted.height : 420)
        monitor.refreshIfStale(maxAge: 20)
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // NSPopover's built-in animation duration is fixed (~0.25s, too
        // slow); show instantly and fade the content in quickly instead.
        hosting.view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hosting.view.animator().alphaValue = 1
        }
        if !pinned {
            startMouseMoveTracking()
        }
    }

    private func closePopover() {
        hoverShowTimer?.invalidate()
        hoverShowTimer = nil
        hoverHideTimer?.invalidate()
        hoverHideTimer = nil
        stopMouseMoveTracking()
        isPinned = false
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func presentationDidClose() {
        hoverShowTimer?.invalidate()
        hoverShowTimer = nil
        hoverHideTimer?.invalidate()
        hoverHideTimer = nil
        stopMouseMoveTracking()
        isPinned = false
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            if isPinned {
                closePopover()
            } else {
                // Hover-opened: the click pins it in place.
                isPinned = true
                stopMouseMoveTracking()
            }
        } else {
            showPopover(pinned: true)
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
            rows: components.lines.map { ($0.label, $0.quota, $0.reset) },
            fallback: components.lines.isEmpty ? components.quota : nil,
            symbolName: components.symbolName,
            offset: AppSettings.menuBarBaselineOffset)
        statusItem.length = contentView.preferredWidth
    }
}
