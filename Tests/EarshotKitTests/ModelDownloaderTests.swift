import CryptoKit
import Foundation
import Testing

@testable import EarshotKit

@Suite struct ModelDownloaderTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "earshot-\(UUID().uuidString)")

    private func source(_ bytes: Int) throws -> (URL, String) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data((0..<bytes).map { UInt8($0 % 251) })
        let url = directory.appending(path: "source.gguf")
        try data.write(to: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (url, digest)
    }

    @Test func installsAVerifiedFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let (url, digest) = try source(3 * 1024 * 1024)
        let destination = directory.appending(path: "models/org/name/rev/model.gguf")
        try await ModelDownloader.download(from: url, to: destination, sha256: digest) { _ in }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: destination.path(percentEncoded: false))
        #expect((attributes[.size] as? NSNumber)?.int64Value == Int64(3 * 1024 * 1024))
    }

    @Test func reportsProgressUpToCompletion() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let (url, digest) = try source(8 * 1024 * 1024)
        let reports = Reports()
        try await ModelDownloader.download(
            from: url, to: directory.appending(path: "model.gguf"), sha256: digest
        ) { reports.add($0) }
        #expect(reports.last == 1)
    }

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func add(_ value: Double) { lock.withLock { values.append(value) } }
        var last: Double? { lock.withLock { values.last } }
    }

    @Test func rejectsAChecksumMismatchAndLeavesNothingBehind() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let (url, _) = try source(1024)
        let destination = directory.appending(path: "models/model.gguf")
        await #expect(throws: ModelDownloader.Failure.self) {
            try await ModelDownloader.download(
                from: url, to: destination, sha256: String(repeating: "0", count: 64)
            ) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }
}
