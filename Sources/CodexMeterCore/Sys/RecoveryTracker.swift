import Foundation

public enum RecoveryEvent: Equatable {
    case entered
    case recovered
}

/// Tracks the global `limit_reached` flag across snapshots so the app can
/// send exactly one "quota recovered" notification per limit episode.
/// The episode flag persists (UserDefaults) so an app restart during a
/// limit episode doesn't swallow the later recovery notice.
///
/// Recovery is only ever confirmed by a fresh successful snapshot —
/// a reset countdown reaching zero does NOT count as recovery.
public final class RecoveryTracker {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "codexmeter.wasLimitReached") {
        self.defaults = defaults
        self.key = key
    }

    /// Tracks the limit flag across confirmed snapshots. `nil` means the
    /// payload didn't carry a usable `limit_reached` — that is neither a
    /// limit episode nor a recovery: no event fires and no state changes,
    /// so parse gaps can never fabricate a recovery.
    @discardableResult
    public func record(limitReached: Bool?) -> RecoveryEvent? {
        guard let limitReached else { return nil }
        let wasLimitReached = defaults.bool(forKey: key)
        defer { defaults.set(limitReached, forKey: key) }

        switch (wasLimitReached, limitReached) {
        case (false, true): return .entered
        case (true, false): return .recovered
        case (_, _): return nil
        }
    }
}
