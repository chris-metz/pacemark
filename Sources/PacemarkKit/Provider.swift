import Foundation

/// A source of limits, e.g. Claude. The app triggers every query; the
/// provider is passive and keeps no limit values across calls.
public nonisolated protocol Provider: Sendable {
    /// Stable id, never shown, e.g. "claude". Prefixes the stored limit ids.
    var id: String { get }
    /// Display name, e.g. "Claude".
    var name: String { get }
    /// Runs one query. Never called concurrently for the same provider;
    /// runs off the main actor.
    func fetch() async -> FetchResult
}

/// The answer to one query: exactly one of three results.
public nonisolated enum FetchResult: Equatable, Sendable {
    /// Success, in display order; the first is the default menu bar limit.
    case limits([Limit], identity: ProviderIdentity? = nil)
    /// Temporary error: old values stay, the retry schedule applies.
    case unavailable
    /// A failed read after the account was identified. A changed identity
    /// invalidates values from the previous account, even on failure.
    case unavailableForAccount(ProviderIdentity, discardPrevious: Bool = false)
    /// Persistent error: old values go, the message replaces the bars.
    case problem(Problem)
}

/// Available account identity, held only in memory. Workspace alone does
/// not identify a person. Missing fields cannot detect every account switch.
public nonisolated struct ProviderIdentity: Equatable, Sendable {
    public let email: String?
    public let accountID: String?
    public init(email: String?, accountID: String?) {
        self.email = email
        self.accountID = accountID
    }
}

public nonisolated struct Limit: Equatable, Sendable, Identifiable {
    /// Unique within the provider, stable, never shown.
    public let id: String
    /// Label above the bar.
    public let title: String
    public let windowLength: TimeInterval?
    /// How a previously observed reset affects this reading.
    public let resetBehavior: ResetBehavior
    /// The one limit that represents the provider in Overview: its general
    /// weekly limit, or a longer general limit when it reports no weekly one.
    public let isOverviewLimit: Bool
    /// nil = no window.
    public let window: ActiveWindow?

    public init(id: String, title: String, windowLength: TimeInterval?, window: ActiveWindow?,
                resetBehavior: ResetBehavior = .inactive, isOverviewLimit: Bool = false) {
        self.id = id
        self.title = title
        self.windowLength = windowLength
        self.window = window
        self.resetBehavior = resetBehavior
        self.isOverviewLimit = isOverviewLimit
    }
}

extension Limit {
    /// How the settings name this limit: `{provider id}/{limit id}`, e.g.
    /// `claude/session` or `claude/model:Fable`. Never shown.
    public nonisolated func qualifiedID(providerID: String) -> String {
        "\(providerID)/\(id)"
    }
}

public nonisolated enum ResetBehavior: Equatable, Sendable {
    /// Claude: a reset means an inactive window with zero utilization.
    case inactive
    /// Codex: wait for a current reading instead of inferring zero.
    case awaitReading
}

/// Known utilization, even when the provider cannot report its reset time.
public nonisolated struct ActiveWindow: Equatable, Sendable {
    /// Percent as delivered; may exceed 100.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// A persistent error, with finished text supplied by the provider.
public nonisolated struct Problem: Equatable, Sendable {
    public let heading: String
    /// Markdown, so commands render as inline code.
    public let message: String
    public let link: ProblemLink?

    public init(heading: String, message: String, link: ProblemLink?) {
        self.heading = heading
        self.message = message
        self.link = link
    }
}

public nonisolated struct ProblemLink: Equatable, Sendable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}
