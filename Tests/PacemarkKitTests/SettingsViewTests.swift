import Foundation
import PacemarkKit
import ServiceManagement
import SwiftUI
import Testing

/// The settings window (§4), rendered in light and dark.
@Suite struct SettingsViewTests {
    /// The defaults, after a query delivered the three Claude limits.
    @Test func settingsWindowDefault() async {
        let model = await model(after: .limits(claudeLimits), at: beforeTheResets)

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    /// No query has finished yet, and nothing is stored.
    @Test func settingsWindowBeforeFirstSuccess() {
        let model = AppModel(provider: FakeProvider())

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    @Test func settingsWindowOpenAtLoginTurnedOffInSystemSettings() {
        let model = AppModel(provider: FakeProvider())

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.requiresApproval)), width: 440)
    }

    @Test func settingsWindowOutsideApplications() {
        let model = AppModel(provider: FakeProvider())
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: URL(filePath: "/Users/chris/code/pacemark/build/Pacemark.app"))
        openAtLogin.refresh()

        expectViewSnapshot(settingsView(model, openAtLogin: openAtLogin), width: 440)

        #expect(loginItem.statusReads == 0)
    }

    /// The stored menu bar limit is missing from the current limits, and
    /// the weekly limit is hidden in the dropdown.
    @Test func settingsWindowNotAvailable() async {
        let settings = PacemarkKit.Settings(hiddenLimits: ["fake/weekly"], menuBarLimitID: "fake/model:Opus",
                                            menuBarLimitTitle: "Opus limit")
        let model = await model(after: .limits(claudeLimits), settings: settings, at: beforeTheResets)

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    // The Limit picker.

    private let pickerEntries: [MenuBarLimitPicker.Entry] = [
        .init(id: "claude/session", title: "Claude · Session limit"),
        .init(id: "claude/weekly", title: "Claude · Weekly limit"),
        .init(id: "claude/model:Fable", title: "Claude · Fable limit"),
    ]

    @Test func theLimitPickerPreservesProviderOrderAndLeavesTheInitialChoiceToTheModel() {
        let picker = menuBarLimitPicker(entries: pickerEntries, settings: PacemarkKit.Settings())

        #expect(picker == MenuBarLimitPicker(
            entries: [
                .init(id: "claude/session", title: "Claude · Session limit"),
                .init(id: "claude/weekly", title: "Claude · Weekly limit"),
                .init(id: "claude/model:Fable", title: "Claude · Fable limit"),
                .init(id: "", title: "—"),
            ],
            selection: "",
            isDisabled: false
        ))
    }

    @Test func theLimitPickerSelectsTheStoredChoice() {
        let settings = PacemarkKit.Settings(menuBarLimitID: "claude/model:Fable", menuBarLimitTitle: "Claude · Fable limit")

        let picker = menuBarLimitPicker(entries: pickerEntries, settings: settings)

        #expect(picker.selection == "claude/model:Fable")
        #expect(picker.entries.count == 3)
    }

    @Test func aStoredChoiceMissingFromTheCurrentLimitsShowsAsNotAvailable() {
        let settings = PacemarkKit.Settings(menuBarLimitID: "claude/model:Opus", menuBarLimitTitle: "Claude · Opus limit")

        let picker = menuBarLimitPicker(entries: pickerEntries, settings: settings)

        #expect(picker.entries.last == .init(id: "claude/model:Opus", title: "Claude · Opus limit (not available)"))
        #expect(picker.entries.count == 4)
        #expect(picker.selection == "claude/model:Opus")
        #expect(!picker.isDisabled)
    }

    @Test(arguments: [("Claude · Weekly limit", "Claude · Weekly limit (not available)"), (nil, "—")] as [(String?, String)])
    func withoutValuesTheLimitPickerIsDisabledAndShowsTheStoredTitle(storedTitle: String?, shown: String) {
        let settings = PacemarkKit.Settings(menuBarLimitID: storedTitle.map { _ in "claude/weekly" },
                                            menuBarLimitTitle: storedTitle)

        let picker = menuBarLimitPicker(entries: [], settings: settings)

        #expect(picker.isDisabled)
        #expect(picker.entries.map(\.title) == [shown])
        #expect(picker.selection == picker.entries.first?.id)
        #expect(picker.selection == settings.menuBarLimitID ?? "")
    }

    @Test func theVersionLineNamesTheCommit() {
        let info = ["CFBundleShortVersionString": "0.1", "PacemarkGitCommit": "a1b2c3d"]

        #expect(versionText(infoDictionary: info) == "Version 0.1 (a1b2c3d)")
    }

    @Test func withoutACommitKeyTheVersionLineHasOnlyTheVersion() {
        let info = ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "42"]

        #expect(versionText(infoDictionary: info) == "Version 0.1")
    }

    private func settingsView(_ model: AppModel, openAtLogin: OpenAtLogin) -> SettingsView {
        SettingsView(model: model, openAtLogin: openAtLogin, version: "Version 0.1 (a1b2c3d)")
    }

    /// The copy at `/Applications/Pacemark.app`, its login item's status
    /// read as the window would on appearing.
    private func installedCopy(_ status: SMAppService.Status) -> OpenAtLogin {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(status), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
        openAtLogin.refresh()
        return openAtLogin
    }
}
