import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let windowSeconds: Int
    public let resetAt: Date

    public init(usedPercent: Int, windowSeconds: Int, resetAt: Date) {
        self.usedPercent = usedPercent
        self.windowSeconds = windowSeconds
        self.resetAt = resetAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let planType: String?
    public let limitReached: Bool
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let resetCreditsAvailable: Int
    public let hasCredits: Bool
    public let creditBalance: String

    public init(planType: String?, limitReached: Bool,
                primary: UsageWindow?, secondary: UsageWindow?,
                resetCreditsAvailable: Int, hasCredits: Bool, creditBalance: String) {
        self.planType = planType
        self.limitReached = limitReached
        self.primary = primary
        self.secondary = secondary
        self.resetCreditsAvailable = resetCreditsAvailable
        self.hasCredits = hasCredits
        self.creditBalance = creditBalance
    }

    public static func parse(_ data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder.snakeCase.decode(UsageResponse.self, from: data)
        return response.toSnapshot()
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// Mirrors the `wham/usage` response; every field optional so partial
/// responses degrade instead of failing the whole snapshot.
private struct UsageResponse: Decodable {
    struct RateLimit: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Int?
            let resetAt: Int?
        }
        let limitReached: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }

    struct Credits: Decodable {
        let hasCredits: Bool?
        let balance: String?
    }

    struct ResetCredits: Decodable {
        let availableCount: Int?
    }

    let planType: String?
    let rateLimit: RateLimit?
    let credits: Credits?
    let rateLimitResetCredits: ResetCredits?
}

private extension UsageResponse {
    func toSnapshot() -> UsageSnapshot {
        func window(_ raw: UsageResponse.RateLimit.Window?) -> UsageWindow? {
            guard let raw,
                  let usedPercent = raw.usedPercent,
                  let resetAt = raw.resetAt
            else { return nil }
            return UsageWindow(
                usedPercent: Int(usedPercent.rounded()),
                windowSeconds: raw.limitWindowSeconds ?? 0,
                resetAt: Date(timeIntervalSince1970: TimeInterval(resetAt)))
        }

        return UsageSnapshot(
            planType: planType,
            limitReached: rateLimit?.limitReached ?? false,
            primary: window(rateLimit?.primaryWindow),
            secondary: window(rateLimit?.secondaryWindow),
            resetCreditsAvailable: rateLimitResetCredits?.availableCount ?? 0,
            hasCredits: credits?.hasCredits ?? false,
            creditBalance: credits?.balance ?? "")
    }
}
