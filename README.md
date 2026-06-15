# Clippy

Native macOS desktop Clippy: a visible paperclip assistant that can chat, react
with classic Clippy animations, request approvals, and drive local computer-use
tools through the app runtime.

There is one mascot: Clippy. The app uses the committed Clippy sprite pack under
`Resources/Characters/Clippy` and one shared local conversation adapter.

## Build

```sh
xcrun swift test
xcrun swift build
```

## Run

```sh
xcrun swift run Clippy
```

For a Launch Services app wrapper:

```sh
Scripts/package-clippy-app.sh
open -n .build/debug/Clippy.app
```

The running app listens for optional debug commands through `CLIPPY_CMD_FILE`:

```text
ask:<message>
open
snapshot
move:<x>,<y>
park:lowerLeft|lowerRight|upperLeft|upperRight
state:idle|thinking|working|notification|attention|error|sweeping|carrying|juggling|sleeping
```

## Resources

The Clippy-compatible source pack is archived in the ignored research folder.
Export it into this repo with:

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

Start with `Docs/STATUS.md` and `Docs/Handbook/README.md` for the current
implementation contract.
