#!/usr/bin/env bash
# Regenerates the live-test clips with macOS voices: 16 kHz mono PCM16 WAV.
set -euo pipefail

out="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Tests/EarshotKitTests/Fixtures"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

clip() { # name voice text
  say -v "$2" -o "$work/$1.aiff" "$3"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$work/$1.aiff" "$work/$1.wav"
}

join() { # output gap-seconds clips...
  local output="$1" gap="$2"
  shift 2
  /usr/bin/python3 - "$output" "$gap" "$@" <<'PY'
import sys, wave
out = wave.open(sys.argv[1], "wb")
out.setnchannels(1); out.setsampwidth(2); out.setframerate(16000)
silence = b"\0\0" * int(16000 * float(sys.argv[2]))
for path in sys.argv[3:]:
    clip = wave.open(path)
    out.writeframes(clip.readframes(clip.getnframes()) + silence)
out.close()
PY
}

clip en1 Samantha "Good morning everyone, let's start with the quarterly numbers."
clip en2 Daniel "Thanks. Revenue grew twelve percent, mostly from the new storage product."
clip de Anna "Ich glaube, wir sollten die Lieferung auf nächste Woche verschieben."
clip es "Mónica" "Estoy de acuerdo, pero necesitamos confirmar con el cliente primero."
clip names Samantha "Jane Doe said we should ask the Zentari team about the Quorvex deal before Velmora goes live."
clip ro Ioana "Mulțumesc. Ce riscuri avem pentru trimestrul următor?"
clip en3 Samantha "So let's talk about how often a plan should change during the week."
clip en4 Daniel "Every day, honestly, the plan is a guess and the week corrects it."

join "$out/two-speakers.wav" 2 "$work/en1.wav" "$work/en2.wav"
join "$out/three-languages.wav" 2 "$work/en2.wav" "$work/de.wav" "$work/es.wav"
# Invented names. Without vocabulary boosting: "the Xanteri team about the Qurvex deal".
join "$out/names.wav" 1 "$work/names.wav"
# Auto-detection writes this Romanian turn in Cyrillic.
join "$out/romanian.wav" 1 "$work/ro.wav"
# Shorter than the 0.8 s endpointing pause: all three languages land in one final.
join "$out/quick-switch.wav" 0.6 "$work/en2.wav" "$work/de.wav" "$work/es.wav"
# Turns 0.15 s apart, shorter than the 0.3-0.5 s the engine's word times trail the speech by.
join "$out/quick-turns.wav" 0.15 "$work/en1.wav" "$work/en2.wav" "$work/en3.wav" "$work/en4.wav"
