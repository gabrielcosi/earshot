import Foundation
import Testing

@testable import EarshotKit

@Suite struct RealtimeClientTests {
    /// Losing the socket must read differently from an error the engine reports on a live stream:
    /// only the first ends the session.
    @Test(.timeLimit(.minutes(1))) func aSocketThatCannotConnectEndsAsDisconnected() async throws {
        // Port 1 (tcpmux) is never served on a Mac, so the connection is refused.
        let client = RealtimeClient(
            engine: EngineEndpoint(url: try #require(URL(string: "http://127.0.0.1:1/"))),
            settings: SessionSettings(speakerDiarization: false))
        var events: [ServerEvent] = []
        for await event in client.events { events.append(event) }
        #expect(events.count == 1)
        guard case .disconnected = events.first else {
            Issue.record("expected a disconnect, got \(events)")
            return
        }
    }
}
