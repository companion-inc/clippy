import Foundation

public enum VoiceEvent: Equatable, Sendable {
    case wakeAccepted
    case transcriptInterim(String)
    case transcriptFinal(String)
    case assistantAudioStarted
    case assistantAudioFinished
    case stopSpeaking
    case failed(String)
}

public enum VoiceEventRouter {
    public static func mascotState(for event: VoiceEvent) -> MascotState? {
        switch event {
        case .wakeAccepted:
            return .listening
        case .transcriptInterim:
            return .hearing
        case .transcriptFinal:
            return .thinking
        case .assistantAudioStarted:
            return .speaking
        case .assistantAudioFinished, .stopSpeaking:
            return .idle
        case .failed:
            return .error
        }
    }
}
