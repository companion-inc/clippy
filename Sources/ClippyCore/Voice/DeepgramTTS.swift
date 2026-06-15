import AVFoundation
import Foundation

/// Clippy's spoken replies via Deepgram Aura-2 streaming TTS.
///
/// This uses Deepgram's WebSocket TTS API, sends sentence chunks as `Speak`
/// messages, flushes each chunk for low latency, and schedules incoming
/// linear16 audio bytes directly into an `AVAudioPlayerNode`.
public final class DeepgramTTS {
    private static let sampleRate: Double = 48_000

    private let apiKey: String
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "clippy.deepgram.tts")
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: DeepgramTTS.sampleRate,
        channels: 1,
        interleaved: false
    )!

    public var voiceModel: String {
        didSet {
            guard oldValue != voiceModel else { return }
            stop()
        }
    }

    private var webSocket: URLSessionWebSocketTask?
    private var queuedText: [String] = []
    private var pendingFlushes = 0
    private var pendingAudioBuffers = 0
    private var active = false
    private var pcmCarry = Data()
    private var idleWork: DispatchWorkItem?

    /// True while text is queued, audio is still arriving, or playback is active.
    public var isSpeaking: Bool {
        stateQueue.sync {
            active || !queuedText.isEmpty || pendingFlushes > 0 || pendingAudioBuffers > 0
        }
    }

    /// Returns nil if there is no Deepgram key configured.
    public init?(voiceModel: String = ClippyVoice.default.id) {
        guard let key = ClippySecrets.deepgramAPIKey else { return nil }
        self.apiKey = key
        self.voiceModel = voiceModel
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        self.session = URLSession(configuration: configuration)
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        audioEngine.prepare()
    }

    /// Queue a chunk to speak. Chunks are sent in order on one WebSocket so audio
    /// begins as soon as Deepgram returns the first bytes for each flushed chunk.
    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stateQueue.async {
            self.active = true
            self.queuedText.append(trimmed)
            self.ensureConnection()
            self.drainTextQueue()
        }
    }

    /// One-shot: stop whatever is playing/queued and speak just this.
    public func speak(_ text: String) {
        stop()
        enqueue(text)
    }

    /// Stop playback and clear both Deepgram's server-side buffer and local audio.
    public func stop() {
        stateQueue.async {
            self.idleWork?.cancel()
            self.idleWork = nil
            self.queuedText.removeAll()
            self.pendingFlushes = 0
            self.pendingAudioBuffers = 0
            self.pcmCarry.removeAll()
            self.active = false
            self.playerNode.stop()
            if let webSocket = self.webSocket {
                self.send(["type": "Clear"], on: webSocket)
                self.send(["type": "Close"], on: webSocket)
                webSocket.cancel(with: .goingAway, reason: nil)
            }
            self.webSocket = nil
        }
    }

    private func ensureConnection() {
        guard webSocket == nil else { return }
        var request = URLRequest(url: makeURL())
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        receiveNext()
    }

    private func drainTextQueue() {
        guard let webSocket else { return }
        while !queuedText.isEmpty {
            let text = queuedText.removeFirst()
            pendingFlushes += 1
            send(["type": "Speak", "text": text], on: webSocket)
            send(["type": "Flush"], on: webSocket)
        }
    }

    private func receiveNext() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            self.stateQueue.async {
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveNext()
                case .failure:
                    self.closeConnection()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        active = true
        switch message {
        case .data(let data):
            playLinear16(data)
        case .string(let text):
            handleControlMessage(text)
        @unknown default:
            break
        }
        scheduleIdleCheck()
    }

    private func handleControlMessage(_ text: String) {
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = object["type"] as? String {
            switch type {
            case "Flushed":
                pendingFlushes = max(0, pendingFlushes - 1)
            case "Cleared":
                pendingFlushes = 0
            default:
                break
            }
            return
        }

        if let audio = Data(base64Encoded: text) {
            playLinear16(audio)
        }
    }

    private func playLinear16(_ data: Data) {
        guard let buffer = Self.makePCMBuffer(fromLinear16: data, carry: &pcmCarry, format: playbackFormat) else {
            return
        }
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            pendingAudioBuffers += 1
            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.stateQueue.async {
                    guard let self else { return }
                    self.pendingAudioBuffers = max(0, self.pendingAudioBuffers - 1)
                    self.scheduleIdleCheck()
                }
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
        } catch {
            pendingAudioBuffers = max(0, pendingAudioBuffers - 1)
        }
    }

    static func makePCMBuffer(
        fromLinear16 data: Data,
        carry: inout Data,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        var bytes = Data()
        if !carry.isEmpty {
            bytes.append(carry)
            carry.removeAll()
        }
        bytes.append(data)

        if bytes.count % 2 == 1, let last = bytes.last {
            carry.append(last)
            bytes.removeLast()
        }

        let sampleCount = bytes.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let raw = [UInt8](bytes)
        for index in 0..<sampleCount {
            let low = UInt16(raw[index * 2])
            let high = UInt16(raw[index * 2 + 1]) << 8
            let sample = Int16(bitPattern: high | low)
            channel[index] = max(-1, Float(sample) / 32_768)
        }
        return buffer
    }

    private func scheduleIdleCheck() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stateQueue.async {
                guard let self else { return }
                if self.queuedText.isEmpty, self.pendingFlushes == 0, self.pendingAudioBuffers == 0 {
                    self.active = false
                }
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func closeConnection() {
        webSocket = nil
        pendingFlushes = 0
        scheduleIdleCheck()
    }

    private func send(_ payload: [String: Any], on webSocket: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        webSocket.send(.string(string)) { [weak self] error in
            guard let self, error != nil else { return }
            self.stateQueue.async {
                self.pendingFlushes = max(0, self.pendingFlushes - 1)
                self.scheduleIdleCheck()
            }
        }
    }

    private func makeURL() -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/speak")!
        components.queryItems = [
            URLQueryItem(name: "model", value: voiceModel),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "\(Int(Self.sampleRate))"),
        ]
        return components.url!
    }
}
