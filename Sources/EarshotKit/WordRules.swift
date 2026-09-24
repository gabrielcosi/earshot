import Foundation

/// A term list the engine is told to favour, and rules that tidy the text it produces. The rules
/// run when a transcript is shown or saved; the transcript itself keeps what was said, so a
/// changed rule applies to older transcripts too and a bad rule never destroys anything.
public struct WordRules: Codable, Sendable, Equatable {
    public struct Removal: Codable, Sendable, Equatable, Identifiable {
        public var id = UUID()
        public var pattern: String
        public var enabled = true
        /// Only in paragraphs detected as this language: "um" is a filler in English and a word
        /// in German.
        public var language: String?

        public init(pattern: String, language: String? = nil) {
            self.pattern = pattern
            self.language = language
        }
    }

    public struct Replacement: Codable, Sendable, Equatable, Identifiable {
        public var id = UUID()
        public var pattern: String
        public var replacement: String
        public var enabled = true

        public init(pattern: String, replacement: String) {
            self.pattern = pattern
            self.replacement = replacement
        }
    }

    /// Mid-range of the 2-3 the engine documents for cache-aware RNNT, and measured: boost 2
    /// already corrected every name in a test sentence, and sentences without them came back
    /// unchanged at 3.
    static let boost = 3.0

    public var vocabulary: [String] = []
    public var removalEnabled = true
    /// No "er": it is the German "he".
    public var removals: [Removal] = [
        Removal(pattern: "uh+"), Removal(pattern: "uhm+"), Removal(pattern: "hm+"),
        Removal(pattern: "um+", language: "en"),
    ]
    public var replacementEnabled = true
    public var replacements: [Replacement] = []
    public var lowercase = false
    public var removePunctuation = false

    public init() {}

    public var speechContexts: [SpeechContext] {
        let phrases = vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
        return phrases.isEmpty ? [] : [SpeechContext(phrases: phrases, boost: Self.boost)]
    }

    public func apply(_ text: String) -> String {
        var result = text
        let language = LanguageDetection.dominant(text)?.languageCode?.identifier
        if removalEnabled {
            for removal in removals where removal.enabled {
                if let only = removal.language, only != language { continue }
                result = Self.replace(removal.pattern, in: result, with: "", swallowComma: true)
            }
        }
        if replacementEnabled {
            for replacement in replacements where replacement.enabled {
                result = Self.replace(
                    replacement.pattern, in: result, with: replacement.replacement,
                    swallowComma: false)
            }
        }
        result = Self.tidy(result, capitalize: text.first?.isUppercase == true)
        if removePunctuation {
            result = result.replacing(/[^\p{L}\p{N}\s'’-]/, with: "")
            result = Self.collapseSpaces(result)
        }
        if lowercase { result = result.lowercased() }
        return result
    }

    /// Whole words only, ignoring case. A removed filler takes its comma along. A pattern that is
    /// not a valid regular expression is skipped.
    private static func replace(
        _ pattern: String, in text: String, with replacement: String, swallowComma: Bool
    ) -> String {
        let body = "(?i)(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}])"
        let full = swallowComma ? body + ",?\\s*" : body
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: full) else {
            return text
        }
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Removes what removals leave behind: punctuation with no word before it, space before
    /// punctuation, repeated spaces.
    private static func tidy(_ text: String, capitalize: Bool) -> String {
        var result = text.replacing(/(^|[.!?])\s*[.,!?]+/) { match in match.output.1 }
        result = result.replacing(/\s+([.,!?;:])/) { match in match.output.1 }
        result = collapseSpaces(result)
        if capitalize, let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.replacing(/\s{2,}/, with: " ").trimmingCharacters(in: .whitespaces)
    }
}
