import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text for one push-to-talk turn — no cloud. Start on the
/// key-down, stop on key-up; `stop()` returns the final transcript. Uses
/// `SFSpeechRecognizer` with on-device recognition + `AVAudioEngine` mic capture.
public final class SpeechCapture {
    public enum CaptureError: Error { case unavailable }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let converter = PCM16AudioConverter(targetSampleRate: 16_000)
    private let audioQueue = DispatchQueue(label: "sidekick.apple-speech.audio")
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var capturedAudio = Data()
    private var isRunning = false
    private var voiceActivityDetector = VoiceActivityDetector()

    /// Fires on the main queue with live Apple Speech partials when Deepgram is unavailable.
    public var onPartialTranscript: ((String) -> Void)?

    /// Fires on the main queue when local audio energy crosses speech/silence thresholds.
    public var onVoiceActivityChanged: ((Bool) -> Void)?

    public init() {}

    public static var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Requests Speech Recognition + Microphone access. Returns true only if both granted.
    public static func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        return speechOK && micOK
    }

    /// Requests only Microphone access — used for Deepgram, which doesn't need
    /// Apple's Speech Recognition permission.
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        guard isRunning == false else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw CaptureError.unavailable
        }
        try MicrophoneTapCoordinator.shared.acquire(.appleSpeech)

        latest = ""
        audioQueue.sync {
            capturedAudio = Data()
            voiceActivityDetector.reset()
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        var didInstallTap = false
        do {
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.request?.append(buffer)
                guard let data = self.converter.convertToPCM16Data(from: buffer), !data.isEmpty else { return }
                self.audioQueue.async {
                    self.capturedAudio.append(data)
                    self.emitVoiceActivityEventIfNeeded(for: data)
                }
            }
            didInstallTap = true
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            if didInstallTap {
                input.removeTap(onBus: 0)
                engine.stop()
            }
            MicrophoneTapCoordinator.shared.release(.appleSpeech)
            request.endAudio()
            self.request = nil
            throw error
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            if let result {
                let text = result.bestTranscription.formattedString
                self?.latest = text
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPartialTranscript?(text)
                    }
                }
            }
        }
    }

    /// Stops capture and returns the final transcript (trimmed).
    @discardableResult
    public func stop() -> String {
        stopResult().transcript
    }

    /// Stops capture and returns the final transcript plus matching turn audio.
    @discardableResult
    public func stopResult() -> VoiceCaptureResult {
        if isRunning {
            isRunning = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            MicrophoneTapCoordinator.shared.release(.appleSpeech)
            emitVoiceActivity(false)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        let audio = audioQueue.sync { capturedAudio }
        return VoiceCaptureResult(
            transcript: latest.trimmingCharacters(in: .whitespacesAndNewlines),
            audio: VoiceCaptureAudio(pcm16Data: audio)
        )
    }

    private func emitVoiceActivityEventIfNeeded(for data: Data) {
        guard let event = voiceActivityDetector.process(pcm16Data: data) else { return }
        emitVoiceActivity(event.isSpeechActive)
    }

    private func emitVoiceActivity(_ isSpeechActive: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onVoiceActivityChanged?(isSpeechActive)
        }
    }
}
