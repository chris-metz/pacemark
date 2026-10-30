# Kimi compatibility and verification

Implementation of [#37](https://github.com/chris-metz/pacemark/issues/37), verified on macOS 27.0.1 with Apple Swift 6.4 on 2026-10-24, against Kimi Code CLI 2.3.1 (`@moonshot-ai/kimi-code` from npm) with a persistent Kimi Code login. No credentials, account identity or live utilization were recorded in fixtures or test logs.

## Supported CLI policy

Pacemark accepts any installed CLI version and does not run `kimi --version`, as for Codex. Compatibility is decided by the responses: no ready line before the server exits, a missing route, or an answer that doesn't decode shows "Can't read Kimi limits". [ADR 0005](adr/0005-kimi-limits-via-local-web-server.md) explains why Pacemark uses the local web server.

The CLI's plan usage was located in the installed bundle: `/usage` in the TUI and the local server's `GET /api/v1/oauth/usage` both read Kimi's `/coding/v1/usages` through the CLI's own token handling. `kimi -p "/usage"` always starts a model turn, and `kimi acp` answers `/usage` with session token counts only.

## Exchange

Each query starts `kimi web --no-open --port 0 --log-level warn`. With a log level, the server prints one line, `Kimi server: http://127.0.0.1:<port>/#token=<token>`; without one, a multi-line banner. Port 0 lets the server pick a free port, so a `kimi web` the user runs is unaffected. Pacemark takes the token from this line only, never from Kimi's `server.token` file, keeps it in memory for the query, and sends it as a bearer token. Without it, the route answers 401.

Pacemark reads `userinfo`, `usage` and `userinfo` again, each with `provider=managed:kimi-code`, then stops the server. Answers are envelopes `{"code":0,"data":{"kind":"ok"|"error",…}}`. Without a login (tested with an empty `KIMI_CODE_HOME`), the server still answers 200, with `kind: "error"` and the message "No token for … Run /login to authenticate."; a rejected token adds `status: 401`. Both show "Sign in to Kimi Code". Other errors, 5xx answers and envelopes with a nonzero `code` are temporary; other HTTP statuses from the local server show "Can't read Kimi limits".

Discovery checks local and Homebrew locations, then the user's interactive login shell, which runs `command -v node; command -v kimi`. `kimi` comes last, so the exit status says whether it was found, with or without `node`. The child's `PATH` starts with the unresolved binary's directory, which with npm under mise also holds `node`. Next comes the directory of the shell's `node`, if it differs, because a pnpm shim takes `node` from `PATH` (see [pnpm installs](#pnpm-installs)). The child environment contains only `HOME`, `USER`, `PATH` and `KIMI_DISABLE_TELEMETRY=1`; API-key, base-URL and home overrides are not inherited, and custom `KIMI_CODE_HOME` locations are not discovered. The whole exchange has one thirty-second deadline, plus up to two seconds for a server that ignores SIGTERM, and a 2 MiB stdout ceiling; stderr, the token and account data are not logged.

The server is stopped with SIGTERM. A graceful shutdown took about 0.05 s and left no entry in Kimi's instance registry; SIGKILL follows only after two seconds. Starting the server has side effects in Kimi's data directory: the first start creates the persistent `server.token`, and each start opens Kimi's session and search indexes.

## Readings and identity

`limit5h`, `limit7d` and `monthTotal` become the 5-hour, weekly and monthly limits, in that order, with IDs `kimi/limit5h`, `kimi/limit7d` and `kimi/monthTotal`. `monthCode`, the Kimi Code share of the monthly limit, and the booster wallet are ignored. Utilization is `usedRatio × 100` and may exceed 100. Overview shows the weekly limit, otherwise the monthly one. Like Codex, Kimi readings wait for a current answer after an observed reset instead of assuming zero.

Kimi reports no window start. The monthly window is the calendar month, in UTC, that ends at the reset: a reset on 31 March has a window from 28 February. The observed reset was more than one calendar month after the verification, apparently because a new plan's first window ends at the midnight after its monthly date. Until the assumed start, the pace is 0 % and any use shows as over pace.

The identity is the account's user ID and email. A change between the two `userinfo` reads discards the response, as for Codex.

## Verification

- Provider tests run a fake `kimi` executable as a real child process and answer the HTTP routes through an injected transport. They cover all three limits, missing entries, missing reset times, utilization above 100, empty answers, six calendar-month boundaries (including leap years and month ends), login and rejected tokens, service and server errors, unreadable answers, missing routes, an account switch, the exact arguments and environment, graceful stopping, missing ready lines, unresponsive processes, cancellation and a missing installation.
- Deliberately broken implementations were caught: no fallback to the monthly limit, a fixed 30-day month, and SIGKILL 50 ms after SIGTERM.
- Native `NSHostingView` snapshots cover Overview with a monthly entry, the Kimi tab, a Kimi login problem and Settings with three providers, in light and dark. All 8 new reference images were visually inspected. The existing two-provider references are unchanged.
- The opt-in live check is `PACEMARK_LIVE_KIMI=1 swift test --filter KimiProviderTests/installedCLICompatibility`. It passed against the installed 2.3.1 CLI in 2.9 s, including discovery through the login shell, and left no server process or instance entry behind.
- `swift build`, the full `swift test` and `scripts/release-notes-test.sh` passed.
- On 2026-10-26, the branch build at `9051a2e`, installed with `scripts/install.sh`, ran in the real menu bar app with Kimi enabled in Settings. Overview showed the monthly limit, the Kimi tab showed the 5-hour and monthly limits, and the 5-hour limit could be chosen for the menu bar, so the request from the signed app bundle reaches the local server. No `kimi web` process or instance entry was left behind.

## Deviations from #37

- GLOSSARY has no separate "Kimi's limits" section. The glossary holds terms only, and the one Kimi-specific fact belongs to the new term **Monthly limit**.
- No fixture with string ratios: the local server's envelope already normalizes `usedRatio` to a number, so a string would mean an incompatible interface.
- Limits follow the fixed order of Kimi's own `/usage` view (5-hour, weekly, monthly), not the JSON key order, which the server builds in that same order.
- The server is stopped with SIGTERM and a two-second grace before SIGKILL, so Kimi can flush its indexes.
- The Settings note under Provider Tabs now reads "Overview always shows each enabled provider's weekly or monthly limit." It still fits on one line.

## Review against `f5933d6`

Standards and Spec were reviewed by separate agents. Fixed: the Settings note still said Overview shows only the weekly limit; names that used the glossary's avoided words (`KimiUsage.swift`, `usages()`, `usage.json`) now follow Codex's `limits`; the error mapping that appeared twice in `KimiProvider.fetch()` is one `failure` function, as in `CodexProvider`; the ready-line prefix is no longer a hard-coded length; window lengths sit next to each limit instead of in a separate switch; ADR 0005 now says why the local server token is not an account credential. Kept: the near-copies of `CodexProcess` and `CodexLocator`, as #37 specified; the "No weekly limit reported" text, which #37 kept for Claude and Codex; and the snapshot test's own copy of the login problem, because PacemarkKit's tests cannot import PacemarkKimi.

## pnpm installs

Implementation of [#40](https://github.com/chris-metz/pacemark/issues/40), verified on 2026-10-30 against Kimi Code CLI 2.4.0 installed through pnpm into `~/Library/pnpm/bin/kimi`, with `node` from mise in `~/.local/share/mise/installs/node/24/bin`.

pnpm's `kimi` is a shell shim that runs `exec node …/main.mjs` and takes `node` from `PATH`. Before #40, the child's `PATH` held only the shim's directory and the system directories, so the shim exited at once and Pacemark showed "Can't read Kimi limits". Now the same login-shell run that finds `kimi` also reports `node`; with fish it took 0.26 s. Pacemark keeps the unresolved `node` path, so mise's `node/24` link still holds after a Node update. Without `node`, `kimi` is still found and the shim's failure shows "Can't read Kimi limits", as before; a dedicated message is out of scope.

- Provider tests run a pnpm-style shim whose scripted server stands in for `node`, reachable only through the added directory, and check the child's `PATH` order. Without `node`, the shim fails with "Can't read Kimi limits". With `node` next to `kimi`, as with npm under mise, `PATH` is unchanged.
- Locator tests read login-shell answers with startup output, without `node` and without `kimi`.
- Deliberately broken implementations were caught: no `node` directory, the `node` directory before the binary's, the old rule that took the last executable line as `kimi`, and an answer whose `node` is ignored.
- fish, zsh, bash and sh exit with status 0 when only `node` is missing, and nonzero when `kimi` is missing.
- The live check passed in 3.1 s, with discovery through fish. In this setup, mise's Node 24 also held an npm-installed `kimi`, but the login shell reported the pnpm shim first. At `a5e9ebc`, before #40, the same check recorded a problem instead of limits. No `kimi web` process was left behind.

Deviation from #40: `node` is looked up only when the login shell is asked for `kimi`. A `kimi` in `~/.local/bin` or a Homebrew location starts as before, without a shell run, so a pnpm shim placed there, with `PNPM_HOME` set to one of them, would still lack `node`. This hasn't been observed.

## Not yet verified

- The monthly window rule across a real reset: after the next one, the following reset should fall on the same day one month later at 00:00 UTC.
- A plan that reports a weekly limit; the observed plan reported only the 5-hour and monthly limits.
- The pnpm install in the real menu bar app.
