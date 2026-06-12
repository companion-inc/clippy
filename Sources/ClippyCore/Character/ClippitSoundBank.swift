import AVFoundation
import Foundation

/// Decodes and plays the original Clippit sound effects from the pack's
/// sounds-mp3.json (sound id -> base64 mp3 data URI, clippy.js format).
@MainActor
public final class ClippitSoundBank {
    public var isMuted = false

    private var players: [String: AVAudioPlayer] = [:]

    public var loadedSoundCount: Int {
        players.count
    }

    public init(packRoot: URL) throws {
        let data = try Data(contentsOf: packRoot.appending(path: "sounds-mp3.json"))
        let dataURIs = try JSONDecoder().decode([String: String].self, from: data)
        for (id, uri) in dataURIs {
            guard
                let marker = uri.range(of: "base64,"),
                let mp3 = Data(base64Encoded: String(uri[marker.upperBound...]))
            else {
                continue
            }
            players[id] = try? AVAudioPlayer(data: mp3)
        }
    }

    /// Plays a sound by its pack id. Restarts the clip if already playing,
    /// matching the original assistant's behavior.
    public func play(_ id: String) {
        guard !isMuted, let player = players[id] else {
            return
        }
        player.currentTime = 0
        player.play()
    }
}
