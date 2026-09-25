import EarshotKit
import Foundation
import os

/// One capture's audio for the length of a session, exactly as sent to the engine, so its times
/// match the transcript's. Kept in the container's caches and deleted after the session, unless
/// "Keep audio" encodes it into the store's audio folder first.
nonisolated final class Recording: Sendable {
    let url: URL
    private let handle: OSAllocatedUnfairLock<FileHandle?>

    private static let directory = URL.cachesDirectory.appending(path: "Earshot")

    /// Recordings left by a crash or a forced quit, which skip the normal clean-up.
    static func removeLeftovers() {
        try? FileManager.default.removeItem(at: directory)
    }

    init(_ channel: Channel) throws {
        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "\(channel.rawValue)-\(UUID().uuidString).pcm")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        handle = OSAllocatedUnfairLock(uncheckedState: try FileHandle(forWritingTo: url))
    }

    func append(_ pcm: Data) {
        handle.withLockUnchecked { try? $0?.write(contentsOf: pcm) }
    }

    func finish() {
        handle.withLockUnchecked { handle in
            try? handle?.close()
            handle = nil
        }
    }

    /// A WAV clip of the recording, for hearing who a speaker is.
    func clip(from start: Double, seconds: Double) -> Data? {
        guard let reader = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? reader.close() }
        let bytesPerSecond = 32_000
        try? reader.seek(toOffset: UInt64(max(0, start) * Double(bytesPerSecond)) & ~1)
        guard let pcm = try? reader.read(upToCount: Int(seconds * Double(bytesPerSecond)) & ~1),
            !pcm.isEmpty
        else { return nil }
        return PCM.wav(pcm)
    }

    func discard() {
        finish()
        try? FileManager.default.removeItem(at: url)
    }
}
