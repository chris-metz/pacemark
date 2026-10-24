import Foundation
import PacemarkKit

/// The local server's envelope around one managed-account answer.
nonisolated struct Envelope: Decodable, Sendable {
    let code: Int
    let data: Managed?
}

/// Kimi's answer for its managed login: `ok` with a payload, or `error`.
nonisolated struct Managed: Decodable, Sendable {
    let kind: String
    let message: String?
    let status: Int?
    let quota: Quota?
    let userInfo: UserInfo?

    struct UserInfo: Decodable, Sendable {
        let userId: String
        let email: String?
    }

    struct Quota: Decodable, Sendable {
        let usages: Usages
    }

    /// `monthCode`, the Kimi Code share of `monthTotal`, is not a limit.
    struct Usages: Decodable, Sendable {
        let limit5h: Entry?
        let limit7d: Entry?
        let monthTotal: Entry?
    }

    struct Entry: Decodable, Sendable {
        let usedRatio: Double
        let resetAt: String?
    }

    var isLoginError: Bool {
        let text = message ?? ""
        return status == 401 || text.contains("No token") || text.contains("/login")
    }
}

nonisolated extension Managed.Usages {
    /// In Kimi's order. Overview shows the weekly limit, otherwise the
    /// monthly one.
    func limits() throws -> [Limit] {
        let overviewID = limit7d != nil ? "limit7d" : "monthTotal"
        let entries = [("limit5h", "5-hour limit", limit5h), ("limit7d", "Weekly limit", limit7d),
                       ("monthTotal", "Monthly limit", monthTotal)]
        return try entries.compactMap { id, title, entry in
            guard let entry else { return nil }
            guard entry.usedRatio.isFinite, entry.usedRatio >= 0 else { throw KimiError.incompatible }
            let resetsAt = try entry.resetAt.map { text in
                guard let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) else {
                    throw KimiError.incompatible
                }
                return date
            }
            let windowLength: TimeInterval? = switch id {
            case "limit5h": 5 * 3600
            case "limit7d": 7 * 86400
            default: resetsAt.map(monthLength(endingAt:))
            }
            return Limit(id: id, title: title, windowLength: windowLength,
                         window: ActiveWindow(utilization: entry.usedRatio * 100, resetsAt: resetsAt),
                         resetBehavior: .awaitReading, isOverviewLimit: id == overviewID)
        }
    }
}

/// Kimi reports no window start: the monthly window is the calendar month,
/// in UTC, that ends at the reset.
nonisolated func monthLength(endingAt reset: Date) -> TimeInterval {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return 30 * 86400 }
    return reset.timeIntervalSince(start)
}
