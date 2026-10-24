# Pacemark

A macOS menu bar app that shows how much of your AI subscription limits you have used, and whether you are on pace.

## Install

```sh
brew install --cask chris-metz/tap/pacemark
```

Or download the DMG from the [latest release](https://github.com/chris-metz/pacemark/releases/latest) and drag Pacemark to Applications.

Requirements:

- macOS 27
- For Claude monitoring: Claude Code 2.1.283 or later, installed and logged in
- For Codex monitoring: Codex CLI, installed with a persistent ChatGPT login (`codex login`)
- For Kimi monitoring: Kimi Code CLI, installed and logged in (`kimi login`)

## Choose providers

Open Settings and enable any of Claude, Codex and Kimi. A fresh installation starts with none enabled. Finding a CLI does not turn monitoring on. On upgrade, an existing saved preference enables Claude once; users who never saved a preference may need to enable it themselves.

Every dropdown opening starts on **Overview**, with one entry per enabled provider: its weekly limit, or its monthly limit when it reports no weekly one. Provider tabs show all reported windows, including model limits. **Provider Tabs** switches in Settings hide rows only in those tabs.

The menu bar keeps one saved limit, independently of the open tab. Its initial choice is the first available limit of the first enabled provider, in Claude/Codex/Kimi order. Disabling that provider preserves the choice and leaves only the gauge; re-enabling it restores the value after a successful query.

Codex readings without reset times retain their percentages, without pace. After an observed Codex reset, Pacemark waits for current data instead of assuming zero. Each provider has its own update age and retry state.

Codex's app-server is experimental. Pacemark reads it with any installed CLI version and checks each response. If a Codex update changes the interface, Pacemark shows "Can't read Codex limits" until a newer Pacemark release reads it again. To install Codex:

```sh
npm install -g @openai/codex
codex login
```

Kimi Code reports its plan limits only through the local server behind its web UI. For each query, Pacemark starts the installed CLI's `kimi web` on 127.0.0.1 for about a second, reads the limits, and stops it. As with Codex, Pacemark accepts any CLI version and checks each response; an incompatible one shows "Can't read Kimi limits". Kimi reports no window start, so the monthly limit's pace assumes the calendar month that ends at its reset. To install Kimi Code:

```sh
npm install -g @moonshot-ai/kimi-code
kimi login
```

Pacemark leaves credentials and refresh to each CLI. It does not monitor API spending or credit balances. See the compatibility and verification notes for [Codex](docs/codex-verification.md) and [Kimi](docs/kimi-verification.md).

## Build from source

Requirements:

- macOS 27
- Xcode 27
- For Claude monitoring: Claude Code 2.1.283 or later, installed and logged in
- For Codex monitoring: Codex CLI, installed with a persistent ChatGPT login (`codex login`)
- For Kimi monitoring: Kimi Code CLI, installed and logged in (`kimi login`)

Then run:

```sh
./scripts/install.sh
```

It builds Pacemark, installs it to `/Applications/Pacemark.app` and launches it.
