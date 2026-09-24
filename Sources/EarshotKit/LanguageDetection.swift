import Foundation
import NaturalLanguage

public enum LanguageDetection {
    /// Measured on conversational utterances: fillers and jargon score 0.25-0.39 and are often the
    /// wrong language ("Mhm." reads as Turkish), real phrases of two words or more score 0.74+.
    static let minimumConfidence = 0.5

    /// The dominant language of `text`, or nil when it is too short or ambiguous to call.
    public static func dominant(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            confidence >= minimumConfidence, language != .undetermined
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
