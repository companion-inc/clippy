# Clippy Project Guidance

## Product Copy

- Clippy is a desktop assistant for explaining what is on screen, helping the user understand software/content, and doing bounded computer tasks. User-facing prompts, suggestions, onboarding copy, screenshots, and demos should sound like that product.
- For voice enrollment or speaker-ID setup, the words are only voice samples, but the prompts should still be realistic Clippy requests such as "Can you explain this to me?", "How do I use this?", or "Can you do this task for me?" Avoid meta voice-profile phrases and generic small talk unless the feature specifically targets those topics.

## Screen Control

- GUI automation is acceptable for live app verification until the user sets a screen-control boundary. After the user says not to control the screen or GUI, continue with source, terminal commands, tests, local files, and logs only; do not send clicks, keys, menu navigation, or screenshots until separately reauthorized.

## Wake Word

- Do not describe a Hey Clippy wake model as production unless it has broad provider or recorded-voice coverage, adversarial negatives, STT label filtering, a separate holdout/eval, a SoundAnalysis load check, and offline positive/negative classification proof. Otherwise call it a starter/prototype model and keep improving it.
