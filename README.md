# Clippy

Native macOS scaffold for Clippy: a morphing visible desktop assistant that can
later listen, see the screen/camera, ask approvals, and act on the computer
through an app-owned tool loop.

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

The Clippit-compatible source pack is archived at:

`/Users/advaitpaliwal/Companion/Code/clippy/Research/sources/repos/pithings-clippy`

Export the local pithings Clippit-compatible pack into this repo:

```sh
node Scripts/export-pithings-clippit.mjs
```

That creates:

```text
Resources/Characters/Clippit/character.json
Resources/Characters/Clippit/sounds-mp3.json
Resources/Characters/Clippit/map.png
Resources/Characters/Clippit/manifest.json
```

## Renderer Split

- Core Animation is for the new original morphing mascot.
- SpriteKit is for classic Clippit-compatible raster sprite packs.

Fable should keep both paths. The original mascot is the long-term product path;
Clippit-compatible packs are the fastest hackathon compatibility path.
