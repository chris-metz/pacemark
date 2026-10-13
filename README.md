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
- For Codex monitoring: Codex CLI **0.162.1**, installed with a persistent ChatGPT login (`codex login`)

## Choose providers

Open Settings and enable Claude, Codex, or both. A fresh installation starts with neither enabled. Finding a CLI does not turn monitoring on. On upgrade, an existing saved preference enables Claude once; users who never saved a preference may need to enable it themselves.

Every dropdown opening starts on **Overview**, with one general weekly entry per enabled provider. Provider tabs show all reported windows, including model limits. **Provider Tabs** switches in Settings hide rows only in those tabs.

The menu bar keeps one saved limit, independently of the open tab. Its initial choice is the first available limit of the first enabled provider, in Claude/Codex order. Disabling that provider preserves the choice and leaves only the gauge; re-enabling it restores the value after a successful query.

Codex readings without reset times retain their percentages, without pace. After an observed Codex reset, Pacemark waits for current data instead of assuming zero. Each provider has its own update age and retry state.

Codex's app-server is experimental. This release supports the tested CLI version **0.162.1**; other versions show setup instructions instead of guessing compatibility. To install that version:

```sh
npm install -g @openai/codex@0.162.1
codex login
```

Pacemark leaves credentials and refresh to each CLI. It does not monitor API spending or credit balances. See the [compatibility and verification notes](docs/codex-verification.md).

## Build from source

Requirements:

- macOS 27
- Xcode 27
- For Claude monitoring: Claude Code 2.1.283 or later, installed and logged in
- For Codex monitoring: Codex CLI **0.162.1**, installed with a persistent ChatGPT login (`codex login`)

Then run:

```sh
./scripts/install.sh
```

It builds Pacemark, installs it to `/Applications/Pacemark.app` and launches it.
