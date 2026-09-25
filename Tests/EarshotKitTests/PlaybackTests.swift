import Foundation
import Testing

@testable import EarshotKit

@Suite struct PlaybackTests {
    private let starts = [2.0, 10.0, 25.0]

    @Test func aClickOnTheWaveformSeeksInProportion() {
        #expect(Playback.time(atFraction: 0.5, of: 120) == 60)
        #expect(Playback.time(atFraction: -0.2, of: 120) == 0)
        #expect(Playback.time(atFraction: 1.4, of: 120) == 120)
        #expect(Playback.fraction(of: 30, in: 120) == 0.25)
        #expect(Playback.fraction(of: 30, in: 0) == 0)
    }

    /// The line being played is the last one to start at or before the playhead.
    @Test func theLineBeingPlayedIsTheOneThePlayheadIsIn() {
        #expect(Playback.line(at: 0, starts: starts) == nil)
        #expect(Playback.line(at: 2, starts: starts) == 0)
        #expect(Playback.line(at: 9.9, starts: starts) == 0)
        #expect(Playback.line(at: 10, starts: starts) == 1)
        #expect(Playback.line(at: 400, starts: starts) == 2)
    }

    /// Playback is next looked at where the next line starts, or where the audio ends.
    @Test func theNextChangeIsTheNextLineOrTheEnd() {
        #expect(Playback.nextChange(after: 0, starts: starts, duration: 30) == 2)
        #expect(Playback.nextChange(after: 10, starts: starts, duration: 30) == 25)
        #expect(Playback.nextChange(after: 26, starts: starts, duration: 30) == 30)
    }

    /// VoiceOver's adjustable action steps a line at a time.
    @Test func steppingForwardGoesToTheNextLineOrTheEnd() {
        #expect(Playback.step(from: 12, forward: true, starts: starts, duration: 30) == 25)
        #expect(Playback.step(from: 25, forward: true, starts: starts, duration: 30) == 30)
    }

    /// As a player's Previous: well into a line it goes back to that line's start, just after
    /// one starts it goes to the line before, so stepping back while playing gets past the line.
    @Test func steppingBackRestartsTheLineOrGoesToTheOneBefore() {
        #expect(Playback.step(from: 14, forward: false, starts: starts, duration: 30) == 10)
        #expect(Playback.step(from: 12, forward: false, starts: starts, duration: 30) == 2)
        #expect(Playback.step(from: 10, forward: false, starts: starts, duration: 30) == 2)
        #expect(Playback.step(from: 3, forward: false, starts: starts, duration: 30) == 0)
        #expect(Playback.step(from: 1, forward: false, starts: starts, duration: 30) == 0)
    }

    /// Both sides share the total's width, so the label does not jump when it passes an hour.
    @Test func theTimeReadsAsElapsedOverTotal() {
        #expect(Playback.clock(5.9, of: 1934) == "00:05 / 32:14")
        #expect(Playback.clock(5, of: 3723) == "0:00:05 / 1:02:03")
        #expect(Playback.clock(4000, of: 3723) == "1:02:03 / 1:02:03")
    }

    @Test func voiceOverHearsDurationsNotClockTimes() {
        let english = Locale(identifier: "en_US")
        #expect(
            Playback.spoken(65, of: 1934, locale: english)
                == "1 minute, 5 seconds of 32 minutes, 14 seconds")
    }
}
