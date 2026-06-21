# Wake Word Status

Understanding: 94/100 - Sidekick has push-to-talk STT/TTS and in-progress speaker identity work. The wake-word implementation now has a local SoundAnalysis/Core ML monitor, a Create ML training/export script, a local sample recorder, docs, pure unit tests, and an installed HeyClippy Core ML model. The current Create ML sound-classifier path works as a starter, but fresh holdout results show it is not production-grade yet.

Log:
- Started from existing dirty tree; preserving current voice-enrollment and speaker-identity changes.
- Target architecture: local Core ML "Hey Clippy" detector gates the existing voice capture path.
- Added a Core ML/SoundAnalysis wake monitor and wired it into the Sidekick menu/runtime.
- Added `Scripts/train-hey-clippy-coreml.swift` for Create ML sound-classifier training.
- Added `Scripts/record-hey-clippy-samples.swift` for local WAV collection.
- Added detector/model-locator tests and wake-word training notes.
- Verified `swift test` passes with 108 tests.
- Verified both standalone scripts typecheck in help/error modes.
- A second `swift test` rerun was cancelled while waiting on an unrelated SwiftPM release-build lock.
- Generated a terminal-only starter corpus under `.build/hey-clippy-cloud-training/WakeWordTraining`.
- Trained and installed `~/Library/Application Support/Sidekick/WakeWord/HeyClippy.mlmodel` from 22 wake clips and 60 negative clips; training error 0.0, validation error 0.25.
- Compiled `HeyClippy.mlmodelc` in the same WakeWord folder and verified it loads through `SNClassifySoundRequest`.
- Verified offline classification through SoundAnalysis: a held-out generated wake clip classified as `hey_clippy` at 0.9997 confidence and a generated negative clip classified as `not_wake` at 0.99995 confidence.
- Enabled `SidekickWakeWordEnabled` and `SidekickSTTEnabled` in the Sidekick preference domains.
- Expanded terminal-only generation with local xAI, Deepgram, and OpenAI TTS credentials. Working provider voices: xAI Ara/Rex/Eve/Leo/Sal; Deepgram Aura 2 Thalia/Orion/Arcas/Asteria/Helena/Odysseus; OpenAI alloy/ash/ballad/coral/echo/sage/shimmer/verse.
- Ran Deepgram STT over generated speech labels: 456 checked, 432 kept after filtering; filtered counts were 105 wake positives and 327 negatives before augmentation/noise.
- Trained the best expanded checkpoint from 430 wake and 1435 negative train files. Training classification error 0.0256; Create ML validation classification error 0.0340.
- A hard-negative-mined retrain from 449 wake and 1525 negatives performed worse on fresh holdout, so it was not kept.
- Fresh provider-generated holdout against the installed checkpoint: 104 files, 66 correct at threshold 0.82; 11 false negatives and 27 false positives. This is not production-grade.
- Fixed runtime wake detection so SoundAnalysis must rank `hey_clippy` as the top class before Sidekick accepts a wake.
