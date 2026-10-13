# Codex compatibility and verification

Implementation of [#36](https://github.com/chris-metz/pacemark/issues/36), verified on macOS 27.0.1 with Apple Swift 6.4 on 2026-10-13.

## Supported CLI policy

This release accepts exactly `codex-cli 0.162.1`. It is a tested supported version, not a claim about the oldest compatible version. Other or unparseable versions receive installation/update instructions. Extend the allowlist only after repeating the protocol and process checks below. Claude retains its existing minimum version and integration.

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints) defines the initialization and account-read protocol. The [CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-app-server) marks app-server experimental. The installed 0.162.1 CLI's `app-server generate-json-schema` output was also inspected. Live compatibility was checked with its persistent ChatGPT login; no credentials, account identity, or live utilization were recorded in fixtures or test logs.

Each query launches a fresh `codex app-server --listen stdio://`, initializes it, reads the account with `refreshToken: false`, reads limits, and reads the account again before accepting the response. No thread or model turn is created. Routine `account/updated` notifications occur during ordinary reads; available identity fields, rather than the notification alone, decide whether to discard a response.

Discovery checks local and Homebrew locations, then the user's interactive login shell. Child environments omit inherited API-key and agent credential overrides. The CLI uses its default persistent login. Custom `CODEX_HOME` locations are not discovered. Shell lookup and the version probe each have a five-second deadline; the complete app-server exchange has a thirty-second deadline and a 2 MiB output ceiling. Cancellation, timeout, and normal completion terminate the process group and await process cleanup. Stderr and account data are not logged.

## Readings and identity

The general bucket is the map entry `codex`; legacy responses are general only when their bucket ID is `codex` or absent. A present map takes precedence, even when it has no general bucket. Both window slots are inspected. Exactly one general window within 5% of 10,080 minutes identifies the Overview weekly entry; actual duration drives pace. Model buckets never become that entry.

IDs use upstream window slots: `codex/primary`, `codex/secondary`, and `codex/model:<bucket-id>/<slot>`. They remain stable when timing fields disappear. Claude's existing qualified IDs are unchanged.

Cached readings carry available email and account/workspace identity in memory. A conflicting known field clears them, including on a failed refresh. Missing fields do not prove a switch. The before/after account check rejects detectable changes during a request; provider generations reject results after disable/re-enable. Neither this protocol nor Pacemark can guarantee detection of switches without identifying fields.

Codex schedules a query at the observed reset, independently of Claude's existing 65-second delay. An expired response remains hidden even when a query succeeds with the old timestamp. Temporary failure retains other valid readings and their original successful-update age. No live reset boundary was waited for; reset timing and delayed responses are covered with fixed clocks and fixtures.

## Verification

- Fixture-driven child-process tests exercise the real JSON-RPC transport, general/model windows, unknown fields, missing timing, empty/ambiguous weekly data, malformed data, login/version problems, temporary service failure, account changes, ordinary notifications, timeouts, and cancellation/cleanup.
- Model/settings tests cover migration from each of the five legacy keys, persisted empty choices, first-provider selection, independent work, hidden weekly rows, fixed selection, and obsolete completions.
- Display regression tests retain Claude's pace, reset, stale-age, and drawn menu bar behavior.
- Native `NSHostingView` snapshots cover Overview, Codex/model windows, setup, placeholders, errors/details, loading, temporary failure, missing reset, expiry, all-hidden tabs, stale readings, and Settings in light/dark. All 60 new or changed reference images were visually inspected.
- The opt-in live check is `PACEMARK_LIVE_CODEX=1 swift test --filter installedCLICompatibility`. It passed against the installed 0.162.1 CLI after verifying the normal account notification behavior.

## Native interaction limitation

A separate `Pacemark Verification.app` bundle was built and launched with its own preference domain. Two Computer Use attempts were blocked by pending macOS Accessibility and Screen Recording permissions. Therefore actual dropdown reopening, menu bar color/dimming, tab clicks, and Settings scrolling/frontmost behavior have not yet been verified interactively. The snapshots and model tests do not establish `MenuBarExtra` lifecycle behavior. Settings uses a 440 × 520 point native scrolling Form; its lower controls still need an interactive scroll check.
