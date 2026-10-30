import AppKit
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
        if ["codex", "details", "hidden"].contains(scenario) { model.selectedPage = .provider("codex") }
        if scenario == "hidden" {
            for limit in codexLimits { model.setLimit(limit, providerID: "codex", shownInDropdown: false) }
        }
        if scenario == "settings" {
            let login = OpenAtLogin(loginItem: FakeLoginItem(.notRegistered), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
            expectViewSnapshot(SettingsView(model: model, openAtLogin: login, version: "Version 0.1 (a1b2c3d)"), width: 440, test: "multi-settings")
        } else {
            expectViewSnapshot(DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE),
                               width: scenario == "setup" ? 300 : 445, test: "multi-\(scenario)")
        }
        if scenario == "loading" { deferred.answer(.unavailable); _ = await timer.armed() }
    }
}

extension MultiProviderViewTests {
    /// A third provider whose Overview limit is monthly, like Kimi's.
    @Test(arguments: ["kimi-overview", "kimi", "kimi-login", "kimi-settings"])
    func kimiScreens(scenario: String) async {
        let login = Problem(heading: "Sign in to Kimi Code",
                            message: "Run `kimi login` in Terminal. Pacemark needs Kimi Code's own login.", link: nil)
        await expectScreen(scenario, providerID: "kimi",
                           answering: scenario == "kimi-login" ? .problem(login) : .limits(Self.kimiLimits),
                           after: [("claude", .limits(Self.claudeRows)), ("codex", .limits(Self.codexLimits))])
    }

    /// A fourth provider with one weekly limit, like Grok's.
    @Test(arguments: ["grok-overview", "grok", "grok-login", "grok-settings"])
    func grokScreens(scenario: String) async {
        let grokLimits = [
            Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 37, resetsAt: date("2026-10-08T09:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let login = Problem(heading: "Sign in to Grok",
                            message: "Run `grok login` in Terminal. Pacemark needs Grok's own login.", link: nil)
        await expectScreen(scenario, providerID: "grok",
                           answering: scenario == "grok-login" ? .problem(login) : .limits(grokLimits),
                           after: [("claude", .limits(Self.claudeRows)), ("codex", .limits(Self.codexLimits)),
                                   ("kimi", .limits(Self.kimiLimits))])
    }

    static let claudeRows = [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
                             weekly(utilization: 63, resetsAt: "2026-10-07T00:59:59.880Z"),
                             fable(utilization: 22, resetsAt: "2026-10-07T01:00:00Z")]
    static let codexLimits = [
        Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
              window: ActiveWindow(utilization: 42, resetsAt: date("2026-10-04T12:00:00Z")), resetBehavior: .awaitReading),
        Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
              window: ActiveWindow(utilization: 20, resetsAt: date("2026-10-09T13:00:00Z")),
              resetBehavior: .awaitReading, isOverviewLimit: true),
    ]
    static let kimiLimits = [
        Limit(id: "limit5h", title: "5-hour limit", windowLength: 18000,
              window: ActiveWindow(utilization: 31, resetsAt: date("2026-10-04T13:20:00Z")), resetBehavior: .awaitReading),
        Limit(id: "monthTotal", title: "Monthly limit", windowLength: 2_592_000,
              window: ActiveWindow(utilization: 18, resetsAt: date("2026-10-25T00:00:00Z")),
              resetBehavior: .awaitReading, isOverviewLimit: true),
    ]

    /// Enables the `earlier` providers and the one named `id`, last, and
    /// renders `scenario`: Overview, the page named `id`, or Settings.
    private func expectScreen(_ scenario: String, providerID id: String, answering result: FetchResult,
                              after earlier: [(id: String, result: FetchResult)]) async {
        let timer = FakeTimer()
        let providers = (earlier + [(id, result)]).map { FakeProvider($0.result, id: $0.id) }
        let model = AppModel(providers: providers, clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = providers.map(\.id)
        model.launch()
        for _ in providers { _ = await timer.armed() }
        if scenario == id { model.selectedPage = .provider(id) }
        if scenario.hasSuffix("-settings") {
            let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(.notRegistered), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
            expectViewSnapshot(SettingsView(model: model, openAtLogin: openAtLogin, version: "Version 0.1 (a1b2c3d)"),
                               width: 440, test: "multi-\(scenario)")
        } else {
            expectViewSnapshot(DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE),
                               width: 445, test: "multi-\(scenario)")
        }
    }
}

extension MultiProviderViewTests {
    /// Claude fine, Codex's 5-hour limit over pace, Kimi signed out and Grok
    /// at 92 %: no dot, orange, red and red (#41).
    @Test(arguments: ["attention-overview", "attention-codex"])
    func attentionDots(scenario: String) async {
        let model = await Self.attentionModel()
        if scenario == "attention-codex" { model.selectedPage = .provider("codex") }
        expectViewSnapshot(DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE),
                           width: 445, test: "multi-\(scenario)")
    }

    /// The tab bar of five segments wanted 345 pt and was squeezed into
    /// 272 pt. After a tab switch the real menu window laid it out at 345 pt
    /// and cut the dropdown off on both sides (#41). No control on any page
    /// may be squeezed below its natural width.
    @Test func noControlIsSqueezedOnAnyPage() async {
        let model = await Self.attentionModel()
        let host = NSHostingView(rootView: DropdownView(model: model).environment(\.timeZone, berlin).environment(\.locale, enDE))
        host.frame.size = host.fittingSize
        for page in [DropdownPage.overview] + model.enabledProviders.map({ .provider($0.id) }) {
            model.selectedPage = page
            host.layoutSubtreeIfNeeded()
            for control in Self.controls(in: host) {
                #expect(control.frame.width >= control.intrinsicContentSize.width - 0.5,
                        "\(type(of: control)) on \(page): \(control.frame.width) pt of \(control.intrinsicContentSize.width) pt")
            }
        }
    }

    private static func controls(in view: NSView) -> [NSControl] {
        (view as? NSControl).map { [$0] } ?? view.subviews.flatMap(controls)
    }

    private static func attentionModel() async -> AppModel {
        let timer = FakeTimer()
        let codex = [
            Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 85, resetsAt: date("2026-10-04T11:30:00Z")), resetBehavior: .awaitReading),
            Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 20, resetsAt: date("2026-10-09T13:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let grok = [
            Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 92, resetsAt: date("2026-10-08T09:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let kimiLogin = Problem(heading: "Sign in to Kimi Code",
                                message: "Run `kimi login` in Terminal. Pacemark needs Kimi Code's own login.", link: nil)
        let claude = [session(utilization: 31, resetsAt: "2026-10-04T10:21:00Z"),
                      weekly(utilization: 15, resetsAt: "2026-10-07T00:00:00Z"),
                      fable(utilization: 0, resetsAt: "2026-10-07T00:00:00Z")]
        let providers = [FakeProvider(.limits(claude), id: "claude"), FakeProvider(.limits(codex), id: "codex"),
                         FakeProvider(.problem(kimiLogin), id: "kimi"), FakeProvider(.limits(grok), id: "grok")]
        let model = AppModel(providers: providers, clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = providers.map(\.id)
        model.launch()
        for _ in providers { _ = await timer.armed() }
        return model
    }
}
