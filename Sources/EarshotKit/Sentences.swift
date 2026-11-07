import Foundation
import NaturalLanguage

/// The unit of translation. A final is often a fragment of a sentence, because endpointing cuts
/// after 800 ms of silence, and a paragraph grows for as long as its speaker holds the floor, so
/// each sentence is translated once and a paragraph's translation is joined from its sentences'.
enum Sentences {
    /// The sentences of `text`, trimmed. Text without a sentence end is one sentence.
    static func split(_ text: String) -> [String] {
        ranges(text).map(\.sentence)
    }

    /// The sentences of the paragraph the segments' texts make, joined with spaces, that hold
    /// text of a marked segment.
    static func holding(_ segments: [(text: String, marked: Bool)]) -> Set<String> {
        guard segments.contains(where: \.marked) else { return [] }
        var text = ""
        var marked: [Range<Int>] = []
        for segment in segments {
            if !text.isEmpty { text += " " }
            let start = text.count
            text += segment.text
            if segment.marked { marked.append(start..<text.count) }
        }
        let offset = { (index: String.Index) in text.distance(from: text.startIndex, to: index) }
        return Set(
            ranges(text).filter { sentence in
                let range = offset(sentence.range.lowerBound)..<offset(sentence.range.upperBound)
                return marked.contains { $0.overlaps(range) }
            }.map(\.sentence))
    }

    private static func ranges(_ text: String) -> [(range: Range<String.Index>, sentence: String)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : (range, sentence)
        }
    }

    /// Joined as `target` writes one sentence after another: Chinese and Japanese end a sentence
    /// with a full-width mark and no space; the other languages Apple translates into use a space.
    static func join(_ sentences: [String], into target: String) -> String {
        let code = Locale.Language(identifier: target).languageCode?.identifier
        return sentences.joined(separator: ["zh", "ja"].contains(code) ? "" : " ")
    }
}
