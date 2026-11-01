import Foundation
import Observation
import os

public nonisolated enum DropdownPage: Hashable, Sendable {
    case overview
    case provider(String)
}

/// Owns settings and independent query state for every enabled provider.
/// The selected dropdown page and the saved menu bar limit are independent
/// choices.
@Observable public final class AppModel {
    public let providers: [any Provider]
    public var settings: Settings {
        didSet {
            settingsStore?.save(settings)
            if settings.enabledProviderIDs != oldValue.enabledProviderIDs {
                reconcileProviders()
            }
            if settings.refreshIntervalMinutes != oldValue.refreshIntervalMinutes {
                for provider in enabledProviders { schedule(provider.id) }
            }
        }
    }
    /// Overview or a provider page, picked in the sidebar.
    public var selectedPage: DropdownPage = .overview
    public private(set) var now: Date
    public private(set) var states: [String: ProviderState] = [:]

    @ObservationIgnored private let settingsStore: SettingsStore?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private let expirySleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var expiryTimers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var queries: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var wakeDeadlines: [String: Date] = [:]
    @ObservationIgnored private var isNetworkSatisfied = false
    @ObservationIgnored private var hasLaunched = false

    public init(
        providers: [any Provider],
        settingsStore: SettingsStore? = nil,
        clock: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        expirySleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        precondition(Set(providers.map(\.id)).count == providers.count, "Provider IDs must be unique")
        self.providers = providers
        self.settingsStore = settingsStore
        settings = settingsStore?.load() ?? Settings()
        self.clock = clock
        self.sleep = sleep
        self.expirySleep = expirySleep
        now = clock()
    }

    isolated deinit {
        for task in timers.values { task.cancel() }
        for task in expiryTimers.values { task.cancel() }
        for task in queries.values { task.cancel() }
    }

    public var enabledProviders: [any Provider] {
        providers.filter { settings.enabledProviderIDs.contains($0.id) }
    }

    public func state(for providerID: String) -> ProviderState {
        states[providerID] ?? ProviderState()
    }

    public func providerDisplay(for providerID: String) -> Display {
        PacemarkKit.display(state(for: providerID), providerID: providerID, settings: settings, now: now)
    }

    public var overview: [OverviewEntry] {
        enabledProviders.map {
            overviewEntry(state(for: $0.id), providerID: $0.id, providerName: $0.name, settings: settings, now: now)
        }
    }

    public var sidebar: [SidebarEntry] {
        enabledProviders.map {
            sidebarEntry(state(for: $0.id), providerID: $0.id, providerName: $0.name, settings: settings, now: now)
        }
    }

    public var menuBar: MenuBarDisplay {
        guard let selection = settings.menuBarLimitID,
              let provider = enabledProviders.first(where: { selection.hasPrefix($0.id + "/") }) else {
            return MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
        }
        return providerDisplay(for: provider.id).menuBar
    }

    public var menuBarLimitPicker: MenuBarLimitPicker {
        let entries = enabledProviders.flatMap { provider in
            (state(for: provider.id).limits ?? []).map {
                MenuBarLimitPicker.Entry(id: $0.qualifiedID(providerID: provider.id), title: "\(provider.name) · \($0.title)")
            }
        }
        return PacemarkKit.menuBarLimitPicker(entries: entries, settings: settings)
    }

    public func pickMenuBarLimit(id: String) {
        for provider in enabledProviders {
            if let limit = state(for: provider.id).limits?.first(where: { $0.qualifiedID(providerID: provider.id) == id }) {
                settings.menuBarLimitID = id
                settings.menuBarLimitTitle = "\(provider.name) · \(limit.title)"
                return
            }
        }
    }

    public func setProvider(_ id: String, enabled: Bool) {
        guard providers.contains(where: { $0.id == id }) else { return }
        if enabled && !settings.enabledProviderIDs.contains(id) {
            settings.enabledProviderIDs.append(id)
        } else if !enabled {
            settings.enabledProviderIDs.removeAll { $0 == id }
        }
    }

    public func setLimit(_ limit: Limit, providerID: String, shownInDropdown isShown: Bool) {
        let id = limit.qualifiedID(providerID: providerID)
        if isShown {
            settings.hiddenLimits.removeAll { $0 == id }
        } else if !settings.hiddenLimits.contains(id) {
            settings.hiddenLimits.append(id)
        }
    }

    public func launch() {
        guard !hasLaunched else { return }
        hasLaunched = true
        reconcileProviders()
    }

    public func dropdownOpened() {
        selectedPage = .overview
        now = clock()
        for provider in enabledProviders where shouldQueryOnOpen(state(for: provider.id), now: now) {
            query(provider.id)
        }
    }

    public func wake() {
        for provider in enabledProviders {
            if isNetworkSatisfied {
                query(provider.id)
            } else {
                wakeDeadlines[provider.id] = clock().addingTimeInterval(30)
                schedule(provider.id)
            }
        }
    }

    public func networkChanged(isSatisfied: Bool) {
        guard isSatisfied != isNetworkSatisfied else { return }
        isNetworkSatisfied = isSatisfied
        guard isSatisfied else { return }
        for provider in enabledProviders {
            if wakeDeadlines[provider.id] != nil || state(for: provider.id).lastOutcome == .unavailable {
                query(provider.id)
            }
        }
    }

    public func minuteTick() { now = clock() }

    private func reconcileProviders() {
        let enabled = Set(enabledProviders.map(\.id))
        if case .provider(let id) = selectedPage, !enabled.contains(id) { selectedPage = .overview }
        for id in states.keys where !enabled.contains(id) {
            generations[id, default: 0] += 1
            timers.removeValue(forKey: id)?.cancel()
            expiryTimers.removeValue(forKey: id)?.cancel()
            queries[id]?.cancel()
            wakeDeadlines[id] = nil
            states[id] = nil
        }
        guard hasLaunched else { return }
        for provider in enabledProviders where states[provider.id] == nil {
            states[provider.id] = ProviderState()
            schedule(provider.id)
        }
        selectInitialMenuBarLimit()
    }

    private func schedule(_ id: String) {
        timers.removeValue(forKey: id)?.cancel()
        guard hasLaunched, settings.enabledProviderIDs.contains(id), queries[id] == nil else { return }
        let current = clock()
        var next = nextQueryAt(state(for: id), interval: settings.refreshInterval, now: current)
        if let deadline = wakeDeadlines[id] { next = min(next, deadline) }
        guard next > current else { query(id); return }
        timers[id] = Task { [weak self, sleep] in
            do { try await sleep(next.timeIntervalSince(current)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.schedule(id)
        }
    }

    private func query(_ id: String) {
        guard hasLaunched, settings.enabledProviderIDs.contains(id), queries[id] == nil,
              let provider = providers.first(where: { $0.id == id }) else { return }
        now = clock()
        states[id, default: ProviderState()].isQuerying = true
        wakeDeadlines[id] = nil
        timers.removeValue(forKey: id)?.cancel()
        scheduleExpiry(id)
        let generation = generations[id, default: 0]
        queries[id] = Task { [weak self] in
            let result = await provider.fetch()
            self?.finish(result, providerID: id, generation: generation)
        }
    }

    /// A running request must not keep an expired reading visible. This
    /// display deadline is independent of query completion and retry work.
    private func scheduleExpiry(_ id: String) {
        expiryTimers.removeValue(forKey: id)?.cancel()
        let current = clock()
        guard let reset = state(for: id).limits?.filter({ $0.resetBehavior == .awaitReading })
            .compactMap({ $0.window?.resetsAt }).filter({ $0 > current }).min() else { return }
        expiryTimers[id] = Task { [weak self, expirySleep] in
            do { try await expirySleep(reset.timeIntervalSince(current)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            now = clock()
            scheduleExpiry(id)
        }
    }

    private func finish(_ result: FetchResult, providerID id: String, generation: Int) {
        queries[id] = nil
        expiryTimers.removeValue(forKey: id)?.cancel()
        guard settings.enabledProviderIDs.contains(id) else { return }
        guard generations[id, default: 0] == generation else { schedule(id); return }
        now = clock()
        states[id, default: ProviderState()].record(result, finishedAt: now)
        selectInitialMenuBarLimit()
        appLog.info("Query finished for \(id, privacy: .public)")
        schedule(id)
    }

    private func selectInitialMenuBarLimit() {
        if settings.menuBarLimitID == nil, let first = enabledProviders.first,
           let limit = state(for: first.id).limits?.first {
            settings.menuBarLimitID = limit.qualifiedID(providerID: first.id)
            settings.menuBarLimitTitle = "\(first.name) · \(limit.title)"
        }
    }
}
