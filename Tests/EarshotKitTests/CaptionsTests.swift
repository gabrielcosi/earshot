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
        transcript.translate(into: "de")
        transcript.record(.translated("Hallo"), for: "Hi", into: "de")
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

    /// A finished line waits for its first sentence's outcome, or a carried live translation.
    @Test func aFinishedLineWaitsUntilItsTranslationStarts() {
        #expect(TranslationWait.pending(translation: nil, started: false))
        #expect(!TranslationWait.pending(translation: nil, started: true))
        #expect(!TranslationWait.pending(translation: "Then search.", started: false))
    }

    /// A line whose sentences stay as said (the pair needs a download) does not vanish while a
    /// sentence merged into it waits for its outcome: the window and the overlay keep it.
    @Test func aShownLineStaysWhileASentenceMergedIntoItWaits() throws {
        var transcript = Transcript()
        transcript.translate(into: "zh")
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Das ist erledigt.", start: 0, end: 1, speaker: 1)],
            on: .system)
        transcript.record(.unavailable, for: "Das ist erledigt.", into: "zh")
        let waits = { (transcript: Transcript) in
            let line = try #require(TranscriptLine.lines(in: transcript).first)
            return TranslationWait.pending(
                translation: line.translation, started: line.translationStarted)
        }
        #expect(try !waits(transcript))
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Nächster Punkt.", start: 2, end: 3, speaker: 1)],
            on: .system)
        #expect(try !waits(transcript))
    }

    /// A change of language translates every line again, newest first; the lines shown meanwhile
    /// stay, as they were said until their translation comes.
    @Test func aShownLineStaysThroughAChangeOfLanguage() throws {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Das ist erledigt.", start: 0, end: 1, speaker: 1)],
            on: .system)
        transcript.record(.translated("That is settled."), for: "Das ist erledigt.", into: "en")
        transcript.translate(into: "fr")
        let line = try #require(TranscriptLine.lines(in: transcript).first)
        #expect(line.translation == nil)
        #expect(!TranslationWait.pending(translation: nil, started: line.translationStarted))
    }

    /// A new turn still waits for its first sentence.
    @Test func aNewLineWaitsForItsFirstSentence() throws {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Das ist erledigt.", start: 0, end: 1, speaker: 1)],
            on: .system)
        let line = try #require(TranscriptLine.lines(in: transcript).first)
        #expect(
            TranslationWait.pending(translation: line.translation, started: line.translationStarted)
        )
    }

    /// Words still being recognized wait for a live translation; words in the target language,
    /// in a language that cannot be translated, or too few to tell the language ("Hm.", which
    /// the translator leaves as said), show as they are.
    @Test func liveWordsWaitUnlessTheyWillNotBeTranslated() {
        let german = "Dann nehmen wir zuerst die Suche und danach den Export."
        #expect(TranslationWait.pending(live: german, translation: nil, into: "en"))
        #expect(!TranslationWait.pending(live: "Hm.", translation: nil, into: "en"))
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
