# Codex menu bar prototype

## Current design review

Open [review.html](review.html) for the consolidated, interactive design reflecting all sixteen decisions below. It uses a 300-pixel dropdown, a separate 440-pixel Settings window, and the existing limit-row appearance. The user approved this design on 2026-10-13 after reviewing the consolidated prototype at commit `4f95b3c`. The native Swift app remains unchanged.

Open the file directly, or run from this directory:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Then open <http://127.0.0.1:8765/review.html>.

Try Overview, the provider tabs, Settings, and the menu bar item. Every reopening selects Overview. Settings lets you enable providers, choose the fixed menu bar limit, hide percentages, and control which rows appear in provider tabs. Scroll within Settings to reach Provider Tabs. All changes are simulated in memory; Reset demo restores the selected scenario.

The Scenario control sits outside the app preview:

| Scenario | What to inspect |
| --- | --- |
| Everyday use | Both weekly entries in Overview; all available windows in provider tabs. |
| First launch | No enabled providers; enabling the first provider selects its first available limit. |
| Upgrade with saved settings | Claude enabled, Codex disabled, existing selection and preferences retained. |
| Weekly limit hidden in its tab | Hiding a row does not remove it from Overview or change the menu bar selection. |
| Pinned provider disabled | Gauge only; re-enabling the provider restores its saved selection. |
| Codex sign-in required | Compact Overview error; Details opens instructions in the Codex tab. |
| Codex not installed | Installation instructions without blocking the healthy provider. |
| Codex still loading | Independent loading state with Claude's readings still available. |
| Codex unavailable, no data yet | Retry message without inventing utilization. |
| Codex values out of date | Last valid values and per-provider age; selected stale value is dimmed. |
| No general weekly limit | Placeholder, even when a model limit is available. |
| Reset time unavailable | Known utilization remains; reset text and pace marker are unavailable. |
| Codex window expired | Old utilization is hidden until a current reading arrives. |

All numbers, window labels, and models are illustrative. The sample Codex model row does not promise a particular limit on any account. No real provider, credential, preference, or app process is accessed. The appearance button changes only the simulated native interface. Actual fetching, migration, timers, login detection, and persistence are documented behavior, not implemented by the HTML.

Browser checks covered all thirteen scenario states, tab changes, reopening, Details navigation, independent provider errors, first-provider selection, disabling and restoring a saved pin, percentage visibility, and hiding a weekly row without changing Overview. Light and dark layouts and Settings scrolling were inspected. No browser console errors were observed. Native tests were not run because native sources were not changed.

Saved screenshots: [Overview](screenshots/review-overview.png), [Codex](screenshots/review-codex.png), [Settings](screenshots/review-settings.png), [Provider Tabs settings](screenshots/review-visibility.png), [compact error](screenshots/review-error-overview.png), [error details](screenshots/review-error-details.png), and [dark appearance](screenshots/review-dark.png).

## Earlier concepts

**Original question:** When Claude and Codex are available, does Pacemark show one fixed limit, follow the selected provider tab, or show both providers?

[index.html](index.html) preserves the original three alternatives and intermediate iterations. Use `review.html` for the complete agreed design.

- `?variant=all`: compare all three. A now includes Overview; B and C remain as the original alternatives.
- `?variant=A`: one fixed limit, initially Claude's session limit, plus the new Overview tab. Overview starts with Claude's weekly limit at 63% and Codex's weekly limit at 20%.
- `?variant=A&scenario=fresh`: first launch with no providers enabled and no saved menu bar limit. Overview prompts the user to enable a provider in Settings.
- `?variant=A&scenario=no-weekly`: a successful Codex response contains an illustrative five-hour limit but no general weekly limit. Overview keeps a Codex placeholder; its provider tab shows the available limit.
- `?variant=A&scenario=stale`: Claude updated just now; Codex failed to update and last succeeded twenty minutes ago. Each Overview entry shows its own status underneath. Pinning Codex demonstrates the existing dimmed menu bar treatment for stale values.
- `?variant=A&scenario=no-reset`: Codex reports 42% weekly utilization without a reset time. Keep its percentage and bar, show "Reset time unavailable," and omit the pace marker and pace text.
- `?variant=B`: the selected limit of the last opened provider.
- `?variant=C`: one limit per provider in a single wider menu bar item. This is one possible arrangement for showing both, not a separate settled decision.

Switch provider tabs, open the simulated Settings to choose limits, or click the menu bar item to close and reopen the dropdown. The bottom switcher and left/right arrow keys change variants. The appearance button previews light and dark. All state lives in memory. No real providers, credentials, preferences, or app processes are accessed.

**Decision:** the user selected **A — one fixed menu bar limit**. Opening another tab does not change the chosen limit. The existing Swift app remains unchanged. Prototype code and its switcher stay on `prototype/codex-menu-bar` and are not part of the Swift package's source targets.

**Overview decision:** add an **Overview** tab alongside Claude and Codex as the default view. It contains only each provider's general weekly limit, one per provider. Model limits with seven-day windows remain in the provider tabs. The fixed menu bar limit remains independent of Overview. A now demonstrates this with the existing bars, pace markers, reset lines, and footer.

**Reopening decision:** every opening of the dropdown selects Overview, including after the user inspected a provider tab. This changes only the visible tab; the pinned menu bar limit stays unchanged. Prototype A now demonstrates this when its menu bar item closes and reopens the dropdown.

**Provider selection decision:** users explicitly enable providers in Settings. Only enabled providers are queried and appear in Overview and provider tabs. An installed command-line tool does not automatically enable its provider. Prototype A now has switches that control its tabs, Overview rows, and available menu bar choices. The default prototype URL shows both providers enabled as sample state; the separate fresh-install scenario shows the actual first-launch decision.

**Disabled pin decision:** disabling the provider of the menu bar limit retains the saved selection and shows only the gauge, without a percentage. Pacemark does not switch to another provider automatically. Re-enabling the provider restores the selected limit; the user can also pick a limit from another enabled provider. Prototype A already demonstrates this behavior.

**Fresh-install decision:** a new installation starts with no providers enabled. The menu bar shows only the gauge; Overview prompts the user to enable providers in Settings. Nothing is queried until a provider is enabled. An empty selection is a valid state.

**Upgrade decision:** when no provider selection has been saved yet, the presence of any existing Pacemark preference key enables Claude and leaves Codex disabled. Without existing saved preferences, both providers start disabled. Preserve the existing menu bar selection and all other settings. Persist the resulting provider selection so a deliberately empty selection remains empty on later launches. Existing users who never changed a setting may need to enable Claude once, because they cannot reliably be distinguished from fresh installations.

**Initial menu bar selection decision:** when there is no saved menu bar selection, automatically select the first enabled provider's first available limit once its limits load. For Claude, this is the session limit. The user can change the selection in Settings. Never replace an existing selection, including one belonging to a disabled provider. The fresh-install prototype demonstrates this with immediately available sample limits.

**Missing weekly limit decision:** after a successful response without a general weekly limit, keep that enabled provider in Overview with the text "No weekly limit reported." Show no percentage or bar for that entry. The provider's own tab remains available and shows its reported limits. This is distinct from loading or a failed query, and does not imply zero utilization or unlimited use. Prototype A demonstrates the case with `scenario=no-weekly`.

**Update status placement decision:** show each provider's update time and error status directly below its entry in Overview. Remove the shared update-age line from Overview's footer; Settings and Quit stay there. Individual provider tabs keep that provider's status in their own footer. Age still means time since the last successful query. The `scenario=stale` preview retains Codex's last value using the current temporary-failure behavior and leaves Claude's status independent.

**Codex setup decision:** require an installed Codex CLI with an existing persistent ChatGPT login. Pacemark reuses that login for account and rate-limit reads through the documented local app-server interface. Show installation or sign-in instructions when the prerequisite is missing. Pacemark does not initiate sign-in, cancellation, or logout; Codex continues to manage credentials. Enabling Codex for monitoring remains an explicit Settings choice. Claude's existing CLI integration and setup stay unchanged.

**Incomplete timing decision:** preserve known Codex utilization when a reset time is missing. Show its percentage and bar with "Reset time unavailable," without a pace marker or pace text. Complete Claude readings keep their existing appearance. The `scenario=no-reset` preview demonstrates 42% utilization with no reset time.

**Expired Codex window decision:** once a previously observed Codex reset time has passed, hide that window's old percentage, bar, and pace until a fresh reading establishes current utilization. Show "Waiting for updated limits." If this is the selected menu bar limit, show only the gauge and retain the selection. A failed refresh still has its own provider status. This differs from a missing reset time accompanying a newly reported percentage, which remains displayable. Claude's existing reset behavior stays unchanged. The consolidated preview includes this state.

**Limit visibility decision:** existing per-limit visibility switches apply only to the provider tabs. Overview always retains the general weekly entry for every enabled provider, including the agreed placeholders and status lines. Rename the Settings section to "Provider Tabs" so the scope is clear. Preserve saved hidden-limit preferences and the independent menu bar selection. Disabling an entire provider still removes it from Overview and removes its provider tab. The consolidated preview includes these controls.

**Codex limit scope decision:** the Codex tab shows all reported usage-limit windows, including general limits and limits for individual models. Overview keeps only the general weekly entry. Additional model limits can be selected for the menu bar and hidden in the Codex tab using the same controls as other limits. Credit balances and API spending are separate from usage-limit windows and are outside this addition. The consolidated preview includes an illustrative Codex model limit.

**Compact error decision:** Overview shows a short message for an affected provider and a Details link that opens its provider tab. Full setup or recovery instructions belong there. A healthy provider remains usable. Loading and temporary failures without previous values also have their own provider presentation. The menu bar reflects the selected limit's provider; an error elsewhere does not replace its healthy percentage. The consolidated preview includes installation, sign-in, loading, and temporary-failure scenarios.

The user approved the consolidated prototype before closing the discussion. Product decisions are settled. Account scope is the current Codex CLI's persistent ChatGPT login; this addition does not introduce account management. The implementation outline below is a handoff from this design review; engineering compatibility checks remain, and native implementation has not started.

## Implementation outline

For example, hiding `claude/weekly` must remove that row from the Claude tab while retaining its Overview entry. If `codex/weekly` is selected for the menu bar and Codex is disabled, the saved selection stays `codex/weekly` and the menu bar shows only the gauge. These are independent settings and display decisions; changing tabs must not rewrite either one.

```text
Before
PacemarkApp -> AppModel -> ClaudeProvider
                |-> one provider state and refresh schedule
                |-> dropdown and menu bar display

After
PacemarkApp -> AppModel -> enabled providers
                |           |-> ClaudeProvider -> Claude CLI
                |           `-> CodexProvider  -> Codex app-server
                |-> independent state and schedule per provider
                |-> Overview and provider tabs
                `-> one saved menu bar limit
```

1. **Extend the shared limit model.** In `Sources/PacemarkKit/Provider.swift`, represent known utilization independently of reset time and identify the general weekly limit explicitly. Update `limitDisplay()` in `LimitDisplay.swift` to distinguish incomplete Codex timing, an expired Codex reading, and Claude's inactive window. Preserve existing qualified limit IDs and Claude behavior.
2. **Add the Codex provider.** Add a separate `Sources/PacemarkCodex/` target and tests in `Package.swift`. Keep binary discovery, the local app-server exchange, authentication classification, response parsing, and setup wording inside it. Normalize all reported usage-limit windows and give them stable IDs. Use the verified general-bucket mapping below; model limits must never stand in for the general weekly entry.
3. **Extend state, scheduling, and settings together.** Change `AppModel` to own a registry of providers and independent `ProviderState`/refresh work for each enabled provider. Keep one owner of shared settings and one in-flight query per provider. Extend `Settings` and `SettingsStore.load/save` with explicit provider choices and the agreed fresh-install/upgrade migration. Disabling a provider stops its work and rejects late results without erasing the saved menu bar selection. Apply the existing global refresh preference independently to enabled providers. Preserve Claude's scheduling behavior; verify Codex's handling of post-reset queries separately from the existing 65-second reset delay.
4. **Build the approved native views.** Extend `DropdownView.swift` with Overview and provider tabs, and `SettingsView.swift` with provider switches, the cross-provider limit picker, and Provider Tabs visibility. Keep selected-tab state in `AppModel` and reset it to Overview on every opening. Separate provider displays from the selected menu bar display in `Display.swift`; retain the drawn `MenuBarLabel` image. Register both providers in `Sources/Pacemark/PacemarkApp.swift`.
5. **Verify and update product documentation.** Cover migration and restart persistence, independent failures and retries, enable/disable races, selection preservation, all Overview placeholders, missing reset times, and expired Codex readings. Use fixture-based Codex protocol tests and retain Claude's regression suite. Add native light/dark snapshots and inspect real `MenuBarExtra` opening and Settings sizing. Update the root `README.md` and `scripts/release-notes.sh` so CLI requirements match the providers a user enables.

The data flow is:

```text
on launch: load settings, migrate once, query only enabled providers
on provider result: reject obsolete results, update only that provider
on limits from the first enabled provider, if no selection is saved: select its first limit
on menu opening: show Overview; leave the saved menu bar selection alone
on an observed Codex reset: hide that old reading until current data arrives
```

The existing Claude query path, complete-reading pace calculation, refresh preference, hidden-limit IDs, menu bar selection, launch-at-login setting, and native app shell remain. The provider adapter and shared representation may need mechanical changes to preserve those behaviors.

Before merging native implementation, validate the Codex protocol against the researched CLI 0.162.1 baseline and establish a supported-version policy. Include fixtures for optional fields, unknown fields, absent or ambiguous windows, malformed responses, setup failures, and available account-identity changes. The prototype does not resolve binary compatibility or prove native window behavior. These are engineering checks, not further product questions.

## Engineering evidence

Upgrade evidence: `SettingsStore.load()` reads defaults without writing a first-run marker. Only changing settings persists the five known preference keys: `refreshIntervalMinutes`, `showPercentage`, `hiddenLimits`, `menuBarLimitID`, and `menuBarLimitTitle`. Their presence can identify an earlier configured installation, but their absence cannot distinguish a new installation from an existing user who kept every default. Startup code does not store a previous version. Cache directories are not reliable evidence.

Current error and age behavior: `ProviderState.record` in `Sources/PacemarkKit/RefreshSchedule.swift` retains values on temporary failures and clears them on persistent problems. `Display.swift` marks a failed refresh as stale only when the last successful query is more than two refresh intervals old; at the default interval, that means more than ten minutes. Stale values remain in the dropdown, its footer says "Couldn't update · Last update … ago," and the menu bar value is dimmed. Persistent problems replace rows with an actionable message and show a warning triangle in the menu bar. Update age means time since the last successful query, not the latest attempt. `DropdownView.swift` currently renders one footer for its single provider. The consolidated preview extends that presentation independently per provider, with the agreed exception for expired Codex readings. Exact Codex error classification remains an implementation task.

Codex mapping evidence: `ActiveWindow` in `Sources/PacemarkKit/Provider.swift` currently requires utilization and reset time together. Codex CLI 0.162.1's generated `RateLimitWindow` schema permits `{ "usedPercent": 42, "windowDurationMins": 10080, "resetsAt": null }`; only utilization is required in a present window. The accepted incomplete-timing decision requires representing those facts independently. A known duration identifies a seven-day window; pace additionally needs a valid reset time. `LimitDisplay.swift` currently maps expired or missing windows to 0% and "Starts with your next message." That Claude-specific assumption must not erase known Codex utilization or invent a zero after a Codex reset.

General Codex bucket mapping is verified against official `openai/codex` tag `rust-v0.162.1`, commit `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`. The [backend client](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/backend-client/src/client.rs#L613-L652) assigns `limitId: "codex"` to ordinary plan usage and appends additional buckets separately. Prefer `rateLimitsByLimitId["codex"]`; when the map is absent, accept the legacy bucket only when its ID is `codex` or absent. The [legacy selection](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/app-server/src/request_processors/account_processor.rs#L1239-L1256) can fall back to a different bucket, so its explicit ID matters. Inspect both primary and secondary windows by duration. Upstream's [weekly classification](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/tui/src/chatwidget/rate_limits.rs#L103-L145) uses 10,080 minutes with a 5% tolerance; use the actual returned duration for pace. An absent or ambiguous weekly window produces the agreed Overview placeholder.

Account-change implementation evidence: the stable interface exposes email/plan in `account/read` and optional account/workspace ID in the rate-limit response. Workspace ID alone does not identify a person: upstream [identity tests](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/app-server/tests/suite/v2/rate_limits_identity_tests.rs#L29-L35) distinguish a user switch within the same workspace. Associate cached readings with the available email and workspace ID, and clear them when identity changes. Discard pending results from an old identity. A fresh app-server process per query avoids relying on cross-process notifications or long-lived [authentication caches](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/login/src/auth/manager.rs#L2387-L2412). Do not claim guaranteed detection of every switch when identity fields are absent. These are implementation recommendations, not additional account-management features. No live account or credentials were accessed.

Codex connection evidence: the [official app-server documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints) documents account and rate-limit reads through an installed Codex CLI. The sequence is `codex app-server --listen stdio://`, `initialize` / `initialized`, `account/read` with `refreshToken: false`, then `account/rateLimits/read`. These account methods need no thread or model turn. Managed authentication keeps token storage and refresh within Codex. This supports the chosen existing-login setup.

Alternative considered and deferred: the same interface supports a Pacemark sign-in button through `account/login/start` with `type: "chatgpt"`, returning a browser URL. This would add completion, cancellation, and error handling while still using the installed CLI and Codex-managed credentials. The [authentication storage documentation](https://learn.chatgpt.com/docs/auth#login-caching) describes a shared cached login; sign-in or logout can therefore affect other clients using that store. Ephemeral credentials in another process are not a reusable login. The [CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-app-server) marks app-server experimental; compatible-version handling remains an implementation question. Documentation was checked without accessing credentials or querying the user's live account.
