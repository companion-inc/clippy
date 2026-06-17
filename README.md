# Clippy

<p align="center">
  <img src="Docs/assets/clippy-attention.gif" alt="Clippy" width="260">
</p>

<p align="center">
  Native macOS Clippy: a visible desktop assistant with classic Office-style
  animations, local CLI brains, voice input, screen grounding, and computer-use
  tools.
</p>

<p align="center">
  <a href="https://github.com/companion-inc/clippy/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/companion-inc/clippy/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/companion-inc/clippy/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/companion-inc/clippy?sort=semver"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-black"></a>
</p>

<p align="center">
  <a href="https://github.com/companion-inc/clippy/releases/latest/download/Clippy.dmg"><strong>Download for macOS</strong></a>
  ·
  <a href="https://github.com/companion-inc/clippy/releases/latest">Latest release</a>
  ·
  <a href="Docs/STATUS.md">Status</a>
  ·
  <a href="Docs/Handbook/README.md">Handbook</a>
</p>

## What Clippy Does

Clippy is a native Swift macOS app that keeps one animated Clippy character on
screen. Click it or use the command channel to chat, use the menu-bar eye or
right-click Clippy for the retro control menu, hold `Control+Option` to talk,
and let the assistant point at or operate the desktop through bundled local
tools.

The product path is local-first:

- The visible app, speech bubble, permissions UI, annotation overlay, character
  renderer, and app packaging live in this repository.
- The assistant brain runs through locally installed CLI sessions: Claude Code
  through `claude`, or Codex through `codex app-server`.
- First launch opens a retro setup screen that detects Codex, Claude Code, voice
  keys, and Mac permissions, then guides install/sign-in for the missing pieces.
- Voice input uses Deepgram when `DEEPGRAM_API_KEY` is configured, with the
  Apple speech stack as the local fallback. Spoken replies use xAI TTS.
- Computer-use calls run through the Clippy-bundled Cua helper in packaged
  builds.

## Preview

| Idle | Attention | Gesture |
| --- | --- | --- |
| ![Clippy idle](Docs/assets/clippy-idle.gif) | ![Clippy attention](Docs/assets/clippy-attention.gif) | ![Clippy gesture](Docs/assets/clippy-gesture-left.gif) |

## Download

Download the current macOS build:

```text
https://github.com/companion-inc/clippy/releases/latest/download/Clippy.dmg
```

Open the DMG, drag `Clippy.app` into Applications, and launch it. When macOS
blocks the first launch of a locally signed build, Control-click `Clippy.app`,
choose `Open`, and approve the prompt once.

Clippy asks for permissions only when the relevant feature needs them:

- Microphone for push-to-talk voice input.
- Screen Recording for screen grounding and pointing.
- Accessibility for computer-use actions you approve.

## Requirements

- macOS 13 or newer.
- One local brain CLI signed in:
  - `claude` for Claude Code.
  - `codex` for Codex app-server.
- Optional: `DEEPGRAM_API_KEY` for streaming speech-to-text.
- Optional: `XAI_API_KEY` for spoken replies.

API keys can be supplied through the environment, Iris local settings, Clippy's
`Configure API Key...` screen, or this local file:

```text
~/Library/Application Support/Clippy/Secrets.json
```

```json
{
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
Scripts/package-clippy-app.sh release
open -n .build/release/Clippy.app
```

`Scripts/package-clippy-app.sh` requires a `cua-driver` binary so packaged
computer-use tools can run from inside `Clippy.app`. Set `CLIPPY_CUA_DRIVER` to
an existing binary, or install the Cua driver in one of the script's default
locations.

## Developer Commands

The running app listens for optional debug commands through `CLIPPY_CMD_FILE`:

```text
ask:<message>
open
hide
show
snapshot
move:<x>,<y>
park:lowerLeft|lowerRight|upperLeft|upperRight
state:idle|thinking|working|notification|attention|error|sweeping|carrying|juggling|sleeping
```

## Repository Layout

- `Sources/Clippy` - macOS application entry point.
- `Sources/ClippyCore` - character rendering, voice, local brain adapters,
  computer-use routing, permissions, windows, and runtime logic.
- `Sources/ClippyMCP` - helper MCP server for Clippy-owned annotations.
- `Resources/Characters/Clippy` - committed sprite pack and animation manifest.
- `Resources/Clippy.icns` - app icon.
- `Scripts` - packaging and asset export scripts.
- `Docs` - implementation status, architecture notes, verification matrix, and
  research handbook.

## Release Process

Every push to `main` runs tests and packages the macOS app. Tagged pushes that
start with `v` publish GitHub Release assets:

- `Clippy.dmg`
- `Clippy.dmg.sha256`
- `Clippy-macOS.zip`
- `Clippy-macOS.zip.sha256`
- `SHA256SUMS.txt`
- `Clippy-macOS.notarization.txt`

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). For architecture context, read
[Docs/STATUS.md](Docs/STATUS.md) and [Docs/Handbook/README.md](Docs/Handbook/README.md)
before changing runtime behavior.

## License

Clippy is released under the [MIT License](LICENSE).
