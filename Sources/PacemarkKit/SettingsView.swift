import AppKit
import SwiftUI

/// The content of the `Pacemark Settings` window (§4): one page in the
/// grouped style of System Settings. Changes apply at once and go straight
/// into the model, which writes them through.
public struct SettingsView: View {
    @Bindable var model: AppModel
    let openAtLogin: OpenAtLogin
    /// The footer's version line, see `versionText(infoDictionary:)`.
    let version: String

    public init(model: AppModel, openAtLogin: OpenAtLogin, version: String) {
        self.model = model
        self.openAtLogin = openAtLogin
        self.version = version
    }

    public var body: some View {
        Form {
            Section("General") {
                OpenAtLoginRow(openAtLogin: openAtLogin)
                Picker("Refresh every", selection: $model.settings.refreshIntervalMinutes) {
                    ForEach(Settings.refreshIntervalChoices, id: \.self) { minutes in
                        Text(verbatim: "\(minutes) min").tag(minutes)
                    }
                }
            }
            Section {
                ForEach(model.providers, id: \.id) { provider in
                    Toggle(provider.name, isOn: Binding {
                        model.settings.enabledProviderIDs.contains(provider.id)
                    } set: { model.setProvider(provider.id, enabled: $0) })
                    .toggleStyle(.switch)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Use each provider's installed command-line tool and existing login.")
            }
            Section("Menu Bar") {
                menuBarLimit
                Toggle("Show percentage", isOn: $model.settings.showPercentage)
            }
            Section("Provider Tabs") {
                shownLimits
            }
            Section {
            } footer: {
                HStack {
                    Text(verbatim: version)
                    Text(verbatim: "·")
                    Link("GitHub", destination: repositoryURL)
                    Spacer()
                    QuitButton("Quit Pacemark")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(height: 520)
    }

    /// The menu bar limit, picked from the current limits.
    private var menuBarLimit: some View {
        let picker = model.menuBarLimitPicker
        let selection = Binding { picker.selection } set: { model.pickMenuBarLimit(id: $0) }
        return Picker("Limit", selection: selection) {
            ForEach(picker.entries) { entry in
                Text(verbatim: entry.title).tag(entry.id)
            }
        }
        .disabled(picker.isDisabled)
    }

    /// Visibility applies only to provider tabs, never to Overview.
    @ViewBuilder private var shownLimits: some View {
        if model.enabledProviders.isEmpty {
            Text("Enable a provider to choose which limits appear in its tab.")
                .foregroundStyle(.secondary)
        }
        ForEach(model.enabledProviders, id: \.id) { provider in
            let limits = model.state(for: provider.id).limits ?? []
            if limits.isEmpty {
                Text("\(provider.name)'s limits appear here once loaded.")
                    .foregroundStyle(.secondary)
            }
            ForEach(limits) { limit in
                Toggle("\(provider.name) · \(limit.title)", isOn: Binding {
                    model.settings.isLimitShownInDropdown(limit, providerID: provider.id)
                } set: { model.setLimit(limit, providerID: provider.id, shownInDropdown: $0) })
            }
        }
        Text("Overview always shows each enabled provider's general weekly limit.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// The `Open at Login` switch with its note (§4). The status is read again
/// when the window appears and when the app becomes active, since the user
/// may have changed it in System Settings.
private struct OpenAtLoginRow: View {
    let openAtLogin: OpenAtLogin

    var body: some View {
        Toggle(isOn: Binding(get: { openAtLogin.isOn }, set: { openAtLogin.switchTo($0) })) {
            Text("Open at Login")
            switch openAtLogin.state {
            case .on, .off:
                EmptyView()
            case .turnedOffInSystemSettings:
                Text("Turned off in System Settings.")
                Button("Open Login Items Settings") {
                    openAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.link)
            case .notInApplications:
                Text("Move Pacemark to Applications to use this.")
            }
        }
        .toggleStyle(.switch)
        .disabled(openAtLogin.state == .notInApplications)
        .onAppear { openAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            openAtLogin.refresh()
        }
    }
}

/// The id of the settings window's `Window` scene.
public let settingsWindowID = "settings"

extension OpenWindowAction {
    /// Opens the settings window, or brings it to the front if it is open,
    /// and activates the app (§5). The activation policy stays `.accessory`,
    /// so no Dock icon appears.
    public func openSettings() {
        self(id: settingsWindowID)
        NSApplication.shared.activate()
    }
}

/// The version line of the settings window's footer (§4):
/// `Version 0.1 (a1b2c3d)`, or `Version 0.1` when the bundle has no commit
/// key.
public nonisolated func versionText(infoDictionary: [String: Any]) -> String {
    let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
    guard let commit = infoDictionary["PacemarkGitCommit"] as? String else {
        return "Version \(version)"
    }
    return "Version \(version) (\(commit))"
}

/// What the settings window's `Limit` picker offers and selects (§4).
public nonisolated struct MenuBarLimitPicker: Equatable, Sendable {
    /// The entries, in order; one placeholder entry while disabled.
    public var entries: [Entry]
    /// The id of the selected entry.
    public var selection: String
    /// There are no current limits: before the first success since launch,
    /// and while a persistent error is shown.
    public var isDisabled: Bool

    public init(entries: [Entry], selection: String, isDisabled: Bool) {
        self.entries = entries
        self.selection = selection
        self.isDisabled = isDisabled
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        /// The limit's qualified id; empty for the placeholder.
        public var id: String
        public var title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }
}

/// The `Limit` picker for the current `limits` (nil before the first
/// success and while a persistent error is shown):
///
/// - With limits, one entry per limit by title, in provider order. It
///   selects the stored choice, or the first limit with nothing stored. A
///   stored choice missing from the limits gets an extra last entry,
///   `<stored title> (not available)`, and is selected.
/// - Without limits, it is disabled and shows the stored title, or `—`
///   without one.
public nonisolated func menuBarLimitPicker(limits: [Limit]?, providerID: String, settings: Settings) -> MenuBarLimitPicker {
    let storedTitle = settings.menuBarLimitTitle ?? "—"
    guard let limits, !limits.isEmpty else {
        return MenuBarLimitPicker(entries: [.init(id: "", title: storedTitle)], selection: "", isDisabled: true)
    }
    var entries = limits.map { MenuBarLimitPicker.Entry(id: $0.qualifiedID(providerID: providerID), title: $0.title) }
    let selection = settings.menuBarLimitID ?? entries[0].id
    if !entries.contains(where: { $0.id == selection }) {
        entries.append(.init(id: selection, title: "\(storedTitle) (not available)"))
    }
    return MenuBarLimitPicker(entries: entries, selection: selection, isDisabled: false)
}

/// Preserves the saved choice even when its provider or window is absent.
public nonisolated func menuBarLimitPicker(entries current: [MenuBarLimitPicker.Entry], settings: Settings) -> MenuBarLimitPicker {
    var entries = current
    let selection = settings.menuBarLimitID ?? ""
    if !entries.contains(where: { $0.id == selection }) {
        let title = settings.menuBarLimitTitle.map { "\($0) (not available)" } ?? "—"
        entries.append(.init(id: selection, title: title))
    }
    return MenuBarLimitPicker(entries: entries, selection: selection, isDisabled: current.isEmpty)
}
