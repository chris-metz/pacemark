# Codex compatibility and verification

Implementation of [#36](https://github.com/chris-metz/pacemark/issues/36), verified on macOS 27.0.1 with Apple Swift 6.4 on 2026-10-13.

## Supported CLI policy

Pacemark accepts any installed CLI version and does not run `codex --version`. Compatibility is decided by the responses: an unknown method, invalid parameters, or a response that doesn't decode shows "Can't read Codex limits". The original release accepted exactly `codex-cli 0.162.1`; that allowlist was dropped because it blocked 0.163.0, which answers correctly. Claude retains its existing minimum version and integration.

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints) defines the initialization and account-read protocol. The [CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-app-server) marks app-server experimental. The installed 0.162.1 CLI's `app-server generate-json-schema` output was also inspected. Live compatibility was checked with its persistent ChatGPT login; no credentials, account identity, or live utilization were recorded in fixtures or test logs.

Each query launches a fresh `codex app-server --listen stdio://`, initializes it, reads the account with `refreshToken: false`, reads limits, and reads the account again before accepting the response. No thread or model turn is created. Routine `account/updated` notifications occur during ordinary reads; available identity fields, rather than the notification alone, decide whether to discard a response.

Discovery checks local and Homebrew locations, then the user's interactive login shell. Child environments omit inherited API-key and agent credential overrides. The CLI uses its default persistent login. Custom `CODEX_HOME` locations are not discovered. Shell lookup has a five-second deadline; the complete app-server exchange has a thirty-second deadline and a 2 MiB output ceiling. Cancellation, timeout, and normal completion terminate the process group and await process cleanup. Stderr and account data are not logged.

## Readings and identity

The general bucket is the map entry `codex`; legacy responses are general only when their bucket ID is `codex` or absent. A present map takes precedence, even when it has no general bucket. Both window slots are inspected. Exactly one general window within 5% of 10,080 minutes identifies the Overview weekly entry; actual duration drives pace. Model buckets never become that entry.

IDs use upstream window slots: `codex/primary`, `codex/secondary`, and `codex/model:<bucket-id>/<slot>`. They remain stable when timing fields disappear. Claude's existing qualified IDs are unchanged.

Cached readings carry available email and account/workspace identity in memory. A conflicting known field clears them, including on a failed refresh. Missing fields do not prove a switch. The before/after account check rejects detectable changes during a request; provider generations reject results after disable/re-enable. Neither this protocol nor Pacemark can guarantee detection of switches without identifying fields.

Codex schedules a query at the observed reset, independently of Claude's existing 65-second delay. An expired response remains hidden even when a query succeeds with the old timestamp. Temporary failure retains other valid readings and their original successful-update age. No live reset boundary was waited for; reset timing and delayed responses are covered with fixed clocks and fixtures.

## Verification

- Fixture-driven child-process tests exercise the real JSON-RPC transport, general/model windows, unknown fields, missing timing, empty/ambiguous weekly data, malformed data, login problems, any CLI version, temporary service failure, account changes, ordinary notifications, timeouts, and cancellation/cleanup.
- Model/settings tests cover migration from each of the five legacy keys, persisted empty choices, first-provider selection, independent work, hidden weekly rows, fixed selection, and obsolete completions.
- Display regression tests retain Claude's pace, reset, stale-age, and drawn menu bar behavior.
- Native `NSHostingView` snapshots cover Overview, Codex/model windows, setup, placeholders, errors/details, loading, temporary failure, missing reset, expiry, all-hidden tabs, stale readings, and Settings in light/dark. All 60 new or changed reference images were visually inspected.
- The opt-in live check is `PACEMARK_LIVE_CODEX=1 swift test --filter installedCLICompatibility`. It passed against the installed 0.162.1 CLI after verifying the normal account notification behavior. After the version gate was dropped, it passed against 0.163.0 on 2026-10-16.
- Final `swift build` and full `swift test` passed. The live compatibility test is opt-in and was run separately; the default suite requires no account. Release preparation also checks that later release notes include the current CLI requirements and that requirements alone cannot create a release without new merges.

## Review against `f09c192`

Standards and Spec were reviewed by separate agents. The obsolete single-provider picker helper was removed, and its tests now exercise the production picker. A final model regression test also exposed an initial-selection gap: when Claude had no limits and was disabled, already loaded Codex limits became the first available choice but were not selected until another query. Reconciliation now selects that limit immediately, only when no choice is saved. Both fixes were rechecked before the full test run.

### Standards

No documented-standard violations or remaining actionable findings. One optional maintainability observation remains: a per-provider runtime value could group the lifecycle dictionaries in `AppModel`. No lifecycle defect was found from their current shape.

### Spec

No remaining code findings or unrequested scope. Native verification combines the agent's Settings checks and the owner's manual acceptance below.

## Native interaction verification

A separate `Pacemark Verification.app` bundle was built and launched with its own preference domain. Initial Computer Use attempts were blocked by pending macOS Accessibility and Screen Recording permissions. After access was granted, Computer Use verified both provider switches, loaded limit controls, scrolling to the lower controls and footer in the 440 × 520 point native Form, and reopening the app to bring Settings forward.

Computer Use could not reach the menu bar status item, so dropdown reopening, tab clicks, and menu bar color/dimming were left to manual testing. The owner tested the rebuilt app from commit `7fd0f33`, installed in `/Applications/Pacemark.app`, reported that it looked good, and approved the release. The automated snapshots and model tests do not independently establish the real `MenuBarExtra` lifecycle.
