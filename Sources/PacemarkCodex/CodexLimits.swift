import Foundation
import PacemarkKit

nonisolated struct RateLimitsResponse: Decodable, Sendable {
    let accountId: String?
    let rateLimits: Bucket
    let rateLimitsByLimitId: [String: Bucket]?

    struct Bucket: Decodable, Sendable {
        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double
        let windowDurationMins: Double?
        let resetsAt: Double?
        var isWeekly: Bool { windowDurationMins.map { abs($0 - 10080) <= 504 } ?? false }
    }

    func limits() throws -> [Limit] {
        let buckets: [(String, Bucket)]
        if let map = rateLimitsByLimitId {
            buckets = map.sorted { left, right in
                if left.key == "codex" { return right.key != "codex" }
                if right.key == "codex" { return false }
                return left.key < right.key
            }
        } else {
            buckets = [(rateLimits.limitId ?? "codex", rateLimits)]
        }
        return try buckets.flatMap { id, bucket in
            let windows = [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, window in
                window.map { (slot, $0) }
            }
            let general = id == "codex"
            let weeklyCount = windows.filter { $0.1.isWeekly }.count
            return try windows.map { slot, window in
                guard window.usedPercent.isFinite,
                      window.windowDurationMins.map({ $0.isFinite && $0 > 0 && $0 <= 52560000 }) ?? true,
                      window.resetsAt.map({ $0.isFinite && $0 > 0 && $0 < 253402300800 }) ?? true else {
                    throw CodexError.incompatible
                }
                let title: String
                if window.isWeekly { title = "Weekly limit" }
                else if let minutes = window.windowDurationMins {
                    title = minutes.truncatingRemainder(dividingBy: 60) == 0
                        ? "\(Int(minutes / 60))-hour limit" : "\(Int(minutes))-minute limit"
                } else { title = slot == "primary" ? "Primary limit" : "Secondary limit" }
                return Limit(id: general ? slot : "model:\(id)/\(slot)",
                    title: general ? title : "\(bucket.limitName ?? id) · \(title)",
                    windowLength: window.windowDurationMins.map { $0 * 60 },
                    window: ActiveWindow(utilization: window.usedPercent, resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:))),
                    resetBehavior: .awaitReading, isGeneralWeekly: general && window.isWeekly && weeklyCount == 1)
            }
        }
    }
}
