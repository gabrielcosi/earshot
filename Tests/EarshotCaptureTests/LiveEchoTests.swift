import EarshotKit
import Foundation
import Testing

/// The canceller in front of the engine (`mise run serve`): what the speakers played, heard back
/// through the microphone, must come out as nothing to transcribe.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_LIVE"] == "1"))
struct LiveEchoTests {
    private static let engine = EngineEndpoint(
        url: URL(string: "http://127.0.0.1:8765/") ?? URL(filePath: "/"),
        apiKey: ProcessInfo.processInfo.environment["EARSHOT_API_KEY"])

    @Test func theEngineTranscribesNothingFromCancelledEcho() async throws {
        let far = try Signal.fixture("two-speakers")
        // The room's bleed measured 20 dB under the speakers' level.
        let microphone = Signal.echo(of: far, delay: Signal.echoDelay, gain: 0.1)
        let cleaned = Signal.pcm(try Signal.cancel(far: far, microphone: microphone))
        let before = try await Retranscriber.transcribe(
            pcm: Signal.pcm(microphone), engine: Self.engine, allowed: ["en-US"]
        ).map(\.word).joined(separator: " ")
        let after = try await Retranscriber.transcribe(
            pcm: cleaned, engine: Self.engine, allowed: ["en-US"]
        ).map(\.word).joined(separator: " ")
        print("echo: \"\(before)\"\ncancelled: \"\(after)\"")
        #expect(before.contains("storage product"), "the uncancelled echo must be transcribable")
        #expect(after.isEmpty, "the engine still heard \"\(after)\"")
    }
}
