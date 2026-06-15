import AVFoundation
import Foundation

/// Clippy's spoken replies via Deepgram Aura-2. Streaming-capable: `enqueue` text
/// chunks (sentences) as the reply streams in and they play back-to-back, in order,
/// so Clippy starts talking before the whole reply is done. Implemented for Clippy's
/// DeepgramTTSClient. Callers pass already-stripped text — tags never reach Deepgram.
public final class DeepgramTTS: NSObject, AVAudioPlayerDelegate {
    private let apiKey: String
    public var voiceModel: String
    private let session: URLSession
    private var player: AVAudioPlayer?
    private var fetch: URLSessionDataTask?
    private var queue: [String] = []
    private var busy = false   // a chunk is being fetched or is currently playing

    /// True while anything is queued, fetching, or playing.
    public var isSpeaking: Bool { busy || !queue.isEmpty }

    /// Returns nil if there is no Deepgram key configured.
    public init?(voiceModel: String = ClippyVoice.default.id) {
        guard let key = ClippySecrets.deepgramAPIKey else { return nil }
        self.apiKey = key
        self.voiceModel = voiceModel
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        super.init()
    }

    /// Queue a chunk to speak after everything already queued (streaming path).
    public func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.append(trimmed)
        playNext()
    }

    /// One-shot: stop whatever is playing/queued and speak just this.
    public func speak(_ text: String) {
        stop()
        enqueue(text)
    }

    /// Stop playback and clear the queue (barge-in, disable TTS).
    public func stop() {
        fetch?.cancel(); fetch = nil
        player?.stop(); player = nil
        queue.removeAll()
        busy = false
    }

    private func playNext() {
        guard !busy, !queue.isEmpty,
              let url = URL(string: "https://api.deepgram.com/v1/speak?model=\(voiceModel)&encoding=mp3") else { return }
        let text = queue.removeFirst()
        busy = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])

        fetch = session.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetch = nil
                if let data,
                   let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let p = try? AVAudioPlayer(data: data) {
                    p.delegate = self
                    self.player = p
                    p.play()
                    // `busy` stays true until audioPlayerDidFinishPlaying advances the queue.
                } else {
                    self.busy = false
                    self.playNext() // skip a failed chunk, keep the speech flowing
                }
            }
        }
        fetch?.resume()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        busy = false
        playNext()
    }
}
