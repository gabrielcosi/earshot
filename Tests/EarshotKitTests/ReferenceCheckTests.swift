import Foundation
import Testing

@testable import EarshotKit

/// A second pass checked against the words it replaces. Synthetic lines only.
@Suite struct ReferenceCheckTests {
    private func words(_ text: String) -> [Word] {
        text.split(separator: " ").map { Word(word: String($0), start: 0, end: 0) }
    }

    private func text(_ words: [Word]) -> String { words.map(\.word).joined(separator: " ") }

    /// What a refinement keeps: the result, unless the check against the reference settles on
    /// another candidate or on the reference itself.
    private func kept(
        _ result: String, reference: String, allowed: [String] = ["en-US", "en-GB", "de-DE"],
        candidates: [(String, String)] = []
    ) -> String {
        let result = words(result)
        let reference = words(reference)
        guard
            let challenge = LanguagePolicy.challenge(
                result, reference: reference, allowed: allowed)
        else { return text(result) }
        return text(
            LanguagePolicy.settle(
                challenge, result: result, reference: reference,
                candidates: [(Languages.auto, result)] + candidates.map { ($0.0, words($0.1)) }))
    }

    private let germanResult = "Das war es echt peinlich in front of the customer."
    private let englishReference = "that was echt peinlich in front of the customer"

    @Test func aResultInAnotherLanguageGivesWayToTheRedoInTheReferencesLanguage() {
        #expect(
            kept(
                germanResult, reference: englishReference,
                candidates: [("en-US", "That was echt peinlich in front of the customer.")])
                == "That was echt peinlich in front of the customer.")
    }

    /// The redo reads as English and keeps both languages, but strays further from the reference.
    @Test func aRedoFartherFromTheReferenceLeavesTheResult() {
        #expect(
            kept(
                germanResult, reference: englishReference,
                candidates: [
                    ("en-US", "This was echt peinlich in front of all of our customers today.")
                ])
                == germanResult)
    }

    /// The live stream, still on English, wrote a German reply as English-sounding words; the
    /// fresh decode heard it right, and forced into English it stays German: closer to the live
    /// words, but not English.
    @Test func aGermanCorrectionOfALineWrittenAsEnglishStands() {
        #expect(
            kept(
                "Schick mir bitte den Link.", reference: "Shick me a bit in link.",
                candidates: [("en-US", "Shick mir bitte den Link.")])
                == "Schick mir bitte den Link.")
    }

    @Test func aResultThatDropsTheReferencesOtherLanguageGivesWayToOneThatKeepsBoth() {
        #expect(
            kept(
                "Aber es ist noch zu langsam.",
                reference: "we tried the new tool, aber es ist noch zu langsam",
                candidates: [
                    ("en-US", "We tried the new tool, but it is still too slow."),
                    ("de-DE", "We tried the new tool, aber es ist noch zu langsam."),
                ]) == "We tried the new tool, aber es ist noch zu langsam.")
    }

    @Test func ofTheCandidatesKeepingBothLanguagesTheClosestToTheReferenceIsKept() {
        #expect(
            kept(
                "Der Vertrag ist unterschrieben.",
                reference: "Der Vertrag ist unterschrieben, so we can finally start",
                candidates: [
                    ("en-GB", "The contract ist unterschrieben, so we can start it all again."),
                    ("de-DE", "Der Vertrag ist unterschrieben."),
                    ("en-US", "The contract ist unterschrieben, so we can finally start."),
                ]) == "The contract ist unterschrieben, so we can finally start.")
    }

    @Test func withNoCandidateKeepingBothLanguagesTheReferenceStays() {
        #expect(
            kept(
                "Der Vertrag ist unterschrieben.",
                reference: "Der Vertrag ist unterschrieben, so we can finally start",
                candidates: [("en-US", "The contract is signed, so we can finally start.")])
                == "Der Vertrag ist unterschrieben, so we can finally start")
    }

    @Test func theCheckWorksForAnyPairOfSpokenLanguages() {
        #expect(
            kept(
                "Mais pas avant dix heures.",
                reference: "we can meet tomorrow morning, mais pas avant dix heures",
                allowed: ["en-US", "fr-FR"],
                candidates: [("fr-FR", "We can meet tomorrow morning, mais pas avant dix heures.")])
                == "We can meet tomorrow morning, mais pas avant dix heures.")
    }

    @Test func aLineTooShortOnEitherSideIsNotChecked() {
        let allowed = ["en-US", "de-DE"]
        #expect(
            LanguagePolicy.challenge(
                words(germanResult), reference: words(englishReference), allowed: allowed) != nil)
        #expect(
            LanguagePolicy.challenge(
                words("Das war."), reference: words(englishReference), allowed: allowed) == nil)
        #expect(
            LanguagePolicy.challenge(
                words(germanResult), reference: words("that was"), allowed: allowed) == nil)
    }

    /// Without spaces between words, counting words or edits means nothing.
    @Test func aSessionSpeakingAJapaneseIsNotChecked() {
        #expect(
            LanguagePolicy.challenge(
                words(germanResult), reference: words(englishReference),
                allowed: ["en-US", "de-DE", "ja-JP"]) == nil)
    }

    @Test func aResultInTheReferencesLanguageIsNotChallenged() {
        #expect(
            LanguagePolicy.challenge(
                words("We booked the meeting room for the whole afternoon."),
                reference: words("we booked the meeting room for the whole afternoon"),
                allowed: ["en-US", "de-DE"]) == nil)
    }
}

@Suite struct ReferenceRedoTests {
    private actor Requests {
        var languages: [String] = []
        func add(_ language: String) { languages.append(language) }
    }

    private struct Unreachable: Error {}

    private func words(_ text: String, from start: Double = 0) -> [Word] {
        text.split(separator: " ").enumerated().map {
            Word(
                word: String($1), start: start + Double($0) * 0.4,
                end: start + Double($0) * 0.4 + 0.3)
        }
    }

    private func text(_ words: [Word]) -> String { words.map(\.word).joined(separator: " ") }

    @Test func aChallengedResultIsRedoneOnceInTheReferencesLanguage() async throws {
        let requests = Requests()
        let refined = try await Retranscriber.transcribe(
            allowed: ["en-US", "de-DE"],
            reference: words("that was echt peinlich in front of the customer")
        ) { language in
            await requests.add(language)
            return language == Languages.auto
                ? (words("Das war es echt peinlich in front of the customer."), "de-DE")
                : (words("That was echt peinlich in front of the customer."), language)
        }
        #expect(text(refined.words) == "That was echt peinlich in front of the customer.")
        #expect(await requests.languages == [Languages.auto, "en-US"])
    }

    @Test func theRedoIsMadeInTheFirstSpokenLanguageOfTheReferences() async throws {
        let requests = Requests()
        _ = try await Retranscriber.transcribe(
            allowed: ["de-DE", "en-GB", "en-US"],
            reference: words("we can ship this on monday if everything works")
        ) { language in
            await requests.add(language)
            return (words("Wir können das am Montag liefern, wenn alles klappt."), "de-DE")
        }
        #expect(await requests.languages == [Languages.auto, "en-GB"])
    }

    @Test func anAcceptedResultThatIsNotChallengedTakesOneRequest() async throws {
        let requests = Requests()
        let refined = try await Retranscriber.transcribe(
            allowed: ["en-US", "de-DE"],
            reference: words("we booked the meeting room for the whole afternoon")
        ) { language in
            await requests.add(language)
            return (words("We booked the meeting room for the whole afternoon."), "en-US")
        }
        #expect(text(refined.words) == "We booked the meeting room for the whole afternoon.")
        #expect(await requests.languages == [Languages.auto])
    }

    /// `auto` strayed, so every spoken language was decoded already: the check asks for none.
    @Test func aChallengeAfterARedoInEveryLanguageAsksForNoMore() async throws {
        let requests = Requests()
        _ = try await Retranscriber.transcribe(
            allowed: ["en-US", "de-DE"],
            reference: words("that was echt peinlich in front of the customer")
        ) { language in
            await requests.add(language)
            return (words("Das war es echt peinlich in front of the customer."), Languages.auto)
        }
        #expect(await requests.languages.count == 3)
    }

    @Test func aLineHeardInAnUnchosenLanguageIsNotChecked() async throws {
        let refined = try await Retranscriber.transcribe(
            allowed: ["en-US", "de-DE"],
            reference: words("we have prepared a short presentation aber es ist noch nicht fertig")
        ) { language in
            language == Languages.auto
                ? (words("Nous avons préparé une courte présentation sur le projet."), "fr-FR")
                : ([], language)
        }
        #expect(refined.heard == "fr-FR")
        #expect(
            text(refined.words) == "Nous avons préparé une courte présentation sur le projet.")
    }

    /// At the end of a session one failed redo must not cost every turn its relabelling.
    @Test func aFailedRedoLeavesTheCheckToTheCandidatesAtHand() async throws {
        let refined = try await Retranscriber.transcribe(
            allowed: ["en-US", "de-DE"],
            reference: words("that was echt peinlich in front of the customer")
        ) { language in
            guard language == Languages.auto else { throw Unreachable() }
            return (words("Das war es echt peinlich in front of the customer."), "de-DE")
        }
        #expect(text(refined.words) == "Das war es echt peinlich in front of the customer.")
    }

    /// No decode keeps the English the turn ends in, so the transcript's words stay, under the
    /// turn's speaker and at their own times, rather than leaving the turn empty.
    @Test func aTurnThatKeepsItsReferenceKeepsItUnderItsSpeaker() async throws {
        let turn = SpeakerTurn(start: 10, end: 14, speaker: 2)
        let reference = words("Der Vertrag ist unterschrieben, so we can finally start", from: 10.4)
        let transcribed = try await Retranscriber.transcribe(
            turns: [turn], references: [reference], allowed: ["en-US", "de-DE"]
        ) { _, language in
            (
                words("Der Vertrag ist unterschrieben."),
                language == Languages.auto ? "de-DE" : language
            )
        }
        #expect(transcribed.first?.words.map(\.word) == reference.map(\.word))
        #expect(transcribed.first?.words.map(\.start) == reference.map(\.start))
        #expect(transcribed.first?.words.allSatisfy { $0.speaker == 2 } == true)
    }
}

@Suite struct TurnReferenceTests {
    private func word(_ text: String, _ start: Double) -> Word {
        Word(word: text, start: start, end: start + 0.3)
    }

    /// Live words trail the speech, so a turn's last word is emitted after the next turn began;
    /// kept as the next turn's reference, it would show up twice, and the other turn's last word
    /// not at all.
    @Test func eachTurnEndsWithItsOwnLastWord() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "",
            words: [
                word("see", 13.2), word("you", 13.5), word("friday", 14.15), word("so", 14.5),
                word("we", 16.8), word("start", 18.1), word("okay", 18.6), word("then", 19),
            ], on: .system)
        let references = transcript.remoteWords(in: [
            SpeakerTurn(start: 10, end: 14, speaker: 1),
            SpeakerTurn(start: 14.1, end: 18, speaker: 2),
            SpeakerTurn(start: 18.05, end: 21, speaker: 1),
        ])
        #expect(
            references.map { $0.map(\.word) } == [
                ["see", "you", "friday"], ["so", "we", "start"], ["okay", "then"],
            ])
    }

    @Test func wordsBetweenTurnsGoToTheNearestWithinTheLagAndMicrophoneWordsToNone() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "", words: [word("one", 0.2), word("two", 2.75), word("far", 6.5)],
            on: .system)
        transcript.applyFinal(transcript: "", words: [word("mine", 3.5)], on: .microphone)
        let references = transcript.remoteWords(in: [
            SpeakerTurn(start: 0, end: 1, speaker: 1), SpeakerTurn(start: 3, end: 4, speaker: 2),
        ])
        #expect(references.map { $0.map(\.word) } == [["one"], ["two"]])
    }

    /// The turn's last word trails it by 0.6 s: placed back into the turn, it is no longer one
    /// the turn missed, so a turn kept as its reference does not also leave it on its own.
    @Test func aTrailingWordKeptInATurnsReferenceIsNotLeftOver() async throws {
        let live =
            "Der Vertrag ist unterschrieben, so we can finally".split(separator: " ")
            .enumerated().map { word(String($1), 10.4 + Double($0) * 0.4) }
            + [Word(word: "start", start: 14.45, end: 14.75)]
        var transcript = Transcript()
        transcript.applyFinal(transcript: "", words: live, on: .system)
        let turns = [SpeakerTurn(start: 10, end: 14, speaker: 2)]
        let transcribed = try await Retranscriber.transcribe(
            turns: turns, references: transcript.remoteWords(in: turns),
            allowed: ["en-US", "de-DE"]
        ) { _, language in
            (
                [
                    Word(word: "Der", start: 0.4, end: 0.7),
                    Word(word: "Vertrag", start: 0.8, end: 1.1),
                ]
                    + ["ist", "unterschrieben."].enumerated().map {
                        Word(word: $1, start: 1.2 + Double($0) * 0.4, end: 1.5 + Double($0) * 0.4)
                    },
                language == Languages.auto ? "de-DE" : language
            )
        }
        transcript.relabel(transcribed)
        let words = transcript.utterances.flatMap { $0.text.split(separator: " ") }
        #expect(
            words.filter { $0 == "start" }.count == 1, "\(transcript.utterances.map(\.speaker))")
    }
}
