@preconcurrency import AVFoundation

/// How kept audio is heard: the microphone's left channel and the Mac's right one mixed into both
/// ears, since either side alone would play in one ear. The player and Export Audio… both use it,
/// so an exported file sounds as Earshot plays it.
enum KeptAudioMix {
    /// A mixer that sums stereo into mono takes each side down 3 dB (measured: 0.5 on one side
    /// came out 0.354 in each ear); 3 dB brings a side that plays alone, as a remote speaker
    /// usually does, back to the level it was recorded at.
    static let gain: Float = 3

    /// Attaches `player`, which plays audio in `format`, and connects it through the mix to the
    /// main mixer. Everything runs at the audio's own rate; the engine converts to the output's.
    ///
    /// Both sides loud at once sum above full scale, so Apple's peak limiter follows the gain; a
    /// side alone at full scale passes it untouched.
    static func connect(
        _ player: AVAudioPlayerNode, playing format: AVAudioFormat, in engine: AVAudioEngine
    ) throws {
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        else { throw CaptureError.unsupportedFormat }
        let mixdown = AVAudioMixerNode()
        let boost = AVAudioUnitEQ(numberOfBands: 0)
        boost.globalGain = gain
        let limiter = AVAudioUnitEffect(
            audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
                componentFlagsMask: 0))
        [player, mixdown, boost, limiter].forEach(engine.attach)
        // macOS 27 replaces connect(_:to:format:) with connectNode(_:to:format:), which is not
        // available on the 26.4 this app still supports.
        engine.connect(player, to: mixdown, format: format)
        engine.connect(mixdown, to: boost, format: mono)
        engine.connect(boost, to: limiter, format: mono)
        engine.connect(limiter, to: engine.mainMixerNode, format: mono)
    }
}
