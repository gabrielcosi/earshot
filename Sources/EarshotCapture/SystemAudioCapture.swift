@preconcurrency import AVFoundation
import CoreAudio
import os

/// Captures what the Mac plays, from every app or from chosen ones, through a Core Audio process
/// tap wrapped in a private aggregate device, and hands out 16 kHz mono PCM16 chunks.
///
/// A tap of chosen apps holds their processes, not the apps: a browser starts a new audio helper
/// when a call begins, so the tap is rebuilt whenever the processes behind the chosen apps change.
///
/// The output device clocks the audio, but the tap reports the aggregate's nominal rate, which
/// defaults to 48 kHz. On a 44.1 kHz output the samples arrive at 44.1 kHz labelled 48 kHz, and
/// remote speech runs 8% fast and drifts 5 minutes behind in an hour. So the aggregate is set to
/// the output's rate before the format is read, and capture restarts when the output changes.
///
/// Unchecked Sendable: after `start`, every change to its state runs on `queue`, where the
/// Core Audio listeners also run.
public final class SystemAudioCapture: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputID = AudioObjectID(kAudioObjectUnknown)
    private var onAudio: (@Sendable (Data) -> Void)?
    private var onRestart: (@Sendable () -> Void)?
    /// `AudioSource` identifiers to capture; empty captures every app.
    private var sources: Set<String>
    /// The process objects the current tap holds, when it holds chosen apps.
    private var tapped: Set<AudioObjectID> = []
    private let queue = DispatchQueue(
        label: "com.gabrielcosi.earshot.system-audio", qos: .userInitiated)
    private let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "capture")

    private static let defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let processList = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let nominalRate = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// `sources` are `AudioSource` identifiers; empty captures every app.
    public init(sources: Set<String> = []) {
        self.sources = sources
    }

    /// Switches to other apps, or to every app with an empty set, while capturing.
    public func listen(to sources: Set<String>) {
        queue.async { [weak self] in
            guard let self, self.sources != sources else { return }
            self.sources = sources
            self.restart()
        }
    }

    /// `onRestart` is called after the tap has been rebuilt on another output device.
    public func start(
        onAudio: @escaping @Sendable (Data) -> Void, onRestart: @escaping @Sendable () -> Void = {}
    ) throws {
        self.onAudio = onAudio
        self.onRestart = onRestart
        try startTap(onAudio: onAudio)
        var address = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, outputChanged)
        var processes = Self.processList
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &processes, queue, processesChanged)
    }

    private lazy var outputChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.restart()
    }

    private lazy var processesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self, !self.sources.isEmpty,
            Set(AudioSources.processObjects(for: self.sources)) != self.tapped
        else { return }
        self.restart()
    }

    /// Rebuilds the tap on the current output device at its current rate.
    private func restart() {
        guard let onAudio else { return }
        stopTap()
        do {
            try startTap(onAudio: onAudio)
            onRestart?()
            log.notice("system audio restarted")
        } catch {
            log.error("system audio restart failed: \(error, privacy: .public)")
        }
    }

    /// Every app, or the processes of the chosen ones; nil while none of those is running, until
    /// the process list changes.
    private func tapDescription() -> CATapDescription? {
        guard !sources.isEmpty else {
            return CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }
        let objects = AudioSources.processObjects(for: sources)
        tapped = Set(objects)
        return objects.isEmpty ? nil : CATapDescription(stereoMixdownOfProcesses: objects)
    }

    private func startTap(onAudio: @escaping @Sendable (Data) -> Void) throws {
        guard let description = tapDescription() else { return }
        description.uuid = UUID()
        description.name = "Earshot"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("AudioHardwareCreateProcessTap") {
            AudioHardwareCreateProcessTap(description, &tapID)
        }

        outputID = try Self.defaultOutputDevice()
        let outputUID = try Self.uid(of: outputID)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Earshot Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]
            ],
        ]
        try check("AudioHardwareCreateAggregateDevice") {
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        }

        var rate = try Self.rate(of: outputID)
        var rateAddress = Self.nominalRate
        try check("set aggregate sample rate") {
            AudioObjectSetPropertyData(
                aggregateID, &rateAddress, 0, nil, UInt32(MemoryLayout<Float64>.size), &rate)
        }
        AudioObjectAddPropertyListenerBlock(outputID, &rateAddress, queue, outputChanged)

        var streamDescription = try Self.tapFormat(tapID)
        guard streamDescription.mSampleRate == rate else {
            throw CaptureError.rateMismatch(tap: streamDescription.mSampleRate, output: rate)
        }
        guard let format = AVAudioFormat(streamDescription: &streamDescription),
            let resampler = Resampler(from: format)
        else { throw CaptureError.unsupportedFormat }

        try check("AudioDeviceCreateIOProcIDWithBlock") {
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
                _, input, _, _, _ in
                guard
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
                    let pcm = resampler.convert(buffer)
                else { return }
                onAudio(pcm)
            }
        }
        try check("AudioDeviceStart") { AudioDeviceStart(aggregateID, procID) }
    }

    public func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        var address = Self.defaultOutput
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, outputChanged)
        var processes = Self.processList
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &processes, queue, processesChanged)
        onAudio = nil
        onRestart = nil
        stopTap()
    }

    private func stopTap() {
        if outputID != kAudioObjectUnknown {
            var address = Self.nominalRate
            AudioObjectRemovePropertyListenerBlock(outputID, &address, queue, outputChanged)
        }
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        (tapID, aggregateID, procID) = (
            AudioObjectID(kAudioObjectUnknown), AudioObjectID(kAudioObjectUnknown), nil
        )
    }

    deinit { stopOnQueue() }

    private func check(_ call: String, _ body: () -> OSStatus) throws {
        let status = body()
        guard status == noErr else { throw CaptureError.coreAudio(call, status) }
    }

    private static func defaultOutputDevice() throws -> AudioObjectID {
        try property(AudioObjectID(kAudioObjectSystemObject), defaultOutput, AudioObjectID(0))
    }

    private static func rate(of device: AudioObjectID) throws -> Float64 {
        try property(device, nominalRate, Float64(0))
    }

    private static func uid(of device: AudioObjectID) throws -> String {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let uid = try property(device, address, Unmanaged<CFString>?.none)
        guard let uid else {
            throw CaptureError.coreAudio("device UID", kAudioHardwareUnknownPropertyError)
        }
        return uid.takeRetainedValue() as String
    }

    private static func property<Value>(
        _ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: Value
    ) throws -> Value {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            guard let base = bytes.baseAddress else { return kAudioHardwareBadPropertySizeError }
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, base)
        }
        guard status == noErr else {
            throw CaptureError.coreAudio("property \(address.mSelector)", status)
        }
        return value
    }

    private static func tapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        return try property(tapID, address, AudioStreamBasicDescription())
    }
}
