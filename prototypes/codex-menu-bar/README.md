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
- `?variant=B`: the selected limit of the last opened provider.
- `?variant=C`: one limit per provider in a single wider menu bar item. This is one possible arrangement for showing both, not a separate settled decision.

Switch provider tabs, open the simulated Settings to choose limits, or click the menu bar item to close and reopen the dropdown. The bottom switcher and left/right arrow keys change variants. The appearance button previews light and dark. All state lives in memory. No real providers, credentials, preferences, or app processes are accessed.

**Decision:** the user selected **A — one fixed menu bar limit**. Opening another tab does not change the chosen limit. The existing Swift app remains unchanged. Prototype code and its switcher stay on `prototype/codex-menu-bar` and are not part of the Swift package's source targets.

**Overview decision:** add an **Overview** tab (working name) alongside Claude and Codex as the default view. It contains only each provider's general weekly limit, one per provider. Model limits with seven-day windows remain in the provider tabs. The fixed menu bar limit remains independent of Overview. A now demonstrates this with the existing bars, pace markers, reset lines, and footer.

Still to clarify: what happens when a provider has no general weekly limit; whether Overview is restored on every dropdown open or only at launch; and how to show independent update times and errors across providers. The prototype currently starts A on Overview and retains the selected tab when the simulated dropdown reopens; that reopening behavior is not a settled decision. The original screenshots preserve the alternatives before Overview was proposed.
