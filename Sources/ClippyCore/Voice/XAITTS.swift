import AVFoundation
import Foundation

/// Clippy's spoken replies via xAI Grok TTS.
///
/// Mirrors Iris' provider shape: HTTP TTS, PCM output, xAI speech tags in the
/// text, and local playback through `AVAudioPlayerNode`.
public final class XAITTS {
    public static let sampleRate: Double = 24_000

    private let apiKey: String
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "clippy.xai.tts")
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: XAITTS.sampleRate,
        channels: 1,
        interleaved: false
    )!

    public var voiceID: String {
        didSet {
            guard oldValue != voiceID else { return }
            stop()
        }
    }

    private var queuedText: [String] = []
    private var currentTask: URLSessionDataTask?
    private var requestInFlight = false
    private var pendingAudioBuffers = 0
    private var active = false
    private var generation = 0
    private var pcmCarry = Data()
    private var idleWork: DispatchWorkItem?
    private var lastNotifiedSpeaking = false

    public var onSpeakingChanged: ((Bool) -> Void)?
    public var onError: ((String) -> Void)?

    public var isSpeaking: Bool {
        stateQueue.sync {
            active || requestInFlight || !queuedText.isEmpty || pendingAudioBuffers > 0
        }
    }

    public init?(voiceID: String = ClippyVoice.default.id) {
        guard let key = ClippySecrets.xaiAPIKey else { return nil }
        self.apiKey = key
        self.voiceID = voiceID
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        audioEngine.prepare()
    }

    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stateQueue.async {
            self.active = true
            self.notifySpeakingChanged(true)
            self.queuedText.append(trimmed)
            self.drainTextQueue()
        }
    }

    public func speak(_ text: String) {
        stop()
        enqueue(text)
    }

    public func stop() {
        stateQueue.async {
            self.generation += 1
            self.idleWork?.cancel()
            self.idleWork = nil
            self.currentTask?.cancel()
            self.currentTask = nil
            self.queuedText.removeAll()
            self.requestInFlight = false
            self.pendingAudioBuffers = 0
            self.pcmCarry.removeAll()
            self.active = false
            self.playerNode.stop()
            self.notifySpeakingChanged(false)
        }
    }

    private func drainTextQueue() {
        guard !requestInFlight, !queuedText.isEmpty else {
            scheduleIdleCheck()
            return
        }

        let text = queuedText.removeFirst()
        requestInFlight = true
        active = true
        let requestGeneration = generation

        guard let request = makeRequest(text: text) else {
            requestInFlight = false
            drainTextQueue()
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.stateQueue.async {
                guard requestGeneration == self.generation else { return }
                self.currentTask = nil
                self.requestInFlight = false
                defer {
                    self.drainTextQueue()
                    self.scheduleIdleCheck()
                }
                if let error {
                    self.notifyError("request failed: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.notifyError("missing HTTP response")
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    self.notifyError("HTTP \(http.statusCode): \(Self.errorMessage(from: data))")
                    return
                }
                guard let data,
                      let audio = Self.audioBytes(from: data),
                      !audio.isEmpty else {
                    self.notifyError("empty or unsupported audio response")
                    return
                }
                self.playLinear16(audio)
            }
        }
        currentTask = task
        task.resume()
    }

    private func makeRequest(text: String) -> URLRequest? {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/tts")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "voice_id": voiceID,
            "language": "en",
            "output_format": [
                "codec": "pcm",
                "sample_rate": Int(Self.sampleRate),
            ],
            "optimize_streaming_latency": 0,
            "text_normalization": true,
        ])
        return request
    }

    static func audioBytes(from data: Data) -> Data? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let base64 = object["audio"] as? String {
            return Data(base64Encoded: base64)
        } else if (try? JSONSerialization.jsonObject(with: data)) != nil {
            return nil
        }
        return data
    }

    static func errorMessage(from data: Data?) -> String {
        guard let data else {
            return "no response body"
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String {
                return error
            }
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let text = String(decoding: data.prefix(240), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "\(data.count) bytes" : text
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

    public static func makePCMBuffer(
        fromLinear16 data: Data,
        carry: inout Data,
        format: AVAudioFormat,
        gain: Float = 1.6
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
        let clampedGain = max(0, min(gain, 4))
        for index in 0..<sampleCount {
            let low = UInt16(raw[index * 2])
            let high = UInt16(raw[index * 2 + 1]) << 8
            let sample = Int16(bitPattern: high | low)
            let scaled = Float(sample) / 32_768 * clampedGain
            channel[index] = max(-1, min(1, scaled))
        }
        return buffer
    }

    private func scheduleIdleCheck() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stateQueue.async {
                guard let self else { return }
                if self.queuedText.isEmpty, !self.requestInFlight, self.pendingAudioBuffers == 0 {
                    self.active = false
                    self.notifySpeakingChanged(false)
                }
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func notifySpeakingChanged(_ speaking: Bool) {
        guard speaking != lastNotifiedSpeaking else { return }
        lastNotifiedSpeaking = speaking
        let callback = onSpeakingChanged
        DispatchQueue.main.async {
            callback?(speaking)
        }
    }

    private func notifyError(_ message: String) {
        let callback = onError
        DispatchQueue.main.async {
            callback?(message)
        }
    }
}
