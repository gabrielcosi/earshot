@preconcurrency import AVFoundation
import EarshotKit

/// Whether Earshot may hear what the Mac plays. There is no public API to ask: a process tap that
/// is not allowed delivers exact zeros with no error anywhere. So this plays a sound through the
/// same tap every session uses, the global one that includes Earshot itself, and reports what the
/// tap heard. Anything but zeros means it may listen (`PCM.isSilent`).
///
/// macOS asks for the permission when such a tap first starts. What was granted meanwhile reaches
/// only a tap built afterwards, so a check that raised the prompt must run again.
public enum SystemAudioCheck {
    /// The system's own alert sound, 1.65 s long: its first samples reach the tap long before it
    /// ends, so playing it is the whole listening window.
    static let ding = URL(filePath: "/System/Library/Sounds/Glass.aiff")

    /// Starting the tap's device returns once it runs, and its buffers follow every ~10 ms. This
    /// only bounds a device that never delivers one.
    private static let firstBufferTimeout = Duration.seconds(2)

    /// What the tap delivered, from its first buffer until the ding was heard or had played to
    /// the end. The ding starts once the tap delivers, so the tap's start never cuts it.
    @concurrent
    public static func listen() async throws -> Data {
        let player = try AVAudioPlayer(contentsOf: ding)
        player.prepareToPlay()
        let (buffers, delivery) = AsyncStream.makeStream(of: Data.self)
        let capture = SystemAudioCapture()
        try capture.start { delivery.yield($0) }
        defer {
            capture.stop()
            player.stop()
        }
        return await collect(buffers, delivery, firstBufferTimeout: firstBufferTimeout) {
            player.play()
            return .seconds(player.duration)
        }
    }

    /// The tap's buffers from the first until one is not silent, or until the sound `play`
    /// starts at the first buffer has lasted as long as `play` says. `delivery` finishes
    /// `buffers`; nothing arriving within `firstBufferTimeout` finishes them too.
    static func collect(
        _ buffers: AsyncStream<Data>, _ delivery: AsyncStream<Data>.Continuation,
        firstBufferTimeout: Duration, play: () -> Duration
    ) async -> Data {
        // Cancelled once the first buffer arrives, and then it must not finish anything: a
        // cancelled sleep returns at once.
        let startTimeout = Task {
            guard (try? await Task.sleep(for: firstBufferTimeout)) != nil else { return }
            delivery.finish()
        }
        var heard = Data()
        var playing: Task<Void, Never>?
        defer { playing?.cancel() }
        for await pcm in buffers {
            heard.append(pcm)
            if playing == nil {
                startTimeout.cancel()
                let length = play()
                playing = Task {
                    try? await Task.sleep(for: length)
                    delivery.finish()
                }
            } else if !PCM.isSilent(pcm) {
                break
            }
        }
        return heard
    }
}
