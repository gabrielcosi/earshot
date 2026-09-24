import Foundation
import Testing

@testable import EarshotKit

@Suite struct LanguagePolicyTests {
    private func words(_ text: String) -> [Word] {
        text.split(separator: " ").map { Word(word: String($0), start: 0, end: 0) }
    }

    @Test func anyLanguageIsAcceptedWhenNoneAreConfigured() {
        #expect(
            LanguagePolicy.accepts(words("Мульцимеск через"), reported: "auto", allowed: []))
    }

    @Test func aReportedLanguageOutsideTheSetIsRejected() {
        #expect(
            !LanguagePolicy.accepts(
                words("Buenos días"), reported: "es-ES", allowed: ["en-US", "de-DE"]))
    }

    @Test func anUndetectedLanguageIsRejected() {
        #expect(!LanguagePolicy.accepts(words("Мульцимеск"), reported: "auto", allowed: ["ro-RO"]))
    }

    @Test func aWordInAScriptNoConfiguredLanguageUsesIsRejected() {
        #expect(
            !LanguagePolicy.accepts(
                words("there was a whole. 外面 that"), reported: "en-US",
                allowed: ["en-US", "de-DE"]))
    }

    @Test func textInTheSetsLanguagesAndScriptsIsAccepted() {
        #expect(
            LanguagePolicy.accepts(
                words("Ich glaube, wir sollten verschieben."), reported: "de-DE",
                allowed: ["en-US", "de-DE"]))
    }

    @Test func picksTheCandidateThatReadsAsTheLanguageItWasForcedInto() {
        let best = LanguagePolicy.best(of: [
            ("es-ES", words("Multimesc, cheriescula vendu trimestrul urmator")),
            ("ro-RO", words("Mulțumesc, riscula ven pentru trimestrul următor,")),
        ])
        #expect(best?.language == "ro-RO")
    }

    @Test func oneConfiguredLanguageIsPinnedLive() {
        #expect(LanguagePolicy.liveLanguage(allowed: ["ro-RO"]) == "ro-RO")
        #expect(LanguagePolicy.liveLanguage(allowed: ["ro-RO", "en-US"]) == Languages.auto)
        #expect(LanguagePolicy.liveLanguage(allowed: []) == Languages.auto)
    }
}
