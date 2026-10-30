import AppKit
import SwiftUI

/// The content of the menu bar item's window (§3). From two enabled
/// providers on, a sidebar with Overview and one entry per provider picks
/// the page on its right (#41); with fewer, the only provider's page or the
/// hint to enable one. Below is a footer with Settings… and Quit. Its state
/// lives in the model, because `MenuBarExtra` discards view state on close.
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
        if model.enabledProviders.count < 2 {
            singlePage
        } else {
            pagesWithSidebar
        }
    }

    /// Nothing to pick: 300 pt with the only provider's page and its update
    /// line in the footer, or the hint to enable providers.
    private var singlePage: some View {
        let display = model.enabledProviders.first.map { model.providerDisplay(for: $0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                if let display {
                    providerPage(display.dropdown)
                } else {
                    Text("Enable providers in Settings to see your limits.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            Divider()
            footer(updateLine: display?.updateLine)
                .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    /// 445 pt: the sidebar and the selected page at the 272 pt the rows had
    /// in the 300 pt dropdown. The width stays on every page.
    private var pagesWithSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                Sidebar(model: model)
                    .padding(.horizontal, 8)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    switch model.selectedPage {
                    case .overview:
                        ForEach(model.overview) { entry in overviewRow(entry) }
                    case .provider(let id):
                        let display = model.providerDisplay(for: id)
                        providerPage(display.dropdown)
                        if let line = display.updateLine {
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 272, alignment: .topLeading)
                .padding(.horizontal, 14)
            }
            Divider()
            footer(updateLine: nil)
                .padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 445)
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
            Button("Details") { model.selectedPage = .provider(providerID) }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    /// A provider's limit rows, or what stands in for them.
    @ViewBuilder private func providerPage(_ content: DropdownContent) -> some View {
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

/// Overview, then one entry per enabled provider with its Overview limit's
/// percentage and a dot when something needs attention (#41). Each entry is a
/// button that selects its page.
private struct Sidebar: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            entry(page: .overview, name: "Overview", percentText: nil, dot: nil, accessibilityText: "Overview")
            ForEach(model.sidebar) { entry in
                self.entry(page: .provider(entry.id), name: entry.name, percentText: entry.percentText,
                           dot: entry.dot, accessibilityText: entry.accessibilityText)
            }
        }
        .frame(width: 128)
    }

    private func entry(page: DropdownPage, name: String, percentText: String?, dot: LimitColor?,
                       accessibilityText: String) -> some View {
        let isSelected = model.selectedPage == page
        return Button {
            model.selectedPage = page
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dot?.color ?? .clear)
                    .frame(width: 7, height: 7)
                Text(verbatim: name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 4)
                if let percentText {
                    Text(verbatim: percentText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
