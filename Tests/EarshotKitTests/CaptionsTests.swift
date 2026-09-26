import Foundation
import Testing

@testable import EarshotKit

@Suite struct CaptionsTests {
    private static let english = Locale(identifier: "en")

    /// The overlay shows the tail of what the window shows: the same speakers, colours, rules, and
    /// translations, even once the first speakers have scrolled off.
    @Test func theLatestLinesAreTheWindowsLastLines() {
        var transcript = Transcript()
        for (index, slot) in [2, 1, 3, 1].enumerated() {
            transcript.applyFinal(
                transcript: "",
                words: [
                    Word(
                        word: "uh line\(index)", start: Double(index),
                        end: Double(index) + 0.5, speaker: slot)
                ], on: .system)
        }
        transcript.applyFinal(
            transcript: "Hi", words: [Word(word: "Hi", start: 5, end: 5.2)], on: .microphone)
        let last = transcript.utterances[transcript.utterances.count - 1]
        transcript.setTranslation(Translation(sourceText: last.text, text: "Hallo"), for: last.id)
        let names: [Speaker: String] = [.remote(slot: 3): "Ada"]
        let rules = WordRules()
        let all = TranscriptLine.lines(in: transcript, names: names, rules: rules)

        for count in 1...3 {
            let latest = TranscriptLine.latest(count, in: transcript, names: names, rules: rules)
            #expect(latest == Array(all.suffix(count)))
        }
        let latest = TranscriptLine.latest(3, in: transcript, names: names, rules: rules)
        #expect(latest.map(\.voice) == [.other(2), .other(1), .me])
        #expect(latest.map(\.speaker) == ["Ada", "Speaker 1", "Me"])
        #expect(latest.map(\.text) == ["line2", "line3", "Hi"])
        #expect(latest.last?.translation == "Hallo")
    }

    @Test func askingForMoreLinesThanThereAreGivesThemAll() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hi", words: [Word(word: "Hi", start: 0, end: 0.2)], on: .microphone)
        #expect(TranscriptLine.latest(3, in: transcript).map(\.text) == ["Hi"])
        #expect(TranscriptLine.latest(3, in: Transcript()).isEmpty)
    }

    private func title(_ spoken: [String], translating: Bool = true) -> String? {
        CaptionsTitle.text(
            spoken: spoken, target: "en", translating: translating, locale: Self.english)
    }

    /// Regional variants are one language; the target language is never translated from.
    @Test func oneLanguageToTranslateFromNamesThePair() {
        for spoken in [["de-DE"], ["de-DE", "de-AT"], ["de-DE", "en-US"]] {
            #expect(title(spoken) == "German → English")
        }
    }

    @Test func severalOrAnySpokenLanguagesNameOnlyTheTarget() {
        for spoken in [["de-DE", "fr-FR"], ["de-DE", "fr-FR", "en-US"], []] {
            #expect(title(spoken) == "Translating into English")
        }
    }

    /// Nothing is translated then: the overlay says "Earshot" and offers no translation.
    @Test func noTranslationOrOnlyTheTargetLanguageTranslatesNothing() {
        #expect(title(["de-DE"], translating: false) == nil)
        #expect(title(["en-GB"]) == nil)
        #expect(title(["en-GB", "en-US"]) == nil)
    }

    /// The translator's outcome is recorded for each finished line: translated, or settled as not
    /// needed, unavailable, or failed.
    @Test func aFinishedLineWaitsUntilItsTranslationIsSettled() {
        #expect(TranslationWait.pending(translation: nil, settled: false))
        #expect(!TranslationWait.pending(translation: nil, settled: true))
        #expect(!TranslationWait.pending(translation: "Then search.", settled: false))
    }

    /// Words still being recognized are the original until a live translation comes, even the
    /// first ones, too few to tell the language; words in the target language, or in a language
    /// that cannot be translated, show as they are.
    @Test func liveWordsWaitUnlessTheyWillNotBeTranslated() {
        let german = "Dann nehmen wir zuerst die Suche und danach den Export."
        #expect(TranslationWait.pending(live: german, translation: nil, into: "en"))
        #expect(TranslationWait.pending(live: "Den", translation: nil, into: "en"))
        #expect(!TranslationWait.pending(live: "Den", translation: "The", into: "en"))
        #expect(
            !TranslationWait.pending(
                live: "and send it round tomorrow morning", translation: nil, into: "en-US"))
        #expect(
            !TranslationWait.pending(
                live: german, translation: nil, into: "en", unavailable: ["de"]))
    }

    /// The sizes are the transcript's own steps, Dynamic Type body sizes, each larger than the
    /// one before.
    @Test func textSizesAreIncreasingTranscriptSteps() {
        let points = CaptionTextSize.allCases.map(\.points)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0 < $1 })
        for size in points {
            #expect(TranscriptTextSize.steps.contains(size))
        }
    }

    /// The main screen's visible frame starts above the Dock.
    private static let main = CGRect(x: 0, y: 70, width: 1512, height: 874)
    private static let second = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
    private static let size = CGSize(width: 620, height: 200)

    @Test func aSavedFrameOnAScreenIsKept() {
        let onSecond = CGRect(x: 2000, y: 300, width: 620, height: 200)
        let straddling = CGRect(x: 1300, y: 300, width: 620, height: 200)
        for saved in [onSecond, straddling] {
            #expect(
                CaptionsPlacement.frame(
                    saved: saved, screens: [Self.main, Self.second], size: Self.size) == saved)
        }
    }

    /// A frame saved on a display that is gone would open where nobody can see or reach it.
    @Test func aFrameOffEveryScreenOpensAtTheBottomCentreOfTheMainScreen() {
        let offScreen = CGRect(x: 2000, y: 300, width: 620, height: 200)
        let expected = CGRect(x: 446, y: 270, width: 620, height: 200)
        #expect(
            CaptionsPlacement.frame(saved: offScreen, screens: [Self.main], size: Self.size)
                == expected)
        #expect(
            CaptionsPlacement.frame(saved: nil, screens: [Self.main, Self.second], size: Self.size)
                == expected)
    }
}
