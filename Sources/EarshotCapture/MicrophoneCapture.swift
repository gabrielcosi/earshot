@preconcurrency import AVFoundation
import os

/// Captures the default input device and hands out 16 kHz mono PCM16 chunks.
///
/// Nonisolated: the tap block runs on an AVAudioEngine thread, and a MainActor-inferred
/// closure there traps on the executor check. Sendable through `state`'s lock: a configuration
/// change restarts the engine from a notification, which arrives off the caller's thread.
public final class MicrophoneCapture: @unchecked Sendable {
    /// About 85 ms at 48 kHz: short enough that partials keep up with speech.
    private static let tapFrames: AVAudioFrameCount = 4096

    private struct State {
        var deviceUID: String?
        var onAudio: (@Sendable (Data) -> Void)?
        var kept: KeptOutput?
        var observer: (any NSObjectProtocol)?
    }

    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    /// The configuration-change notification is posted on the engine's internal queue, where a
    /// block waiting for `state` while `stop()` holds it and stops the engine would deadlock.
    /// Delivered here instead, the block waits on a queue the engine never needs.
    private let restarts = OperationQueue()
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "capture")

    public init() {
        restarts.maxConcurrentOperationCount = 1
    }

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// `deviceUID` nil captures the system default input. `kept` receives the same audio at its
    /// own rate.
    public func start(
        deviceUID: String?, kept: KeptOutput? = nil, onAudio: @escaping @Sendable (Data) -> Void
    ) throws {
        try state.withLockUnchecked { state in
            state.deviceUID = deviceUID
            state.onAudio = onAudio
            state.kept = kept
            try install(state)
            state.observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: restarts
            ) { [weak self] _ in self?.restart() }
        }
    }

    /// Another process starting or stopping voice processing (a FaceTime or browser call)
    /// changes the input hardware's configuration: the engine stops itself, and the input's
    /// format can change with it. Measured: `isRunning` is false afterwards, and a tap installed
    /// for the new format restarts cleanly.
    private func restart() {
        state.withLockUnchecked { state in
            guard state.onAudio != nil else { return }
            do {
                try install(state)
                log.notice("microphone restarted after a configuration change")
            } catch {
                log.error("microphone restart failed: \(error, privacy: .public)")
            }
        }
    }

    /// Taps the input at its current format and starts the engine.
    private func install(_ state: State) throws {
        guard let onAudio = state.onAudio else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        if let uid = state.deviceUID, let device = AudioDevices.device(uid: uid) {
            try input.auAudioUnit.setDeviceID(device)
        }
        guard
            let tap = MicrophoneTap(
                format: input.outputFormat(forBus: 0), kept: state.kept, onAudio: onAudio)
        else { throw CaptureError.unsupportedFormat }
        input.installTap(onBus: 0, bufferSize: Self.tapFrames, format: tap.format) { buffer, _ in
            tap.receive(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        state.withLockUnchecked { state in
            if let observer = state.observer { NotificationCenter.default.removeObserver(observer) }
            state.observer = nil
            state.onAudio = nil
            state.kept = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }
}

/// The input's format at one point in its life and the conversion that follows it. A
/// configuration change replaces the tap; the callback it feeds stays the same.
struct MicrophoneTap {
    let format: AVAudioFormat
    private let resampler: Resampler
    private let onAudio: @Sendable (Data) -> Void
    private let kept: (resampler: Resampler, onAudio: @Sendable (Data) -> Void)?

    init?(
        format: AVAudioFormat, kept: KeptOutput? = nil, onAudio: @escaping @Sendable (Data) -> Void
    ) {
        guard let resampler = Resampler(from: format) else { return nil }
        if let kept {
            guard let keptResampler = Resampler(from: format, rate: kept.rate) else { return nil }
            self.kept = (keptResampler, kept.onAudio)
        } else {
            self.kept = nil
        }
        self.format = format
        self.resampler = resampler
        self.onAudio = onAudio
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        if let pcm = resampler.convert(buffer) { onAudio(pcm) }
        if let kept, let pcm = kept.resampler.convert(buffer) { kept.onAudio(pcm) }
    }
}

public enum CaptureError: LocalizedError {
    case unsupportedFormat
    case coreAudio(String, OSStatus)
    case permissionDenied(String)
    case rateMismatch(tap: Float64, output: Float64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "The capture format cannot be converted to mono PCM."
        case .coreAudio(let call, let status): "\(call) failed (OSStatus \(status))."
        case .permissionDenied(let what): "\(what) access was denied in System Settings."
        case .rateMismatch(let tap, let output):
            "System audio reports \(Int(tap)) Hz on a \(Int(output)) Hz output device."
        }
    }
}
