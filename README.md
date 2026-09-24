![Earshot app icon](docs/assets/icon.png)

# Earshot

**Every word your Mac hears, on your Mac.** Live transcripts with speakers and translation, fully on-device.

**[Download for macOS](https://github.com/gabrielcosi/earshot/releases/latest)**

Earshot lives in the menu bar of Apple silicon Macs running macOS 26.4 or newer. Start listening when a call begins, or when a video or podcast plays, in any app: it transcribes what you say and everything the Mac plays, tells the speakers apart, and translates what is not in your language as it goes.

- **Nothing leaves your Mac.** Speech recognition and speaker detection run on the Mac's GPU with NVIDIA's Nemotron models. Translation and summaries use Apple's on-device models.
- **You and everyone else.** Your microphone is always "Me". Everything the Mac plays is split into up to eight speakers, and you name them when you stop.
- **Many languages at once.** Recognition follows the language each person speaks, and anything not in your language is translated.
- **Plain files.** Every transcript is a Markdown file, saved after each finished line.

## Install

1. [Download the latest DMG](https://github.com/gabrielcosi/earshot/releases/latest) and open it.
2. Drag `Earshot.app` into Applications, then launch it.
3. Earshot opens the Model Library. Download a transcription model, and a speaker detection model if you want speakers.

The first time you start listening, macOS asks for two permissions:

- **Microphone** lets Earshot transcribe what you say. It is only needed while **Include my microphone** is on.
- **System Audio Recording** lets Earshot hear the other side of the call, from whatever app plays it.

Earshot checks for signed updates automatically. Use **Check for Updates…** in About to check now.

## Use

Click the ear in the menu bar and choose **Start listening**. The transcript window opens and fills in as people speak. Choose **Stop** when you're done: Earshot tidies the speaker boundaries and asks you to name the speakers, with a few of their lines to read and play.

- **Spoken** in the menu sets which languages are spoken, so Earshot ignores languages it mishears in noise.
- **Translate into** your language translates every line in another language. macOS asks to download a language pair the first time it is needed.
- **Listening to** in the menu picks the apps to transcribe, for a call next to music or a video. It starts on all apps. Two tabs in the same browser count as one app.
- **Include my microphone** can be turned off to transcribe a podcast or a video with nobody talking over it.
- **Words** holds names and terms Earshot should recognize, and replacements to apply to the text.
- **Summarize** adds an overview, decisions, and action items to a transcript's file, every time you stop if you turn that on in Settings. Apple Intelligence writes them unless you choose an endpoint.
- **Keep audio** saves your microphone and what the Mac plays next to the transcript, about 23 MB an hour, so you can play back any line.

Transcripts are saved to Earshot's own folder, or to a folder you choose in **Settings > Transcripts**.

## Privacy

Audio never leaves your Mac. Recognition, speaker detection, and translation all run locally, and audio is only written to disk when **Keep audio** is on.

Earshot goes online for three things:

- **Models** download from Hugging Face when you choose them in the Model Library.
- **Updates** are checked against this repository's GitHub releases.
- **Summaries**, only when you choose an OpenAI-compatible or Anthropic endpoint instead of Apple Intelligence. The transcript text is then sent to that endpoint. Its API key is kept in your keychain.

## Troubleshooting

**The other side of the call is missing.** Check that Earshot is allowed under **System Settings > Privacy & Security > Screen & System Audio Recording**.

**Every line appears twice, once as "Me".** Without headphones, the microphone hears the other side of the call through the speakers. Use headphones, or turn on **Cancel speaker echo** in **Settings > Microphone** when you listen on speakers. When you are only listening, turn off **Include my microphone**.

**A language comes out wrong.** Choose the languages that are spoken under **Spoken**. With one language chosen, Earshot transcribes only that language.

**Names come out misspelled.** Add them in **Words**. Earshot listens for them and fixes them in the final text.

## Contributing

Building, tests, and releases are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0, see [LICENSE](LICENSE). Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
