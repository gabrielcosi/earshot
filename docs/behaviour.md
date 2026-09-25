# Platform behaviour

What the speech engine, Core Audio, and Apple's frameworks actually do, established by experiment on Apple silicon with macOS 27. Each entry says how it was measured. The engine entries are for NeMo-Speech.cpp 0.1.0 (`97a15af`) with the Metal build, `nemotron-3.5-asr-streaming-0.6b` q8_0, and `Nemotron-3-Diarization` q8_0; re-measure after an engine or model update.

## Engine: realtime WebSocket

- **Endpointing is off unless the config enables it.** Without `asr.endpointing.enable: true`, a realtime session returns one final when the client commits, however long the session and however many pauses it contains. Measured: three turns with 2 s of silence between them came back as one final; with endpointing on, as three.
- **Endpointing depends on real-time pacing.** The same clip streamed at 5x real time with 0.75 s pauses produced no intermediate finals. The live tests stream at 1x for this reason.
- **Small messages stall a session while another session is open.** The engine coordinates input across the sessions that share the recognizer. With a microphone session open next to it, a session fed the process tap's ~10 ms buffers (342 bytes) is processed at 0.41x real time: its finals arrive 6–9 s after the speech, and the engine drops the connection after 25–35 s without a close frame. The same buffers on a lone session keep up. Coalesced into 100 ms messages, both sessions keep real time. Measured with two concurrent clients and a packet capture of the app.
- **A commit is answered in about 100 ms.** The engine sends the last final and then `input_audio_buffer.committed`. Measured: 97 ms from sending the commit to receiving `committed`.
- **Realtime audio counts against `max-upload-mb`.** The server adds every PCM chunk of a session to one upload budget and rejects the session when it exceeds the limit. At 16 kHz PCM16 (32 KB/s), the default 512 MB ends a session after about 4.5 hours. `config/server.yaml` sets 2048 MB.
- **Finals carry no language.** The realtime `completed` event has `transcript`, `words`, and `audio_processed`, but not the detected language, even with `language: auto`. The HTTP `verbose_json` response has it. The app detects the language of each utterance itself.
- **Word times are relative to the start of the session**, in seconds. Speaker slots are 1-based, in order of first appearance, and absent when diarization is off.
- The request `model` field is ignored. The server uses its one loaded ASR model.

## Engine: word boosting

- **Boosting needs the tokenizer embedded in the GGUF.** The August Nemotron 3.5 file (revision `1c8deaec`, which the engine's index pins) lacks `asr.tokenizer.spm_model`; the engine logs "no phrases could be tokenized … boosting disabled" and ignores `speech_contexts`. NVIDIA's re-conversion (revision `ea30d66d`, 2026-09-10) embeds it, and the app's catalog uses that file.
- **Boost 3 fixes names the recognizer nearly gets.** A sentence with the invented names "Zentari" and "Quorvex" came back as "Xanteri" and "Qurvex" without boosting and right with boosting at 3. Sentences without boosted names came back unchanged. A third name, "Velmora", came back partly doubled ("Vilmora Velmora's"): boosting can repeat a word it is pushed towards.

## Engine: language

The model has prompts for about 100 locales (the `asr.rnnt.prompt_dictionary` GGUF key), plus `auto`.

- **`auto` works for the major European languages.** Separate utterances in English, German, Spanish, and Italian were each detected and transcribed correctly.
- **`auto` fails on Romanian.** It produced Cyrillic text. Setting `ro-RO` explicitly gave a correct transcript. For such languages, pin the language in the menu.
- **A language switch inside one stream loses the first one or two words.** With English, German, and Spanish turns in one session, the language followed each switch, but "Vielen Dank" became "feeling dunk" and "Estoy de acuerdo" became "Ist durch de acuerdo". The same turns sent as separate requests were transcribed without errors. The app transcribes each final's audio again as a separate HTTP request and swaps in the result: with 0.6 s pauses between English, German, and Spanish turns, the live stream wrote the Spanish opening "Estoy de acuerdo" as "Ich doile", and the second pass heard it correctly. A clip that holds several languages loses words even offline, so the second pass depends on endpointing having cut the finals at the switches.
- **Pinning the wrong language is worse than `auto`.** With `en-US` pinned, the German and Spanish turns were garbled.

## Engine: diarization

- **Speaker separation does not depend on language.** In mixed-language clips, the speakers were separated across language switches.
- **Live speaker tags land a word or two off at turn boundaries.** The live diarizer decides on about a second of audio and the word times trail the speech, so the last words of one speaker are tagged with the next (with three voices 0.6 s apart, "verschieben Estoy de acuerdo, | pero"). Diarizing the whole recording in offline mode (`POST /v1/audio/diarizations`, `mode=offline`) gives the turns, but placing the refined words into them by time still hands a turn's last word to the next speaker at quick changes: word times are emission times, starting 0.2-0.7 s and ending 0.06-0.34 s after the speech (on `say` voices, a turn's last word was timed entirely after the voice had stopped), and the engine pads each turn 0.229 s before and 0.079 s after what it heard (`pad_onset`/`pad_offset` in the diarizer's postprocessing), so with a 0.15 s gap two of seven boundary words moved to the wrong speaker, and on a four-voice podcast 18 words at 26 turn changes. Transcribing each turn's audio on its own (`POST /v1/audio/transcriptions` on the turn's slice) puts every word with its speaker: 0 errors at 14 synthetic turn changes with 0 and 0.15 s gaps. The app does this when a session stops. Live words that no turn covers (on the podcast, 32 of 652: an intro over music and a stretch of three voices at once) stay under "Unknown speaker": the live pass numbers speakers independently of the offline one, so its slot would name the wrong person.
- **Offline diarization holds about 6.6 minutes.** Full attention is bounded by 5,000 encoder frames of 80 ms (`pos_emb_max_len`); a longer recording fails and returns no turns. `mode=streaming` covers long-form audio: a 7.6-minute recording of two `say` voices came back with both speakers across the whole length, in 12.7 s. The app uses offline mode up to the limit and streaming beyond it; either way each turn is then transcribed from its own audio.
- **Similar synthetic voices can share a slot.** In a streamed English, German, and Spanish clip, the English and German `say` voices were assigned the same speaker. Offline passes over the same audio separated them. Real voices are not yet measured.

## Engine: process and startup

- **The engine outlives the app that started it.** It is a plain child process, and macOS has no signal for a parent's death: after `kill -9` of its parent, the engine kept running with parent PID 1, still listening. With `--exit-with-parent` (Earshot's patch) it exits within about 0.5 s, measured, as its parent PID changes.
- **`listener.ready` sits in a buffer when stdout is a pipe.** Without a flush, the event with the bound address only arrived when the engine exited; Earshot's patch flushes it.
- **A model the configuration names but the app does not pass is downloaded.** With `diar.model_path` in the configuration and no `--diar-model`, the engine fetched the 113 MB diarizer from Hugging Face into its cache before listening. The configuration names no models.
- **SIGTERM does not stop an engine a client is connected to.** The shutdown watcher in `app/serve.cpp` stops only the listening socket; the server then joins its worker threads, which keep serving the open WebSocket connections. During a session the engine was still running more than 2 s after SIGTERM, and an app that waited for it hung, since the connections were its own. With no connection open it exits 60–590 ms after SIGTERM over 13 runs (both models loaded, 1 s after `listener.ready`, timed from `kill -TERM` to `wait` returning in a shell). Earshot waits 1 s, then sends SIGKILL.

- **A cold start takes about 6 s** from `nemo-speech serve` to `/ready` returning 200 on a recent Apple silicon Mac, loading about 810 MB of GGUFs.

## Core Audio: process tap sample rate

- **The tap reports the aggregate device's nominal rate, not the rate the audio arrives at.** A private aggregate device defaults to 48 kHz. The output device clocks the audio, so on a 44.1 kHz output the tap delivers 44,100 samples per second labelled as 48 kHz. Measured: on a 44.1 kHz output, the system audio's timestamps ran 8% short of the microphone's over a long recording, the ratio 0.919 = 44.1 / 48. With the aggregate's nominal rate set to the output's rate, `kAudioTapPropertyFormat` reports 44,100 Hz.
- **The output device can change mid-session**, for example when headphones connect. The tap follows the device it was built on, so `SystemAudioCapture` rebuilds it when the default output device or its nominal rate changes.

## Echo cancellation

Measured with the fixtures played through a Mac's speakers as the remote side, the built-in microphone recording the room, and the process tap's audio as the reference. The bleed sat about 20 dB under the speakers' level and 20 dB above the room's noise, and the engine transcribed all of it.

- **WebRTC AEC3 cancels it below the room's noise.** With the reference fed as the tap delivers it, 50 to 150 ms ahead of the microphone, the bleed fell from -28 dBFS to -55 to -58 dBFS, and the engine transcribed nothing from it in every run. High-pass filter on, no gain control, no noise suppression; about 1.3 % of one core.
- **The reference must lead the microphone.** AEC3 searches for the echo up to about 500 ms behind its reference and never ahead of it. Aligned exactly with the microphone, it cancelled only 9 dB. The tap leads the microphone by 90 to 100 ms (the 4096-frame input tap plus device latencies), which is inside the search.
- **A talker in the room survives, trimmed in exact double talk.** A second clip mixed into the microphone came through and was transcribed, except one phrase that overlapped the remote side word for word.
- **Only one clock.** The built-in microphone and speakers share a clock. A reference stretched by 1000 ppm, as a USB or Bluetooth microphone on its own clock would see, degrades the cancellation.
- **VoiceProcessingIO cannot take the tap as reference.** Apple's unit cancels what the same audio unit plays. Fed the speakers from another process, its residual was still transcribed in 3 of 8 runs, and it ducks other audio while it runs.
- **SpeexDSP reaches 11 to 16 dB** with the same reference; the engine still transcribed most of the residual.

## Apple Translation

- `TranslationSession(installedSource:target:preferredStrategy:)` works outside SwiftUI. It needs macOS 26.4.
- **Romanian is unsupported** as a source language (`LanguageAvailability.status` returns `.unsupported`). Romanian utterances are transcribed but not translated.
- Pairs that are `.supported` but not `.installed` need the SwiftUI `translationTask` prompt to download their language pack.

## Core Audio: which process plays

- **Apps play from helpers.** Chromium and Electron apps (measured: Discord) play from helper processes whose parent is the app. WebKit apps each get their own media process with launchd as its parent, which macOS names after the app ("Safari Graphics and Media", "Mail Graphics and Media"). Measured by listing `kAudioHardwarePropertyProcessObjectList` with each process's PID, bundle identifier, and `NSRunningApplication`.
- **Daemons keep outputs open.** `com.apple.CoreSpeech` reported `kAudioProcessPropertyIsRunningOutput` with nothing audible playing; it has no `NSRunningApplication`, so it is not offered as a source.
- **A tap by bundle identifier does not follow helpers.** With a video playing in Safari, a tap of `CATapDescription.bundleIDs = ["com.apple.Safari"]` delivered no samples in 3 s; `["com.apple.WebKit.GPU"]` delivered the video at -22 dBFS, as it would any WebKit app's sound.
- **A command-line player has no app.** `afplay` reports as playing but has no bundle identifier or `NSRunningApplication`, so it is not offered either.

## AAC and playback of kept audio

Measured with `AVAudioFile` writing AAC on macOS 27.

- **A bitrate sets how much of the band survives.** Tones under noise, stereo: at 24 kHz, 64 kbit/s already passes everything up to 12 kHz; at 48 kHz, 96 kbit/s cuts above 16 kHz and 128 kbit/s reaches about 17 kHz. On `say` speech, the error against the input was 23 dB at 16 kHz and 64 kbit/s, 19.5 dB at 24 kHz and 64 kbit/s, 23 dB at 24 kHz and 96 kbit/s, and 28 dB at 48 kHz and 128 kbit/s.
- **Size follows the bitrate, less in pauses.** With both sides speaking without a pause, an hour came to 34 MB at 16 kHz and 64 kbit/s, 47 MB at 24 kHz and 96 kbit/s, and 62 MB at 48 kHz and 128 kbit/s. On the test fixtures, with pauses and the microphone speaking part of the time, it came to 27, 36, and 43 MB.
- **Encoding runs far faster than real time**: about 400 times at 16 kHz and 130 times at 48 kHz, so an hour at High takes about 27 s.
- **A mixer summing stereo into mono takes each side down 3 dB.** Through an `AVAudioMixerNode` connected in mono, 0.5 on one channel came out 0.354 in both ears of the stereo output, and 0.5 on both came out 0.707. Earshot adds 3 dB after it, so a side alone plays at its recorded level, and Apple's peak limiter (`kAudioUnitSubType_PeakLimiter`) after that: both sides at 0.8 came out at 0.95, and one side alone at 1.0 at 0.999.
