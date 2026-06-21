import AVFoundation
import Foundation

/// Decodes and plays the original Clippy sound effects from the pack's
/// sounds-mp3.json (sound id -> base64 mp3 data URI, clippy.js format).
@MainActor
public final class SidekickSoundBank {
    public var isMuted: Bool
    private let soundDataByID: [String: Data]

    private var players: [String: QueuedSoundPlayer] = [:]

    public var loadedSoundCount: Int {
        soundDataByID.count
    }

    public init(packRoot: URL, isMuted: Bool = false) throws {
        self.isMuted = isMuted
        let data = try Data(contentsOf: packRoot.appending(path: "sounds-mp3.json"))
        let dataURIs = try JSONDecoder().decode([String: String].self, from: data)
        var decoded: [String: Data] = [:]
        for (id, uri) in dataURIs {
            guard
                let marker = uri.range(of: "base64,"),
                let mp3 = Data(base64Encoded: String(uri[marker.upperBound...]))
            else {
                continue
            }
            decoded[id] = mp3
        }
        self.soundDataByID = decoded
    }

    /// Plays a sound by its pack id. Restarts the clip if already playing,
    /// matching the original assistant's behavior.
    public func play(_ id: String) {
        guard !isMuted, let player = player(for: id) else {
            return
        }
        player.play()
    }

    private func player(for id: String) -> QueuedSoundPlayer? {
        if let player = players[id] {
            return player
        }
        guard let data = soundDataByID[id],
              let audioPlayer = try? AVAudioPlayer(data: data)
        else {
            return nil
        }
        let player = QueuedSoundPlayer(player: audioPlayer, label: "ai.companion.sidekick.sound-effects.\(id)")
        players[id] = player
        return player
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
