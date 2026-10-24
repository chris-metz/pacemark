# Kimi limits through the installed CLI's local web server

Pacemark reads Kimi Code plan limits by briefly starting the installed CLI's local web server (`kimi web`) on a free loopback port, reading its usage and account routes with the bearer token the server prints on startup, and stopping it. Kimi owns credential storage and refresh, as Claude Code and Codex do (ADR 0001, ADR 0004). Pacemark never reads Kimi's credential files or calls Kimi's API itself, and no model turn starts. The bearer token is not an exception to ADR 0001's "no token": it authorizes only the local server, not the Kimi account, and Pacemark takes it from its own child's output, never from disk.

The CLI exposes plan usage nowhere else without a model turn: `kimi -p "/usage"` always runs a turn, and `kimi acp` answers `/usage` with session token counts only. Reading Kimi's token and calling its usage API directly would be faster, but contradicts ADR 0001, and an expired token could not be refreshed. Driving the TUI's `/usage` in a pseudo-terminal would depend on display text. The server's routes are internal and undocumented, so, as for Codex, Pacemark validates every response and shows "Can't read Kimi limits" when one does not decode.

## Consequences

- Each query starts a full Kimi server, which opens Kimi's session and search indexes; its first start creates Kimi's persistent server token file. Pacemark stops it with SIGTERM and waits, so it can release its instance registration and flush its indexes, and disables Kimi's telemetry for these starts.
- Kimi reports no window start, so the monthly window is taken as the calendar month that ends at the reset. The first window of a new plan can be about a day longer.
