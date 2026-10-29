# Grok limits through the installed CLI's agent interface

Pacemark reads the Grok subscription limit by briefly starting the installed CLI's agent (`grok agent --no-leader stdio`) and asking it for `_x.ai/billing` over ACP, the Agent Client Protocol: JSON-RPC over stdio. Grok owns credential storage and refresh, as Claude Code, Codex and Kimi Code do (ADR 0001, ADR 0004, ADR 0005). Pacemark never reads Grok's credential file or calls xAI itself, and no model turn starts.

The CLI offers no other way to read the limit without a model turn. Reading `~/.grok/auth.json` and calling xAI directly would be faster, but contradicts ADR 0001, and an expired login could not be refreshed. Driving the TUI's `/usage` in a pseudo-terminal would depend on display text. `_x.ai/billing` is an internal, undocumented extension method, so, as for Codex and Kimi, Pacemark validates every response and shows "Can't read Grok limits" when one does not decode.

Monitoring xAI API spending with an API key of Pacemark's own was rejected as well. Pacemark would have to store a credential, and spending is an amount of money, not a limit with a pace. It is also unnecessary: calls with API keys created on grok.com draw on the same subscription allowance, so the one limit already counts them.

## Consequences

- Each query starts a full Grok agent, which touches its session search index and log and fetches models, settings and announcements from xAI. Pacemark disables Grok's telemetry for these starts, runs the agent in an empty temporary directory so it loads no project configuration, and never starts or joins a shared leader process.
- Pacemark stops the agent by closing its input, which ends it normally after about two seconds. SIGTERM follows only after three seconds, SIGKILL two seconds later.
- With all four providers enabled, five regular tab segments don't fit the dropdown's width, so its tab bar then uses the small control size.
