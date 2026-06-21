# Hey Clippy Wake Word

Sidekick's Hey Clippy wake word path is local-first:

1. Create ML trains a small `MLSoundClassifier` from labeled audio folders.
2. The script writes `HeyClippy.mlmodel` into Sidekick's Application Support wake-word folder.
3. Sidekick loads that model through Core ML and runs it with SoundAnalysis on live mic buffers.
4. Only a confident `hey_clippy` classification starts the existing voice capture path.

No microphone audio is sent to STT while the wake monitor is only listening for the phrase.

## Dataset

Use two labels:

```text
WakeWordTraining/
  hey_clippy/
    sample-001.wav
    sample-002.wav
  not_wake/
    background-001.wav
    clippy-other-phrases-001.wav
```

Good negatives matter as much as positives. Include typing, room noise, silence,
near-misses like "hey clipboard", and Clippy's own TTS speaking "Hey Clippy" so
the monitor learns the sounds that should not trigger.

Record local starter samples:

```bash
swift Scripts/record-hey-clippy-samples.swift --label hey_clippy --count 20
swift Scripts/record-hey-clippy-samples.swift --label not_wake --count 40
```

## Train Locally

```bash
swift Scripts/train-hey-clippy-coreml.swift --data WakeWordTraining
```

The default output is:

```text
~/Library/Application Support/Sidekick/WakeWord/HeyClippy.mlmodel
```

To test a different model path without installing it there:

```bash
SIDEKICK_WAKE_WORD_MODEL=/path/to/HeyClippy.mlmodel swift run Sidekick
```

## DGX Path

The current script uses Apple's Create ML trainer on the Mac because SoundAnalysis
can consume that model directly. A DGX-trained wake model is still possible, but
that is a separate path:

1. Train a PyTorch/TensorFlow audio classifier on DGX.
2. Convert it to Core ML with `coremltools`.
3. Verify the converted model exposes the audio classifier input/output shape
   required by `SNClassifySoundRequest`.
4. Point `SIDEKICK_WAKE_WORD_MODEL` at the converted `.mlmodel` or `.mlmodelc`.
