import Foundation
import Testing

@testable import EarshotKit

@Suite struct EngineLogTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An engine that crashed is followed by a new launch, often from just opening the menu; the
    /// crash must still be in the log afterwards.
    @Test func aNewLaunchKeepsWhatEarlierLaunchesWrote() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appending(path: "engine.log")
        try EngineLog.open(log).write(Data("first launch crashed\n".utf8))
        try EngineLog.open(log).write(Data("second launch\n".utf8))
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("first launch crashed"))
        #expect(text.contains("second launch"))
        #expect(text.components(separatedBy: "--- launch ").count - 1 == 2)
    }

    @Test func aFullLogMovesAsideAndANewOneStarts() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appending(path: "engine.log")
        try Data(repeating: 0x61, count: EngineLog.limit + 1).write(to: log)
        try EngineLog.open(log).write(Data("fresh\n".utf8))
        let previous = log.deletingPathExtension().appendingPathExtension("previous.log")
        #expect(try Data(contentsOf: previous).count == EngineLog.limit + 1)
        #expect(try String(contentsOf: log, encoding: .utf8).hasSuffix("fresh\n"))
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2 && lines[0].hasPrefix("--- launch "))
    }
}
