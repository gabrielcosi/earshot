@preconcurrency import AVFoundation
import EarshotKit

/// Converts any capture format to mono PCM16 at one rate: the server's 16 kHz, or the rate kept
/// audio is recorded at.
final class Resampler {
    private let target: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from source: AVAudioFormat, rate: Double = 16_000) {
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: source, to: target)
        else { return nil }
        converter.downmix = true
        self.target = target
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
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
