import AVFoundation
import Foundation

/// Clippy's spoken replies via Deepgram Aura-2 **streaming** TTS over a WebSocket.
/// Text is pushed in as the model produces it (`{"type":"Speak"}` + `{"type":"Flush"}`)
/// and Deepgram streams back raw linear16 PCM, which plays through an AVAudioEngine
/// node as it arrives — so Clippy talks in real time instead of after the whole reply.
/// Callers pass already-stripped text, so grounding tags never reach Deepgram.
public final class DeepgramTTS: NSObject {
    private let apiKey: String
    public var voiceModel: String {
        didSet { if oldValue != voiceModel { reset() } } // a new voice needs a new socket
    }
    private let session: URLSession
    private let sampleRate = 24000

    private var ws: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var engineStarted = false

    private let lock = NSLock()
    private var pendingBuffers = 0 // scheduled but not finished playing

    /// True while audio is still queued or playing.
    public var isSpeaking: Bool {
        lock.lock(); defer { lock.unlock() }
        return pendingBuffers > 0
    }

    /// Returns nil if there is no Deepgram key configured.
    public init?(voiceModel: String = ClippyVoice.default.id) {
        guard let key = ClippySecrets.deepgramAPIKey,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else { return nil }
        self.apiKey = key
        self.voiceModel = voiceModel
        self.format = fmt
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Push a chunk to speak as it streams in. Opens the socket lazily.
    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openIfNeeded()
        sendJSON(["type": "Speak", "text": trimmed])
        sendJSON(["type": "Flush"])
    }

    /// One-shot speak — same streaming path.
    public func speak(_ text: String) { enqueue(text) }

    /// Barge-in / disable: tell Deepgram to drop buffered audio and stop playback now.
    public func stop() {
        sendJSON(["type": "Clear"])
        player.stop()
        lock.lock(); pendingBuffers = 0; lock.unlock()
        if engineStarted { player.play() } // ready for the next reply
    }

    private func reset() {
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        stop()
    }

    // MARK: - WebSocket

    private func openIfNeeded() {
        guard ws == nil else { return }
        var comps = URLComponents(string: "wss://api.deepgram.com/v1/speak")!
        comps.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "model", value: voiceModel),
        ]
        guard let url = comps.url else { return }
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        ws = task
        task.resume()
        startEngine()
        receive(on: task)
    }

    private func startEngine() {
        guard !engineStarted else { return }
        do {
            try engine.start()
            player.play()
            engineStarted = true
        } catch {
            engineStarted = false
        }
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let ws,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(text)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                if case let .data(pcm) = message { self.schedule(pcm: pcm) }
                // `.string` messages are metadata/warnings — ignore.
                self.receive(on: task) // keep listening
            case .failure:
                if self.ws === task { self.ws = nil } // socket closed; reopen on next enqueue
            }
        }
    }

    private func schedule(pcm data: Data) {
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        // linear16 = little-endian Int16 mono -> Float32 in [-1, 1].
        var samples = [Int16](repeating: 0, count: frames)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0, count: frames * 2) }
        let out = buffer.floatChannelData![0]
        for i in 0..<frames { out[i] = Float(Int16(littleEndian: samples[i])) / 32768.0 }

        lock.lock(); pendingBuffers += 1; lock.unlock()
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.pendingBuffers = max(0, self.pendingBuffers - 1); self.lock.unlock()
        }
        if engineStarted, !player.isPlaying { player.play() }
    }
}
