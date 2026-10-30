import Foundation
import PacemarkKit

/// The account behind Grok's own login.
nonisolated struct AuthInfo: Decodable, Sendable {
    let email: String?
    let principalId: String?

    /// Without a login, every field is null.
    var identity: ProviderIdentity? {
        principalId.map { ProviderIdentity(email: email, accountID: $0) }
    }
}

/// `_x.ai/billing`: the subscription's credit use in its current window.
nonisolated struct BillingResponse: Decodable, Sendable {
    let config: Config?

    struct Config: Decodable, Sendable {
        let creditUsagePercent: Double?
        let currentPeriod: Window?
    }

    struct Window: Decodable, Sendable {
        let type: String
        let start: String
        let end: String
    }

    func limits() throws -> [Limit] {
        guard let config else { throw GrokError.incompatible }
        guard let window = config.currentPeriod else { return [] }
        guard let percent = config.creditUsagePercent, percent.isFinite, percent >= 0 else { throw GrokError.incompatible }
        let start = try Self.date(window.start)
        let end = try Self.date(window.end)
        guard end > start else { throw GrokError.incompatible }
        let (id, title) = if window.type.hasSuffix("_WEEKLY") { ("weekly", "Weekly limit") }
            else if window.type.hasSuffix("_MONTHLY") { ("monthly", "Monthly limit") }
            else { throw GrokError.incompatible }
        return [Limit(id: id, title: title, windowLength: end.timeIntervalSince(start),
                      window: ActiveWindow(utilization: percent, resetsAt: end),
                      resetBehavior: .awaitReading, isOverviewLimit: true)]
    }

    private static func date(_ text: String) throws -> Date {
        guard let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) else {
            throw GrokError.incompatible
        }
        return date
    }
}
