#!/usr/bin/env swift

import AVFoundation
import Foundation

struct RecorderOptions {
    var outputURL = URL(fileURLWithPath: "WakeWordTraining")
    var label = "hey_clippy"
    var count = 10
    var seconds = 1.6
}

enum RecorderScriptError: Error, CustomStringConvertible {
    case usage
    case microphoneDenied
    case invalidLabel(String)
    case invalidNumber(String)

    var description: String {
        switch self {
        case .usage:
            return recorderUsageText
        case .microphoneDenied:
            return "Microphone access was denied."
        case .invalidLabel(let value):
            return "Invalid label '\(value)'. Use hey_clippy or not_wake."
        case .invalidNumber(let value):
            return "Invalid numeric argument: \(value)"
        }
    }
}

let recorderUsageText = """
Usage:
  swift Scripts/record-hey-clippy-samples.swift --label hey_clippy --count 20
  swift Scripts/record-hey-clippy-samples.swift --label not_wake --count 40

Options:
  --output WakeWordTraining
  --seconds 1.6

The script records 16 kHz mono WAV files into WakeWordTraining/<label>/.
"""

do {
    let options = try parseRecorderOptions(Array(CommandLine.arguments.dropFirst()))
    guard ["hey_clippy", "not_wake"].contains(options.label) else {
        throw RecorderScriptError.invalidLabel(options.label)
    }
    guard requestMicrophoneAccess() else {
        throw RecorderScriptError.microphoneDenied
    }

    let labelURL = options.outputURL.appendingPathComponent(options.label, isDirectory: true)
    try FileManager.default.createDirectory(at: labelURL, withIntermediateDirectories: true)
    let startingIndex = nextSampleIndex(in: labelURL, label: options.label)

    print("Recording \(options.count) \(options.label) samples")
    print("Output: \(labelURL.path)")
    for offset in 0..<options.count {
        let index = startingIndex + offset
        let fileURL = labelURL.appendingPathComponent(String(format: "%@-%03d.wav", options.label, index))
        print("")
        print("[\(offset + 1)/\(options.count)] Press Return, then record for \(options.seconds)s.")
        if options.label == "hey_clippy" {
            print("Say: Hey Clippy")
        } else {
            print("Record silence, room noise, typing, or a near-miss phrase.")
        }
        _ = readLine()
        try recordSample(to: fileURL, seconds: options.seconds)
        print("Wrote \(fileURL.path)")
    }
} catch let error as RecorderScriptError {
    fputs("\(error.description)\n", stderr)
    exit(error.description == recorderUsageText ? 64 : 1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

func parseRecorderOptions(_ args: [String]) throws -> RecorderOptions {
    var options = RecorderOptions()
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            throw RecorderScriptError.usage
        case "--output":
            index += 1
            guard index < args.count else { throw RecorderScriptError.usage }
            options.outputURL = URL(fileURLWithPath: expandPath(args[index]))
        case "--label":
            index += 1
            guard index < args.count else { throw RecorderScriptError.usage }
            options.label = args[index]
        case "--count":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                throw RecorderScriptError.invalidNumber(index < args.count ? args[index] : arg)
            }
            options.count = value
        case "--seconds":
            index += 1
            guard index < args.count, let value = Double(args[index]) else {
                throw RecorderScriptError.invalidNumber(index < args.count ? args[index] : arg)
            }
            options.seconds = value
        default:
            throw RecorderScriptError.usage
        }
        index += 1
    }
    return options
}

func requestMicrophoneAccess() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    AVCaptureDevice.requestAccess(for: .audio) { allowed in
        granted = allowed
        semaphore.signal()
    }
    semaphore.wait()
    return granted
}

func nextSampleIndex(in directory: URL, label: String) -> Int {
    let files = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )) ?? []
    let prefix = "\(label)-"
    let existing = files.compactMap { url -> Int? in
        guard url.pathExtension.lowercased() == "wav",
              url.deletingPathExtension().lastPathComponent.hasPrefix(prefix) else {
            return nil
        }
        return Int(url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count))
    }
    return (existing.max() ?? 0) + 1
}

func recordSample(to fileURL: URL, seconds: Double) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
    recorder.prepareToRecord()
    recorder.record()
    Thread.sleep(forTimeInterval: seconds)
    recorder.stop()
}

func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}
