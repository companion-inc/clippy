import AVFoundation
import CoreML
import Foundation
import Speech
import SoundAnalysis

public struct WakeWordDetection: Equatable, Sendable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

public struct WakeWordDetector: Equatable, Sendable {
    public let acceptedLabels: Set<String>
    public let threshold: Double

    public init(
        acceptedLabels: Set<String> = ["hey_clippy", "hey clippy"],
        threshold: Double = 0.82
    ) {
        self.acceptedLabels = Set(acceptedLabels.map(Self.normalized))
        self.threshold = threshold
    }

    public func detection(label: String, confidence: Double) -> WakeWordDetection? {
        guard confidence >= threshold,
              acceptedLabels.contains(Self.normalized(label)) else {
            return nil
        }
        return WakeWordDetection(label: label, confidence: confidence)
    }

    public func detection(rankedClassifications: [(label: String, confidence: Double)]) -> WakeWordDetection? {
        guard let top = rankedClassifications.first else {
            return nil
        }
        return detection(label: top.label, confidence: top.confidence)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

public struct WakePhraseVerifier: Equatable, Sendable {
    public let acceptedPhrases: Set<String>

    public init(acceptedPhrases: Set<String> = ["hey clippy", "hay clippy", "hey clipy", "hey clippie"]) {
        self.acceptedPhrases = Set(acceptedPhrases.map(Self.normalized))
    }

    public func containsWakePhrase(_ transcript: String) -> Bool {
        let normalizedTranscript = Self.normalized(transcript)
        return acceptedPhrases.contains { phrase in
            normalizedTranscript == phrase
                || normalizedTranscript.hasPrefix("\(phrase) ")
                || normalizedTranscript.hasSuffix(" \(phrase)")
                || normalizedTranscript.contains(" \(phrase) ")
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }
            .reduce(into: "") { partial, character in
                if character == " ", partial.last == " " {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum WakeWordModelLocator {
    public static let environmentKey = "SIDEKICK_WAKE_WORD_MODEL"
    public static let legacyEnvironmentKey = "CLIPPY_WAKE_WORD_MODEL"
    public static let defaultBaseName = "HeyClippy"

    public static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Sidekick", isDirectory: true)
            .appendingPathComponent("WakeWord", isDirectory: true)
    }

    public static func defaultModelURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        if let raw = (environment[environmentKey] ?? environment[legacyEnvironmentKey])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }

        for fileExtension in ["mlmodelc", "mlmodel"] {
            let url = appSupportDirectory.appendingPathComponent(defaultBaseName).appendingPathExtension(fileExtension)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        for fileExtension in ["mlmodelc", "mlmodel"] {
            if let url = bundle.url(forResource: defaultBaseName, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }
}

public enum CoreMLWakeWordMonitorError: Error, Equatable {
    case modelMissing
    case analyzerRejectedRequest
    case speechRecognitionNotAuthorized
    case speechRecognitionUnavailable
}

public final class CoreMLWakeWordMonitor: NSObject {
    public struct Configuration: Equatable, Sendable {
        public let modelURL: URL
        public let detector: WakeWordDetector
        public let phraseVerifier: WakePhraseVerifier
        public let analysisWindowSeconds: Double?
        public let minSecondsBetweenDetections: Double
        public let requiresLocalPhraseVerification: Bool
        public let phraseVerificationWindowSeconds: Double

        public init(
            modelURL: URL,
            detector: WakeWordDetector = WakeWordDetector(),
            phraseVerifier: WakePhraseVerifier = WakePhraseVerifier(),
            analysisWindowSeconds: Double? = 1.0,
            minSecondsBetweenDetections: Double = 2.0,
            requiresLocalPhraseVerification: Bool = true,
            phraseVerificationWindowSeconds: Double = 3.0
        ) {
            self.modelURL = modelURL
            self.detector = detector
            self.phraseVerifier = phraseVerifier
            self.analysisWindowSeconds = analysisWindowSeconds
            self.minSecondsBetweenDetections = minSecondsBetweenDetections
            self.requiresLocalPhraseVerification = requiresLocalPhraseVerification
            self.phraseVerificationWindowSeconds = phraseVerificationWindowSeconds
        }
    }

    public var onWake: ((WakeWordDetection) -> Void)?
    public var onError: ((String) -> Void)?

    private let configuration: Configuration
    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "sidekick.wake-word.analysis")
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var framePosition: AVAudioFramePosition = 0
    private var running = false
    private var lastDetection = Date.distantPast
    private var lastVerifiedPhrase = Date.distantPast
    private var pendingDetection: WakeWordDetection?
    private var pendingDetectionDate: Date?

    public init(configuration: Configuration) {
        self.configuration = configuration
        super.init()
    }

    public var isRunning: Bool {
        running
    }

    public static var isSpeechVerificationAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public static var needsSpeechVerificationAuthorization: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    public static func requestSpeechVerificationAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func start() throws {
        guard !running else { return }
        guard FileManager.default.fileExists(atPath: configuration.modelURL.path) else {
            throw CoreMLWakeWordMonitorError.modelMissing
        }
        if configuration.requiresLocalPhraseVerification {
            guard Self.isSpeechVerificationAuthorized else {
                throw CoreMLWakeWordMonitorError.speechRecognitionNotAuthorized
            }
            guard let speechRecognizer, speechRecognizer.isAvailable, speechRecognizer.supportsOnDeviceRecognition else {
                throw CoreMLWakeWordMonitorError.speechRecognitionUnavailable
            }
        }

        let modelURL = try Self.loadableModelURL(for: configuration.modelURL)
        let model = try MLModel(contentsOf: modelURL)
        let request = try SNClassifySoundRequest(mlModel: model)
        request.overlapFactor = 0.5
        if let seconds = configuration.analysisWindowSeconds {
            request.windowDuration = CMTime(seconds: seconds, preferredTimescale: 1_000)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        try analyzer.add(request, withObserver: self)

        let speechRequest = makeSpeechRequestIfNeeded()
        try MicrophoneTapCoordinator.shared.acquire(.wakeWord)
        var didInstallTap = false
        self.request = request
        self.analyzer = analyzer
        self.speechRequest = speechRequest
        if let speechRequest {
            speechTask = speechRecognizer?.recognitionTask(with: speechRequest) { [weak self] result, _ in
                guard let self,
                      let text = result?.bestTranscription.formattedString else {
                    return
                }
                self.analysisQueue.async {
                    self.handleVerifierTranscript(text)
                }
            }
        }
        framePosition = 0
        lastVerifiedPhrase = Date.distantPast
        pendingDetection = nil
        pendingDetectionDate = nil
        do {
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.speechRequest?.append(buffer)
                self.analysisQueue.async {
                    self.analyzer?.analyze(buffer, atAudioFramePosition: self.framePosition)
                    self.framePosition += AVAudioFramePosition(buffer.frameLength)
                }
            }
            didInstallTap = true
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            if didInstallTap {
                input.removeTap(onBus: 0)
                engine.stop()
            }
            MicrophoneTapCoordinator.shared.release(.wakeWord)
            speechRequest?.endAudio()
            speechTask?.cancel()
            analyzer.removeAllRequests()
            self.analyzer = nil
            self.request = nil
            self.speechRequest = nil
            self.speechTask = nil
            throw error
        }
    }

    public func stop() {
        guard running || analyzer != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        MicrophoneTapCoordinator.shared.release(.wakeWord)
        speechRequest?.endAudio()
        speechTask?.cancel()
        analysisQueue.async { [analyzer] in
            analyzer?.completeAnalysis()
            analyzer?.removeAllRequests()
        }
        analyzer = nil
        request = nil
        speechRequest = nil
        speechTask = nil
        running = false
    }

    deinit {
        stop()
    }

    private static func loadableModelURL(for url: URL) throws -> URL {
        if url.pathExtension == "mlmodel" {
            return try MLModel.compileModel(at: url)
        }
        return url
    }

    private func makeSpeechRequestIfNeeded() -> SFSpeechAudioBufferRecognitionRequest? {
        guard configuration.requiresLocalPhraseVerification else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        return request
    }

    private func handleCandidateDetection(_ detection: WakeWordDetection) {
        let now = Date()
        guard now.timeIntervalSince(lastDetection) >= configuration.minSecondsBetweenDetections else {
            return
        }
        guard configuration.requiresLocalPhraseVerification else {
            acceptDetection(detection, at: now)
            return
        }
        if now.timeIntervalSince(lastVerifiedPhrase) <= configuration.phraseVerificationWindowSeconds {
            acceptDetection(detection, at: now)
            return
        }
        pendingDetection = detection
        pendingDetectionDate = now
    }

    private func handleVerifierTranscript(_ transcript: String) {
        guard configuration.phraseVerifier.containsWakePhrase(transcript) else {
            return
        }
        let now = Date()
        lastVerifiedPhrase = now
        guard let detection = pendingDetection,
              let detectionDate = pendingDetectionDate,
              now.timeIntervalSince(detectionDate) <= configuration.phraseVerificationWindowSeconds,
              now.timeIntervalSince(lastDetection) >= configuration.minSecondsBetweenDetections else {
            return
        }
        acceptDetection(detection, at: now)
    }

    private func acceptDetection(_ detection: WakeWordDetection, at now: Date) {
        lastDetection = now
        pendingDetection = nil
        pendingDetectionDate = nil
        DispatchQueue.main.async { [weak self] in
            self?.onWake?(detection)
        }
    }
}

extension CoreMLWakeWordMonitor: SNResultsObserving {
    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let rankedClassifications = result.classifications.map {
            (label: $0.identifier, confidence: $0.confidence)
        }
        guard let detection = configuration.detector.detection(rankedClassifications: rankedClassifications) else {
            return
        }
        analysisQueue.async { [weak self] in
            self?.handleCandidateDetection(detection)
        }
    }

    public func request(_ request: SNRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error.localizedDescription)
        }
    }
}
