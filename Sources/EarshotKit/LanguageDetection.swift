import Foundation
import NaturalLanguage

public enum LanguageDetection {
    /// Measured on conversational utterances: fillers and jargon score 0.25-0.39 and are often the
    /// wrong language ("Mhm." reads as Turkish), real phrases of two words or more score 0.74+.
    static let minimumConfidence = 0.5

    /// Measured with the same recognizer: real phrases of two words or more score 0.74 and up,
    /// while one-word sentences score 0.5-0.6 for the wrong language ("Ja." Finnish, "Sí."
    /// Catalan, "Nu." Romanian) as often as for the right one.
    static let sentenceConfidence = 0.74

    /// Languages in `Languages.codes` that `NLLanguageRecognizer` cannot detect: a constraint to
    /// one of them gets no hypothesis at all.
    private static let undetectable: Set<String> = ["sl", "et", "lv", "lt", "mt", "ms"]

    /// The dominant language of `text`, or nil when it is too short or ambiguous to call. `spoken`
    /// holds locale codes, empty for any language.
    public static func dominant(_ text: String, among spoken: [String] = []) -> Locale.Language? {
        dominant(text, minimum: minimumConfidence, among: constraint(spoken))
    }

    /// The language of a sentence, or of its paragraph when the sentence alone is too short to
    /// tell: "Ja." inside a German paragraph is German.
    public static func dominant(
        _ sentence: String, within paragraph: String?, among spoken: [String] = []
    ) -> Locale.Language? {
        let constraint = constraint(spoken)
        guard let paragraph else {
            return dominant(sentence, minimum: minimumConfidence, among: constraint)
        }
        return dominant(sentence, minimum: sentenceConfidence, among: constraint)
            ?? dominant(paragraph, minimum: minimumConfidence, among: constraint)
    }

    private static func dominant(_ text: String, minimum: Double, among constraint: [NLLanguage]?)
        -> Locale.Language?
    {
        hypothesis(text, minimum: minimum, among: constraint).map {
            Locale.Language(identifier: $0.rawValue)
        }
    }

    static func hypothesis(_ text: String, minimum: Double, among constraint: [NLLanguage]?)
        -> NLLanguage?
    {
        let recognizer = NLLanguageRecognizer()
        if let constraint { recognizer.languageConstraints = constraint }
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            confidence >= minimum, language != .undetermined
        else { return nil }
        return language
    }

    /// The language of `text`, read freely and as surely as a sentence's, when it is none of the
    /// spoken ones, which must all be languages the recognizer can detect. Named as the Spoken
    /// menu offers it ("no-NO" for `nb`), or as the recognizer does when the menu has none.
    static func unspoken(_ text: String, spoken: [String]) -> String? {
        guard let constraint = constraint(spoken),
            let language = hypothesis(text, minimum: sentenceConfidence, among: nil),
            !constraint.contains(language)
        else { return nil }
        return Languages.codes.first { recognizerLanguage($0) == language } ?? language.rawValue
    }

    /// The recognizer's languages for the spoken ones; nil leaves it free, for any language and
    /// when one of them is a language it cannot detect. It drops such a constraint without a word,
    /// so speech in that language would read as one of the others.
    static func constraint(_ spoken: [String]) -> [NLLanguage]? {
        let languages = spoken.map(recognizerLanguage)
        guard !languages.isEmpty, !languages.contains(where: { undetectable.contains($0.rawValue) })
        else { return nil }
        return languages
    }

    /// The recognizer knows Norwegian as Bokmål and Chinese by its script, not as `no` and `zh`.
    static func recognizerLanguage(_ code: String) -> NLLanguage {
        let language = Locale.Language(identifier: code)
        return switch language.languageCode?.identifier ?? code {
        case "no": .norwegian
        case "zh":
            language.maximalIdentifier.contains("Hant") ? .traditionalChinese : .simplifiedChinese
        case let code: NLLanguage(code)
        }
    }

    /// Whether two languages are the same for the purpose of deciding to translate (`en-GB` == `en-US`).
    public static func sameLanguage(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        lhs.languageCode == rhs.languageCode
            && (lhs.languageCode?.identifier != "zh" || lhs.script == rhs.script
                || lhs.script == nil
                || rhs.script == nil)
    }
}
