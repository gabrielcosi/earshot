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

    /// The dominant language of `text`, or nil when it is too short or ambiguous to call.
    public static func dominant(_ text: String) -> Locale.Language? {
        dominant(text, minimum: minimumConfidence)
    }

    /// The language of a sentence, or of its paragraph when the sentence alone is too short to
    /// tell: "Ja." inside a German paragraph is German.
    public static func dominant(_ sentence: String, within paragraph: String?) -> Locale.Language? {
        guard let paragraph else { return dominant(sentence) }
        return dominant(sentence, minimum: sentenceConfidence) ?? dominant(paragraph)
    }

    private static func dominant(_ text: String, minimum: Double) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            confidence >= minimum, language != .undetermined
        else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    /// Whether two languages are the same for the purpose of deciding to translate (`en-GB` == `en-US`).
    public static func sameLanguage(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        lhs.languageCode == rhs.languageCode
            && (lhs.languageCode?.identifier != "zh" || lhs.script == rhs.script
                || lhs.script == nil
                || rhs.script == nil)
    }
}
