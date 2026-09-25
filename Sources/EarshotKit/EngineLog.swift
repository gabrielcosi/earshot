import Foundation

/// The engine's log, kept across launches: the engine is launched again whenever the menu opens,
/// so a log started fresh each time would lose the output of the launch that crashed.
public enum EngineLog {
    /// A launch writes about 120 bytes to stdout (the `listener.ready` line) and a few lines of
    /// model loading to stderr, so 1 MiB holds thousands of launches.
    static let limit = 1 << 20

    /// Opens `url` for appending, first moving a log over `limit` to `<name>.previous.log`, and
    /// writes a line marking this launch.
    public static func open(_ url: URL) throws -> FileHandle {
        let files = FileManager.default
        let path = url.path(percentEncoded: false)
        let size = (try? files.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        if size > limit {
            let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
            try? files.removeItem(at: previous)
            try files.moveItem(at: url, to: previous)
        }
        if !files.fileExists(atPath: path) {
            try files.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            files.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("--- launch \(Date.now.ISO8601Format()) ---\n".utf8))
        return handle
    }
}
