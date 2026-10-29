# Grok compatibility and verification

Implementation of [#39](https://github.com/chris-metz/pacemark/issues/39), verified on macOS 27.0.1 with Apple Swift 6.4 on 2026-10-29, against the Grok CLI 1.0.70 (alpha channel, installed through mise) with a SuperGrok login. No credentials, account identity or live utilization were recorded in fixtures or test logs.

## Supported CLI policy

Pacemark accepts any installed CLI version and does not run `grok --version`, as for Codex and Kimi. The responses decide compatibility: an agent that ends before its first answer, a missing method, or an answer that doesn't decode shows "Can't read Grok limits". [ADR 0006](adr/0006-grok-limits-via-local-agent.md) explains why Pacemark uses the agent interface.

## Exchange

Each query starts `grok agent --no-leader stdio`. The agent speaks ACP, JSON-RPC 2.0 with one message per line. Pacemark sends `initialize` (`protocolVersion` 1, no client capabilities), `_x.ai/auth/info`, `_x.ai/billing` and `_x.ai/auth/info` again. It matches each answer by its `id` and skips the notifications the agent sends in between (models, settings, announcements, MCP servers). The extension methods need the leading underscore; without it the agent answers `-32601`. Neither `authenticate` nor `session/new` is needed.

`_x.ai/auth/info` without a login answers with every field `null`, and `_x.ai/billing` answers the JSON-RPC error `-32000 Authentication required`. Both show "Sign in to Grok". `-32601` and `-32602` show "Can't read Grok limits". Other JSON-RPC errors, and the overall timeout, are temporary.

Discovery checks `~/.grok/bin` (the official installer's location), `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, then the user's interactive login shell, which resolves mise's `grok`. The child environment contains only `HOME`, `USER`, `PATH` (the binary's directory first) and `GROK_TELEMETRY_ENABLED=0`. `XAI_API_KEY`, `GROK_HOME`, config and endpoint overrides are not inherited, and custom `GROK_BIN_DIR` or `GROK_HOME` locations are not discovered. The agent runs in a fresh, empty temporary directory, which is removed afterwards, so it loads no project configuration. `--no-leader` keeps it from starting or joining a shared leader process. The whole exchange has one thirty-second deadline and a 2 MiB stdout ceiling. Stderr and account data are not logged.

Pacemark stops the agent by closing its input. The real agent then exits with status 0 after about 2.1 s. An agent that keeps running gets SIGTERM after three seconds and SIGKILL two seconds later. After a timeout or cancellation, Pacemark sends SIGTERM right away. Each start touches Grok's session search index and log and fetches models, settings and announcements from xAI. It creates no session and starts no model turn.

## Readings and identity

`config.currentPeriod` becomes one limit. A type ending in `_WEEKLY` is the weekly limit (`grok/weekly`); a type ending in `_MONTHLY` is the monthly limit (`grok/monthly`). Grok reports the window's start and end, so the window length is exact and the reset time is the end. Utilization is `creditUsagePercent` as delivered and may exceed 100. The limit is the Overview limit and, like Codex and Kimi readings, waits for a current answer after an observed reset instead of assuming zero. A `config` without `currentPeriod` yields no limits, so Overview shows "No weekly limit reported". The prepaid balance, the subscription tier and the on-demand fields are ignored.

The limit counts all use the subscription includes. On grok.com/dashboard/usage, calls with API keys created on grok.com appear as product "Grok API" with usage type "Included" and no cost, next to Grok Build, Cursor and Grok Bot.

The identity is the account's `principalId` and email. If it changes between the two `_x.ai/auth/info` reads, the response is discarded, as for Codex and Kimi.

## Verification

- Provider tests run a fake `grok` executable as a real child process that answers the agent's methods over stdio. They cover weekly and monthly periods, no period, utilization above 100, an unknown period type, `end ≤ start`, negative, non-numeric and missing percentages, a malformed timestamp, a missing `config`, an unexpected result, `-32601` and `-32602`, an agent that exits before its first answer, a missing login, a login that ends during the query, "Authentication required", service errors, an account switch, notifications between answers, the exact arguments, environment and working directory, stopping by closing input, the SIGTERM fallback, unresponsive processes, cancellation and a missing installation.
- Three implementations seen to fail during development were caught: an unknown period type taken as weekly, a missing SIGTERM fallback (the query waited 20 s for the fake agent), and a cancelled query read as an agent that exited, which showed "Can't read Grok limits".
- Native `NSHostingView` snapshots cover Overview with a Grok entry, the Grok tab, a Grok login problem and Settings with four providers, in light and dark. All 8 new reference images were visually inspected. The existing references are unchanged.
- The opt-in live check is `PACEMARK_LIVE_GROK=1 swift test --filter GrokProviderTests/installedCLICompatibility`. It passed against the installed 1.0.70 CLI in 3.5 s, including discovery through the login shell, and left no agent process or temporary directory behind.
- `swift build`, the full `swift test` and `scripts/release-notes-test.sh` passed.

## Deviations from #39

- With four enabled providers, the dropdown's five tab segments don't fit its 300 pt width at regular size (313 pt needed, 272 pt available), so the tab bar then uses the small control size (267.5 pt). The owner chose this on 2026-10-29 over a wider dropdown. With up to three providers, the dropdown is unchanged.
- `-32602 Invalid params` is an incompatible response too, as for Codex.
- A second `_x.ai/auth/info` without a login also shows "Sign in to Grok", as Codex does for its second account read.

## Not yet verified

- That `creditUsagePercent` is a percentage, not a ratio: compare it with the percentage on grok.com/dashboard/usage.
- The monthly period's type string; only `USAGE_PERIOD_TYPE_WEEKLY` was observed.
- An expired login, which Grok's README says happens after 7 days, presumably answering "Authentication required".
- Team accounts, for which the TUI can say "Usage limits are managed by your team".
- The "Install Grok" link to https://x.ai/cli, which answers 403 to curl; check it in a browser.
- The branch build in the real menu bar app (`scripts/install.sh`).
