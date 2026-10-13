import Foundation
import PacemarkKit
import Testing

@Suite(.timeLimit(.minutes(1))) struct MultiProviderTests {
    @Test func onlyEnabledProvidersLoadAndFirstProviderOwnsTheInitialSelection() async {
        let claude = FakeProvider(.limits(claudeLimits), id: "claude")
        let codex = FakeProvider(.limits(claudeLimits), id: "codex")
        let timer = FakeTimer()
        let model = AppModel(providers: [claude, codex], clock: { beforeTheResets },
                             sleep: { try await timer.sleep($0) })
        model.launch()
        #expect(model.enabledProviders.isEmpty)
        #expect(model.settings.menuBarLimitID == nil)
        #expect(claude.fetchCount == 0 && codex.fetchCount == 0)
        model.setProvider("claude", enabled: true)
        _ = await timer.armed()
        #expect(model.settings.menuBarLimitID == "claude/session")
        #expect(codex.fetchCount == 0)
        model.setProvider("claude", enabled: false)
        #expect(model.menuBar.content == .glyph())
        #expect(model.settings.menuBarLimitID == "claude/session")
    }
}

@MainActor final class DeferredProvider: Provider {
    let id: String
    let name: String
    private var pending: [CheckedContinuation<FetchResult, Never>] = []
    private let starts: AsyncStream<Void>
    private let started: AsyncStream<Void>.Continuation
    init(_ id: String) {
        self.id = id
        self.name = id.capitalized
        (starts, started) = AsyncStream.makeStream(of: Void.self)
    }
    func fetch() async -> FetchResult {
        await withCheckedContinuation { pending.append($0); started.yield(()) }
    }
    func waitForQuery() async {
        for await _ in starts { return }
    }
    func answer(_ result: FetchResult) { pending.removeFirst().resume(returning: result) }
}

extension MultiProviderTests {
    @Test func aSlowProviderDoesNotBlockAnotherOrStealTheInitialSelection() async {
        let claude = DeferredProvider("claude")
        let codex = DeferredProvider("codex")
        let timer = FakeTimer()
        let model = AppModel(providers: [claude, codex], clock: { beforeTheResets }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["claude", "codex"]
        model.launch()
        await claude.waitForQuery()
        await codex.waitForQuery()
        codex.answer(.limits(claudeLimits))
        _ = await timer.armed()
        #expect(model.state(for: "claude").isQuerying)
        #expect(model.state(for: "codex").lastOutcome == .success)
        #expect(model.settings.menuBarLimitID == nil)
        claude.answer(.limits(claudeLimits))
        _ = await timer.armed()
        #expect(model.settings.menuBarLimitID == "claude/session")
        model.selectedTab = .provider("codex")
        model.dropdownOpened()
        #expect(model.selectedTab == .overview)
        #expect(model.settings.menuBarLimitID == "claude/session")
    }

    @Test func disablingAndReenablingRejectsTheOldCompletionBeforeStartingANewQuery() async {
        let provider = DeferredProvider("codex")
        let timer = FakeTimer()
        let model = AppModel(providers: [provider], clock: { beforeTheResets }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["codex"]
        model.settings.menuBarLimitID = "codex/weekly"
        model.launch()
        await provider.waitForQuery()
        model.setProvider("codex", enabled: false)
        model.setProvider("codex", enabled: true)
        provider.answer(.problem(notLoggedIn))
        await provider.waitForQuery()
        #expect(model.state(for: "codex").lastOutcome == nil)
        #expect(model.menuBar.content == .glyph())
        provider.answer(.limits(claudeLimits))
        _ = await timer.armed()
        #expect(model.menuBar.content == .percentage("36%", isRed: false, isDimmed: false))
        #expect(model.settings.menuBarLimitID == "codex/weekly")
    }

    @Test func anotherProvidersProblemDoesNotReplaceTheSelectedHealthyPercentage() async {
        let timer = FakeTimer()
        let model = AppModel(providers: [FakeProvider(.limits(claudeLimits), id: "claude"),
                                        FakeProvider(.problem(notLoggedIn), id: "codex")],
                             clock: { beforeTheResets }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["claude", "codex"]
        model.launch()
        _ = await timer.armed()
        _ = await timer.armed()
        #expect(model.menuBar.content == .percentage("14%", isRed: false, isDimmed: false))
        #expect(model.overview[1].content == .problem(notLoggedIn))
        model.pickMenuBarLimit(id: "claude/weekly")
        model.setLimit(claudeLimits[1], providerID: "claude", shownInDropdown: false)
        #expect(model.overview[0].content == .limit(claudeLimits[1]))
        #expect(model.settings.menuBarLimitID == "claude/weekly")
    }

    @Test func disablingAnUnloadedFirstProviderChoosesTheAlreadyLoadedProviderWithoutASavedSelection() async {
        let timer = FakeTimer()
        let model = AppModel(providers: [FakeProvider(.problem(notLoggedIn), id: "claude"),
                                        FakeProvider(.limits(claudeLimits), id: "codex")],
                             clock: { beforeTheResets }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["claude", "codex"]
        model.launch()
        _ = await timer.armed()
        _ = await timer.armed()
        #expect(model.settings.menuBarLimitID == nil)

        model.setProvider("claude", enabled: false)

        #expect(model.settings.menuBarLimitID == "codex/session")
        #expect(model.settings.menuBarLimitTitle == "Codex · Session limit")
        #expect(model.menuBar.content == .percentage("14%", isRed: false, isDimmed: false))
    }
}

extension MultiProviderTests {
    @Test func codexExpiresWhileARefreshIsStillRunning() async {
        let provider = DeferredProvider("codex")
        let timer = FakeTimer()
        let expiry = FakeTimer()
        var time = beforeTheResets
        let reset = time + 90
        let limits = [
            Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 42, resetsAt: reset), resetBehavior: .awaitReading),
            Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 20, resetsAt: reset + 10), resetBehavior: .awaitReading),
        ]
        let model = AppModel(providers: [provider], clock: { time }, sleep: { try await timer.sleep($0) },
                             expirySleep: { try await expiry.sleep($0) })
        model.settings.enabledProviderIDs = ["codex"]
        model.networkChanged(isSatisfied: true)
        model.launch()
        await provider.waitForQuery()
        provider.answer(.limits(limits))
        _ = await timer.armed()
        time += 10
        model.wake()
        await provider.waitForQuery()
        #expect(await expiry.armed() == 80)
        time = reset
        expiry.fire()
        #expect(await expiry.armed() == 10)
        #expect(model.menuBar.content == .glyph())
        #expect(model.state(for: "codex").isQuerying)
        provider.answer(.unavailable)
        _ = await timer.armed()
        #expect(model.menuBar.content == .glyph())
    }
}
