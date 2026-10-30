# Dropdown without tabs (prototype)

Throwaway prototype, never merged into `main`. Question: what should the dropdown look like with four providers, now that the segmented tab bar no longer fits its 300 pt?

## Why the tab bar broke

The segmented `Picker` in `DropdownView` makes every segment as wide as the widest label ("Overview"). Its natural width, measured with an `NSHostingView` on macOS 27.0.1:

| Segments | Natural width | Available |
|---|---|---|
| 3 (Overview + 2 providers) | 242 pt | 272 pt |
| 4 (Overview + 3 providers) | 322 pt | 272 pt |
| 5 (Overview + 4 providers, small) | 345 pt | 272 pt |

On the first layout, SwiftUI compresses the bar to 272 pt, which is what the snapshots and the first real-app check saw. After a tab switch the content height changes, the menu window measures again, and the bar takes its natural 345 pt. The stack becomes 373 pt wide, `.frame(width: 300)` centers it, and about 36 pt are cut off on each side. The owner's screenshot of 2026-10-30 matches: 69 pt segments, everything shifted about 36 pt left. The re-measuring itself was not reproduced in a real menu window.

## Variants

`PrototypeDropdownView` in `Sources/PacemarkKit/DropdownPrototype.swift`, shown with `scripts/prototype-dropdown.sh` (`-PrototypeDropdown YES`), switched with the pink bar or ← →. Renders of four providers in light and dark are in this directory (`PACEMARK_RENDER_PROTOTYPE=1 swift test --filter DropdownPrototypeRenders`).

- **A, One list**: every provider with all its limits, no navigation. About 650 pt high.
- **B, Accordion**: today's Overview with a disclosure chevron per provider; a click opens it in place.
- **C, Compact table**: one line per limit (short name, bar, percentage, reset); pace text in the tooltip.
- **D, Sidebar**: 445 pt wide; providers on the left with a dot and their Overview percentage, the selection's limits on the right.
- **E, Menu instead of tabs**: today's dropdown with a pop-up menu in place of the tab bar.

## Decisions

1. **Layout: D, Sidebar** (owner, 2026-10-30).
2. **Start page: Overview stays** the first sidebar entry and is selected on every opening, as decided in #36. Only Overview shows the pace of every provider at once; the sidebar's percentages help switching (owner, 2026-10-30).
3. **Sidebar only from two enabled providers.** With one, the dropdown stays 300 pt wide and shows that provider's limits directly, an exception to decision 2: Overview would only repeat its weekly or monthly limit. With none, it shows the hint to enable providers in Settings, also 300 pt wide (owner, 2026-10-30).
4. **The dot marks attention only**, across every limit of the provider: orange when any limit is over pace, red when any limit is at 90 % or more, exhausted, or when the provider has a problem; otherwise no dot. The percentage stays the provider's Overview limit (owner, 2026-10-30).
5. **"Provider page"** replaces "provider tab" in the glossary, README, Settings (section **Provider Pages**) and code (e.g. `DropdownTab` becomes `DropdownPage`) (owner, 2026-10-30).

## Details settled without a question

- With the sidebar the dropdown is 445 pt wide: a 128 pt sidebar and a page with today's 272 pt content width, so the limit rows look as they do today. It keeps that width on every page; only the height changes.
- The Overview page keeps today's content: one entry per provider with its own update line, and **Details** on a compact error, which selects that provider's page.
- A sidebar entry shows the Overview limit's percentage, `–` without values or while waiting for updated limits, `…` while loading, and nothing for a problem or a provider without a weekly or monthly limit.
- The dot counts the limits shown on the provider's page and its Overview limit, which Overview always shows. Limits hidden on the page don't count. A temporary failure or stale values give no dot.

## Renders after the decisions

- `d-attention-overview-*.png`: Overview with Claude fine (no dot), Codex's 5-hour limit over pace (orange), Kimi signed out (red) and Grok at 92 % (red).
- `d-attention-*.png`: the same, with Codex's page selected.
- `d-one-provider-*.png`: Claude alone, without a sidebar.
