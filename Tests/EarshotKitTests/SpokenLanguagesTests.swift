import Foundation
import NaturalLanguage
import Testing

@testable import EarshotKit

/// Translation reads each line as one of the spoken languages, and a line the engine heard in
/// another language is left as it was said.
@Suite struct SpokenLanguagesTests {
    private static let englishAndGerman = ["en-US", "de-DE"]

    /// Alone, "Ja." reads as Finnish, and the others as too ambiguous to tell (docs/behaviour.md,
    /// Apple Translation); among English and German they read as German.
    @Test(arguments: ["Ja.", "Mhm.", "Na ja.", "Ok, super."])
    func shortWordsReadAsASpokenLanguage(_ text: String) {
        #expect(
            LanguageDetection.dominant(text, among: Self.englishAndGerman)?.languageCode?
                .identifier == "de")
    }

    /// The recognizer drops a constraint to a language it cannot detect without a word, so
    /// French would read as German among Slovenian and German.
    @Test func aSpokenLanguageTheRecognizerCannotDetectLeavesItFree() {
        #expect(
            LanguageDetection.dominant("Je ne sais pas.", among: ["sl-SI", "de-DE"])?
                .languageCode?.identifier == "fr")
    }

    /// Every language the Spoken menu offers is constrained to the recognizer's name for it, or
    /// leaves the recognizer free when it knows no such language.
    @Test(arguments: Languages.codes)
    func everySpokenLanguageIsOneTheRecognizerKnowsOrNone(_ code: String) {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [LanguageDetection.recognizerLanguage(code)]
        recognizer.processString("abc def ghi")
        let known = !recognizer.languageHypotheses(withMaximum: 1).isEmpty
        #expect((LanguageDetection.constraint([code]) != nil) == known)
    }

    @Test func norwegianAndChineseTakeTheRecognizersNames() {
        #expect(LanguageDetection.recognizerLanguage("no-NO") == .norwegian)
        #expect(LanguageDetection.recognizerLanguage("zh-CN") == .simplifiedChinese)
        #expect(LanguageDetection.recognizerLanguage("zh-TW") == .traditionalChinese)
    }

    /// Showing translations alone, "Ja." spoken among English and German is German, and is not
    /// waited for when translating into German.
    @Test func liveWordsReadAsTheSpokenLanguages() {
        #expect(
            !TranslationWait.pending(
                live: "Ja.", translation: nil, into: "de", spoken: Self.englishAndGerman))
    }

    @Test func onlyAnUnchosenLanguageIsReportedAsHeard() {
        #expect(LanguagePolicy.unchosen("fr-FR", allowed: Self.englishAndGerman) == "fr-FR")
        #expect(LanguagePolicy.unchosen("de-AT", allowed: Self.englishAndGerman) == nil)
        #expect(LanguagePolicy.unchosen(Languages.auto, allowed: Self.englishAndGerman) == nil)
        #expect(LanguagePolicy.unchosen(nil, allowed: Self.englishAndGerman) == nil)
        #expect(LanguagePolicy.unchosen("fr-FR", allowed: []) == nil)
        #expect(LanguagePolicy.unchosen("nb-NO", allowed: ["no-NO", "en-US"]) == nil)
    }

    private func words(_ text: String) -> [Word] {
        text.split(separator: " ").map { Word(word: String($0), start: 0, end: 0) }
    }

    private func heard(_ reported: String, said: String, forced: String) -> String? {
        LanguagePolicy.heard(
            reported, allowed: Self.englishAndGerman, said: words(said),
            redo: (language: "de-DE", words: words(forced)))
    }

    /// German speech `auto` reported as Dutch: forced into German, it reads as German.
    @Test func aMisreadSpokenLanguageIsNotHeardAsAnother() {
        let german = "Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben."
        #expect(heard("nl-NL", said: german, forced: german) == nil)
    }

    /// Replies this short read low even in their own language, so the redo cannot tell.
    @Test(arguments: [("fi-FI", "Ja."), ("nl-NL", "Okay."), ("nl-NL", "Ja, ja.")])
    func aReplyTooShortToTellIsNotHeardAsAnother(_ reported: String, _ said: String) {
        #expect(heard(reported, said: said, forced: said) == nil)
    }

    /// The engine left this French clip's language as `auto`; its words tell it.
    @Test func speechWhoseLanguageTheEngineLeftOpenIsHeardByItsWords() {
        let said = "Nous avons préparé une courte présentation sur le projet"
        #expect(heard(Languages.auto, said: said, forced: "") == "fr-FR")
    }

    /// Fillers read freely as another language ("Mhm, ja, okay." as Finnish at 0.69), under how
    /// sure a sentence must be.
    @Test func fillersTheEngineLeftOpenAreNotHeardAsAnother() {
        #expect(heard(Languages.auto, said: "Mhm, ja, okay.", forced: "Mhm, ja, okay.") == nil)
    }

    /// Read freely, Norwegian is Bokmål (`nb`): not another language when it is spoken.
    @Test(arguments: [
        (
            "no-NO", "Jeg vet ikke om vi kan levere neste uke.",
            "Jeg vet ikke om vi kan levere neste uke."
        ),
        ("no-NO", "Jeg vet ikke om vi kan levere neste uke.", ""),
    ])
    func aSpokenLanguageTheEngineLeftOpenIsNotHeardAsAnother(
        _ spoken: String, _ said: String, _ forced: String
    ) {
        #expect(
            LanguagePolicy.heard(
                Languages.auto, allowed: [spoken, "en-US"], said: words(said),
                redo: (language: spoken, words: words(forced))) == nil)
    }

    /// A redo forced into Slovenian, which the recognizer cannot read, cannot tell a misread from
    /// another language: the engine's Croatian is not taken for a third language.
    @Test func noLanguageIsHeardAsAnotherBesideOneTheRecognizerCannotRead() {
        let slovenian = "Ne vem še, ali lahko dostavimo naslednji teden."
        #expect(
            LanguagePolicy.heard(
                "hr-HR", allowed: ["sl-SI", "en-US"], said: words(slovenian),
                redo: (language: "sl-SI", words: words(slovenian))) == nil)
    }

    /// Read freely as `nb` and `zh-Hant`, they are named as the Spoken menu offers them, so the
    /// notice can add them.
    @Test(arguments: [
        ("Jeg vet ikke om vi kan levere neste uke.", "no-NO"),
        ("我 不 知 道 我 們 下 週 能 不 能 交 貨 。", "zh-TW"),
    ])
    func aLanguageTheEngineLeftOpenIsNamedAsTheMenuOffersIt(_ said: String, _ code: String) {
        #expect(heard(Languages.auto, said: said, forced: "") == code)
    }

    /// Norwegian added to Spoken clears the mark its line got as Bokmål.
    @Test func aLineReadAsBokmalIsTranslatedOnceNorwegianIsSpoken() {
        let said = "Jeg vet ikke om vi kan levere neste uke."
        var transcript = Transcript()
        transcript.translate(into: "en")
        let final = transcript.applyFinal(transcript: "", words: words(said), on: .system)
        transcript.refine(
            final, with: words(said), heard: heard(Languages.auto, said: said, forced: ""))
        #expect(transcript.pendingSentences.isEmpty)
        transcript.translateHeard(spoken: Self.englishAndGerman + ["no-NO"])
        #expect(transcript.pendingSentences.map(\.text) == [said])
    }

    /// The recognizer knows Norwegian as `nb`: a Norwegian redo reads as Norwegian.
    @Test func aRedoReadsAsTheLanguageByTheRecognizersName() {
        let norwegian = words("Jeg vet ikke om vi kan levere neste uke.")
        #expect(LanguagePolicy.agreement((language: "no-NO", words: norwegian)) > 0.9)
    }

    @Test func speechTheEngineLeftOpenInASpokenLanguageIsNotHeardAsAnother() {
        let german = "Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben."
        #expect(heard(Languages.auto, said: german, forced: "") == nil)
    }

    /// What the engine gave for `say` voices forced into German (docs/behaviour.md): French kept
    /// as French, Dutch with one German word, and Spanish as nothing; and a short French reply.
    @Test(arguments: [
        (
            "fr-FR", "Je ne sais pas encore si nous pouvons livrer la semaine prochaine.",
            "Je ne sais pas encore si nous pouvons livrer la semaine prochaine."
        ),
        (
            "nl-NL", "Ik weet niet zeker of we volgende week kunnen leveren.",
            "Ich weet niet zeker of we volgende week kunnen leveren."
        ),
        ("es-ES", "Estoy de acuerdo, pero necesitamos confirmar con el cliente primero.", ""),
        ("fr-FR", "Oui, merci beaucoup.", ""),
    ])
    func speechForcedIntoASpokenLanguageIsHeardAsItsOwn(
        _ reported: String, _ said: String, _ forced: String
    ) {
        #expect(heard(reported, said: said, forced: forced) == reported)
    }

    private func word(_ text: String, _ start: Double, speaker: Int? = 1) -> Word {
        Word(word: text, start: start, end: start + 0.3, speaker: speaker)
    }

    /// A German line, then French that the second pass heard as French.
    private func heardFrench() -> Transcript {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(transcript: "", words: [word("Danke.", 0)], on: .system)
        let french = transcript.applyFinal(
            transcript: "", words: [word("Je", 1), word("sais.", 1.4)], on: .system)
        transcript.refine(french, with: [word("Je", 1), word("sais.", 1.4)], heard: "fr-FR")
        return transcript
    }

    @Test func aLineHeardInAnUnchosenLanguageIsNotTranslated() throws {
        var transcript = heardFrench()
        #expect(transcript.pendingSentences.map(\.text) == ["Danke."])
        transcript.record(.translated("Thanks."), for: "Danke.", into: "en")
        let paragraph = try #require(transcript.utterances.first)
        #expect(paragraph.translation.text == "Thanks. Je sais.")
        #expect(paragraph.translation.settled)
    }

    /// A new target language translates every line again, but not this one.
    @Test func itStaysUntranslatedInAnotherLanguage() {
        var transcript = heardFrench()
        transcript.translate(into: "es")
        #expect(transcript.pendingSentences.map(\.text) == ["Danke."])
    }

    /// Endpointing can cut a final mid-sentence; the sentence holding the French is left whole.
    @Test func aSentenceThatRunsIntoTheLineIsLeftToo() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(
            transcript: "", words: [word("Wir", 0), word("haben", 0.4)], on: .system)
        let french = transcript.applyFinal(transcript: "", words: [word("sais.", 1)], on: .system)
        transcript.refine(french, with: [word("sais.", 1)], heard: "fr-FR")
        #expect(transcript.pendingSentences.isEmpty)
        #expect(
            TranscriptLine.lines(in: transcript).first.map {
                TranslationWait.pending(translation: $0.translation, started: $0.translationStarted)
            } == false)
    }

    /// Its live translation, made when French was not spoken, goes when the mark arrives.
    @Test func aMarkDropsTheLiveTranslationCarriedOntoTheLine() throws {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Je sais", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Je sais", text: "I know"), on: .system)
        let french = transcript.applyFinal(
            transcript: "", words: [word("Je", 0), word("sais.", 0.4)], on: .system)
        #expect(transcript.utterances.first?.translation.text == "I know")
        transcript.refine(french, with: [word("Je", 0), word("sais.", 0.4)], heard: "fr-FR")
        #expect(try #require(transcript.utterances.first).translation.text == nil)
    }

    /// Added to Spoken, French is translated after all, from French: the translation made for
    /// it before it was marked read it as a spoken language.
    @Test func linesHeardInALanguageAddedLaterAreTranslated() throws {
        var transcript = heardFrench()
        transcript.record(.translated("Thanks."), for: "Danke.", into: "en")
        transcript.record(.translated("I am."), for: "Je sais.", into: "en")
        let unchanged = transcript.translateHeard(spoken: Self.englishAndGerman)
        #expect(!unchanged)
        #expect(transcript.pendingSentences.isEmpty)
        let added = transcript.translateHeard(spoken: Self.englishAndGerman + ["fr-FR"])
        #expect(added)
        #expect(transcript.pendingSentences.map(\.text) == ["Je sais."])
        transcript.record(.translated("I know."), for: "Je sais.", into: "en")
        #expect(try #require(transcript.utterances.first).translation.text == "Thanks. I know.")
    }

    @Test func aTurnHeardInAnUnchosenLanguageIsNotTranslated() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(transcript: "", words: [word("Danke.", 0)], on: .system)
        transcript.relabel([
            TranscribedTurn(
                turn: SpeakerTurn(start: 0, end: 0.5, speaker: 1), words: [word("Danke.", 0)]),
            TranscribedTurn(
                turn: SpeakerTurn(start: 1, end: 2, speaker: 2), words: [word("Merci", 1)],
                heard: "fr-FR"),
        ])
        #expect(transcript.pendingSentences.map(\.text) == ["Danke."])
    }

    @Test func anUnchosenLanguageIsNoticedOnceInTwoLines() {
        var transcript = Transcript()
        var unchosen = UnchosenLanguages()
        let first = transcript.applyFinal(transcript: "", words: [word("Je", 0)], on: .system)
        transcript.refine(first, with: [word("Je", 0)], heard: "fr-FR")
        #expect(unchosen.notices(in: transcript, spoken: Self.englishAndGerman).isEmpty)
        let second = transcript.applyFinal(
            transcript: "", words: [word("Oui", 3, speaker: 2)], on: .system)
        transcript.refine(second, with: [word("Oui", 3)], heard: "fr-CA")
        #expect(
            unchosen.notices(in: transcript, spoken: Self.englishAndGerman)
                == [.languageNotSpoken("fr-FR")])
        #expect(unchosen.notices(in: transcript, spoken: Self.englishAndGerman).isEmpty)
    }

    /// One clip of French across a change of speaker is one line heard, not two.
    @Test func aFinalSplitBetweenSpeakersCountsOnce() {
        var transcript = Transcript()
        var unchosen = UnchosenLanguages()
        let final = transcript.applyFinal(
            transcript: "", words: [word("Oui", 0, speaker: 1), word("merci", 1, speaker: 2)],
            on: .system)
        transcript.refine(final, with: [word("Oui", 0), word("merci", 1)], heard: "fr-FR")
        #expect(transcript.utterances.count == 2)
        #expect(unchosen.notices(in: transcript, spoken: Self.englishAndGerman).isEmpty)
    }

    /// Added from the notice while a refinement was running: the notice would be wrong.
    @Test func aLanguageSpokenByNowIsNotNoticed() {
        var transcript = Transcript()
        for start in [0.0, 3] {
            let final = transcript.applyFinal(
                transcript: "", words: [word("Je", start, speaker: Int(start))], on: .system)
            transcript.refine(final, with: [word("Je", start)], heard: "fr-FR")
        }
        var unchosen = UnchosenLanguages()
        #expect(
            unchosen.notices(in: transcript, spoken: Self.englishAndGerman + ["fr-FR"]).isEmpty)
    }

    @Test func theNoticeNamesTheLanguageAndTheMenuOffersIt() {
        let english = Locale(identifier: "en")
        #expect(
            Problem.languageNotSpoken("fr-CA").message(in: english)
                == "Earshot heard French, which isn't in your Spoken languages.")
        #expect(Problem.languageNotSpoken("fr-CA").id == Problem.languageNotSpoken("fr-FR").id)
        #expect(Languages.code(for: "fr-CA") == "fr-CA")
        #expect(Languages.code(for: "fr") == "fr-FR")
        #expect(Languages.code(for: "sw-KE") == nil)
    }
}
