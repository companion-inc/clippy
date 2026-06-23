# Sidekick Migration Status

Understanding: 99/100 - current repo state, prior rename memory, local clippy.js source, imported packs, generic sidekick selection, character-aware prompts, wrapped option headers, product paths, release scripts, CI rename, folder/remote rename, README character roster, packaging, live relaunch, command-channel sidekick switching, and immediate post-switch rendering are verified. Prompt-layer files remain intentionally untouched because their prerequisite editing skills are unavailable locally.

## Goal

Rename the product/repo/folder from Clippy to Sidekick, keep Clippy as one selectable character, import the available clippy.js character packs, make prompts character-aware, and fix the bubble layout so option headers never require horizontal or awkward header scrolling.

## Current Evidence

- Current local checkout: `/Users/advaitpaliwal/Companion/Code/sidekick`.
- Current GitHub repo/remote: `companion-inc/sidekick`.
- Local checkout is now the Sidekick folder; any earlier same-name checkout was replaced by the completed rename.
- Existing app already has `CharacterPack`, `RasterCharacterPack`, and a committed `Resources/Characters/Clippy` raster pack.
- Local clippy.js source exists at `Research/sources/repos/pithings-clippy`.
- Worktree is dirty with wake-word, record/replay, rich-bubble, grounding, and app changes that must be preserved.

## Requirements

- [x] Rename local folder to `/Users/advaitpaliwal/Companion/Code/sidekick`.
- [x] Rename GitHub repo to `companion-inc/sidekick` and set `origin` to the Sidekick URL.
- [x] Rename package, executable, app bundle, helper tools, storage paths, env vars, docs, tests, and user-facing copy to Sidekick where product-level.
- [x] Preserve Clippy as the default selectable character, not as the product shell.
- [x] Import clippy.js character packs into `Resources/Characters/<Character>`.
- [x] Make character loading generic instead of `sidekickPackDescriptor`-only.
- [x] Add selection for the imported sidekicks.
- [x] Add character mannerism/prompt metadata so replies and animation choices match the active sidekick without breaking bounded desktop-assistant behavior.
- [x] Fix bubble header/options layout so header text wraps instead of truncating or requiring scrolling when options are visible.
- [x] Run deterministic Swift tests/build after the rename and delete stale `.build` if the path move poisons SwiftPM caches.
- [x] Relaunch or package the live app if runtime behavior is changed and report the process path/PID.

## Log

- Started from dirty `main` at `b5943b7`; preserving existing uncommitted work.
- Verified prior memory: an earlier rename used GitHub repo rename + local folder move + remote update, but current live repo is back to `companion-inc/sidekick`.
- Updated `Scripts/export-pithings-clippy.mjs` to export every local clippy.js agent pack and generated Bonzi, Clippy, F1, Genie, Genius, Links, Merlin, Peedy, Rocky, and Rover resources.
- Added `SidekickSpec.all` sidekick metadata, dynamic Sidekick system prompts, app menu/debug-command switching, generic resource lookup, animation fallback for missing pack animations, and compact option prompt layout.
- Verification: `swift test` passed with 139 tests.
- Renamed app support paths, release assets, package script, CI packaging, entitlements, app icon resource, and docs to Sidekick; kept `CLIPPY_*` only as legacy fallbacks and kept Clippy as a selectable character.
- Renamed GitHub repo to `companion-inc/sidekick`, changed `origin` to `https://github.com/companion-inc/sidekick.git`, and moved the checkout to `/Users/advaitpaliwal/Companion/Code/sidekick`.
- Cleared stale `.build` after the folder move because SwiftPM still pointed Sparkle artifacts at `/Users/advaitpaliwal/Companion/Code/clippy/.build`.
- Verification: `swift test` passed with 139 tests from `/Users/advaitpaliwal/Companion/Code/sidekick`.
- Renamed MCP server identifiers from `clippy-annotation` / `clippy-record-replay` to `sidekick-annotation` / `sidekick-record-replay`.
- Verification: `swift test --filter codexConversationStreamCancellationTerminatesTheChildProcess` passed after one full-suite transient cancellation miss, and the final full `swift test` passed with 139 tests.
- Verification: `Scripts/package-sidekick-app.sh debug` built and signed `.build/debug/Sidekick.app`.
- Verification: relaunched `.build/debug/Sidekick.app`; live `Sidekick` PID is 17883 at `/Users/advaitpaliwal/Companion/Code/sidekick/.build/arm64-apple-macosx/debug/Sidekick.app/Contents/MacOS/Sidekick`.
- Verification: command channel switched to Rover and wrote `/tmp/frame-99.png` plus `/tmp/chat.png`; the character snapshot showed Rover and the chat bubble snapshot showed `Switched to Rover.` without clipping.
- Fixed a latent recorder crash by avoiding `NSAppleScript` off the main thread; background desktop-context capture now uses `/usr/bin/osascript`.
- Renamed app/framework/test types from Clippy-prefixed names to Sidekick-prefixed names where they refer to the app or runtime; retained Clippy identifiers only for the default character pack, wake phrase, and legacy compatibility paths.
- Fixed the character identity split: Sidekick is the app/product shell, while the active character is the spoken persona. Onboarding now says `Hi, I'm <character>`, and the agent prompt explicitly says not to introduce itself as Sidekick.
- Fixed choices-mode bubble layout to wrap long prompt text with unlimited lines instead of capping at two lines and truncating the tail.
- Fixed AppKit lifecycle termination: unsolicited `applicationShouldTerminate` requests are canceled while Sidekick is running; the explicit Quit Sidekick menu path still exits.
- Verification: final `swift test` passed with 140 tests.
- Verification: `Scripts/package-sidekick-app.sh debug` built and signed `.build/debug/Sidekick.app`.
- Verification: relaunched `.build/debug/Sidekick.app`; live `Sidekick` PID is 2138 at `/Users/advaitpaliwal/Companion/Code/sidekick/.build/arm64-apple-macosx/debug/Sidekick.app/Contents/MacOS/Sidekick`, with `SidekickComputerUseRuntime` PID 2481 and `SidekickRecordReplayMCP` PID 2482.
- Verification: after a 12-second idle window that previously terminated the app, Sidekick stayed alive. Command channel switched to Rover and wrote `/tmp/frame-99.png` plus `/tmp/chat.png`; the character snapshot showed Rover and the chat bubble snapshot showed `Ask Rover...`.
- Fixed switch-disappear bug: new sidekicks now render an initial visible texture before their window is shown, generic packs use their real `Greet` or `Greeting` animation names, and switching keeps the previous character visible until the replacement has started.
- Verification: final `swift test` passed with 142 tests.
- Verification: `Scripts/package-sidekick-app.sh debug` built and signed `.build/debug/Sidekick.app`.
- Verification: relaunched `.build/debug/Sidekick.app`; live `Sidekick` PID is 37157 at `/Users/advaitpaliwal/Companion/Code/sidekick/.build/arm64-apple-macosx/debug/Sidekick.app/Contents/MacOS/Sidekick`, with `SidekickComputerUseRuntime` PID 37224 and `SidekickRecordReplayMCP` PID 37227.
- Verification: immediate `sidekick:bonzi` plus `snapshot` produced visible `/tmp/frame-99.png`; `/tmp/chat.png` showed `Switched to Bonzi.`.
- Updated `README.md` so Sidekick is the product shell, Clippy is one selectable character, and the full Bonzi, Clippy, F1, Genie, Genius, Links, Merlin, Peedy, Rocky, and Rover roster is listed with repo-backed animation examples.
