# Chronicle + Record & Replay Status

Understanding: 76/100 - Codex splits this into a sparse local recorder plus a Record & Replay skill that starts/stops capture, reads `session.json` and `events.jsonl`, then creates a real skill. Sidekick already has Codex app-server MCP wiring, screen capture, desktop metadata, and packaging helpers, so the first slice should reuse those surfaces.

## Progress

- Completed: confirmed Codex's bundled Record & Replay MCP exposes `event_stream_start`, `event_stream_status`, and `event_stream_stop`.
- Completed: confirmed Sidekick's Codex app-server lane already injects MCP server runtimes per thread.
- Completed: added Sidekick-owned Chronicle recorder that writes `session.json`, `events.jsonl`, sparse screenshots, desktop metadata, focused element snapshots, and mouse/key events.
- Completed: added `SidekickRecordReplayMCP` with Codex-compatible `event_stream_start`, `event_stream_status`, and `event_stream_stop` tools.
- Completed: wired the Record & Replay MCP into Codex thread config and taught Sidekick to route workflow/video-to-skill requests to that lane.
- Completed: updated packaging to include and sign `SidekickRecordReplayMCP`.

## Decisions

- Store recordings under `~/Library/Application Support/Sidekick/Chronicle/<session-id>/`.
- Treat `events.jsonl` as the primary evidence and `session.json` as status/path metadata.
- Capture semantic UI evidence first: desktop metadata, focused accessibility element, screenshots, mouse/key events. Video import can be layered on after this path exists.
- Expose the recorder through MCP rather than a separate agent transport, because Sidekick already routes Codex tool-lane conversations through MCP config.

## Verification Log

- Passed: `swift test` on 2026-06-20, 129 tests.
- Passed: `Scripts/package-sidekick-app.sh debug` on 2026-06-20.
- Passed: packaged `.build/debug/Sidekick.app/Contents/MacOS/SidekickRecordReplayMCP` initialized and listed `event_stream_start`, `event_stream_status`, and `event_stream_stop`.
- Passed: relaunched `.build/debug/Sidekick.app`; live `Sidekick` process PID was 9485 after relaunch.
- Completed: added visible retro-menu controls: `Record Workflow...`, `Stop Recording and Make Skill`, and `Cancel Recording`.
- Passed: `swift test` after menu wiring on 2026-06-20, 129 tests.
- Passed: repackaged and relaunched `.build/debug/Sidekick.app`; live `Sidekick` process PID was 28121 after relaunch.
