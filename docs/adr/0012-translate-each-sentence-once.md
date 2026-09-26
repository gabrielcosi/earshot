# ADR-0012 — Translate each sentence once, in one queue

- **Status:** Accepted
- **Date:** 2026-09-26
- **Deciders:** gabrielcosi
- **Supersedes:** [ADR-0003](0003-apple-translation-per-utterance.md)
- **Scope:** What is translated, when, with which strategy, and what the window, the captions overlay, and the store show of it

## Context

[ADR-0003](0003-apple-translation-per-utterance.md) translated each finished utterance with the low-latency strategy and did not translate partials. By this release the app translated partials with `.lowLatency` and paragraphs with `.highFidelity`, and a paragraph is a speaker's whole turn: finals of the same speaker join it however long the pauses. Each final sent the whole paragraph again, and so did its refinement, each as its own request with nothing to stop a superseded one. A slow two-minute monologue came to about 29,000 characters of `.highFidelity` work for 90 s of speech, and the overlay trailed the speaker by 25–35 s. At the end of a session, relabelling rebuilt every remote paragraph from its turn's audio with new ids, so every translation was dropped and made again, and the first Markdown file had none.

Apple's Translation service runs one request at a time, across sessions too, and a request right after one of the other strategy's takes 300–400 ms longer. `translate(_:)` cannot be stopped early: cancelling the calling task only makes it throw once it is done. A `.highFidelity` request drops sentences from the middle of text longer than about 7,000 characters without an error ([behaviour](../behaviour.md#apple-translation)).

## Decision

**Each sentence is translated once, with `.lowLatency`, in one queue that runs one request at a time. A paragraph's translation is joined from its sentences'.**

- A paragraph is split into sentences with NaturalLanguage's sentence tokenizer. A sentence is detected on its own, so a paragraph that switches language is translated sentence by sentence. A sentence detected with less than 0.74 confidence takes its paragraph's language: one-word sentences such as "Ja." read as another language as often as not.
- The session keeps each sentence's outcome by its text: translated, kept (already in the target language, or too short to tell), unavailable (the pair needs a download or is unsupported), or failed. It is cleared when a session starts, the target language changes, or translation is turned on; a downloaded pair clears the unavailable ones.
- A paragraph shows its sentences' translations in order, up to the first sentence without an outcome; kept, unavailable, and failed sentences show as they were said. It is settled when every sentence has an outcome, and only then is its translation stored, against the paragraph's text. A refinement or a longer paragraph asks only for the sentences whose text changed.
- The queue holds the sentences without an outcome, the newest paragraph first, rebuilt after every change, so a sentence rewritten before its turn is never sent. Each channel's words in flight have one slot, and only the latest text waits. When both wait, they take turns: words in flight wait for at most the sentence being translated, and a speaker who never pauses still gets their sentences translated.
- Showing translations alone, a finished line waits until one of its sentences has an outcome, unless it carries a live translation; from then on it stays, while sentences merged into it later are translated, and through a change of language, as it was said until its new translation comes. Words in flight too short to tell their language show as they are, as the translator leaves them.
- A final keeps the live translation of the words it closes, shown after the paragraph's translated sentences until one of that final's sentences has its own outcome, so no sentence shows twice. A finished line never goes blank while it is translated. A new target language drops it.
- Relabelling looks up the rebuilt paragraphs' sentences in the session's outcomes before the session is sealed, so what was translated while listening is in the window and the first Markdown file at once. The rest is translated newest first, and the file is exported again as it lands.
- A pair that needs a download or is unsupported is reported once, by a sentence, not for each sentence. Words in flight are detected alone, and one word reads as another language, so they never report a pair; they only mark its language, and words in it show as they are, even once the problem is dismissed. A download asks for the models of the strategy used.
- A paragraph's stored translation is written again whenever it changes: another language, or a sentence translated after its pair was downloaded.
- The `translation` log category records each sentence's request as a `.notice` and each partial's as a `.debug`: characters, time waited and taken, sentences waiting, and the outcome. A summary follows relabelling at the end of a session; the sentences translated after relabelling are logged but not in it. It never records text.

## Consequences

- The work grows with what is said, not with its square: a simulated two-minute monologue requests 2.8 times the characters spoken, each final and refinement included, and twice as long a monologue twice that. Each sentence is translated within a second of the final that finished it.
- A sentence is translated without the sentences around it: a pronoun or an elided subject can come out worse than it would in a whole paragraph.
- `.lowLatency` reads less fluently than `.highFidelity` would on the same sentence.
- A final that ends mid-sentence has its fragment translated, and the sentence again once it is complete.
- A sentence whose translation failed is not tried again in the session: it shows as it was said, as a failed paragraph did before.
- A turn's audio decoded again at the end of a session does not always give the same sentence: another word, a capital, or a full stop makes it a new sentence to translate. On the test fixtures, a third to three fifths of the sentences were reused.

## Rejected

- **The paragraph at every final.** It is the cost this replaces: quadratic in the length of a turn.
- **Each final's words, as a segment.** A slow speaker's final is a fragment of a sentence, and German puts verbs at the end of a clause.
- **`.highFidelity` for finished sentences.** It takes 0.4–0.9 s a sentence, and switching strategies between them and partials makes a partial wait more than a second behind one.
- **Requests in parallel.** The service runs them one at a time, and a partial beside a sentence waits longer than one queued behind it.
- **Translating a whole paragraph again when its turn ends or the session stops.** A monologue's turn ends only at stop, a 4,000-character paragraph takes about 10 s with `.highFidelity`, longer paragraphs lose sentences without an error, and it would change text the user is already reading.
- **Waiting for a final's refinement before translating it.** Every line would wait for the second pass; translating the final and then the sentences the refinement changed costs at most a sentence.
