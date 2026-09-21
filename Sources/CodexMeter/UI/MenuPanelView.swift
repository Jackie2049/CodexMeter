import CodexMeterCore
import SwiftUI

/// The dropdown panel shown by the menu bar item.
/// Compact native styling: quiet captions, one dominant number per window,
/// opaque semantic background, settings exposed inline.
struct MenuPanelView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage("pollIntervalSeconds") private var pollInterval = 60
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let status = statusItem {
                statusBanner(status)
            }

            windowSections
            infoLines

            Divider()
                .padding(.top, 14)

            settings

            Divider()
                .padding(.vertical, 12)

            bottomBar
        }
        .padding(18)
        .frame(width: 330, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            monitor.start()
            monitor.refreshIfStale(maxAge: 20)
        }
        // Keep the reset countdown ticking while the panel is open, and
        // opportunistically refresh if the panel stays open a long time.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            if enabled { NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("CodexMeter")
                .font(.system(size: 13, weight: .semibold))
            if let plan = monitor.snapshot?.planType {
                Text(plan.uppercased())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("退出 CodexMeter") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .help("更多操作")
            .accessibilityLabel("更多操作")
        }
        .padding(.bottom, 14)
    }

    // MARK: - Compact status line (errors only; low quota speaks via color)

    private struct StatusItem {
        let text: String
        let color: Color
        let showsRetry: Bool
    }

    private var statusItem: StatusItem? {
        switch monitor.authState {
        case .noAuth:
            return StatusItem(text: "未登录 · 请在终端运行 codex login", color: .red, showsRetry: false)
        case .loginExpired:
            return StatusItem(text: "登录已过期 · 请重新运行 codex login", color: .red, showsRetry: false)
        case .ok, .unknown:
            if monitor.snapshot?.limitReached == true {
                return StatusItem(text: "额度已触顶，等待窗口重置", color: .red, showsRetry: false)
            }
            if monitor.lastError != nil, monitor.snapshot != nil {
                return StatusItem(text: "更新失败 · 数据来自 \(relativeUpdateText)", color: .orange, showsRetry: true)
            }
            if monitor.isStale, monitor.snapshot != nil {
                return StatusItem(text: "数据待更新", color: .orange, showsRetry: false)
            }
            return nil
        }
    }

    private func statusBanner(_ status: StatusItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(status.color)
            Text(status.text)
                .font(.system(size: 12))
                .foregroundStyle(status.color)
            Spacer(minLength: 8)
            if status.showsRetry {
                Button("重试") {
                    Task { await monitor.refreshNow() }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Windows

    private var presentWindows: [UsageWindow] {
        [monitor.snapshot?.primary, monitor.snapshot?.secondary]
            .compactMap { $0 }
            .sorted { $0.windowSeconds < $1.windowSeconds }
    }

    @ViewBuilder
    private var windowSections: some View {
        let windows = presentWindows
        if windows.isEmpty {
            if monitor.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("获取用量中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }
        } else {
            VStack(spacing: 14) {
                ForEach(windows, id: \.windowSeconds) { window in
                    windowSection(window)
                }
            }
        }
    }

    private func windowSection(_ window: UsageWindow) -> some View {
        let remaining = window.remainingPercent
        let tier = QuotaThresholds.tier(forRemaining: remaining)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(QuotaDisplay.longLabel(seconds: window.windowSeconds))
                        .font(.system(size: 13, weight: .medium))
                    Text("剩余")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(remaining)%")
                    .font(.system(size: 27, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.color(for: tier))
            }

            quotaBar(fraction: Double(remaining) / 100, color: Self.color(for: tier))

            Text(QuotaDisplay.resetText(resetAt: window.resetAt, now: now))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(Self.fullDateTime(window.resetAt))
        }
    }

    private func quotaBar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Quiet info lines (only when present)

    @ViewBuilder
    private var infoLines: some View {
        if let snapshot = monitor.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.resetCreditsAvailable > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(snapshot.resetCreditsAvailable) 次可用重置")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if snapshot.hasCredits {
                    Text("Credits $\(snapshot.creditBalance)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Settings (exposed inline)

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("轮询间隔", selection: $pollInterval) {
                ForEach(AppSettings.pollIntervalOptions, id: \.self) { option in
                    Text(AppSettings.label(forInterval: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Toggle("用量阈值通知", isOn: $notificationsEnabled)

            if LoginItem.isSupported {
                Toggle("开机自启", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { _ = LoginItem.setEnabled($0) }))
            }
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.top, 12)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(updateText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await monitor.refreshNow() }
            } label: {
                Group {
                    if monitor.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(monitor.isRefreshing)
            .help("立即刷新")
            .accessibilityLabel("立即刷新")

            Spacer()

            Button {
                Self.openCodexApp()
            } label: {
                HStack(spacing: 3) {
                    Text("打开 Codex")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
    }

    // MARK: - Text helpers

    private var updateText: String {
        guard monitor.lastRefresh != nil else { return "尚未更新" }
        if monitor.lastError != nil || monitor.isStale {
            return "上次成功更新 \(relativeUpdateText)"
        }
        return relativeUpdateText == "刚刚" ? "刚刚更新" : "\(relativeUpdateText)更新"
    }

    /// "刚刚" / "42 秒前" / "3 分钟前" / "1 天 2 小时前" — success-time age.
    private var relativeUpdateText: String {
        guard let lastRefresh = monitor.lastRefresh else { return "—" }
        let age = now.timeIntervalSince(lastRefresh)
        if age < 5 { return "刚刚" }
        let total = Int(age.rounded())
        if total < 60 { return "\(total) 秒前" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时 \(minutes % 60) 分前" }
        return "\(hours / 24) 天 \(hours % 24) 小时前"
    }

    static func color(for tier: QuotaTier) -> Color {
        switch tier {
        case .critical: .red
        case .warning: .orange
        case .normal: .accentColor
        }
    }

    static func fullDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter.string(from: date)
    }

    static func openCodexApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
