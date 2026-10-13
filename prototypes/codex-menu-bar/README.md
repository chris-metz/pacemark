# Codex menu bar prototype

**Question:** When Claude and Codex are available, does Pacemark show one fixed limit, follow the selected provider tab, or show both providers?

This is a throwaway HTML simulation of the native SwiftUI app. The three variants use the existing limit-row layout, pace markers, and footer. All numbers are illustrative. Codex has one weekly limit in this sample; actual available limits depend on the account. The agreed Codex connection is recorded below; limit mapping remains under discussion.

Open `index.html` directly, or run from this directory:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Then open <http://127.0.0.1:8765/>.

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

**Overview decision:** add an **Overview** tab (working name) alongside Claude and Codex as the default view. It contains only each provider's general weekly limit, one per provider. Model limits with seven-day windows remain in the provider tabs. The fixed menu bar limit remains independent of Overview. A now demonstrates this with the existing bars, pace markers, reset lines, and footer.

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

Still to clarify: expired Codex readings, the scope of additional reported Codex limits, loading and persistent-problem presentation, and how existing visibility settings interact with Overview. Account-change behavior will be covered in the final design review. The user asked for an estimate; about five remaining decisions plus a final summary were proposed. Group related edge cases and resolve routine implementation choices through engineering research rather than adding interview questions. The original screenshots preserve the alternatives before Overview was proposed.

Upgrade evidence: `SettingsStore.load()` reads defaults without writing a first-run marker. Only changing settings persists the five known preference keys: `refreshIntervalMinutes`, `showPercentage`, `hiddenLimits`, `menuBarLimitID`, and `menuBarLimitTitle`. Their presence can identify an earlier configured installation, but their absence cannot distinguish a new installation from an existing user who kept every default. Startup code does not store a previous version. Cache directories are not reliable evidence.

Current error and age behavior, for the next design decisions: `ProviderState.record` in `Sources/PacemarkKit/RefreshSchedule.swift` retains values on temporary failures and clears them on persistent problems. `Display.swift` marks a failed refresh as stale only when the last successful query is more than two refresh intervals old; at the default interval, that means more than ten minutes. Stale values remain in the dropdown, its footer says "Couldn't update · Last update … ago," and the menu bar value is dimmed. Persistent problems replace rows with an actionable message and show a warning triangle in the menu bar. Update age means time since the last successful query, not the latest attempt. `DropdownView.swift` currently renders one footer for its single provider. Overview placement is settled above; Codex outcome mapping and presentation without previous values still need clarification.

Codex mapping evidence: `ActiveWindow` in `Sources/PacemarkKit/Provider.swift` currently requires utilization and reset time together. Codex CLI 0.162.1's generated `RateLimitWindow` schema permits `{ "usedPercent": 42, "windowDurationMins": 10080, "resetsAt": null }`; only utilization is required in a present window. The accepted incomplete-timing decision requires representing those facts independently. A known duration identifies a seven-day window; pace additionally needs a valid reset time. `LimitDisplay.swift` currently maps expired or missing windows to 0% and "Starts with your next message." That Claude-specific assumption must not erase known Codex utilization. What to show after a previously observed Codex reset time passes is still open.

Codex connection evidence: the [official app-server documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints) documents account and rate-limit reads through an installed Codex CLI. The sequence is `codex app-server --listen stdio://`, `initialize` / `initialized`, `account/read` with `refreshToken: false`, then `account/rateLimits/read`. These account methods need no thread or model turn. Managed authentication keeps token storage and refresh within Codex. This supports the chosen existing-login setup.

Alternative considered and deferred: the same interface supports a Pacemark sign-in button through `account/login/start` with `type: "chatgpt"`, returning a browser URL. This would add completion, cancellation, and error handling while still using the installed CLI and Codex-managed credentials. The [authentication storage documentation](https://learn.chatgpt.com/docs/auth#login-caching) describes a shared cached login; sign-in or logout can therefore affect other clients using that store. Ephemeral credentials in another process are not a reusable login. The [CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-app-server) marks app-server experimental; compatible-version handling remains an implementation question. Documentation was checked without accessing credentials or querying the user's live account.
