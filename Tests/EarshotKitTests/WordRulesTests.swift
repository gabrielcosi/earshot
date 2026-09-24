import Foundation
import Testing

@testable import EarshotKit

@Suite struct WordRulesTests {
    @Test func defaultsRemoveFillersAndTheirCommas() {
        let rules = WordRules()
        #expect(
            rules.apply("Uh, I think um we should, uhh, ship it.") == "I think we should, ship it.")
        #expect(rules.apply("Hmm. Okay.") == "Okay.")
    }

    /// "er" (he) and "um" (in order to) are German words, not fillers.
    @Test func defaultsKeepGermanWordsThatLookLikeFillers() {
        #expect(
            WordRules().apply("Er hat recht, um ehrlich zu sein, das Projekt ist gut.")
                == "Er hat recht, um ehrlich zu sein, das Projekt ist gut.")
    }

    @Test func fillerPatternsMatchWholeWordsOnly() {
        #expect(WordRules().apply("The umbrella and the human") == "The umbrella and the human")
    }

    @Test func replacementsMatchWholeWordsIgnoringCase() {
        var rules = WordRules()
        rules.replacements = [
            WordRules.Replacement(pattern: "acme corp", replacement: "Acme Corp")
        ]
        #expect(rules.apply("I work at ACME corp daily") == "I work at Acme Corp daily")
    }

    @Test func aDisabledRuleOrSectionDoesNothing() {
        var rules = WordRules()
        rules.removalEnabled = false
        #expect(rules.apply("uh yes") == "uh yes")
        rules.removalEnabled = true
        rules.removals[0].enabled = false
        #expect(rules.apply("uh yes") == "uh yes")
    }

    @Test func anInvalidPatternIsSkipped() {
        var rules = WordRules()
        rules.removals.append(WordRules.Removal(pattern: "("))
        #expect(rules.apply("uh hello") == "hello")
    }

    @Test func formattingOptions() {
        var rules = WordRules()
        rules.lowercase = true
        rules.removePunctuation = true
        #expect(rules.apply("Okay, let's GO!") == "okay let's go")
    }

    @Test func vocabularyBecomesOneBoostedContext() throws {
        var rules = WordRules()
        #expect(rules.speechContexts.isEmpty)
        rules.vocabulary = ["Jane Doe", " ", "Acme Corp"]
        let context = try #require(rules.speechContexts.first)
        #expect(context.phrases == ["Jane Doe", "Acme Corp"])
        #expect(context.boost == 3)
    }

    @Test func sessionUpdateCarriesTheVocabulary() throws {
        var settings = SessionSettings(speakerDiarization: false)
        settings.speechContexts = [SpeechContext(phrases: ["Zentari"], boost: 3)]
        let json = try ClientEvent.sessionUpdate(settings).encoded()
        #expect(
            json.contains(#""speech_contexts":[{"boost":3,"phrases":["Zentari"]}]"#)
                || json.contains(#""speech_contexts":[{"phrases":["Zentari"],"boost":3}]"#))
    }
}
