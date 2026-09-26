import Foundation
import Testing

@testable import EarshotKit

@Suite struct SentenceTests {
    @Test func aParagraphSplitsIntoTrimmedSentences() {
        #expect(
            Sentences.split("Hallo zusammen. Wie geht es euch?  Gut!")
                == ["Hallo zusammen.", "Wie geht es euch?", "Gut!"])
    }

    /// A slow speaker's final often ends mid-sentence.
    @Test func textWithoutASentenceEndIsOneSentence() {
        #expect(Sentences.split("und dann haben wir") == ["und dann haben wir"])
        #expect(Sentences.split("").isEmpty)
    }

    @Test func sentencesJoinAsTheTargetLanguageWritesThem() {
        #expect(Sentences.join(["Hello.", "How are you?"], into: "en-GB") == "Hello. How are you?")
        #expect(Sentences.join(["你好。", "你好吗？"], into: "zh-Hans") == "你好。你好吗？")
        #expect(Sentences.join(["こんにちは。", "元気ですか？"], into: "ja") == "こんにちは。元気ですか？")
    }

    /// Alone, "Ja." reads as Finnish and "Sí." as Catalan; inside a paragraph they take its
    /// language, and a whole sentence in another language keeps its own.
    @Test func aOneWordSentenceTakesItsParagraphsLanguage() {
        let german = "Ja. Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben."
        let spanish = "Sí. Estoy de acuerdo, pero necesitamos confirmar con el cliente primero."
        let language = { (sentence: String, paragraph: String?) in
            LanguageDetection.dominant(sentence, within: paragraph)?.languageCode?.identifier
        }
        #expect(language("Ja.", german) == "de")
        #expect(language("Sí.", spanish) == "es")
        #expect(language("Okay, I'll send the client an email this afternoon.", german) == "en")
        #expect(language("Ja.", nil) == LanguageDetection.dominant("Ja.")?.languageCode?.identifier)
    }
}

@Suite struct ParagraphTranslationTests {
    private static let german = "Hallo zusammen. Wie geht es euch? Gut."

    private func transcript(_ text: String = german, speaker: Int = 1, at start: Double = 0)
        -> Transcript
    {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(
            transcript: "",
            words: [Word(word: text, start: start, end: start + 1, speaker: speaker)],
            on: .system)
        return transcript
    }

    private func translation(_ transcript: Transcript) -> ParagraphTranslation? {
        transcript.utterances.first?.translation
    }

    /// A later sentence never shows before an earlier one has its translation.
    @Test func onlyTheTranslatedStartShows() {
        var transcript = transcript()
        transcript.record(.translated("How are you?"), for: "Wie geht es euch?", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: nil, settled: false, started: true))
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(
                    text: "Hello everyone. How are you?", settled: false, started: true))
        transcript.record(.translated("Good."), for: "Gut.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(
                    text: "Hello everyone. How are you? Good.", settled: true, started: true))
    }

    /// Nothing waits for a sentence that will not be translated: it shows as it was said.
    @Test func keptUnavailableAndFailedSentencesShowAsSaid() {
        var transcript = transcript()
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        transcript.record(.unavailable, for: "Wie geht es euch?", into: "en")
        transcript.record(.failed, for: "Gut.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(
                    text: "Hello everyone. Wie geht es euch? Gut.", settled: true, started: true))
    }

    @Test func aParagraphWithNothingTranslatedSettlesWithoutATranslation() {
        var transcript = transcript("Okay. Thanks.")
        transcript.record(.kept, for: "Okay.", into: "en")
        #expect(translation(transcript)?.settled == false)
        transcript.record(.kept, for: "Thanks.", into: "en")
        #expect(translation(transcript) == ParagraphTranslation.untranslated)
    }

    /// The final that closes a partial keeps the partial's translation on its line, so a line
    /// never goes blank while its sentences are translated.
    @Test func aFinalCarriesItsLiveTranslationUntilItsSentencesAreTranslated() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Hallo zusammen.", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Hallo zusammen.", text: "Hello all."), on: .system)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hallo zusammen.", start: 0, end: 1, speaker: 1)],
            on: .system)
        #expect(transcript.liveLines.isEmpty)
        #expect(TranscriptLine.lines(in: transcript).first?.translation == "Hello all.")
        // The next words in flight start without one.
        transcript.applyPartial("Wie", on: .system)
        #expect(transcript.liveLines == [LiveLine(channel: .system, text: "Wie", translation: nil)])

        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: "Hello everyone.", settled: true, started: true))
    }

    /// The carried translation stands for the words the latest final added, after what is
    /// already translated; the next final replaces it, with its own or with none.
    @Test func theCarriedTranslationFollowsTheTranslatedSentences() {
        var transcript = transcript("Hallo zusammen.")
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        transcript.applyPartial("Wie geht es", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Wie geht es", text: "How is it"), on: .system)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Wie geht es", start: 2, end: 3, speaker: 1)],
            on: .system)
        #expect(translation(transcript)?.text == "Hello everyone. How is it")

        transcript.applyFinal(
            transcript: "", words: [Word(word: "euch?", start: 4, end: 5, speaker: 1)],
            on: .system)
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: "Hello everyone.", settled: false, started: true)
        )
    }

    /// A final of two sentences carries the live translation of both: once the first has its
    /// own, the carried one would say it again, so the line shows the first alone until the
    /// second is translated.
    @Test func aTwoSentenceFinalNeverShowsASentenceTwice() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Hallo zusammen. Wie geht es euch?", on: .system)
        transcript.setLiveTranslation(
            Translation(
                sourceText: "Hallo zusammen. Wie geht es euch?", text: "Hello all. How are you?"),
            on: .system)
        transcript.applyFinal(
            transcript: "",
            words: [Word(word: "Hallo zusammen. Wie geht es euch?", start: 0, end: 2, speaker: 1)],
            on: .system)
        #expect(translation(transcript)?.text == "Hello all. How are you?")

        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: "Hello everyone.", settled: false, started: true)
        )
        transcript.record(.translated("How are you all?"), for: "Wie geht es euch?", into: "en")
        #expect(translation(transcript)?.text == "Hello everyone. How are you all?")
    }

    /// The carried translation is in the language it was made for.
    @Test func aNewTargetDropsTheCarriedTranslation() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Hallo zusammen.", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Hallo zusammen.", text: "Hello all."), on: .system)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hallo zusammen.", start: 0, end: 1, speaker: 1)],
            on: .system)
        transcript.applyPartial("Wie geht", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Wie geht", text: "How goes"), on: .system)
        transcript.translate(into: "fr")
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: nil, settled: false, started: false))
        #expect(transcript.liveLines.first?.translation == nil)
    }

    /// Turned off, nothing replaces a carried translation: the line shows as it was said.
    @Test func turningTranslationOffDropsTheCarriedTranslation() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Hallo zusammen.", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Hallo zusammen.", text: "Hello all."), on: .system)
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Hallo zusammen.", start: 0, end: 1, speaker: 1)],
            on: .system)
        transcript.dropLiveTranslations()
        #expect(translation(transcript)?.text == nil)
    }

    /// What was stored is stored again when the language changes, or when a sentence left as
    /// said is translated after its pair was downloaded.
    @Test func aChangedTranslationIsStoredAgain() throws {
        var transcript = transcript("Hallo zusammen. Wie geht es euch?")
        let id = try #require(transcript.utterances.first?.id)
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        transcript.record(.unavailable, for: "Wie geht es euch?", into: "en")
        let first = transcript.translationsToStore(besides: [:])
        #expect(
            first[id]
                == StoredTranslation(
                    source: "Hallo zusammen. Wie geht es euch?", language: "en",
                    text: "Hello everyone. Wie geht es euch?"))
        #expect(transcript.translationsToStore(besides: first).isEmpty)

        transcript.forgetUnavailable()
        transcript.record(.translated("How are you?"), for: "Wie geht es euch?", into: "en")
        let fuller = transcript.translationsToStore(besides: first)
        #expect(fuller[id]?.text == "Hello everyone. How are you?")

        transcript.translate(into: "fr")
        transcript.record(.translated("Bonjour à tous."), for: "Hallo zusammen.", into: "fr")
        transcript.record(.translated("Comment ça va ?"), for: "Wie geht es euch?", into: "fr")
        #expect(transcript.translationsToStore(besides: fuller)[id]?.language == "fr")
    }

    /// Translating into the language spoken leaves nothing to show: what was stored goes, so the
    /// exported file matches the window.
    @Test func aTranslationNoLongerNeededIsRemoved() throws {
        var transcript = transcript("Hallo zusammen.")
        let id = try #require(transcript.utterances.first?.id)
        let store = try TranscriptStore.inMemory()
        let transcriptID = UUID()
        try store.saveLive(transcriptID, startedAt: .now, utterances: transcript.utterances)
        let save = { (changed: [UUID: StoredTranslation]) in
            for (paragraph, stored) in changed {
                try store.setTranslation(
                    stored.text, of: stored.source, language: stored.language, for: paragraph)
            }
        }
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        let first = transcript.translationsToStore(besides: [:])
        try save(first)
        #expect(try store.view(transcriptID)?.paragraphs.first?.translation == "Hello everyone.")

        transcript.translate(into: "de")
        transcript.record(.kept, for: "Hallo zusammen.", into: "de")
        let changed = transcript.translationsToStore(besides: first)
        #expect(changed[id]?.text == nil && changed[id] != nil)
        try save(changed)
        #expect(try store.view(transcriptID)?.paragraphs.first?.translation == nil)
        #expect(transcript.translationsToStore(besides: changed).isEmpty)
    }

    /// A final split between two speakers has no one line its live translation belongs to.
    @Test func aFinalOfTwoSpeakersCarriesNothing() {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyPartial("Hallo Tschüss", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Hallo Tschüss", text: "Hello bye"), on: .system)
        transcript.applyFinal(
            transcript: "",
            words: [
                Word(word: "Hallo", start: 0, end: 1, speaker: 1),
                Word(word: "Tschüss", start: 1, end: 2, speaker: 2),
            ], on: .system)
        #expect(transcript.utterances.map(\.translation.text) == [nil, nil])
    }

    /// A refinement rewrites a final's words: only the sentences whose text changed are asked for
    /// again, not the paragraph.
    @Test func aRefinementAsksOnlyForTheSentencesItChanged() {
        var transcript = transcript("Hallo zusammen.")
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        let final = transcript.applyFinal(
            transcript: "", words: [Word(word: "Wie geht es dir?", start: 2, end: 3, speaker: 1)],
            on: .system)
        #expect(transcript.pendingSentences.map(\.text) == ["Wie geht es dir?"])
        transcript.refine(final, with: [Word(word: "Wie geht es euch?", start: 2, end: 3)])
        #expect(transcript.pendingSentences.map(\.text) == ["Wie geht es euch?"])
        #expect(transcript.pendingSentences.first?.paragraph == "Hallo zusammen. Wie geht es euch?")
    }

    @Test func pendingSentencesStartWithTheNewestParagraph() {
        var transcript = transcript("Eins. Zwei.")
        transcript.applyFinal(
            transcript: "", words: [Word(word: "Drei. Vier.", start: 2, end: 3, speaker: 2)],
            on: .system)
        #expect(transcript.pendingSentences.map(\.text) == ["Drei.", "Vier.", "Eins.", "Zwei."])
    }

    /// The language changed while a sentence was being translated: its result is for the old one.
    @Test func anOutcomeForAnotherTargetIsDropped() {
        var transcript = transcript("Hallo zusammen.")
        transcript.translate(into: "fr")
        transcript.record(.translated("Hello everyone."), for: "Hallo zusammen.", into: "en")
        #expect(
            translation(transcript)
                == ParagraphTranslation(text: nil, settled: false, started: false))
        #expect(transcript.pendingSentences.map(\.text) == ["Hallo zusammen."])
    }

    @Test func anInstalledPairIsTriedAgain() {
        var transcript = transcript()
        for sentence in Sentences.split(Self.german) {
            transcript.record(.unavailable, for: sentence, into: "en")
        }
        #expect(translation(transcript)?.settled == true)
        transcript.forgetUnavailable()
        #expect(transcript.pendingSentences.count == 3)
    }
}

/// At the end of a session each remote paragraph is rebuilt from its turn's audio; what was
/// translated while listening shows at once, in the window and in the first exported file.
@Suite struct RelabelledTranslationTests {
    private func word(_ text: String, _ start: Double, speaker: Int? = nil) -> Word {
        Word(word: text, start: start, end: start + 0.3, speaker: speaker)
    }

    private func translated() -> Transcript {
        var transcript = Transcript()
        transcript.translate(into: "en")
        transcript.applyFinal(
            transcript: "",
            words: [
                word("Das", 0, speaker: 1), word("ist", 0.4, speaker: 1),
                word("erledigt.", 0.8, speaker: 1), word("Nächster", 1.6, speaker: 1),
                word("Punkt.", 2.0, speaker: 1),
            ], on: .system)
        transcript.record(.translated("That is settled."), for: "Das ist erledigt.", into: "en")
        transcript.record(.translated("Next item."), for: "Nächster Punkt.", into: "en")
        transcript.relabel([
            TranscribedTurn(
                turn: SpeakerTurn(start: 0, end: 1.2, speaker: 2),
                words: [word("Das", 0), word("ist", 0.4), word("erledigt.", 0.8)]),
            TranscribedTurn(
                turn: SpeakerTurn(start: 1.1, end: 2.5, speaker: 1),
                words: [word("Nächster", 1.6), word("Punkt.", 2.0)]),
        ])
        return transcript
    }

    @Test func rebuiltParagraphsKeepTheirTranslations() {
        let transcript = translated()
        #expect(
            transcript.utterances.map(\.translation.text) == ["That is settled.", "Next item."])
        #expect(transcript.pendingSentences.isEmpty)
        #expect(transcript.sentenceCoverage == (known: 2, pending: 0))
    }

    /// As the app stores a settled paragraph's translation, before it seals the session.
    @Test func theFirstExportAfterRelabellingHasThem() throws {
        let transcript = translated()
        let store = try TranscriptStore.inMemory()
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        try store.saveLive(id, startedAt: started, utterances: transcript.utterances)
        for (paragraph, stored) in transcript.translationsToStore(besides: [:]) {
            try store.setTranslation(
                stored.text, of: stored.source, language: stored.language, for: paragraph)
        }
        try store.seal(id, at: started)
        let markdown = try #require(try store.view(id)).markdown()
        #expect(markdown.contains("Das ist erledigt.\n> That is settled."))
        #expect(markdown.contains("Nächster Punkt.\n> Next item."))
    }
}
