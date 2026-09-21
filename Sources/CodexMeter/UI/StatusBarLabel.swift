import CodexMeterCore
import SwiftUI

/// Menu bar label: `⚡ 33% | 5%` (5-hour | weekly). Colors shift with load;
/// errors and missing data degrade to "–" / ⚠ marks.
struct StatusBarLabel: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
                .monospacedDigit()
        }
    }

    private var icon: String {
        switch monitor.authState {
        case .noAuth, .loginExpired: return "exclamationmark.triangle"
        case .ok, .unknown: return "bolt.fill"
        }
    }

    private var text: String {
        switch monitor.authState {
        case .noAuth: return "未登录"
        case .loginExpired: return "过期"
        case .unknown, .ok:
            guard let snapshot = monitor.snapshot,
                  let primary = snapshot.primary,
                  let secondary = snapshot.secondary
            else { return "–% | –%" }
            let primaryText = snapshot.limitReached ? "顶" : "\(primary.usedPercent)%"
            return "\(primaryText) | \(secondary.usedPercent)%"
        }
    }

    private static func usageColor(_ percent: Int) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .primary
    }
}
