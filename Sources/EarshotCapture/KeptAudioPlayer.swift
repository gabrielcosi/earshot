@preconcurrency import AVFoundation
import AppKit

/// Plays kept audio from any point with both channels in both ears, through `KeptAudioMix`.
/// AVAudioPlayer plays a file's channels as they are and on macOS cannot remap them, so the Mac's
/// audio, on the right, would play in one ear only.
///
/// The engine is built on first play, paused with playback, and stopped by `stop()`. It stops
/// itself when the output device or its format changes, and can fall silent over the Mac's sleep;
/// both rebuild the output connection and carry on from where playback was.
@MainActor
public final class KeptAudioPlayer {
    public let duration: Double
    public private(set) var isPlaying = false
    /// Called when playback stops on its own: at the end, which puts it back at the start, or
    /// when the output could not start again after it changed.
    public var onEnd: () -> Void = {}
    private let file: AVAudioFile
    private let node = AVAudioPlayerNode()
    private var engine: AVAudioEngine?
    /// Where the scheduled segment starts; the node counts its time from there.
    private var segmentStart = 0.0
    /// Where playback is, as last known: while paused, and whenever the node cannot say.
    private var position = 0.0
    /// Tells the completion of the segment playing from that of one a seek or a pause replaced.
    private var generation = 0
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    public convenience init?(audio: URL) {
        self.init(audio: audio, engine: nil)
    }

    /// `engine` is a test's engine in offline rendering mode; nil builds one for the output.
    init?(audio: URL, engine: AVAudioEngine?) {
        guard let file = try? AVAudioFile(forReading: audio) else { return nil }
        self.file = file
        self.engine = engine
        duration = Double(file.length) / file.processingFormat.sampleRate
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        engine?.stop()
    }

    public var currentTime: Double {
        guard isPlaying, let rendered = node.lastRenderTime,
            let time = node.playerTime(forNodeTime: rendered)
        else { return position }
        position = min(segmentStart + max(Double(time.sampleTime), 0) / time.sampleRate, duration)
        return position
    }

    /// False when the output could not start.
    @discardableResult
    public func play() -> Bool {
        guard let engine = prepared() else { return false }
        if position >= duration { position = 0 }
        guard schedule(from: position) else { return false }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return false
        }
        node.play()
        isPlaying = true
        return true
    }

    /// From `start`; false, with nothing changed, when the audio ends before it, as audio kept
    /// only in part does before the later lines.
    public func play(from start: Double) -> Bool {
        guard start < duration else { return false }
        seek(to: start)
        return isPlaying || play()
    }

    public func seek(to time: Double) {
        position = min(max(time, 0), duration)
        guard isPlaying else { return }
        // At the end there is nothing to schedule: the node refuses a segment of no frames.
        guard schedule(from: position) else { return end() }
        node.play()
    }

    public func pause() {
        position = currentTime
        halt()
        engine?.pause()
    }

    /// Pauses and lets the output go, for when the player is out of sight.
    public func stop() {
        pause()
        engine?.stop()
    }

    private func halt() {
        generation += 1
        isPlaying = false
        node.stop()
    }

    private func prepared() -> AVAudioEngine? {
        if let engine, node.engine != nil { return engine }
        let engine = engine ?? AVAudioEngine()
        do {
            try KeptAudioMix.connect(node, playing: file.processingFormat, in: engine)
        } catch {
            return nil
        }
        engine.prepare()
        self.engine = engine
        observe(.default, .AVAudioEngineConfigurationChange, object: engine)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        return engine
    }

    /// False when nothing is left from `start` to play.
    private func schedule(from start: Double) -> Bool {
        generation += 1
        let current = generation
        node.stop()
        let rate = file.processingFormat.sampleRate
        let first = min(AVAudioFramePosition(start * rate), file.length)
        guard first < file.length else { return false }
        segmentStart = Double(first) / rate
        node.scheduleSegment(
            file, startingFrame: first, frameCount: AVAudioFrameCount(file.length - first),
            at: nil, completionCallbackType: .dataPlayedBack,
            completionHandler: Self.onMain { [weak self] in self?.finished(current) })
        return true
    }

    private func finished(_ segment: Int) {
        guard segment == generation, isPlaying else { return }
        end()
    }

    private func end() {
        halt()
        position = 0
        engine?.pause()
        onEnd()
    }

    /// The output changed under the engine, or the Mac woke: the output connection is made again
    /// at whatever format the output has now, and playback carries on only if it was playing.
    private func reconnect() {
        guard let engine else { return }
        let playing = isPlaying
        position = currentTime
        halt()
        engine.stop()
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        if playing, !play() { onEnd() }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil
    ) {
        let observer = center.addObserver(
            forName: name, object: object, queue: nil,
            using: Self.onMain { [weak self] in self?.reconnect() })
        observers.append((center, observer))
    }

    /// Engine callbacks and these notifications arrive on other threads. A closure formed in this
    /// MainActor type would be isolated to it and trap there, so the closure handed out is formed
    /// here, nonisolated, and hops to the main actor.
    nonisolated private static func onMain<Argument>(
        _ body: @escaping @MainActor () -> Void
    ) -> @Sendable (Argument) -> Void {
        { _ in Task { @MainActor in body() } }
    }
}
