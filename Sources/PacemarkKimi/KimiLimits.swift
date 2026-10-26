import Foundation
import PacemarkKit

/// The local server's envelope around one answer about the account.
nonisolated struct Envelope: Decodable, Sendable {
    let code: Int
    let data: AccountResponse?
}

/// Kimi's answer about its own Kimi Code login: `ok` with the account's
/// profile or plan, or `error`.
nonisolated struct AccountResponse: Decodable, Sendable {
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
        let usages: Windows
    }

    /// `monthCode`, the Kimi Code share of `monthTotal`, is not a limit.
    struct Windows: Decodable, Sendable {
        let limit5h: Window?
        let limit7d: Window?
        let monthTotal: Window?
    }

    struct Window: Decodable, Sendable {
        let usedRatio: Double
        let resetAt: String?
    }

    var isLoginError: Bool {
        let text = message ?? ""
        return status == 401 || text.contains("No token") || text.contains("/login")
    }
}

nonisolated extension AccountResponse.Windows {
    /// In the order Kimi's `/usage` shows them. Overview shows the weekly
    /// limit, otherwise the monthly one.
    func limits() throws -> [Limit] {
        let overviewID = limit7d != nil ? "limit7d" : "monthTotal"
        let windows: [(id: String, title: String, window: AccountResponse.Window?, length: (Date?) -> TimeInterval?)] = [
            ("limit5h", "5-hour limit", limit5h, { _ in 5 * 3600 }),
            ("limit7d", "Weekly limit", limit7d, { _ in 7 * 86400 }),
            ("monthTotal", "Monthly limit", monthTotal, { $0.map(monthLength(endingAt:)) }),
        ]
        return try windows.compactMap { id, title, window, length in
            guard let window else { return nil }
            guard window.usedRatio.isFinite, window.usedRatio >= 0 else { throw KimiError.incompatible }
            let resetsAt = try window.resetAt.map { text in
                guard let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) else {
                    throw KimiError.incompatible
                }
                return date
            }
            return Limit(id: id, title: title, windowLength: length(resetsAt),
                         window: ActiveWindow(utilization: window.usedRatio * 100, resetsAt: resetsAt),
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
