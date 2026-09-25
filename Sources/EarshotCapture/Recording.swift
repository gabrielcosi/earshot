import EarshotKit
import Foundation
import os

/// One capture's audio as mono PCM16 for the length of a session. Kept in the container's caches
/// and deleted after the session, unless "Keep audio" encodes it into the store's audio folder
/// first.
public final class Recording: Sendable {
    public let url: URL
    public let rate: Double
    private let state: OSAllocatedUnfairLock<State>

    private struct State {
        var handle: FileHandle?
        var failure: NSError?
    }

    public static let directory = URL.cachesDirectory.appending(path: "Earshot")
    private static let log = Logger(subsystem: "com.gabrielcosi.earshot", category: "capture")

    /// Recordings left by a crash or a forced quit, which skip the normal clean-up.
    public static func removeLeftovers() {
        try? FileManager.default.removeItem(at: directory)
    }

    public convenience init(_ channel: Channel, rate: Double = 16_000, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(
            path: "\(channel.rawValue)-\(Int(rate))-\(UUID().uuidString).pcm")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        try self.init(url: url, rate: rate, handle: FileHandle(forWritingTo: url))
    }

    init(url: URL, rate: Double, handle: FileHandle) {
        self.url = url
        self.rate = rate
        state = OSAllocatedUnfairLock(uncheckedState: State(handle: handle))
    }

    /// After a write fails, such as on a full disk, nothing more is written: the file stays what
    /// was heard up to then, with no gap that would put later audio at the wrong time.
    public func append(_ pcm: Data) {
        state.withLockUnchecked { state in
            guard let handle = state.handle, state.failure == nil else { return }
            do {
                try handle.write(contentsOf: pcm)
            } catch {
                state.failure = error as NSError
                Self.log.error(
                    "recording \(self.url.lastPathComponent, privacy: .public) stopped: \(error, privacy: .public)"
                )
            }
        }
    }

    /// The write that failed, when the file holds only the audio before it.
    public var failure: NSError? {
        state.withLockUnchecked(\.failure)
    }

    public func finish() {
        state.withLockUnchecked { state in
            try? state.handle?.close()
            state.handle = nil
        }
    }

    /// A WAV clip of the recording, for hearing who a speaker is.
    public func clip(from start: Double, seconds: Double) -> Data? {
        guard let reader = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? reader.close() }
        let bytesPerSecond = rate * 2
        try? reader.seek(toOffset: UInt64(max(0, start) * bytesPerSecond) & ~1)
        guard let pcm = try? reader.read(upToCount: Int(seconds * bytesPerSecond) & ~1),
            !pcm.isEmpty
        else { return nil }
        return PCM.wav(pcm)
    }

    public func discard() {
        finish()
        try? FileManager.default.removeItem(at: url)
    }
}

/// A session's recordings: what the engine heard at 16 kHz, which relabelling and naming read, and,
/// when the session started with Keep audio at Medium or High, the same audio at that rate for the
/// kept file. The higher-rate files are removed however the session ends.
public final class SessionRecordings: Sendable {
    public let system: Recording
    public let microphone: Recording?
    public let keptSystem: Recording?
    /// None while echo is cancelled: the cancelled microphone exists only at the engine's rate,
    /// and the raw one would play the other side a second time.
    public let keptMicrophone: Recording?
    /// What was chosen when the session started; a change applies from the next session.
    let quality: AudioQuality

    public convenience init(
        microphone: Bool, keeping quality: AudioQuality?, echoCancelled: Bool,
        in directory: URL = Recording.directory
    ) throws {
        let kept = quality == .low ? nil : quality
        var created: [Recording] = []
        func record(_ channel: Channel, at rate: Double = 16_000) throws -> Recording {
            let recording = try Recording(channel, rate: rate, in: directory)
            created.append(recording)
            return recording
        }
        do {
            try self.init(
                system: record(.system),
                microphone: microphone ? record(.microphone) : nil,
                keptSystem: kept.map { try record(.system, at: $0.sampleRate) },
                keptMicrophone: microphone && !echoCancelled
                    ? kept.map { try record(.microphone, at: $0.sampleRate) } : nil,
                quality: quality ?? .low)
        } catch {
            // Those made before the failure would otherwise wait for the next launch.
            created.forEach { $0.discard() }
            throw error
        }
    }

    init(
        system: Recording, microphone: Recording?, keptSystem: Recording?,
        keptMicrophone: Recording?, quality: AudioQuality
    ) {
        self.system = system
        self.microphone = microphone
        self.keptSystem = keptSystem
        self.keptMicrophone = keptMicrophone
        self.quality = quality
    }

    private var all: [Recording] {
        [system, microphone, keptSystem, keptMicrophone].compactMap(\.self)
    }

    public func finish() {
        all.forEach { $0.finish() }
    }

    /// Encodes the kept audio into `destination`. Each channel comes from its higher-rate
    /// recording, or from the engine's when that one stopped early. Returns the failed write when
    /// even the recording used stopped early, so only part of the session was kept. Blocking:
    /// call it off the main actor.
    public func keep(to destination: URL) throws -> NSError? {
        finish()
        let system = Self.complete(keptSystem, else: self.system)
        let microphone = self.microphone.map { Self.complete(keptMicrophone, else: $0) }
        try TranscriptAudio.encode(
            microphone: microphone.map(TranscriptAudio.Source.init),
            system: TranscriptAudio.Source(system), quality: quality, to: destination)
        return system.failure ?? microphone?.failure
    }

    private static func complete(_ preferred: Recording?, else fallback: Recording) -> Recording {
        if let preferred, preferred.failure == nil { preferred } else { fallback }
    }

    /// Everything but the engine's system recording, which naming plays from.
    public func discardAllButSystem() {
        [microphone, keptSystem, keptMicrophone].forEach { $0?.discard() }
    }

    public func discard() {
        all.forEach { $0.discard() }
    }
}
