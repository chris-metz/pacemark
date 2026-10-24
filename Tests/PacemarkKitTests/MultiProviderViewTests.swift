import Foundation
import PacemarkKit
import SwiftUI
import Testing

@Suite struct MultiProviderViewTests {
    @Test(arguments: ["overview", "codex", "setup", "no-weekly", "error", "details", "loading", "no-values", "expired", "no-reset", "hidden", "stale", "settings"])
    func approvedScreens(scenario: String) async {
        let timer = FakeTimer()
        var time = scenario == "stale" ? now - 23 * 60 : now
        let codexLimits = [
            Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 42, resetsAt: date("2026-10-04T12:00:00Z")), resetBehavior: .awaitReading),
            Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 20, resetsAt: scenario == "no-reset" ? nil : (scenario == "expired" ? now - 1 : date("2026-10-09T13:00:00Z"))),
                  resetBehavior: .awaitReading, isOverviewLimit: scenario != "no-weekly"),
            Limit(id: "model:x/primary", title: "Model X · Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 73, resetsAt: date("2026-10-09T13:00:00Z")), resetBehavior: .awaitReading),
        ]
        let problem = Problem(heading: "Codex CLI not found", message: "Install the Codex CLI, then run `codex login` in Terminal and sign in with ChatGPT.",
                              link: ProblemLink(title: "Install Codex", url: URL(string: "https://learn.chatgpt.com/docs/cli")!))
        let result: FetchResult = switch scenario {
        case "error", "details": .problem(problem)
        case "no-values": .unavailable
        default: .limits(codexLimits)
        }
        let deferred = DeferredProvider("codex")
        let claudeRows = [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
                          weekly(utilization: 63, resetsAt: "2026-10-07T00:59:59.880Z"),
                          fable(utilization: 22, resetsAt: "2026-10-07T01:00:00Z")]
        let claude = FakeProvider(.limits(claudeRows), .limits(claudeRows), id: "claude")
        let codex: any Provider = scenario == "loading" ? deferred : FakeProvider(result, .unavailable, id: "codex")
        let model = AppModel(providers: [claude, codex], clock: { time }, sleep: { try await timer.sleep($0) })
        if scenario != "setup" { model.settings.enabledProviderIDs = ["claude", "codex"] }
        model.launch()
        if scenario != "setup" {
            _ = await timer.armed()
            if scenario == "loading" { await deferred.waitForQuery() }
            else { _ = await timer.armed() }
        }
        if scenario == "stale" {
            time = now
            model.dropdownOpened()
            _ = await timer.armed()
            _ = await timer.armed()
        }
        if ["codex", "details", "hidden"].contains(scenario) { model.selectedTab = .provider("codex") }
        if scenario == "hidden" {
            for limit in codexLimits { model.setLimit(limit, providerID: "codex", shownInDropdown: false) }
        }
        if scenario == "settings" {
            let login = OpenAtLogin(loginItem: FakeLoginItem(.notRegistered), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
            expectViewSnapshot(SettingsView(model: model, openAtLogin: login, version: "Version 0.1 (a1b2c3d)"), width: 440, test: "multi-settings")
        } else {
            expectViewSnapshot(DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE),
                               width: 300, test: "multi-\(scenario)")
        }
        if scenario == "loading" { deferred.answer(.unavailable); _ = await timer.armed() }
    }
}

extension MultiProviderViewTests {
    /// A third provider whose Overview limit is monthly, like Kimi's.
    @Test(arguments: ["kimi-overview", "kimi", "kimi-login", "kimi-settings"])
    func kimiScreens(scenario: String) async {
        let timer = FakeTimer()
        let kimiLimits = [
            Limit(id: "limit5h", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 31, resetsAt: date("2026-10-04T13:20:00Z")), resetBehavior: .awaitReading),
            Limit(id: "monthTotal", title: "Monthly limit", windowLength: 2_592_000,
                  window: ActiveWindow(utilization: 18, resetsAt: date("2026-10-25T00:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let codexLimits = [
            Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 42, resetsAt: date("2026-10-04T12:00:00Z")), resetBehavior: .awaitReading),
            Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 20, resetsAt: date("2026-10-09T13:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let login = Problem(heading: "Sign in to Kimi Code",
                            message: "Run `kimi login` in Terminal. Pacemark needs Kimi Code's own login.", link: nil)
        let claudeRows = [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
                          weekly(utilization: 63, resetsAt: "2026-10-07T00:59:59.880Z"),
                          fable(utilization: 22, resetsAt: "2026-10-07T01:00:00Z")]
        let model = AppModel(providers: [FakeProvider(.limits(claudeRows), id: "claude"),
                                         FakeProvider(.limits(codexLimits), id: "codex"),
                                         FakeProvider(scenario == "kimi-login" ? .problem(login) : .limits(kimiLimits), id: "kimi")],
                             clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = ["claude", "codex", "kimi"]
        model.launch()
        for _ in 0..<3 { _ = await timer.armed() }
        if scenario == "kimi" { model.selectedTab = .provider("kimi") }
        if scenario == "kimi-settings" {
            let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(.notRegistered), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
            expectViewSnapshot(SettingsView(model: model, openAtLogin: openAtLogin, version: "Version 0.1 (a1b2c3d)"),
                               width: 440, test: "multi-\(scenario)")
        } else {
            expectViewSnapshot(DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE),
                               width: 300, test: "multi-\(scenario)")
        }
    }
}
