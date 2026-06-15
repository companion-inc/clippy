import AVFoundation
import Foundation

/// Clippy's spoken replies via Deepgram Aura-2. POSTs text to `/v1/speak` and
/// plays the returned MP3. Implemented for Clippy's DeepgramTTSClient.
public final class DeepgramTTS {
    private let apiKey: String
    public var voiceModel: String
    private let session: URLSession
    private var player: AVAudioPlayer?

    /// Returns nil if there is no Deepgram key configured.
    public init?(voiceModel: String = ClippyVoice.default.id) {
        guard let key = ClippySecrets.deepgramAPIKey else { return nil }
        self.apiKey = key
        self.voiceModel = voiceModel
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    public func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://api.deepgram.com/v1/speak?model=\(voiceModel)&encoding=mp3") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": trimmed])

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let data,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return }
            DispatchQueue.main.async {
                self.player = try? AVAudioPlayer(data: data)
                self.player?.play()
            }
        }.resume()
    }

    public func stop() {
        player?.stop()
        player = nil
    }
}
