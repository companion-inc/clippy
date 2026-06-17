import AVFoundation
import Foundation

/// Push-to-talk voice capture backed by Deepgram Nova-3 streaming STT. Owns the
/// mic (`AVAudioEngine`), converts to 16 kHz PCM16, streams over the websocket,
/// and returns the final transcript with only a Deepgram key configured locally.
public final class DeepgramVoiceCapture {
    private let apiKey: String
    private let engine = AVAudioEngine()
    private let converter = PCM16AudioConverter(targetSampleRate: 16_000)
    private let urlSession = URLSession(configuration: .default)
    private let stateQueue = DispatchQueue(label: "clippy.deepgram.state")
    private let sendQueue = DispatchQueue(label: "clippy.deepgram.send")

    private var webSocket: URLSessionWebSocketTask?
    private var committed: [String] = []
    private var interim = ""
    private var finalHandler: ((String) -> Void)?
    private var deliveredFinal = false
    private var fallbackWork: DispatchWorkItem?

    /// Fires on the main queue with the live (interim) transcript as the user speaks.
    public var onPartialTranscript: ((String) -> Void)?

    /// Returns nil if there is no Deepgram key configured (caller falls back to Apple).
    public init?() {
        guard let key = ClippySecrets.deepgramAPIKey else { return nil }
        self.apiKey = key
    }

    /// Opens the websocket and starts streaming the mic.
    public func start() throws {
        committed = []
        interim = ""
        deliveredFinal = false
        finalHandler = nil

        var request = URLRequest(url: Self.makeURL())
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = urlSession.webSocketTask(with: request)
        webSocket = task
        task.resume()
        receiveNext()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self,
                  let data = self.converter.convertToPCM16Data(from: buffer), !data.isEmpty else { return }
            self.sendQueue.async {
                self.webSocket?.send(.data(data)) { _ in }
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture, flushes Deepgram, and delivers the final transcript on the main queue.
    public func finish(_ completion: @escaping (String) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        stateQueue.async { self.finalHandler = completion }
        send(["type": "Finalize"])

        let work = DispatchWorkItem { [weak self] in
            self?.stateQueue.async { self?.deliver(self?.bestTranscript() ?? "") }
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    public func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        send(["type": "CloseStream"])
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    // MARK: - Websocket receive

    private struct ResultsMessage: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable { let transcript: String? }
            let alternatives: [Alternative]?
        }
        let type: String?
        let is_final: Bool?
        let speech_final: Bool?
        let channel: Channel?
    }

    private func receiveNext() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let text: String?
                switch message {
                case .string(let value): text = value
                case .data(let value): text = String(data: value, encoding: .utf8)
                @unknown default: text = nil
                }
                if let text { self.handle(text) }
                self.receiveNext()
            case .failure:
                self.stateQueue.async {
                    if !self.deliveredFinal { self.deliver(self.bestTranscript()) }
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(ResultsMessage.self, from: data),
              (message.type ?? "") == "Results" else { return }
        let transcript = message.channel?.alternatives?.first?.transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isFinal = message.is_final ?? false
        let isSpeechFinal = message.speech_final ?? false

        stateQueue.async {
            if isFinal {
                if !transcript.isEmpty { self.committed.append(transcript) }
                self.interim = ""
            } else {
                self.interim = transcript
            }
            let partial = self.bestTranscript()
            if !partial.isEmpty, let onPartial = self.onPartialTranscript {
                DispatchQueue.main.async { onPartial(partial) }
            }
            guard self.finalHandler != nil else { return }
            if isSpeechFinal || (isFinal && !transcript.isEmpty) {
                self.deliver(self.bestTranscript())
            }
        }
    }

    private func bestTranscript() -> String {
        var segments = committed
        let trimmed = interim.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { segments.append(trimmed) }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called on `stateQueue`.
    private func deliver(_ transcript: String) {
        guard !deliveredFinal else { return }
        deliveredFinal = true
        fallbackWork?.cancel()
        fallbackWork = nil
        let handler = finalHandler
        finalHandler = nil
        send(["type": "CloseStream"])
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        DispatchQueue.main.async { handler?(transcript) }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        sendQueue.async { self.webSocket?.send(.string(string)) { _ in } }
    }

    private static func makeURL() -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        return components.url!
    }
}
