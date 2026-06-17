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
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""

    /// Fires on the main queue with live Apple Speech partials when Deepgram is unavailable.
    public var onPartialTranscript: ((String) -> Void)?

    public init() {}

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
        guard let recognizer, recognizer.isAvailable else {
            throw CaptureError.unavailable
        }
        latest = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        try engine.start()

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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
