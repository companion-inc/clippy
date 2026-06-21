import Foundation

public struct VoiceActivityEvent: Equatable, Sendable {
    public let isSpeechActive: Bool
    public let levelDBFS: Double

    public init(isSpeechActive: Bool, levelDBFS: Double) {
        self.isSpeechActive = isSpeechActive
        self.levelDBFS = levelDBFS
    }
}

public struct VoiceActivityDetector: Sendable {
    public struct Configuration: Equatable, Sendable {
        public let speechStartThresholdDBFS: Double
        public let speechEndThresholdDBFS: Double
        public let minimumSpeechDuration: TimeInterval
        public let minimumSilenceDuration: TimeInterval

        public init(
            speechStartThresholdDBFS: Double = -42,
            speechEndThresholdDBFS: Double = -50,
            minimumSpeechDuration: TimeInterval = 0.10,
            minimumSilenceDuration: TimeInterval = 0.45
        ) {
            self.speechStartThresholdDBFS = speechStartThresholdDBFS
            self.speechEndThresholdDBFS = speechEndThresholdDBFS
            self.minimumSpeechDuration = minimumSpeechDuration
            self.minimumSilenceDuration = minimumSilenceDuration
        }
    }

    public let configuration: Configuration
    public private(set) var isSpeechActive = false
    public private(set) var lastLevelDBFS = -Double.infinity

    private var aboveThresholdDuration: TimeInterval = 0
    private var belowThresholdDuration: TimeInterval = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        isSpeechActive = false
        lastLevelDBFS = -Double.infinity
        aboveThresholdDuration = 0
        belowThresholdDuration = 0
    }

    public mutating func process(
        pcm16Data: Data,
        sampleRate: Int = 16_000,
        channels: Int = 1
    ) -> VoiceActivityEvent? {
        let duration = Self.durationSeconds(
            pcm16Data: pcm16Data,
            sampleRate: sampleRate,
            channels: channels
        )
        guard duration > 0 else { return nil }

        let level = Self.levelDBFS(pcm16Data: pcm16Data)
        lastLevelDBFS = level

        if isSpeechActive {
            guard level < configuration.speechEndThresholdDBFS else {
                belowThresholdDuration = 0
                return nil
            }
            belowThresholdDuration += duration
            guard belowThresholdDuration >= configuration.minimumSilenceDuration else {
                return nil
            }
            isSpeechActive = false
            aboveThresholdDuration = 0
            return VoiceActivityEvent(isSpeechActive: false, levelDBFS: level)
        }

        guard level >= configuration.speechStartThresholdDBFS else {
            aboveThresholdDuration = 0
            return nil
        }
        aboveThresholdDuration += duration
        guard aboveThresholdDuration >= configuration.minimumSpeechDuration else {
            return nil
        }
        isSpeechActive = true
        belowThresholdDuration = 0
        return VoiceActivityEvent(isSpeechActive: true, levelDBFS: level)
    }

    public static func durationSeconds(
        pcm16Data: Data,
        sampleRate: Int = 16_000,
        channels: Int = 1
    ) -> TimeInterval {
        guard sampleRate > 0, channels > 0 else { return 0 }
        return Double(pcm16Data.count / 2) / Double(sampleRate * channels)
    }

    public static func levelDBFS(pcm16Data: Data) -> Double {
        let sampleCount = pcm16Data.count / 2
        guard sampleCount > 0 else { return -Double.infinity }

        var sumSquares = 0.0
        pcm16Data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<sampleCount {
                let byteIndex = index * 2
                let low = UInt16(bytes[byteIndex])
                let high = UInt16(bytes[byteIndex + 1]) << 8
                let sample = Int16(bitPattern: high | low)
                let normalized = Double(sample) / 32768.0
                sumSquares += normalized * normalized
            }
        }

        guard sumSquares > 0 else { return -Double.infinity }
        let rms = sqrt(sumSquares / Double(sampleCount))
        return 20 * log10(max(rms, Double.leastNonzeroMagnitude))
    }
}
