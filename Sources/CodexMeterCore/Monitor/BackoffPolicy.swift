import Foundation

public enum BackoffPolicy {
    public static let baseDelay: TimeInterval = 30
    public static let maxDelay: TimeInterval = 600

    /// Retry delay after `n` consecutive failures: 30s doubling, capped at 10min.
    /// nil when there have been no failures (poll on the normal interval).
    public static func delay(afterConsecutiveFailures failures: Int) -> TimeInterval? {
        guard failures > 0 else { return nil }
        let exponent = min(failures - 1, 32)
        return min(baseDelay * pow(2, Double(exponent)), maxDelay)
    }
}
