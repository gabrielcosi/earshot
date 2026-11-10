import Foundation
import NaturalLanguage

/// A second pass checked against the words it replaces: a live final's, or the transcript's in a
/// speaker turn. A fresh decode can read a line in the wrong spoken language, or render a line
/// that switches language mid-sentence in only one of them; the words it replaces, wrong as they
/// may be in other ways, still show which languages were spoken (docs/behaviour.md, Engine:
/// language).
extension LanguagePolicy {
    /// Why a result is doubted.
    struct Challenge: Equatable {
        /// The spoken language to redo the clip in: the first one in the reference's language,
        /// nil when the reference's language cannot be told.
        let language: String?
        /// The reference's language, and every spoken language it shows in a short run of words.
        let dominant: NLLanguage?
        let shown: Set<NLLanguage>
        let constraint: [NLLanguage]
    }

    /// Measured on `say` voices: three-word runs read at 0.9 or more show a second language in
    /// none of 322 one-language windows and in 44 of 55 that span two, and challenge 1 of 182
    /// one-language windows of the code-switch set (docs/behaviour.md, Engine: language).
    static let runWords = 3
    static let runConfidence = 0.9

    /// Written without spaces between words, so counting words or the edits between two lines
    /// means nothing in them.
    private static let unspaced: Set<String> = ["zh", "ja", "th"]

    /// Nil when the result stands: either line is too short to tell its language, or the spoken
    /// languages cannot be told apart. Otherwise when the result reads as another spoken
    /// language than the reference, or lost a second language the reference shows. Losing the
    /// reference's own language is the first case: a live stream still on the previous
    /// language writes a switch as words that read as it.
    static func challenge(_ result: [Word], reference: [Word], allowed: [String]) -> Challenge? {
        guard result.count >= forcedMinimumWords, reference.count >= forcedMinimumWords,
            !allowed.contains(where: { unspaced.contains(Languages.language($0)) }),
            let constraint = LanguageDetection.constraint(allowed), Set(constraint).count > 1
        else { return nil }
        let dominant = LanguageDetection.hypothesis(
            text(reference), minimum: LanguageDetection.minimumConfidence, among: constraint)
        let heard = LanguageDetection.hypothesis(
            text(result), minimum: LanguageDetection.minimumConfidence, among: constraint)
        let challenge = Challenge(
            language: allowed.first { LanguageDetection.recognizerLanguage($0) == dominant },
            dominant: dominant, shown: shown(reference, among: constraint),
            constraint: constraint)
        let disagree = dominant != nil && heard != nil && dominant != heard
        return disagree || drops(result, challenge) ? challenge : nil
    }

    /// The redo in the reference's language when it reads as that language and comes at least as
    /// close to the reference as the result; otherwise the result, which is how a real
    /// correction stands: the stale stream's words forced into the old language do not read as
    /// it. Whichever it is, when it drops a second language the reference shows, the candidate
    /// closest to the reference that keeps every language it shows, or else the reference.
    static func settle(
        _ challenge: Challenge, result: [Word], reference: [Word],
        candidates: [(language: String, words: [Word])]
    ) -> [Word] {
        let target = normalized(reference)
        let distances = candidates.map { distance(normalized($0.words), target) }
        var pick = result
        if let language = challenge.language,
            let index = candidates.firstIndex(where: { $0.language == language }),
            agreement(candidates[index]) >= forcedAgreement,
            distances[index] <= distance(normalized(result), target)
        {
            pick = candidates[index].words
        }
        guard drops(pick, challenge) else { return pick }
        return candidates.indices
            .filter {
                challenge.shown.isSubset(
                    of: shown(candidates[$0].words, among: challenge.constraint))
            }
            .min { distances[$0] < distances[$1] }
            .map { candidates[$0].words } ?? reference
    }

    /// Whether `words` lose a language the reference shows besides its own.
    private static func drops(_ words: [Word], _ challenge: Challenge) -> Bool {
        !challenge.shown.subtracting(shown(words, among: challenge.constraint))
            .subtracting(challenge.dominant.map { [$0] } ?? []).isEmpty
    }

    /// The spoken languages some run of `runWords` words reads as surely.
    private static func shown(_ words: [Word], among constraint: [NLLanguage]) -> Set<NLLanguage> {
        let tokens = text(words).split(separator: " ")
        guard tokens.count >= runWords else { return [] }
        // Only one language can read at 0.9 or more.
        return Set(
            (0...(tokens.count - runWords)).compactMap { start in
                LanguageDetection.hypothesis(
                    tokens[start..<start + runWords].joined(separator: " "),
                    minimum: runConfidence, among: constraint)
            })
    }

    static func text(_ words: [Word]) -> String { words.map(\.word).joined(separator: " ") }

    /// Live words are lower case and mostly unpunctuated, a second pass's are not.
    private static func normalized(_ words: [Word]) -> [String] {
        text(words).split(separator: " ")
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
    }

    /// Word edit distance.
    private static func distance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs.count + rhs.count }
        var previous = Array(0...rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1]
            for (column, right) in rhs.enumerated() {
                current.append(
                    min(
                        previous[column + 1] + 1, current[column] + 1,
                        previous[column] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
