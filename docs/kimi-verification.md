# Kimi compatibility and verification

Implementation of [#37](https://github.com/chris-metz/pacemark/issues/37), verified on macOS 27.0.1 with Apple Swift 6.4 on 2026-10-24, against Kimi Code CLI 2.3.1 (`@moonshot-ai/kimi-code` from npm) with a persistent Kimi Code login. No credentials, account identity or live utilization were recorded in fixtures or test logs.

## Supported CLI policy

Pacemark accepts any installed CLI version and does not run `kimi --version`, as for Codex. Compatibility is decided by the responses: no ready line before the server exits, a missing route, or an answer that doesn't decode shows "Can't read Kimi limits". [ADR 0005](adr/0005-kimi-limits-via-local-web-server.md) explains why Pacemark uses the local web server.

The CLI's plan usage was located in the installed bundle: `/usage` in the TUI and the local server's `GET /api/v1/oauth/usage` both read Kimi's `/coding/v1/usages` through the CLI's own token handling. `kimi -p "/usage"` always starts a model turn, and `kimi acp` answers `/usage` with session token counts only.

## Exchange

Each query starts `kimi web --no-open --port 0 --log-level warn`. With a log level, the server prints one line, `Kimi server: http://127.0.0.1:<port>/#token=<token>`; without one, a multi-line banner. Port 0 lets the server pick a free port, so a `kimi web` the user runs is unaffected. Pacemark takes the token from this line only, never from Kimi's `server.token` file, keeps it in memory for the query, and sends it as a bearer token. Without it, the route answers 401.

Pacemark reads `userinfo`, `usage` and `userinfo` again, each with `provider=managed:kimi-code`, then stops the server. Answers are envelopes `{"code":0,"data":{"kind":"ok"|"error",…}}`. Without a login (tested with an empty `KIMI_CODE_HOME`), the server still answers 200, with `kind: "error"` and the message "No token for … Run /login to authenticate."; a rejected token adds `status: 401`. Both show "Sign in to Kimi Code". Other errors and 5xx answers are temporary.

Discovery checks local and Homebrew locations, then the user's interactive login shell. With mise, the shell resolves `kimi` to a Node script next to `node`, so the child's `PATH` starts with the unresolved binary's directory. The child environment contains only `HOME`, `USER`, `PATH` and `KIMI_DISABLE_TELEMETRY=1`; API-key, base-URL and home overrides are not inherited, and custom `KIMI_CODE_HOME` locations are not discovered. The whole exchange has one thirty-second deadline and a 2 MiB stdout ceiling; stderr, the token and account data are not logged.

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

## Not yet verified

- The real `MenuBarExtra` app with Kimi enabled, including the HTTP request from the signed app bundle. Loopback IP addresses are outside App Transport Security, but only the test runner made the request.
- The monthly window rule across a real reset: after the next one, the following reset should fall on the same day one month later at 00:00 UTC.
- A plan that reports a weekly limit; the observed plan reported only the 5-hour and monthly limits.
