import AppKit
import Combine
import CodexMeterCore
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    enum AuthState: Equatable {
        case unknown
        case ok
        case noAuth          // no ~/.codex/auth.json (or API-key mode)
        case loginExpired    // refresh token rejected → run codex login
    }

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = false

    private let authStore: CodexAuthStore
    private let client: CodexUsageClient
    private let gate: NotificationGate
    private let recoveryTracker: RecoveryTracker

    private var pollTimer: Timer?
    private var stalenessTimer: Timer?
    private var consecutiveFailures = 0
    private var lastAutoRefresh: Date?
    private let tokenLeadTime: TimeInterval = 24 * 3600
    private var started = false

    init(authStore: CodexAuthStore = CodexAuthStore(),
         client: CodexUsageClient = CodexUsageClient(),
         gate: NotificationGate = NotificationGate(defaults: .standard),
         recoveryTracker: RecoveryTracker = RecoveryTracker(defaults: .standard)) {
        self.authStore = authStore
        self.client = client
        self.gate = gate
        self.recoveryTracker = recoveryTracker
    }

    func start() {
        guard !started else { return }
        started = true
        schedulePoll(firingNow: true)
        startStalenessTicker()
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshIfStale(maxAge: 5) }
        }
    }

    /// Keeps `isStale` honest between polls so the menu bar marker flips
    /// on wall-clock time, not only on refresh attempts.
    private func startStalenessTicker() {
        stalenessTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStaleness() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        stalenessTimer = timer
    }

    private func updateStaleness() {
        isStale = Staleness.isStale(lastRefresh: lastRefresh, now: Date(), interval: pollInterval)
    }

    var pollInterval: TimeInterval {
        TimeInterval(AppSettings.pollInterval)
    }

    /// Current effective wait before the next automatic poll:
    /// the configured interval when healthy, backoff when failing.
    var nextPollDelay: TimeInterval {
        BackoffPolicy.delay(afterConsecutiveFailures: consecutiveFailures) ?? pollInterval
    }

    private func schedulePoll(firingNow: Bool) {
        pollTimer?.invalidate()
        let delay = firingNow ? 0.5 : nextPollDelay
        let timer = Timer(timeInterval: delay, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastAutoRefresh ?? .distantPast) >= self.pollInterval - 1 {
                    Task { await self.refreshNow() }
                    self.schedulePoll(firingNow: false)
                }
            }
        }
        timer.tolerance = delay * 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        if firingNow {
            lastAutoRefresh = Date()
            Task { await self.refreshNow() }
        }
    }

    /// Refresh only when data is older than `maxAge` — used when the
    /// panel opens so the user sees near-live numbers.
    func refreshIfStale(maxAge: TimeInterval) {
        guard !isRefreshing else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maxAge { return }
        Task { await self.refreshNow() }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        NSLog("CodexMeter: refreshNow begin")

        do {
            guard var credentials = try authStore.readCredentials() else {
                authState = .noAuth
                lastError = nil
                consecutiveFailures = 0
                NSLog("CodexMeter: no credentials (auth.json missing or API-key mode)")
                return
            }
            let expiry = try? authStore.tokenExpiry()
            NSLog("CodexMeter: credentials ok, expiry=\(expiry.map { "\($0)" } ?? "unknown")")
            if RefreshDecision.shouldRefresh(tokenExp: expiry, now: Date(), leadTime: tokenLeadTime) {
                NSLog("CodexMeter: proactive token refresh")
                credentials = try await authStore.refresh()
            }

            do {
                try await fetchAndApply(credentials: credentials)
            } catch UsageClientError.unauthorized {
                // Access token died mid-flight: refresh once and retry once.
                NSLog("CodexMeter: 401 → refreshing token and retrying")
                let refreshed = try await authStore.refresh()
                try await fetchAndApply(credentials: refreshed)
            }

            authState = .ok
            lastError = nil
            consecutiveFailures = 0
            lastRefresh = Date()
            updateStaleness()
        } catch AuthStoreError.refreshRejected {
            authState = .loginExpired
            lastError = "登录已过期，请重新运行 codex login"
            consecutiveFailures = 7 // → max backoff (10 min)
            NSLog("CodexMeter: refresh rejected — login expired")
        } catch {
            lastError = Self.describe(error)
            consecutiveFailures += 1
            NSLog("CodexMeter: refresh failed: \(error)")
        }
    }

    private func fetchAndApply(credentials: CodexCredentials) async throws {
        let fresh = try await client.fetchUsage(credentials: credentials)
        snapshot = fresh
        if let primary = fresh.primary, let secondary = fresh.secondary {
            NSLog("CodexMeter refresh: primary=%d%% secondary=%d%% plan=%@", primary.usedPercent, secondary.usedPercent, fresh.planType ?? "-")
        }

        // Recovery tracking runs on every successful refresh, independent
        // of both notification toggles — state stays truthful while
        // notifications are off, and re-enabling never backfills events
        // that already passed. A payload without limit_reached is unknown:
        // neither an episode nor a recovery.
        let reached: Bool? = fresh.limitReachedKnown ? fresh.limitReached : nil
        let recoveryEvent = recoveryTracker.record(limitReached: reached)

        // Threshold alerts, merged into a single notification per refresh.
        if AppSettings.notificationsEnabled {
            let alerts = gate.evaluate(snapshot: fresh)
            if !alerts.isEmpty {
                NotificationManager.shared.deliver(message: alerts.map(\.message).joined(separator: "；"))
            }
        }

        // 恢复通知只受“重置提醒”开关控制；同一次触顶只通知一次
        //（状态由 RecoveryTracker 持久化推进，不会重复触发）。
        if recoveryEvent == .recovered, AppSettings.resetReminderEnabled {
            NotificationManager.shared.deliver(title: "Codex 额度已恢复",
                                               body: "可以继续使用 Codex 了。")
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let UsageClientError.http(status): "服务返回错误 (HTTP \(status))"
        case let url as URLError where url.code == .timedOut: "请求超时"
        case let url as URLError where url.code == .notConnectedToInternet: "无网络连接"
        case let url as URLError where url.code == .cannotFindHost: "无法解析 chatgpt.com"
        case is DecodingError: "响应解析失败"
        default: "网络错误: \(error.localizedDescription)"
        }
    }
}
