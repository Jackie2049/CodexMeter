import CodexMeterCore
import SwiftUI

/// The dropdown panel shown by the menu bar item.
/// Hierarchy: attention card (most urgent) → window rows → badges →
/// refresh row → settings (collapsed) → actions.
struct MenuPanelView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage("pollIntervalSeconds") private var pollInterval = 60
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var now = Date()
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            attentionCard
            windows
            badges
            refreshRow

            Divider()

            settings

            Divider()

            HStack {
                Button("打开 Codex") { Self.openCodexApp() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 310, alignment: .leading)
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

    // MARK: - Attention card (most urgent state on top)

    @ViewBuilder
    private var attentionCard: some View {
        if let snapshot = monitor.snapshot {
            if snapshot.limitReached {
                card(text: "额度已触顶，等待窗口重置", color: .red)
            } else if let lowest = presentWindows.min(by: { $0.remainingPercent < $1.remainingPercent }),
                      lowest.remainingPercent <= 30 {
                let label = QuotaDisplay.longLabel(seconds: lowest.windowSeconds)
                card(text: "\(label) 额度剩余 \(lowest.remainingPercent)%，\(resetPhrase(window: lowest))",
                     color: QuotaThresholds.tier(forRemaining: lowest.remainingPercent) == .critical ? .red : .orange)
            }
        }
    }

    private func card(text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Windows

    private var presentWindows: [UsageWindow] {
        [monitor.snapshot?.primary, monitor.snapshot?.secondary]
            .compactMap { $0 }
            .sorted { $0.windowSeconds < $1.windowSeconds }
    }

    @ViewBuilder
    private var windows: some View {
        switch monitor.authState {
        case .noAuth:
            VStack(alignment: .leading, spacing: 6) {
                Text("未找到 Codex 登录").font(.headline)
                Text("请在终端运行 `codex login`，或打开 Codex app 登录后重试。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .loginExpired:
            VStack(alignment: .leading, spacing: 6) {
                Text("登录已过期").font(.headline).foregroundStyle(.red)
                Text("请重新运行 `codex login`，本工具会自动恢复。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unknown, .ok:
            let windows = presentWindows
            if windows.isEmpty {
                if monitor.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("获取用量中…").font(.callout).foregroundStyle(.secondary)
                    }
                } else if let error = monitor.lastError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("暂无数据").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(windows, id: \.windowSeconds) { window in
                    windowRow(window: window)
                }
            }
        }
    }

    private func windowRow(window: UsageWindow) -> some View {
        let remaining = window.remainingPercent
        let tier = QuotaThresholds.tier(forRemaining: remaining)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(QuotaDisplay.longLabel(seconds: window.windowSeconds))
                    .font(.headline)
                Spacer()
                Text("剩余 \(remaining)%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.color(for: tier))
            }
            ProgressView(value: Double(remaining), total: 100)
            Text("重置于 \(Self.resetTimeText(window))（\(Self.resetLeadText(window, now: now))）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func resetPhrase(window: UsageWindow) -> String {
        if window.windowSeconds <= 86400 {
            return Self.resetLeadText(window, now: now).appending("重置")
        }
        return "\(Self.resetTimeText(window))重置"
    }

    static func resetTimeText(_ window: UsageWindow) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(window.windowSeconds <= 86400 ? "HH:mm" : "MMMd")
        return formatter.string(from: window.resetAt)
    }

    /// Short window → live countdown; long window → absolute lead time.
    static func resetLeadText(_ window: UsageWindow, now: Date) -> String {
        let remaining = window.resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "即将重置" }
        return "剩余 \(countdown(remaining))"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm%02ds", minutes, seconds) }
        return "\(seconds)s"
    }

    // MARK: - Badges

    @ViewBuilder
    private var badges: some View {
        if let snapshot = monitor.snapshot {
            HStack(spacing: 6) {
                if let plan = snapshot.planType {
                    Badge(text: plan.uppercased(), color: .accentColor)
                }
                if snapshot.limitReached {
                    Badge(text: "已触顶", color: .red)
                }
                if snapshot.resetCreditsAvailable > 0 {
                    Badge(text: "\(snapshot.resetCreditsAvailable) 次可用重置", color: .indigo)
                }
                if snapshot.hasCredits {
                    Badge(text: "Credits $\(snapshot.creditBalance)", color: .green)
                }
            }
        }
    }

    // MARK: - Refresh state row

    private var refreshRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await monitor.refreshNow() }
            } label: {
                if monitor.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(monitor.isRefreshing)
            .help("立即刷新")

            Text(dataFreshnessText)
                .font(.caption)
                .foregroundStyle(dataFreshnessColor)
                .monospacedDigit()

            Spacer()
        }
    }

    private var dataFreshnessText: String {
        if monitor.lastError != nil, monitor.snapshot != nil {
            return "更新失败，数据来自 \(Self.countdown(now.timeIntervalSince(monitor.lastRefresh ?? now)))前"
        }
        if monitor.isStale {
            return "数据待更新"
        }
        guard let lastRefresh = monitor.lastRefresh else { return "尚未刷新" }
        let seconds = Int(now.timeIntervalSince(lastRefresh))
        if seconds < 5 { return "刚刚刷新" }
        if seconds < 90 { return "\(seconds) 秒前刷新" }
        return "上次刷新 \(Self.countdown(TimeInterval(seconds)))前"
    }

    private var dataFreshnessColor: Color {
        (monitor.lastError != nil && monitor.snapshot != nil) || monitor.isStale ? .orange : .secondary
    }

    // MARK: - Settings (collapsed)

    private var settings: some View {
        DisclosureGroup("设置", isExpanded: $settingsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("轮询间隔", selection: $pollInterval) {
                    ForEach(AppSettings.pollIntervalOptions, id: \.self) { option in
                        Text(AppSettings.label(forInterval: option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("用量阈值通知", isOn: $notificationsEnabled)

                if LoginItem.isSupported {
                    Toggle("开机自启", isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { _ = LoginItem.setEnabled($0) }))
                }
            }
            .padding(.top, 8)
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: - Helpers

    static func color(for tier: QuotaTier) -> Color {
        switch tier {
        case .critical: .red
        case .warning: .orange
        case .normal: .primary
        }
    }

    static func openCodexApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
