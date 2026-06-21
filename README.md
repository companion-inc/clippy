# Sidekick

<p align="center">
  <img src="Docs/assets/clippy-attention.gif" alt="Sidekick Clippy character" width="260">
</p>

<p align="center">
  Native macOS Sidekick: a visible desktop assistant with selectable classic
  animated characters, local CLI brains, voice input, screen grounding, and
  computer-use tools.
</p>

<p align="center">
  <a href="https://github.com/companion-inc/sidekick/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/companion-inc/sidekick/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/companion-inc/sidekick/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/companion-inc/sidekick?sort=semver"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-black"></a>
</p>

<p align="center">
  <a href="https://github.com/companion-inc/sidekick/releases/latest/download/Sidekick.dmg"><strong>Download for macOS</strong></a>
  ·
  <a href="https://github.com/companion-inc/sidekick/releases/latest">Latest release</a>
  ·
  <a href="Docs/STATUS.md">Status</a>
  ·
  <a href="Docs/Handbook/README.md">Handbook</a>
</p>

## What Sidekick Does

Sidekick is a native Swift macOS app that keeps one animated sidekick on screen.
Clippy is the default character, and the app can switch between the classic
character packs exported from clippy.js. Click the sidekick or use the command
channel to chat, press `Control+Space` to type from anywhere, use the menu-bar
eye or right-click the sidekick for the retro control menu, hold
`Control+Option` to talk, and let the assistant point at or operate the desktop
through bundled local tools.

The product path is local-first:

- The visible app, speech bubble, permissions UI, annotation overlay, character
  renderer, and app packaging live in this repository.
- The assistant brain runs through locally installed ChatGPT or Claude
  connectors. Existing local OpenAI/Anthropic API keys are offered in setup when
  account sign-in is not set up.
- First launch runs guided setup in Sidekick's own speech bubble: choose ChatGPT
  or Claude, accept or replace discovered API keys, and grant Mac permissions.
- Voice input uses Deepgram when `DEEPGRAM_API_KEY` is configured, with the
  Apple speech stack as the local fallback. Spoken replies use xAI TTS.
- Computer-use calls run through the Sidekick-bundled Cua helper in packaged
  builds.
- Record & Replay uses a Sidekick-owned local Chronicle recorder to save
  workflow evidence under `~/Library/Application Support/Sidekick/Chronicle`,
  then asks the Codex brain to turn the resulting event stream into a reusable
  skill.

## Preview

| Idle | Attention | Gesture |
| --- | --- | --- |
| ![Clippy idle](Docs/assets/clippy-idle.gif) | ![Clippy attention](Docs/assets/clippy-attention.gif) | ![Clippy gesture](Docs/assets/clippy-gesture-left.gif) |

## Download

Download the current macOS build:

```text
https://github.com/companion-inc/sidekick/releases/latest/download/Sidekick.dmg
```

Open the DMG, drag `Sidekick.app` into Applications, and launch it. When macOS
blocks the first launch of a locally signed build, Control-click `Sidekick.app`,
choose `Open`, and approve the prompt once.

Sidekick checks for signed updates automatically in the background. You can also
open the Sidekick menu and choose **Check for Updates...**.

Sidekick asks for permissions only when the relevant feature needs them:

- Microphone for push-to-talk voice input.
- Screen Recording for screen grounding and pointing.
- Full Disk Access for local app databases.
- Accessibility for computer-use actions you approve.

## Requirements

- macOS 13 or newer.
- One local account connector signed in, or installed with its matching local API key:
  - Claude through `claude`.
  - ChatGPT through `codex`.
- Optional: `DEEPGRAM_API_KEY` for streaming speech-to-text.
- Optional: `XAI_API_KEY` for spoken replies.
- Optional: Accessibility permission for recording mouse/key workflow events
  during Record & Replay.

API keys can be supplied through the environment, Iris local settings,
Sidekick's `Configure API Key...` screen for voice keys, or this local file:

```text
~/Library/Application Support/Sidekick/Secrets.json
```

```json
{
  "anthropicAPIKey": "...",
  "openAIAPIKey": "...",
  "sttAPIKey": "...",
  "ttsAPIKey": "..."
}
```

## Build From Source

```sh
swift test
swift build
```

To build the Launch Services app wrapper:

```sh
Scripts/package-sidekick-app.sh release
open -n .build/release/Sidekick.app
```

`Scripts/package-sidekick-app.sh` requires a `cua-driver` binary so packaged
computer-use tools can run from inside `Sidekick.app`. Set `SIDEKICK_CUA_DRIVER` to
an existing binary, or install the Cua driver in one of the script's default
locations.

## Developer Commands

The running app listens for optional debug commands through `SIDEKICK_CMD_FILE`:

```text
ask:<message>
sidekick:clippy|bonzi|f1|genie|genius|links|merlin|peedy|rocky|rover
open
hide
show
snapshot
move:<x>,<y>
park:lowerLeft|lowerRight|upperLeft|upperRight
state:idle|thinking|working|notification|attention|error|sweeping|carrying|juggling|sleeping
```

## Repository Layout

- `Sources/Sidekick` - macOS application entry point.
- `Sources/SidekickCore` - character rendering, voice, local brain adapters,
  computer-use routing, permissions, windows, and runtime logic.
- `Sources/SidekickMCP` - helper MCP server for Sidekick-owned annotations.
- `Resources/Characters/*` - committed sidekick sprite packs and animation manifests.
- `Resources/Sidekick.icns` - app icon.
- `Scripts` - packaging and asset export scripts.
- `Docs` - implementation status, architecture notes, verification matrix, and
  research handbook.

## Release Process

Every push to `main` runs tests and packages the macOS app. Tagged pushes that
start with `v` publish GitHub Release assets:

- `Sidekick.dmg`
- `Sidekick.dmg.sha256`
- `Sidekick-macOS.zip`
- `Sidekick-macOS.zip.sha256`
- `SHA256SUMS.txt`
- `Sidekick-macOS.notarization.txt`
- `appcast.xml` for Sparkle OTA updates

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). For architecture context, read
[Docs/STATUS.md](Docs/STATUS.md) and [Docs/Handbook/README.md](Docs/Handbook/README.md)
before changing runtime behavior.

## License

Sidekick is released under the [MIT License](LICENSE).
