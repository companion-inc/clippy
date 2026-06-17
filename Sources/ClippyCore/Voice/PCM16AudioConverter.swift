import AVFoundation
import Foundation

/// Converts mic `AVAudioPCMBuffer`s to 16 kHz mono linear-PCM16 `Data` for the
/// Deepgram websocket.
final class PCM16AudioConverter {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var currentInputDescription: String?

    init(targetSampleRate: Double) {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    func convertToPCM16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        let inputDescription = buffer.format.settings.description
        if currentInputDescription != inputDescription {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            currentInputDescription = inputDescription
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var providedSource = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if providedSource {
                outStatus.pointee = .noDataNow
                return nil
            }
            providedSource = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error,
              let pointer = output.audioBufferList.pointee.mBuffers.mData else {
            return nil
        }
        let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(output.frameLength) * bytesPerFrame
        guard byteCount > 0 else { return nil }
        return Data(bytes: pointer, count: byteCount)
    }
}
