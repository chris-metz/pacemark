import AppKit
import SwiftUI

/// The content of the menu bar item's window (§3): the limit rows or what
/// stands in for them, and a footer with the update line, Settings… and Quit.
/// Its state lives in the model, because `MenuBarExtra` discards view state
/// on close.
public struct DropdownView: View {
    @Bindable var model: AppModel

    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    /// Closes the dropdown.
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("View", selection: $model.selectedTab) {
                Text("Overview").tag(DropdownTab.overview)
                ForEach(model.enabledProviders, id: \.id) { provider in
                    Text(provider.name).tag(DropdownTab.provider(provider.id))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 14) {
                switch model.selectedTab {
                case .overview:
                    if model.overview.isEmpty {
                        Text("Enable providers in Settings to see your limits.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.overview) { entry in overviewRow(entry) }
                    }
                case .provider(let id):
                    content(model.providerDisplay(for: id).dropdown)
                }
            }
            .padding(.horizontal, 14)
            Divider()
            footer(updateLine: updateLine)
                .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    private var updateLine: String? {
        guard case .provider(let id) = model.selectedTab else { return nil }
        return model.providerDisplay(for: id).updateLine
    }

    private func overviewRow(_ entry: OverviewEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if case .limit(let limit) = entry.content {
                var row = limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale)
                let _ = row.title = "\(entry.name) · \(limit.title)"
                let _ = row.accessibilityText = "\(entry.name), \(row.accessibilityText)"
                LimitRow(display: row)
            } else {
                Text(entry.name).font(.system(size: 13, weight: .semibold))
                switch entry.content {
                case .limit: EmptyView()
                case .noWeeklyLimit: Text("No weekly limit reported").foregroundStyle(.secondary)
                case .loading: Text("Loading…").foregroundStyle(.secondary)
                case .noValues: compactProblem("Can't load limits right now", providerID: entry.id)
                case .problem(let problem): compactProblem(problem.heading, providerID: entry.id)
                }
            }
            if let line = entry.updateLine {
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactProblem(_ message: String, providerID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).foregroundStyle(.secondary)
            Button("Details") { model.selectedTab = .provider(providerID) }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder private func content(_ content: DropdownContent) -> some View {
        switch content {
        case .loading:
            Text("Loading…")
                .foregroundStyle(.secondary)
        case .problem(let problem):
            ProblemView(problem: problem)
        case .limits(let limits):
            ForEach(limits) { limit in
                LimitRow(display: limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale))
            }
        case .allHidden:
            Text("All limits are hidden.")
                .foregroundStyle(.secondary)
        case .noValues:
            ProblemView(problem: Problem(
                heading: "Can't load your limits right now",
                message: "Trying again shortly.",
                link: nil
            ))
        }
    }

    private func footer(updateLine: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let updateLine {
                Text(updateLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Settings…") {
                    dismiss()
                    openWindow.openSettings()
                }
                .keyboardShortcut(",")
                QuitButton("Quit")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

/// A heading, a Markdown message and an optional link, in place of the
/// limit rows (§3 Other contents). The message is selectable so a command
/// like `claude update` can be copied.
private struct ProblemView: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.heading)
                .font(.system(size: 13, weight: .semibold))
            Text(markdown(problem.message))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let link = problem.link {
                Link(link.title, destination: link.url)
                    .padding(.top, 4)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The message with inline Markdown such as `code`; as plain text if it
    /// doesn't parse.
    private func markdown(_ message: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message, options: options)) ?? AttributedString(message)
    }
}
