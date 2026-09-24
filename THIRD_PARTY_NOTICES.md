# Third-party notices

## Shipped with the app

- **[NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp)** by NVIDIA, Apache License 2.0. The `nemo-speech` engine and its libraries are built from the `vendor/NeMo-Speech.cpp` submodule and bundled in `Earshot.app/Contents/Helpers`. Its own third-party notices (among them ggml, cpp-httplib, and SentencePiece) are in the submodule's `THIRD_PARTY_NOTICES.md` and `NOTICE`.

- **[webrtc-audio-processing](https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing)**, the WebRTC audio processing module (AEC3) packaged by the PulseAudio project, BSD 3-Clause License (Google and the WebRTC project authors). Built from source by `mise run engine:aec` and linked into the app as a static library for the "Cancel speaker echo" setting.
- **[Abseil](https://github.com/abseil/abseil-cpp)** by Google, Apache License 2.0. Built as part of webrtc-audio-processing and linked into the same library.
- **[Sparkle](https://sparkle-project.org)**, MIT License. The update framework, in `Earshot.app/Contents/Frameworks`.

The license texts of all of these are copied into `Earshot.app/Contents/Resources/Licenses`, which About opens.

## Downloaded at run time, not shipped

The app downloads speech models from Hugging Face when you choose them in the Model Library. Each model's license is shown there and applies to that model:

- [Nemotron 3.5 ASR Streaming](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) and [Nemotron Speech Streaming](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b), NVIDIA Open Model License.
- [Nemotron 3 Diarization](https://huggingface.co/nvidia/Nemotron-3-Diarization), NVIDIA Open Model License (OpenMDW 1.1).
- [Streaming Sortformer v2](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2), CC-BY-4.0.

## In the tests

- `Tests/EarshotKitTests/Fixtures/model-index.json` is a copy of NeMo-Speech.cpp's `models/index.json` (Apache License 2.0).
- The audio fixtures are synthesized with macOS system voices by `scripts/fixtures.sh`.
