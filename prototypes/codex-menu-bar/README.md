# Codex menu bar prototype

**Question:** When Claude and Codex are available, does Pacemark show one fixed limit, follow the selected provider tab, or show both providers?

This is a throwaway HTML simulation of the native SwiftUI app. The three variants use the existing limit-row layout, pace markers, and footer. All numbers are illustrative. Codex has one weekly limit in this sample; actual available limits depend on the account. The sketches do not settle Codex's data source or limit mapping.

Open `index.html` directly, or run from this directory:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Then open <http://127.0.0.1:8765/>.

- `?variant=all`: compare all three. A now includes Overview; B and C remain as the original alternatives.
- `?variant=A`: one fixed limit, initially Claude's session limit, plus the new Overview tab. Overview starts with Claude's weekly limit at 63% and Codex's weekly limit at 20%.
- `?variant=A&scenario=fresh`: first launch with no providers enabled and no saved menu bar limit. Overview prompts the user to enable a provider in Settings.
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

Still to clarify: how the initial menu bar limit is chosen when the first provider is enabled; what happens when a provider has no general weekly limit; and how to show independent update times and errors across providers. The fresh-install prototype currently waits for an explicit menu bar choice after enabling a provider; that initial-pin behavior is provisional. The original screenshots preserve the alternatives before Overview was proposed.

Upgrade evidence: `SettingsStore.load()` reads defaults without writing a first-run marker. Only changing settings persists the five known preference keys: `refreshIntervalMinutes`, `showPercentage`, `hiddenLimits`, `menuBarLimitID`, and `menuBarLimitTitle`. Their presence can identify an earlier configured installation, but their absence cannot distinguish a new installation from an existing user who kept every default. Startup code does not store a previous version. Cache directories are not reliable evidence.
