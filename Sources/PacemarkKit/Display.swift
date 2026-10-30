import Foundation

/// Everything the menu bar item and the dropdown show (§6.3).
public nonisolated struct Display: Equatable, Sendable {
    /// What the dropdown shows above its footer.
    public var dropdown: DropdownContent
    /// How old the values are: `Updated 4 min ago`, or `Couldn't update ·
    /// Last update 23 min ago` while they are stale; nil without values.
    public var updateLine: String?
    public var menuBar: MenuBarDisplay

    public init(dropdown: DropdownContent, updateLine: String?, menuBar: MenuBarDisplay) {
        self.dropdown = dropdown
        self.updateLine = updateLine
        self.menuBar = menuBar
    }
}

/// What the dropdown shows above its footer (§3 Other contents).
public nonisolated enum DropdownContent: Equatable, Sendable {
    /// No query has finished since launch.
    case loading
    /// A persistent error: its heading, message and link.
    case problem(Problem)
    /// One row per limit that isn't hidden, in provider order.
    case limits([Limit])
    /// There are limits, and the settings hide every one of them.
    case allHidden
    /// The last query failed temporarily and nothing has loaded yet.
    case noValues
}

/// What the menu bar item and the dropdown show for `state` at `now`
/// (§6.3). The settings name limits by their qualified id, so they need the
/// id of the provider that `state` belongs to.
public nonisolated func display(_ state: ProviderState, providerID: String, settings: Settings, now: Date) -> Display {
    let staleAge = staleAge(state, interval: settings.refreshInterval, now: now)
    let dropdown: DropdownContent = switch (state.lastOutcome, state.limits) {
    case (nil, _): .loading
    case (.problem(let problem)?, _): .problem(problem)
    case (_, let limits?): visibleRows(limits, providerID: providerID, settings: settings)
    default: .noValues
    }
    return Display(
        dropdown: dropdown,
        updateLine: staleAge.map(staleLine) ?? updatedLine(state, now: now),
        menuBar: menuBarDisplay(state, providerID: providerID, settings: settings, isStale: staleAge != nil, now: now)
    )
}

/// The limits the settings don't hide, or `allHidden` if they hide every
/// one.
private nonisolated func visibleRows(_ limits: [Limit], providerID: String, settings: Settings) -> DropdownContent {
    let visible = limits.filter { settings.isLimitShownInDropdown($0, providerID: providerID) }
    return visible.isEmpty && !limits.isEmpty ? .allHidden : .limits(visible)
}

/// The menu bar item (§2 States) for the menu bar limit: the picked one, or
/// the first limit only when no selection has been saved. With the percentage
/// off, the glyph carries red and dimming; the accessibility text still
/// names the limit and its percentage.
private nonisolated func menuBarDisplay(
    _ state: ProviderState,
    providerID: String,
    settings: Settings,
    isStale: Bool,
    now: Date
) -> MenuBarDisplay {
    if case .problem(let problem) = state.lastOutcome {
        return MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: \(problem.heading)")
    }
    let limits = state.limits ?? []
    let picked = limits.first { $0.qualifiedID(providerID: providerID) == settings.menuBarLimitID }
    guard let limit = picked ?? (settings.menuBarLimitID == nil ? limits.first : nil) else {
        return MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
    }
    let menuBarLimitDisplay = limitDisplay(limit, now: now)
    guard menuBarLimitDisplay.state != .waitingForUpdate else {
        return MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
    }
    let isRed = menuBarLimitDisplay.state.isRed
    return MenuBarDisplay(
        content: settings.showPercentage
            ? .percentage(menuBarLimitDisplay.percentText, isRed: isRed, isDimmed: isStale)
            : .glyph(isRed: isRed, isDimmed: isStale),
        accessibilityText: "\(limit.title) \(menuBarLimitDisplay.percentText)" + (isStale ? ", not up to date" : "")
    )
}

/// How long ago the last success finished, if the values are stale: the
/// last query failed temporarily, there are values, and they are more than
/// two refresh intervals old. A query still running doesn't count as failed.
private nonisolated func staleAge(_ state: ProviderState, interval: TimeInterval, now: Date) -> TimeInterval? {
    guard state.lastOutcome == .unavailable, state.limits != nil, let lastSuccessAt = state.lastSuccessAt else {
        return nil
    }
    let age = now.timeIntervalSince(lastSuccessAt)
    return age > 2 * interval ? age : nil
}

/// `Updated 4 min ago`, or `Updated just now` below a minute after the last
/// success, while there are values; nil otherwise.
private nonisolated func updatedLine(_ state: ProviderState, now: Date) -> String? {
    guard state.limits != nil, let lastSuccessAt = state.lastSuccessAt else { return nil }
    let age = now.timeIntervalSince(lastSuccessAt)
    return age < 60 ? "Updated just now" : "Updated \(ageText(age)) ago"
}

/// `Couldn't update · Last update 23 min ago`.
private nonisolated func staleLine(age: TimeInterval) -> String {
    "Couldn't update · Last update \(ageText(age)) ago"
}

/// The age in `min` below an hour, in `hr` below a day and in days from then
/// on, each rounded down.
private nonisolated func ageText(_ age: TimeInterval) -> String {
    let minutes = Int(age / 60)
    return switch minutes {
    case ..<60: "\(minutes) min"
    case ..<(24 * 60): "\(minutes / 60) hr"
    case ..<(2 * 24 * 60): "1 day"
    default: "\(minutes / (24 * 60)) days"
    }
}

/// One enabled provider in Overview, independent of provider-page visibility.
public nonisolated struct OverviewEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let content: Content
    public let updateLine: String?

    public enum Content: Equatable, Sendable {
        case limit(Limit)
        case noWeeklyLimit
        case loading
        case noValues
        case problem(Problem)
    }
}

public nonisolated func overviewEntry(_ state: ProviderState, providerID: String, providerName: String,
                                      settings: Settings, now: Date) -> OverviewEntry {
    let content: OverviewEntry.Content
    switch state.lastOutcome {
    case nil: content = .loading
    case .problem(let problem): content = .problem(problem)
    default:
        if let limits = state.limits {
            let overviewLimits = limits.filter(\.isOverviewLimit)
            content = overviewLimits.count == 1 ? .limit(overviewLimits[0]) : .noWeeklyLimit
        } else { content = .noValues }
    }
    return OverviewEntry(id: providerID, name: providerName, content: content,
                         updateLine: display(state, providerID: providerID, settings: settings, now: now).updateLine)
}

/// One enabled provider in the dropdown's sidebar (#41): its name, its
/// Overview limit's percentage and a dot when something needs attention.
public nonisolated struct SidebarEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// The Overview limit's `{U}%`; `–` without values or while it waits for
    /// updated limits; `…` while loading; nil for a problem or without an
    /// Overview limit.
    public let percentText: String?
    /// Red for a problem or a counted limit at 90% or more, orange for a
    /// counted limit over pace; nil when nothing needs attention.
    public let dot: LimitColor?
    /// The entry as one accessibility element, e.g. `Codex, 20%, a limit is
    /// over pace`.
    public let accessibilityText: String

    public init(id: String, name: String, percentText: String?, dot: LimitColor?, accessibilityText: String) {
        self.id = id
        self.name = name
        self.percentText = percentText
        self.dot = dot
        self.accessibilityText = accessibilityText
    }
}

/// The sidebar entry for `state` at `now`. The dot counts the limits shown on
/// the provider page and the Overview limit, which Overview always shows.
/// A temporary failure or stale values add no dot of their own.
public nonisolated func sidebarEntry(_ state: ProviderState, providerID: String, providerName: String,
                                     settings: Settings, now: Date) -> SidebarEntry {
    let overview = overviewEntry(state, providerID: providerID, providerName: providerName, settings: settings, now: now)
    var counted: [Limit] = []
    if case .limits(let shown) = display(state, providerID: providerID, settings: settings, now: now).dropdown {
        counted = shown
    }
    if case .limit(let limit) = overview.content, !counted.contains(limit) {
        counted.append(limit)
    }
    let limitStates = counted.map { limitDisplay($0, now: now).state }
    // A problem's heading already says what needs attention.
    let (dot, attentionText): (LimitColor?, String?) =
        if case .problem = overview.content { (.red, nil) }
        else if limitStates.contains(where: \.isRed) { (.red, "a limit is at 90% or more") }
        else if limitStates.contains(.overPace) { (.orange, "a limit is over pace") }
        else { (nil, nil) }

    let percentText: String?
    let statusText: String?
    switch overview.content {
    case .limit(let limit):
        let row = limitDisplay(limit, now: now)
        (percentText, statusText) = row.state == .waitingForUpdate
            ? ("–", "waiting for updated limits")
            : (row.percentText, row.percentText)
    case .noWeeklyLimit: (percentText, statusText) = (nil, nil)
    case .loading: (percentText, statusText) = ("…", "loading")
    case .noValues: (percentText, statusText) = ("–", "can't load limits right now")
    case .problem(let problem): (percentText, statusText) = (nil, problem.heading)
    }
    let accessibilityText = [providerName, statusText, attentionText].compactMap { $0 }.joined(separator: ", ")
    return SidebarEntry(id: providerID, name: providerName, percentText: percentText,
                        dot: dot, accessibilityText: accessibilityText)
}
