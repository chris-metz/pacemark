import Foundation
import PacemarkKit
import Testing

/// A provider's sidebar entry (#41): the Overview limit's percentage and a
/// dot when any counted limit needs attention, at a fixed `now`.
@Suite struct SidebarTests {
    /// 72.7 % of the window has passed at `now`.
    private func fiveHour(_ utilization: Double) -> Limit {
        Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
              window: ActiveWindow(utilization: utilization, resetsAt: date("2026-10-04T11:30:00Z")), resetBehavior: .awaitReading)
    }

    /// 63.2 % of the window has passed at `now`.
    private func codexWeekly(_ utilization: Double) -> Limit {
        Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
              window: ActiveWindow(utilization: utilization, resetsAt: date("2026-10-07T00:00:00Z")),
              resetBehavior: .awaitReading, isOverviewLimit: true)
    }

    private func entry(_ state: ProviderState, settings: Settings = Settings()) -> SidebarEntry {
        sidebarEntry(state, providerID: "codex", providerName: "Codex", settings: settings, now: now)
    }

    @Test func limitsUnderPaceShowTheOverviewPercentageWithoutADot() {
        let result = entry(succeeded([fiveHour(58), codexWeekly(15)], at: now))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: "15%", dot: nil,
                                       accessibilityText: "Codex, 15%"))
    }

    @Test func anyLimitOverPaceGivesAnOrangeDot() {
        let result = entry(succeeded([fiveHour(85), codexWeekly(15)], at: now))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: "15%", dot: .orange,
                                       accessibilityText: "Codex, 15%, a limit is over pace"))
    }

    @Test(arguments: [90.0, 100.0])
    func anyLimitAt90PercentOrMoreGivesARedDotOverAnOrangeOne(utilization: Double) {
        let result = entry(succeeded([fiveHour(utilization), codexWeekly(80)], at: now))

        #expect(result.dot == .red)
        #expect(result.accessibilityText == "Codex, 80%, a limit is at 90% or more")
    }

    @Test func aProblemGivesARedDotAndNoPercentage() {
        let problem = Problem(heading: "Sign in to Codex", message: "Run `codex login` in Terminal.", link: nil)
        let result = entry(ProviderState(lastAttemptAt: now, lastOutcome: .problem(problem)))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: nil, dot: .red,
                                       accessibilityText: "Codex, Sign in to Codex"))
    }

    @Test func loadingShowsAnEllipsis() {
        let result = entry(ProviderState(isQuerying: true))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: "…", dot: nil,
                                       accessibilityText: "Codex, loading"))
    }

    @Test func aTemporaryFailureWithoutValuesShowsADashAndNoDot() {
        let result = entry(ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, failureStreak: 1))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: "–", dot: nil,
                                       accessibilityText: "Codex, can't load limits right now"))
    }

    @Test func staleValuesStillCount() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, limits: [fiveHour(85), codexWeekly(15)],
                                  lastSuccessAt: now - 23 * 60, failureStreak: 1)

        let result = entry(state)

        #expect(result.percentText == "15%")
        #expect(result.dot == .orange)
    }

    @Test func staleValuesAddNoDotOfTheirOwn() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, limits: [fiveHour(58), codexWeekly(15)],
                                  lastSuccessAt: now - 23 * 60, failureStreak: 1)

        #expect(entry(state).dot == nil)
    }

    @Test func aLimitHiddenOnThePageDoesNotCount() {
        let result = entry(succeeded([fiveHour(85), codexWeekly(15)], at: now),
                           settings: Settings(hiddenLimits: ["codex/primary"]))

        #expect(result.dot == nil)
    }

    @Test func theOverviewLimitCountsEvenWhenHiddenOnThePage() {
        let result = entry(succeeded([fiveHour(58), codexWeekly(70)], at: now),
                           settings: Settings(hiddenLimits: ["codex/weekly"]))

        #expect(result.percentText == "70%")
        #expect(result.dot == .orange)
    }

    @Test func anOverviewLimitWaitingForUpdatedLimitsShowsADash() {
        let expired = Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                            window: ActiveWindow(utilization: 95, resetsAt: now - 60),
                            resetBehavior: .awaitReading, isOverviewLimit: true)

        let result = entry(succeeded([fiveHour(58), expired], at: now))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: "–", dot: nil,
                                       accessibilityText: "Codex, waiting for updated limits"))
    }

    @Test func withoutAnOverviewLimitTheEntryHasNoPercentageButItsLimitsCount() {
        let result = entry(succeeded([fiveHour(85)], at: now))

        #expect(result == SidebarEntry(id: "codex", name: "Codex", percentText: nil, dot: .orange,
                                       accessibilityText: "Codex, a limit is over pace"))
    }

    @Test func theModelListsOneEntryPerEnabledProviderInProviderOrder() async {
        let timer = FakeTimer()
        let providers = [FakeProvider(.limits([fiveHour(58), codexWeekly(15)]), id: "codex"),
                         FakeProvider(.limits([fiveHour(85), codexWeekly(15)]), id: "kimi"),
                         FakeProvider(.limits([]), id: "grok")]
        let model = AppModel(providers: providers, clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["kimi", "codex"]
        model.launch()
        _ = await timer.armed()
        _ = await timer.armed()

        #expect(model.sidebar.map(\.id) == ["codex", "kimi"])
        #expect(model.sidebar.map(\.dot) == [nil, .orange])
    }
}
