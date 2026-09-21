import CodexMeterCore
import SwiftUI

/// Menu bar label: remaining quota per window, e.g. `5h 67% · 周 95%`.
/// Slots are duration-based; a plan without a window shows `—` for it.
/// limitReached switches the icon (numbers stay). Stale/failed data adds
/// a warning marker so old numbers are never mistaken for live ones.
struct StatusBarLabel: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 3) {
            Text("Codex")
                .font(.system(size: 11, weight: .semibold))
            Image(systemName: icon)
            Text(text)
                .monospacedDigit()
            if showsDataWarning {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
        .help("剩余额度")
    }

    private var icon: String {
        switch monitor.authState {
        case .noAuth, .loginExpired: return "exclamationmark.triangle"
        case .ok, .unknown:
            return monitor.snapshot?.limitReached == true
                ? "exclamationmark.triangle.fill"
                : "bolt.fill"
        }
    }

    private var text: String {
        switch monitor.authState {
        case .noAuth: return "未登录"
        case .loginExpired: return "过期"
        case .unknown, .ok:
            return monitor.snapshot.flatMap { QuotaDisplay.statusBarText($0) } ?? "–"
        }
    }

    private var showsDataWarning: Bool {
        monitor.snapshot != nil && (monitor.lastError != nil || monitor.isStale)
    }
}
