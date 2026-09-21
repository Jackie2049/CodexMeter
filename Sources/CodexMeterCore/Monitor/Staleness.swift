import Foundation

public enum Staleness {
    /// Data is stale once it has not been refreshed for more than twice the
    /// normal poll interval. nil lastRefresh = never refreshed = stale.
    public static func isStale(lastRefresh: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) > interval * 2
    }
}
