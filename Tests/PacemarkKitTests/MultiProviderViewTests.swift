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
                  resetBehavior: .awaitReading, isGeneralWeekly: scenario != "no-weekly"),
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
