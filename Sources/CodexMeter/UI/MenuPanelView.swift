import CodexMeterCore
import SwiftUI

/// The dropdown panel shown by the menu bar item.
struct MenuPanelView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage("pollIntervalSeconds") private var pollInterval = 60
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Usage sections

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
            if let snapshot = monitor.snapshot {
                if let primary = snapshot.primary {
                    windowRow(title: "5 小时",
                              percent: primary.usedPercent,
                              resetAt: primary.resetAt,
                              showsCountdown: true)
                }
                if let secondary = snapshot.secondary {
                    windowRow(title: "1 周",
                              percent: secondary.usedPercent,
                              resetAt: secondary.resetAt,
                              showsCountdown: false)
                }
            } else if monitor.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("获取用量中…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let error = monitor.lastError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func windowRow(title: String, percent: Int, resetAt: Date, showsCountdown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("\(percent)%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.usageColor(percent))
            }
            ProgressView(value: Double(min(percent, 100)), total: 100)
            Text(resetDescription(resetAt: resetAt, showsCountdown: showsCountdown))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func resetDescription(resetAt: Date, showsCountdown: Bool) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd a hh:mm")

        if showsCountdown {
            let remaining = resetAt.timeIntervalSince(now)
            if remaining <= 0 { return "即将重置…" }
            return "重置于 \(formatter.string(from: resetAt))（剩余 \(Self.countdown(remaining))）"
        }
        return "\(formatter.string(from: resetAt)) 重置"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm%02ds", minutes, seconds) }
        return "\(seconds)s"
    }

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

            Text(lastRefreshText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = monitor.lastError, monitor.snapshot != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help(error)
            }
            Spacer()
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh = monitor.lastRefresh else { return "尚未刷新" }
        let seconds = Int(now.timeIntervalSince(lastRefresh))
        if seconds < 5 { return "刚刚刷新" }
        if seconds < 90 { return "\(seconds) 秒前刷新" }
        return "上次刷新 \(Self.countdown(TimeInterval(seconds)))前"
    }

    // MARK: - Settings

    private var settings: some View {
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
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: - Helpers

    static func usageColor(_ percent: Int) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .primary
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
