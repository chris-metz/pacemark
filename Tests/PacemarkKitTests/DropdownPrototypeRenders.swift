import AppKit
import Foundation
@testable import PacemarkKit
import SwiftUI
import Testing

// PROTOTYPE, throwaway: renders every dropdown prototype variant with four
// providers to prototypes/dropdown/, for comparing them side by side. Runs
// only with PACEMARK_RENDER_PROTOTYPE=1.

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PACEMARK_RENDER_PROTOTYPE"] == "1"))
struct DropdownPrototypeRenders {
    static let output = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "prototypes/dropdown", directoryHint: .isDirectory)

    @Test(arguments: [
        ("A", DropdownTab.overview, "a"),
        ("B", DropdownTab.overview, "b"),
        ("B", DropdownTab.provider("claude"), "b-claude-open"),
        ("C", DropdownTab.overview, "c"),
        ("D", DropdownTab.overview, "d"),
        ("D", DropdownTab.provider("claude"), "d-claude"),
        ("E", DropdownTab.overview, "e"),
        ("E", DropdownTab.provider("claude"), "e-claude"),
    ])
    func render(variant: String, tab: DropdownTab, file: String) async throws {
        let timer = FakeTimer()
        let codex = [
            Limit(id: "primary", title: "5-hour limit", windowLength: 18000,
                  window: ActiveWindow(utilization: 58, resetsAt: date("2026-10-04T11:30:00Z")), resetBehavior: .awaitReading),
            Limit(id: "secondary", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 20, resetsAt: date("2026-10-09T13:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let grok = [
            Limit(id: "weekly", title: "Weekly limit", windowLength: 604800,
                  window: ActiveWindow(utilization: 37, resetsAt: date("2026-10-08T09:00:00Z")),
                  resetBehavior: .awaitReading, isOverviewLimit: true),
        ]
        let claude = [session(utilization: 31, resetsAt: "2026-10-04T10:21:00Z"),
                      weekly(utilization: 15, resetsAt: "2026-10-07T00:00:00Z"),
                      fable(utilization: 0, resetsAt: "2026-10-07T00:00:00Z")]
        let providers = [
            FakeProvider(.limits(claude), id: "claude"),
            FakeProvider(.limits(codex), id: "codex"),
            FakeProvider(.limits(MultiProviderViewTests.kimiLimits), id: "kimi"),
            FakeProvider(.limits(grok), id: "grok"),
        ]
        let model = AppModel(providers: providers, clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = providers.map(\.id)
        model.launch()
        for _ in providers { _ = await timer.armed() }
        model.selectedTab = tab

        let view = PrototypeDropdownView(model: model, variant: PrototypeVariant(rawValue: variant)!, showsSwitcher: false)
            .environment(\.timeZone, berlin)
            .environment(\.locale, enDE)
        let width: CGFloat = variant == "D" ? 445 : 300
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            let pixels = Snapshot.render(view, width: width, appearance: appearance)
            try pixels.png.write(to: Self.output.appending(path: "\(file)-\(name).png"))
        }
    }

    /// Variant D after the decisions: dots only for attention, and no
    /// sidebar with a single provider.
    @Test(arguments: ["d-attention", "d-attention-overview", "d-one-provider"])
    func renderSidebar(file: String) async throws {
        let timer = FakeTimer()
        let claude = [session(utilization: 31, resetsAt: "2026-10-04T10:21:00Z"),
                      weekly(utilization: 15, resetsAt: "2026-10-07T00:00:00Z"),
                      fable(utilization: 0, resetsAt: "2026-10-07T00:00:00Z")]
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
        let providers = file == "d-one-provider"
            ? [FakeProvider(.limits(claude), id: "claude")]
            : [FakeProvider(.limits(claude), id: "claude"), FakeProvider(.limits(codex), id: "codex"),
               FakeProvider(.problem(kimiLogin), id: "kimi"), FakeProvider(.limits(grok), id: "grok")]
        let model = AppModel(providers: providers, clock: { now }, sleep: { try await timer.sleep($0) })
        model.settings.enabledProviderIDs = providers.map(\.id)
        model.launch()
        for _ in providers { _ = await timer.armed() }
        if file == "d-attention" { model.selectedTab = .provider("codex") }

        let view = PrototypeDropdownView(model: model, variant: .d, showsSwitcher: false)
            .environment(\.timeZone, berlin)
            .environment(\.locale, enDE)
        let width: CGFloat = file == "d-one-provider" ? 300 : 445
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            let pixels = Snapshot.render(view, width: width, appearance: appearance)
            try pixels.png.write(to: Self.output.appending(path: "\(file)-\(name).png"))
        }
    }
}
