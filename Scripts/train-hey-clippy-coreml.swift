#!/usr/bin/env swift

import CreateML
import Foundation

struct Options {
    var dataURL: URL?
    var outputURL: URL = defaultOutputURL()
    var iterations = 35
    var overlap = 0.5
}

enum ScriptError: Error, CustomStringConvertible, Equatable {
    case usage
    case missingDataDirectory(URL)
    case missingRequiredLabel(String, URL)
    case invalidNumber(String)

    var description: String {
        switch self {
        case .usage:
            return usageText
        case .missingDataDirectory(let url):
            return "Training data directory not found: \(url.path)"
        case .missingRequiredLabel(let label, let url):
            return "Missing required label directory '\(label)' under \(url.path)"
        case .invalidNumber(let value):
            return "Invalid numeric argument: \(value)"
        }
    }
}

let usageText = """
Usage:
  swift Scripts/train-hey-clippy-coreml.swift --data WakeWordTraining [--output HeyClippy.mlmodel]

Expected data layout:
  WakeWordTraining/
    hey_clippy/*.wav
    not_wake/*.wav

The exported model is loaded locally by Sidekick's SoundAnalysis wake-word monitor.
"""

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    guard let dataURL = options.dataURL else {
        throw ScriptError.usage
    }
    guard FileManager.default.isDirectory(at: dataURL) else {
        throw ScriptError.missingDataDirectory(dataURL)
    }
    for label in ["hey_clippy", "not_wake"] {
        let labelURL = dataURL.appendingPathComponent(label, isDirectory: true)
        guard FileManager.default.isDirectory(at: labelURL) else {
            throw ScriptError.missingRequiredLabel(label, dataURL)
        }
    }

    let counts = labelCounts(in: dataURL)
    print("Training Hey Clippy wake-word model")
    for label in counts.keys.sorted() {
        print("- \(label): \(counts[label] ?? 0) files")
    }
    if (counts["hey_clippy"] ?? 0) < 20 || (counts["not_wake"] ?? 0) < 40 {
        print("Warning: useful wake-word models need more data; this will train, but false wakes/misses will be high.")
    }

    let parameters = MLSoundClassifier.ModelParameters(
        validation: .split(strategy: .automatic),
        maxIterations: options.iterations,
        overlapFactor: options.overlap
    )
    let classifier = try MLSoundClassifier(
        trainingData: .labeledDirectories(at: dataURL),
        parameters: parameters
    )

    try FileManager.default.createDirectory(
        at: options.outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try classifier.write(
        to: options.outputURL,
        metadata: MLModelMetadata(
            author: NSFullUserName(),
            shortDescription: "Local wake-word classifier for Hey Clippy.",
            version: "1",
            additional: [
                "wakeLabel": "hey_clippy",
                "negativeLabel": "not_wake",
                "recommendedThreshold": "0.82",
            ]
        )
    )

    print("Training classification error: \(classifier.trainingMetrics.classificationError)")
    print("Validation classification error: \(classifier.validationMetrics.classificationError)")
    print("Wrote \(options.outputURL.path)")
} catch let error as ScriptError {
    fputs("\(error.description)\n", stderr)
    exit(error == .usage ? 64 : 1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            throw ScriptError.usage
        case "--data":
            index += 1
            guard index < args.count else { throw ScriptError.usage }
            options.dataURL = URL(fileURLWithPath: expandPath(args[index]))
        case "--output":
            index += 1
            guard index < args.count else { throw ScriptError.usage }
            options.outputURL = URL(fileURLWithPath: expandPath(args[index]))
        case "--iterations":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                throw ScriptError.invalidNumber(index < args.count ? args[index] : arg)
            }
            options.iterations = value
        case "--overlap":
            index += 1
            guard index < args.count, let value = Double(args[index]) else {
                throw ScriptError.invalidNumber(index < args.count ? args[index] : arg)
            }
            options.overlap = value
        default:
            throw ScriptError.usage
        }
        index += 1
    }
    return options
}

func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

func defaultOutputURL() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    return appSupport
        .appendingPathComponent("Sidekick", isDirectory: true)
        .appendingPathComponent("WakeWord", isDirectory: true)
        .appendingPathComponent("HeyClippy.mlmodel")
}

func labelCounts(in dataURL: URL) -> [String: Int] {
    let labels = (try? FileManager.default.contentsOfDirectory(
        at: dataURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )) ?? []

    var counts: [String: Int] = [:]
    for labelURL in labels where FileManager.default.isDirectory(at: labelURL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: labelURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        counts[labelURL.lastPathComponent] = files.filter { $0.pathExtension.isEmpty == false }.count
    }
    return counts
}

extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
