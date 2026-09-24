@preconcurrency import AVFoundation
import EarshotKit

/// Converts any capture format to the 16 kHz mono PCM16 the server expects.
final class Resampler {
    static let target: AVAudioFormat = {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
            )
        else { preconditionFailure("16 kHz mono float32 is always a valid format") }
        return format
    }()

    private let converter: AVAudioConverter

    init?(from source: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: Self.target) else { return nil }
        converter.downmix = true
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let ratio = Self.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: capacity) else {
            return nil
        }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else {
            return nil
        }
        return PCM.int16LittleEndian(
            UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
