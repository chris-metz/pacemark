import AppKit
import SwiftUI

// PROTOTYPE, throwaway: never merge into main. Lives on the branch
// prototype/dropdown-without-tabs.
//
// Question: what should the dropdown look like with four providers, now that
// the segmented tab bar no longer fits its 300 pt?
//
// Five layouts without the segmented tab bar, on the real dropdown with real
// data, switchable with the bar at the bottom or with ← and →. Shown only
// when Pacemark runs with `-PrototypeDropdown YES`; otherwise the app shows
// the normal DropdownView.

public enum PrototypeVariant: String, CaseIterable, Sendable {
    case a = "A", b = "B", c = "C", d = "D", e = "E"

    public var name: String {
        switch self {
        case .a: "One list"
        case .b: "Accordion"
        case .c: "Compact table"
        case .d: "Sidebar"
        case .e: "Menu instead of tabs"
        }
    }
}

/// Whether the app shows the prototype instead of the normal dropdown.
public var isDropdownPrototypeEnabled: Bool {
    UserDefaults.standard.bool(forKey: "PrototypeDropdown")
}

public struct PrototypeDropdownView: View {
    @Bindable var model: AppModel
    /// Fixed for rendering; nil follows the switcher.
    let fixedVariant: PrototypeVariant?
    let showsSwitcher: Bool

    @AppStorage("PrototypeDropdownVariant") private var storedVariant = PrototypeVariant.a.rawValue

    public init(model: AppModel, variant: PrototypeVariant? = nil, showsSwitcher: Bool = true) {
        self.model = model
        fixedVariant = variant
        self.showsSwitcher = showsSwitcher
    }

    private var variant: PrototypeVariant {
        fixedVariant ?? PrototypeVariant(rawValue: storedVariant) ?? .a
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch variant {
            case .a: OneListVariant(model: model)
            case .b: AccordionVariant(model: model)
            case .c: CompactTableVariant(model: model)
            case .d: SidebarVariant(model: model)
            case .e: MenuVariant(model: model)
            }
            if showsSwitcher {
                PrototypeSwitcher(variant: variant) { storedVariant = $0.rawValue }
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - A: One list

/// Every enabled provider with all its limits, one after the other. No
/// navigation at all; each section has its own update line.
private struct OneListVariant: View {
    let model: AppModel
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 18) {
                if model.enabledProviders.isEmpty {
                    Text("Enable providers in Settings to see your limits.").foregroundStyle(.secondary)
                }
                ForEach(model.enabledProviders, id: \.id) { provider in
                    let display = model.providerDisplay(for: provider.id)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(provider.name.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let line = display.updateLine {
                                Text(line).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        PrototypeContent(content: display.dropdown, now: model.now, timeZone: timeZone, locale: locale)
                    }
                }
            }
            .padding(.horizontal, 14)
            Divider()
            PrototypeFooter(updateLine: nil).padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }
}

// MARK: - B: Accordion

/// Today's Overview, with a disclosure chevron per provider. A click opens
/// that provider in place, with all its limits; one at a time.
private struct AccordionVariant: View {
    let model: AppModel
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                if model.overview.isEmpty {
                    Text("Enable providers in Settings to see your limits.").foregroundStyle(.secondary)
                }
                ForEach(model.overview) { entry in
                    section(entry)
                }
            }
            .padding(.horizontal, 14)
            Divider()
            PrototypeFooter(updateLine: nil).padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    private func isExpanded(_ id: String) -> Bool {
        model.selectedTab == .provider(id)
    }

    private func section(_ entry: OverviewEntry) -> some View {
        let expanded = isExpanded(entry.id)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 8) {
                if expanded {
                    let display = model.providerDisplay(for: entry.id)
                    Text(entry.name).font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 12) {
                        PrototypeContent(content: display.dropdown, now: model.now, timeZone: timeZone, locale: locale)
                    }
                } else {
                    PrototypeOverviewRow(entry: entry, now: model.now, timeZone: timeZone, locale: locale)
                }
                if let line = entry.updateLine {
                    Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                model.selectedTab = expanded ? .overview : .provider(entry.id)
            }
        }
    }
}

// MARK: - C: Compact table

/// Every limit of every provider on one line: short name, bar with pace
/// marker, percentage and reset. Pace text and full reset line in the
/// tooltip.
private struct CompactTableVariant: View {
    let model: AppModel
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if model.enabledProviders.isEmpty {
                    Text("Enable providers in Settings to see your limits.").foregroundStyle(.secondary)
                }
                ForEach(model.enabledProviders, id: \.id) { provider in
                    let display = model.providerDisplay(for: provider.id)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(provider.name).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if let line = display.updateLine {
                                Text(line.replacingOccurrences(of: "Updated ", with: ""))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        switch display.dropdown {
                        case .limits(let limits):
                            ForEach(limits) { limit in
                                compactRow(limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale))
                            }
                        case .loading:
                            Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
                        case .allHidden:
                            Text("All limits are hidden.").font(.system(size: 11)).foregroundStyle(.secondary)
                        case .noValues:
                            Text("Can't load limits right now").font(.system(size: 11)).foregroundStyle(.secondary)
                        case .problem(let problem):
                            Label(problem.heading, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .help(problem.message)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            Divider()
            PrototypeFooter(updateLine: nil).padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    private func compactRow(_ row: LimitDisplay) -> some View {
        HStack(spacing: 8) {
            Text(shortTitle(row.title))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 62, alignment: .leading)
            PrototypeBar(fillFraction: row.fillFraction, fillColor: row.fillColor.color, paceMarker: row.paceMarker)
            Text(row.percentText)
                .monospacedDigit()
                .fontWeight(.semibold)
                .frame(width: 34, alignment: .trailing)
            Text(shortReset(row.resetLine))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)
        }
        .font(.system(size: 11))
        .help([row.resetLine, row.paceText].compactMap { $0 }.joined(separator: " · "))
    }

    private func shortTitle(_ title: String) -> String {
        title.hasSuffix(" limit") ? String(title.dropLast(6)) : title
    }

    private func shortReset(_ line: String) -> String {
        if line.hasPrefix("Resets in ") { return String(line.dropFirst(10)) }
        if line.hasPrefix("Resets ") { return String(line.dropFirst(7)) }
        return "–"
    }
}

// MARK: - D: Sidebar

/// A wider dropdown: providers listed on the left with their Overview
/// percentage and a dot when something needs attention, the selected page on
/// the right. With fewer than two enabled providers there is no sidebar: one
/// provider's page, or the hint to enable providers, at 300 pt.
private struct SidebarVariant: View {
    let model: AppModel
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        if model.enabledProviders.count < 2 {
            singlePage
        } else {
            sidebarLayout
        }
    }

    /// Decision 3: no sidebar with zero or one enabled provider.
    private var singlePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                if let provider = model.enabledProviders.first {
                    PrototypeContent(content: model.providerDisplay(for: provider.id).dropdown,
                                     now: model.now, timeZone: timeZone, locale: locale)
                } else {
                    Text("Enable providers in Settings to see your limits.").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            Divider()
            PrototypeFooter(updateLine: model.enabledProviders.first.flatMap { model.providerDisplay(for: $0.id).updateLine })
                .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    private var sidebarLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarItem(title: "Overview", tab: .overview, detail: nil, dot: nil)
                    ForEach(model.overview) { entry in
                        sidebarItem(title: entry.name, tab: .provider(entry.id),
                                    detail: detail(entry), dot: attention(entry))
                    }
                }
                .frame(width: 128)
                .padding(.horizontal, 8)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    switch model.selectedTab {
                    case .overview:
                        ForEach(model.overview) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                PrototypeOverviewRow(entry: entry, now: model.now, timeZone: timeZone, locale: locale)
                                if isProblem(entry) {
                                    Button("Details") { model.selectedTab = .provider(entry.id) }
                                        .buttonStyle(.link)
                                        .font(.system(size: 11))
                                }
                                if let line = entry.updateLine {
                                    Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    case .provider(let id):
                        let display = model.providerDisplay(for: id)
                        PrototypeContent(content: display.dropdown, now: model.now, timeZone: timeZone, locale: locale)
                        if let line = display.updateLine {
                            Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 272, alignment: .topLeading)
                .padding(.horizontal, 14)
            }
            Divider()
            PrototypeFooter(updateLine: nil).padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 445)
    }

    private func sidebarItem(title: String, tab: DropdownTab, detail: String?, dot: Color?) -> some View {
        let selected = model.selectedTab == tab
        return HStack(spacing: 6) {
            Circle()
                .fill(dot ?? .clear)
                .frame(width: 7, height: 7)
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer(minLength: 4)
            if let detail {
                Text(detail).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.primary.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedTab = tab }
    }

    private func isProblem(_ entry: OverviewEntry) -> Bool {
        switch entry.content {
        case .problem, .noValues: true
        case .limit, .noWeeklyLimit, .loading: false
        }
    }

    /// The Overview limit's percentage; – without values, … while loading.
    private func detail(_ entry: OverviewEntry) -> String? {
        switch entry.content {
        case .limit(let limit):
            let row = limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale)
            return row.state == .waitingForUpdate ? "–" : row.percentText
        case .noValues: return "–"
        case .loading: return "…"
        case .problem, .noWeeklyLimit: return nil
        }
    }

    /// Decision 4: red for a problem or any limit at 90 % or more, orange for
    /// any limit over pace, else no dot. Counts the limits on the provider's
    /// page and its Overview limit, even when hidden on the page.
    private func attention(_ entry: OverviewEntry) -> Color? {
        if case .problem = entry.content { return Color(nsColor: .systemRed) }
        var limits: [Limit] = []
        if case .limits(let shown) = model.providerDisplay(for: entry.id).dropdown { limits = shown }
        if case .limit(let overview) = entry.content { limits.append(overview) }
        let states = limits.map { limitDisplay($0, now: model.now, timeZone: timeZone, locale: locale).state }
        if states.contains(where: \.isRed) { return Color(nsColor: .systemRed) }
        if states.contains(.overPace) { return Color(nsColor: .systemOrange) }
        return nil
    }
}

// MARK: - E: Menu instead of tabs

/// Today's dropdown, with a pop-up menu in place of the segmented tab bar.
private struct MenuVariant: View {
    @Bindable var model: AppModel
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $model.selectedTab) {
                Text("Overview").tag(DropdownTab.overview)
                Divider()
                ForEach(model.enabledProviders, id: \.id) { provider in
                    Text(provider.name).tag(DropdownTab.provider(provider.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 14) {
                switch model.selectedTab {
                case .overview:
                    ForEach(model.overview) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            PrototypeOverviewRow(entry: entry, now: model.now, timeZone: timeZone, locale: locale)
                            if let line = entry.updateLine {
                                Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                case .provider(let id):
                    PrototypeContent(content: model.providerDisplay(for: id).dropdown,
                                     now: model.now, timeZone: timeZone, locale: locale)
                }
            }
            .padding(.horizontal, 14)
            Divider()
            PrototypeFooter(updateLine: updateLine).padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    private var updateLine: String? {
        guard case .provider(let id) = model.selectedTab else { return nil }
        return model.providerDisplay(for: id).updateLine
    }
}

// MARK: - Shared pieces

/// One provider's rows, or what stands in for them, as the provider tab
/// shows them today.
private struct PrototypeContent: View {
    let content: DropdownContent
    let now: Date
    let timeZone: TimeZone
    let locale: Locale

    var body: some View {
        switch content {
        case .loading:
            Text("Loading…").foregroundStyle(.secondary)
        case .problem(let problem):
            PrototypeProblemView(problem: problem)
        case .limits(let limits):
            ForEach(limits) { limit in
                LimitRow(display: limitDisplay(limit, now: now, timeZone: timeZone, locale: locale))
            }
        case .allHidden:
            Text("All limits are hidden.").foregroundStyle(.secondary)
        case .noValues:
            PrototypeProblemView(problem: Problem(heading: "Can't load your limits right now",
                                                  message: "Trying again shortly.", link: nil))
        }
    }
}

/// One Overview entry as today, without its update line.
private struct PrototypeOverviewRow: View {
    let entry: OverviewEntry
    let now: Date
    let timeZone: TimeZone
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch entry.content {
            case .limit(let limit):
                var row = limitDisplay(limit, now: now, timeZone: timeZone, locale: locale)
                let _ = row.title = "\(entry.name) · \(limit.title)"
                LimitRow(display: row)
            case .noWeeklyLimit:
                Text(entry.name).font(.system(size: 13, weight: .semibold))
                Text("No weekly limit reported").foregroundStyle(.secondary)
            case .loading:
                Text(entry.name).font(.system(size: 13, weight: .semibold))
                Text("Loading…").foregroundStyle(.secondary)
            case .noValues:
                Text(entry.name).font(.system(size: 13, weight: .semibold))
                Text("Can't load limits right now").foregroundStyle(.secondary)
            case .problem(let problem):
                Text(entry.name).font(.system(size: 13, weight: .semibold))
                Text(problem.heading).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrototypeProblemView: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.heading).font(.system(size: 13, weight: .semibold))
            Text((try? AttributedString(markdown: problem.message,
                                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(problem.message))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let link = problem.link {
                Link(link.title, destination: link.url).padding(.top, 4)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A slimmer LimitBar for the compact table: 5 pt high, marker 2 pt over.
private struct PrototypeBar: View {
    let fillFraction: Double
    let fillColor: Color
    let paceMarker: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 5)
                Capsule().fill(fillColor).frame(width: width * fillFraction, height: 5)
                if let paceMarker {
                    Rectangle().fill(.primary).frame(width: 1.5, height: 9)
                        .offset(x: width * paceMarker - 0.75)
                }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: 9)
    }
}

private struct PrototypeFooter: View {
    let updateLine: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let updateLine {
                Text(updateLine).font(.system(size: 11)).foregroundStyle(.secondary)
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

/// The prototype's own control, deliberately not styled like the app.
private struct PrototypeSwitcher: View {
    let variant: PrototypeVariant
    let select: (PrototypeVariant) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("PROTOTYPE \(variant.rawValue) · \(variant.name)")
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .systemPink)))
    }

    private func step(_ offset: Int) {
        let all = PrototypeVariant.allCases
        let index = all.firstIndex(of: variant)!
        select(all[(index + offset + all.count) % all.count])
    }
}
