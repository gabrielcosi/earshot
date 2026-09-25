import Foundation

/// How kept audio is encoded: stereo AAC, the microphone on the left and the Mac's audio on the
/// right. Low is the engine's own 16 kHz; Medium and High record the captures a second time at
/// their rate while the session runs.
///
/// Each bitrate is the one at which AAC keeps the whole band of its rate, measured with tones
/// under noise: 24 kHz passes everything up to 12 kHz at 64 kbit/s already, and 96 kbit/s brings
/// its error on speech to Low's (23 dB); 48 kHz reaches about 17 kHz at 128 kbit/s, where
/// 96 kbit/s cuts at 16 kHz.
public enum AudioQuality: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var sampleRate: Double {
        switch self {
        case .low: 16_000
        case .medium: 24_000
        case .high: 48_000
        }
    }

    /// For both channels together.
    var bitRate: Int {
        switch self {
        case .low: 64_000
        case .medium: 96_000
        case .high: 128_000
        }
    }

    /// Encoded at the highest rate that was recorded, never above what was chosen: a session
    /// recorded only at 16 kHz, such as one where Keep audio was turned on midway, stays at Low.
    static func encoding(_ rates: [Double], cappedAt preset: AudioQuality) -> AudioQuality {
        of(rate: min(rates.max() ?? preset.sampleRate, preset.sampleRate))
    }

    /// The preset whose rate a kept file was written at.
    static func of(rate: Double) -> AudioQuality {
        allCases.last { $0.sampleRate <= rate } ?? .low
    }
}

/// A capture's audio a second time, at the rate kept audio is recorded at, alongside the 16 kHz
/// it sends the engine.
public struct KeptOutput: Sendable {
    public let rate: Double
    public let onAudio: @Sendable (Data) -> Void

    public init(rate: Double, onAudio: @escaping @Sendable (Data) -> Void) {
        self.rate = rate
        self.onAudio = onAudio
    }
}
