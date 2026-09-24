import Foundation

public enum PCM {
    /// 16 kHz mono PCM16, the format every stream to the engine uses.
    static let bytesPerSecond = 32_000

    /// Converts mono float samples in [-1, 1] to little-endian signed 16-bit PCM, clipping overs.
    public static func int16LittleEndian(_ samples: UnsafeBufferPointer<Float>) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for (index, sample) in samples.enumerated() {
                let clipped = min(max(sample, -1), 1)
                out[index] = Int16(clipped * Float(Int16.max)).littleEndian
            }
        }
        return data
    }
}

/// Coalesces capture buffers into fixed-size messages for the engine.
public struct PCMChunker: Sendable {
    /// 100 ms of 16 kHz PCM16. The engine pays a fixed cost per message: fed the process tap's
    /// ~10 ms buffers it keeps up at only 0.4x real time and drops the connection after ~25 s.
    public static let engineChunkBytes = 3200

    private let chunkBytes: Int
    private var pending = Data()

    public init(chunkBytes: Int = engineChunkBytes) {
        self.chunkBytes = chunkBytes
    }

    /// Returns every full chunk now available; the remainder waits for more audio or `flush()`.
    public mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var chunks: [Data] = []
        while pending.count >= chunkBytes {
            chunks.append(Data(pending.prefix(chunkBytes)))
            pending.removeFirst(chunkBytes)
        }
        return chunks
    }

    public mutating func flush() -> Data? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return pending
    }
}

/// The last few seconds of a stream's audio, addressed by stream time.
struct AudioHistory: Sendable {
    private let capacity: Int
    private var buffer = Data()
    /// Stream offset, in bytes, of `buffer`'s first byte.
    private var origin = 0

    init(seconds: Int) {
        capacity = seconds * PCM.bytesPerSecond
    }

    mutating func append(_ pcm: Data) {
        buffer.append(pcm)
        let excess = buffer.count - capacity
        if excess > 0 {
            let drop = excess - excess % 2
            buffer.removeFirst(drop)
            origin += drop
        }
    }

    /// PCM16 between two stream times in seconds, or nil when the span is no longer held.
    func pcm(from start: Double, to end: Double) -> Data? {
        let first = Int(start * 16_000) * 2
        let last = min(Int(end * 16_000) * 2, origin + buffer.count)
        guard first >= origin, last > first else { return nil }
        let base = buffer.startIndex
        return Data(buffer[(base + first - origin)..<(base + last - origin)])
    }
}

extension PCM {
    /// The 16 kHz mono PCM16 between two times in seconds, on sample boundaries.
    public static func slice(_ pcm: Data, from start: Double, to end: Double) -> Data {
        let first = min(max(0, Int(start * 16_000) * 2), pcm.count)
        let last = min(max(first, Int(end * 16_000) * 2), pcm.count)
        return Data(pcm[(pcm.startIndex + first)..<(pcm.startIndex + last)])
    }

    /// A WAV file around 16 kHz mono PCM16, for the engine's HTTP transcription endpoint.
    public static func wav(_ pcm: Data) -> Data {
        var header = Data()
        func append<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(16_000))
        append(UInt32(32_000))
        append(UInt16(2))
        append(UInt16(16))
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        return header + pcm
    }
}
