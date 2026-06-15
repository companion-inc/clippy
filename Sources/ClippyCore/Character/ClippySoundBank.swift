import AVFoundation
import Foundation

/// Decodes and plays the original Clippy sound effects from the pack's
/// sounds-mp3.json (sound id -> base64 mp3 data URI, clippy.js format).
@MainActor
public final class ClippySoundBank {
    public var isMuted = false

    private var players: [String: QueuedSoundPlayer] = [:]

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
            guard let player = try? AVAudioPlayer(data: mp3) else {
                continue
            }
            player.prepareToPlay()
            players[id] = QueuedSoundPlayer(player: player, label: "ai.companion.clippy.sound-effects.\(id)")
        }
    }

    /// Plays a sound by its pack id. Restarts the clip if already playing,
    /// matching the original assistant's behavior.
    public func play(_ id: String) {
        guard !isMuted, let player = players[id] else {
            return
        }
        player.play()
    }
}

// AVAudioPlayer is not Sendable; this wrapper confines every player mutation
// and play call to one private serial queue.
private final class QueuedSoundPlayer: @unchecked Sendable {
    private let player: AVAudioPlayer
    private let queue: DispatchQueue

    init(player: AVAudioPlayer, label: String) {
        self.player = player
        self.queue = DispatchQueue(label: label)
    }

    func play() {
        queue.async {
            self.player.currentTime = 0
            self.player.prepareToPlay()
            self.player.play()
        }
    }
}
