import Foundation

public struct VoiceCaptureAudio: Equatable, Sendable {
    public let pcm16Data: Data
    public let sampleRate: Int
    public let channels: Int

    public init(pcm16Data: Data, sampleRate: Int = 16_000, channels: Int = 1) {
        self.pcm16Data = pcm16Data
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var durationSeconds: Double {
        guard sampleRate > 0, channels > 0 else { return 0 }
        return Double(pcm16Data.count) / Double(sampleRate * channels * 2)
    }

    public var isEmpty: Bool {
        pcm16Data.isEmpty
    }

    public func wavData() -> Data {
        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + pcm16Data.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate * channels * 2))
        data.appendUInt16LE(UInt16(channels * 2))
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(pcm16Data.count))
        data.append(pcm16Data)
        return data
    }
}

public struct VoiceCaptureResult: Equatable, Sendable {
    public let transcript: String
    public let audio: VoiceCaptureAudio

    public init(transcript: String, audio: VoiceCaptureAudio) {
        self.transcript = transcript
        self.audio = audio
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
