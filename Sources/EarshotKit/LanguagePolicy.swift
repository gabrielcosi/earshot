import Foundation
import NaturalLanguage

/// Keeps transcripts to the languages the user said are spoken. The engine's `auto`
/// chooses among all of its ~100 languages, so noise or a mumbled word can come back as a
/// language nobody spoke.
public enum LanguagePolicy {
    /// One configured language is pinned; the engine cannot restrict `auto` to a subset.
    public static func liveLanguage(allowed: [String]) -> String {
        allowed.count == 1 ? allowed[0] : Languages.auto
    }

    /// Whether an `auto` result can stand: the engine's detected language is configured, and no
    /// word is written in a script none of the configured languages uses.
    public static func accepts(_ words: [Word], reported: String?, allowed: [String]) -> Bool {
        guard !allowed.isEmpty else { return true }
        guard let reported, reported != Languages.auto,
            allowed.contains(where: { sameLanguage($0, reported) })
        else { return false }
        let permitted = Set(allowed.flatMap(scripts(of:)))
        return words.allSatisfy { scripts(in: $0.word).isSubset(of: permitted) }
    }

    /// Among transcripts of the same audio forced into different languages, the one whose text
    /// reads most like the language it was forced into. The engine's word confidences cannot
    /// decide this: forced into a wrong language it still reports 1.0 for every word.
    public static func best(of candidates: [(language: String, words: [Word])])
        -> (language: String, words: [Word])?
    {
        candidates.max { lhs, rhs in agreement(lhs) < agreement(rhs) }
    }

    private static func agreement(_ candidate: (language: String, words: [Word])) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(candidate.words.map(\.word).joined(separator: " "))
        let code = Locale.Language(identifier: candidate.language).languageCode?.identifier ?? ""
        let hypotheses = recognizer.languageHypotheses(withMaximum: 30)
        return hypotheses.first { $0.key.rawValue.hasPrefix(code) }?.value ?? 0
    }

    private static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        Locale.Language(identifier: lhs).languageCode
            == Locale.Language(identifier: rhs).languageCode
    }

    /// ISO 15924 scripts a language is written in; Japanese and Korean mix several.
    static func scripts(of language: String) -> [String] {
        let script =
            Locale.Language(identifier: language).maximalIdentifier
            .split(separator: "-").dropFirst().first { $0.count == 4 }.map(String.init) ?? "Latn"
        switch script {
        case "Jpan": return ["Hira", "Kana", "Hani"]
        case "Kore": return ["Hang", "Hani"]
        case "Hans", "Hant": return ["Hani"]
        default: return [script]
        }
    }

    /// The scripts of a word's letters. Digits and punctuation belong to no script.
    static func scripts(in word: String) -> Set<String> {
        Set(
            word.unicodeScalars.compactMap { scalar in
                guard scalar.properties.isAlphabetic else { return nil }
                return script(of: scalar.value)
            })
    }

    private static let ranges: [(ClosedRange<UInt32>, String)] = [
        (0x0041...0x024F, "Latn"), (0x1E00...0x1EFF, "Latn"),
        (0x0370...0x03FF, "Grek"), (0x1F00...0x1FFF, "Grek"),
        (0x0400...0x052F, "Cyrl"),
        (0x0590...0x05FF, "Hebr"),
        (0x0600...0x06FF, "Arab"), (0x0750...0x077F, "Arab"),
        (0x0900...0x097F, "Deva"),
        (0x0980...0x09FF, "Beng"),
        (0x0E00...0x0E7F, "Thai"),
        (0x1100...0x11FF, "Hang"), (0xAC00...0xD7AF, "Hang"),
        (0x3040...0x309F, "Hira"),
        (0x30A0...0x30FF, "Kana"),
        (0x3400...0x4DBF, "Hani"), (0x4E00...0x9FFF, "Hani"),
    ]

    private static func script(of value: UInt32) -> String {
        ranges.first { $0.0.contains(value) }?.1 ?? "Zzzz"
    }
}
