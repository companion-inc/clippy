# Sidekick

Native macOS scaffold for Sidekick: a visible desktop assistant with a swappable
mascot. It can listen, see the screen/camera, ask approvals, and act on the
computer through an app-owned tool loop.

Start with `Docs/STATUS.md` and `Docs/Handbook/README.md`.

## Build

```sh
swift test
swift build
```

## Research Archive

The research archive lives inside this repo folder but is ignored by git:

`/Users/advaitpaliwal/Companion/Code/clippy/Research/sources/repos`

## Resource Export

The Clippy-compatible source pack is archived at:

`/Users/advaitpaliwal/Companion/Code/clippy/Research/sources/repos/pithings-clippy`

Export the local pithings Clippy-compatible pack into this repo:

```sh
node Scripts/export-pithings-clippy.mjs
```

That creates:

```text
Resources/Characters/Clippy/character.json
Resources/Characters/Clippy/sounds-mp3.json
Resources/Characters/Clippy/map.png
Resources/Characters/Clippy/manifest.json
```

## Renderer Split

- Core Animation is for the original morphing mascot fallback.
- SpriteKit is for classic Clippy-compatible raster sprite packs.

Sidekick should keep both paths. The product name is not tied to one mascot:
Clippy-compatible packs are the current default, and future mascots should slot
behind the same `DesktopMascot` surface.

## Mascot Themes

Each mascot ships with a `MascotTheme`. The app shell asks the active mascot for
balloon styling, approval styling, chat/menu copy, greeting/reply/error
animations, and agent-state animation bindings. Clippy owns the MS Agent-style
yellow bubble and Clippy animation names; future Claude/Codex sidekicks should
bring their own theme instead of inheriting Clippy-specific UI.
