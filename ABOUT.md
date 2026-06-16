# About Clippy

Clippy is Companion's native macOS desktop assistant. It brings the classic
paperclip back as a real local app: an animated on-screen character, a chat
bubble, push-to-talk voice, screen grounding, approvals, and computer-use tools.

The app is built in Swift and packaged as `Clippy.app`. It uses locally signed-in
CLI sessions for the assistant brain, keeps provider keys on the user's machine,
and bundles the helper binaries needed for desktop actions in release builds.

This repository contains the app source, sprite assets, packaging scripts,
GitHub Actions release flow, and implementation notes.
