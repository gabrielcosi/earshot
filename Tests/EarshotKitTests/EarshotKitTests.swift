import Foundation
import Testing

@testable import EarshotKit

@Suite struct RealtimeProtocolTests {
    @Test func sessionUpdateUsesServerFieldNames() throws {
        let json = try ClientEvent.sessionUpdate(SessionSettings(speakerDiarization: true))
            .encoded()
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["type"] as? String == "session.update")
        let session = try #require(object["session"] as? [String: Any])
        #expect(session["sample_rate"] as? Int == 16_000)
        #expect(session["speaker_diarization"] as? Bool == true)
        #expect(session["word_timestamps"] as? Bool == true)
    }

    @Test func decodesFinalWithSpeakers() throws {
        let event = try ServerEvent.decode(
            """
            {"type":"conversation.item.input_audio_transcription.completed","transcript":"Hi there",
             "audio_processed":1.2,"event_id":"event_3",
             "words":[{"word":"Hi","start":0.1,"end":0.3,"confidence":1,"speaker":2},
                      {"word":"there","start":0.4,"end":0.6,"confidence":1,"speaker":2}]}
            """)
        #expect(
            event
                == .final(
                    transcript: "Hi there",
                    words: [
                        Word(word: "Hi", start: 0.1, end: 0.3, speaker: 2),
                        Word(word: "there", start: 0.4, end: 0.6, speaker: 2),
                    ]))
    }

    @Test func decodesPartialAndError() throws {
        #expect(
            try ServerEvent.decode(
                #"{"type":"conversation.item.input_audio_transcription.delta","delta":"hel"}"#)
                == .partial(delta: "hel"))
        #expect(
            try ServerEvent.decode(#"{"type":"error","error":{"message":"boom"}}"#)
                == .error("boom"))
    }
}

@Suite struct TranscriptTests {
    @Test func splitsFinalBySpeakerRuns() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "a b c",
            words: [
                Word(word: "a", start: 0, end: 1, speaker: 1),
                Word(word: "b", start: 1, end: 2, speaker: 2),
                Word(word: "c", start: 2, end: 3, speaker: 2),
            ],
            on: .system
        )
        #expect(transcript.utterances.map(\.speaker) == [.remote(slot: 1), .remote(slot: 2)])
        #expect(transcript.utterances.map(\.text) == ["a", "b c"])
    }

    @Test func interleavesChannelsByStartTime() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "later", words: [Word(word: "later", start: 5, end: 6, speaker: 1)],
            on: .system)
        transcript.applyFinal(
            transcript: "first", words: [Word(word: "first", start: 1, end: 2)], on: .microphone)
        #expect(transcript.utterances.map(\.text) == ["first", "later"])
        #expect(transcript.utterances.first?.speaker == .me)
    }

    @Test func mergesAdjacentFinalsFromTheSameSpeaker() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "one", words: [Word(word: "one", start: 0, end: 1)], on: .microphone)
        transcript.applyFinal(
            transcript: "two", words: [Word(word: "two", start: 1.5, end: 2)], on: .microphone)
        #expect(transcript.utterances.count == 1)
        #expect(transcript.utterances.first?.text == "one two")
    }

    @Test func partialsAccumulateAndClearOnFinal() {
        var transcript = Transcript()
        transcript.applyPartial("hel", on: .microphone)
        transcript.applyPartial("lo", on: .microphone)
        #expect(transcript.partials[.microphone] == "hello")
        transcript.applyFinal(transcript: "hello", words: [], on: .microphone)
        #expect(transcript.partials[.microphone] == nil)
        #expect(transcript.utterances.first?.text == "hello")
    }
}

@Suite struct ExportTests {
    @Test func timestamps() {
        #expect(MarkdownExport.timestamp(65.9) == "01:05")
        #expect(MarkdownExport.timestamp(3725) == "1:02:05")
        #expect(MarkdownExport.timestamp(65.9, hundredths: true) == "01:05.90")
        #expect(MarkdownExport.timestamp(3725.041, hundredths: true) == "1:02:05.04")
    }

    @Test func pcmClipsAndScales() {
        let data = [Float(0), 1, -1, 2].withUnsafeBufferPointer(PCM.int16LittleEndian)
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(values == [0, Int16.max, -Int16.max, Int16.max])
    }
}

@Suite struct TranslationTests {
    @Test func detectsSpokenLanguages() {
        let cases = [
            ("Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben.", "de"),
            ("Estoy de acuerdo, pero necesitamos confirmar con el cliente primero.", "es"),
            ("Okay, I'll send the client an email this afternoon.", "en"),
        ]
        for (text, code) in cases {
            #expect(LanguageDetection.dominant(text)?.languageCode?.identifier == code)
        }
    }

    @Test(arguments: ["Mhm.", "Okay.", "Kubernetes cluster upgrade."])
    func fillersAndJargonAreNotTranslated(_ text: String) {
        #expect(LanguageDetection.dominant(text) == nil)
    }

    @Test(arguments: [("Genau.", "de"), ("Sí, claro.", "es"), ("Vale, perfecto.", "es")])
    func shortRealPhrasesAreDetected(_ text: String, _ code: String) {
        #expect(LanguageDetection.dominant(text)?.languageCode?.identifier == code)
    }

    @Test func regionalVariantsCountAsTheSameLanguage() {
        #expect(
            LanguageDetection.sameLanguage(
                Locale.Language(identifier: "en-GB"), Locale.Language(identifier: "en-US")))
        #expect(
            !LanguageDetection.sameLanguage(
                Locale.Language(identifier: "de"), Locale.Language(identifier: "en")))
    }

    @Test func mergingMakesATranslationStale() {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hallo", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        let id = try? #require(transcript.utterances.first?.id)
        transcript.setTranslation(
            Translation(sourceText: "Hallo", text: "Hello"), for: id ?? UUID())
        #expect(transcript.utterances.first?.currentTranslation == "Hello")
        transcript.applyFinal(
            transcript: "zusammen", words: [Word(word: "zusammen", start: 1.2, end: 2, speaker: 1)],
            on: .system)
        #expect(transcript.utterances.count == 1)
        #expect(transcript.utterances.first?.currentTranslation == nil)
    }
}

@Suite struct ChunkerTests {
    @Test func coalescesTapBuffersIntoFullChunks() {
        var chunker = PCMChunker(chunkBytes: 3200)
        var sent: [Data] = []
        for _ in 0..<20 { sent += chunker.append(Data(count: 342)) }
        #expect(sent.map(\.count) == [3200, 3200])
        #expect(chunker.flush()?.count == 20 * 342 - 6400)
        #expect(chunker.flush() == nil)
    }

    @Test func splitsOversizedBuffers() {
        var chunker = PCMChunker(chunkBytes: 3200)
        #expect(chunker.append(Data(count: 7000)).map(\.count) == [3200, 3200])
        #expect(chunker.flush()?.count == 600)
    }
}

@Suite struct SpeakerTurnTests {
    private func final(_ text: String, at start: Double, speaker: Int? = nil) -> (String, [Word]) {
        (text, [Word(word: text, start: start, end: start + 0.5, speaker: speaker)])
    }

    @Test func slowSpeakerStaysInOneParagraph() {
        var transcript = Transcript()
        for (index, piece) in ["So I think", "we should", "move the release"].enumerated() {
            let (text, words) = final(piece, at: Double(index) * 3, speaker: 1)
            transcript.applyFinal(transcript: text, words: words, on: .system)
        }
        #expect(transcript.utterances.map(\.text) == ["So I think we should move the release"])
    }

    @Test func anotherSpeakerEndsTheTurn() {
        var transcript = Transcript()
        let (first, firstWords) = final("So I think", at: 0, speaker: 1)
        transcript.applyFinal(transcript: first, words: firstWords, on: .system)
        let (reply, replyWords) = final("okay", at: 2)
        transcript.applyFinal(transcript: reply, words: replyWords, on: .microphone)
        let (next, nextWords) = final("we should", at: 4, speaker: 1)
        transcript.applyFinal(transcript: next, words: nextWords, on: .system)
        #expect(transcript.utterances.map(\.text) == ["So I think", "okay", "we should"])
    }

    /// Words still being recognized stay out of the finished lines until their final arrives,
    /// so a line never changes under the reader.
    @Test func aPartialStaysOutOfTheSpeakersParagraph() {
        var transcript = Transcript()
        let (text, words) = final("So I think", at: 0, speaker: 1)
        transcript.applyFinal(transcript: text, words: words, on: .system)
        transcript.applyPartial("we sho", on: .system)
        #expect(TranscriptLine.lines(in: transcript).map(\.text) == ["So I think"])
        #expect(
            transcript.liveLines == [LiveLine(channel: .system, text: "we sho", translation: nil)])
    }

    @Test func eachSpeakingChannelHasItsOwnLiveLineMicrophoneFirst() {
        var transcript = Transcript()
        transcript.applyPartial("so we", on: .system)
        transcript.applyPartial("sounds", on: .microphone)
        #expect(transcript.liveLines.map(\.channel) == [.microphone, .system])
        #expect(transcript.liveLines.map(\.text) == ["sounds", "so we"])
    }
}

@Suite struct LiveTranslationTests {
    @Test func liveTranslationFollowsTheGrowingPartial() {
        var transcript = Transcript()
        transcript.applyPartial("Ich glaube", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Ich glaube", text: "I think"), on: .system)
        #expect(transcript.liveLines.last?.translation == "I think")
        transcript.applyPartial(" wir", on: .system)
        #expect(transcript.liveLines.last?.translation == "I think")
    }

    @Test func liveTranslationOfAnAbandonedPartialIsDropped() {
        var transcript = Transcript()
        transcript.applyPartial("Ich glaube", on: .system)
        transcript.applyFinal(transcript: "Ich glaube", words: [], on: .system)
        transcript.applyPartial("Wie", on: .system)
        transcript.setLiveTranslation(
            Translation(sourceText: "Ich glaube", text: "I think"), on: .system)
        #expect(transcript.liveLines == [LiveLine(channel: .system, text: "Wie", translation: nil)])
    }

    @Test func finalClearsTheLiveTranslation() {
        var transcript = Transcript()
        transcript.applyPartial("Hallo", on: .system)
        transcript.setLiveTranslation(Translation(sourceText: "Hallo", text: "Hello"), on: .system)
        transcript.applyFinal(
            transcript: "Hallo", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        transcript.applyPartial("Wie", on: .system)
        #expect(transcript.liveLines == [LiveLine(channel: .system, text: "Wie", translation: nil)])
    }

    @Test func aSlowTranslationOfAnOlderParagraphDoesNotReplaceANewerOne() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hallo", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        let id = try #require(transcript.utterances.first?.id)
        transcript.applyFinal(
            transcript: "zusammen", words: [Word(word: "zusammen", start: 2, end: 3, speaker: 1)],
            on: .system)
        transcript.setTranslation(
            Translation(sourceText: "Hallo zusammen", text: "Hello everyone"), for: id)
        transcript.setTranslation(Translation(sourceText: "Hallo", text: "Hello"), for: id)
        #expect(transcript.utterances.first?.translation?.text == "Hello everyone")
    }

    @Test func aParagraphKeepsShowingItsPreviousTranslationWhileItGrows() throws {
        var transcript = Transcript()
        transcript.applyFinal(
            transcript: "Hallo", words: [Word(word: "Hallo", start: 0, end: 1, speaker: 1)],
            on: .system)
        let id = try #require(transcript.utterances.first?.id)
        transcript.setTranslation(Translation(sourceText: "Hallo", text: "Hello"), for: id)
        transcript.applyFinal(
            transcript: "zusammen", words: [Word(word: "zusammen", start: 2, end: 3, speaker: 1)],
            on: .system)
        #expect(transcript.utterances.first?.translation?.text == "Hello")
        #expect(transcript.utterances.first?.currentTranslation == nil)
    }
}

@Suite struct EngineEndpointTests {
    @Test func requestsCarryTheBearerKey() throws {
        let engine = EngineEndpoint(
            url: try #require(URL(string: "http://127.0.0.1:8765/")), apiKey: "k")
        let request = engine.request("v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(request.url?.absoluteString == "http://127.0.0.1:8765/v1/audio/transcriptions")
    }

    @Test func theRealtimeSocketUsesWebSocketScheme() throws {
        let engine = EngineEndpoint(url: try #require(URL(string: "http://127.0.0.1:8765/")))
        let request = engine.request("v1/audio/transcriptions/realtime", scheme: "ws")
        #expect(
            request.url?.absoluteString == "ws://127.0.0.1:8765/v1/audio/transcriptions/realtime")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

@Suite struct AudioSinkTests {
    private final class Receiver: AudioReceiver, @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [UInt8] = []
        func send(audio: Data) { lock.withLock { chunks.append(contentsOf: audio) } }
        var received: [UInt8] { lock.withLock { chunks } }
    }

    @Test func audioBeforeAttachArrivesFirstAndInOrder() {
        let sink = AudioSink()
        let receiver = Receiver()
        sink.send(Data([1, 2]))
        sink.send(Data([3]))
        sink.attach(receiver)
        sink.send(Data([4]))
        #expect(receiver.received == [1, 2, 3, 4])
    }

    @Suite struct DiarizerModeTests {
        @Test func fullAttentionUpToItsLimitAndStreamingBeyond() {
            #expect(Diarizer.mode(forSeconds: 60) == "offline")
            #expect(Diarizer.mode(forSeconds: Diarizer.offlineLimit) == "offline")
            #expect(Diarizer.mode(forSeconds: Diarizer.offlineLimit + 1) == "streaming")
        }
    }

}
