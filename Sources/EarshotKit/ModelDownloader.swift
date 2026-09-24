import CryptoKit
import Foundation
import os

/// Downloads one model file, verifies its SHA-256, and moves it into place atomically, so a
/// file at the destination is always complete.
public enum ModelDownloader {
    public enum Failure: LocalizedError {
        case http(Int)
        case checksum(expected: String, actual: String)

        public var errorDescription: String? {
            switch self {
            case .http(let status): "The download failed with HTTP \(status)."
            case .checksum: "The downloaded file is corrupt (checksum mismatch)."
            }
        }
    }

    /// Hashing reads the file in pieces this large, so a 700 MB model never sits in memory.
    private static let hashChunkBytes = 8 * 1024 * 1024

    public static func download(
        from source: URL,
        to destination: URL,
        sha256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = ProgressDelegate(report: progress)
        let (temporary, response) = try await URLSession.shared.download(
            from: source, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.http(http.statusCode)
        }
        let actual = try await digest(of: temporary)
        guard actual == sha256 else { throw Failure.checksum(expected: sha256, actual: actual) }

        let manager = FileManager.default
        try manager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }

    @concurrent
    private static func digest(of file: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkBytes), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The async `download(from:delegate:)` never calls a task delegate's `didWriteData`, so
    /// progress comes from observing the task's own `Progress`, handed over in `didCreateTask`.
    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        let report: @Sendable (Double) -> Void
        private let observation = OSAllocatedUnfairLock<NSKeyValueObservation?>(initialState: nil)

        init(report: @escaping @Sendable (Double) -> Void) {
            self.report = report
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            let report = report
            let observer = task.progress.observe(\.fractionCompleted) { progress, _ in
                report(progress.fractionCompleted)
            }
            observation.withLock { $0 = observer }
        }
    }
}
