#!/usr/bin/env python3
"""Watches the queue for utterances and turns them into a transcript.

Runs as a daemon with the Whisper model held in memory - loading it per file
would cost several seconds each time and fall hopelessly behind a conversation.

Defaults to CPU on purpose. The GPU in this machine is busy running the game
we're transcribing people talking about, and a 16-thread Ryzen handles short
utterances comfortably faster than real time. Set EARSHOT_DEVICE=cuda if you're
transcribing on a machine that isn't also playing GTA.
"""
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from faster_whisper import WhisperModel

HERE = Path(__file__).resolve().parent
QUEUE = Path(os.environ.get("QUEUE_DIR", HERE / "queue"))
TRANSCRIPTS = Path(os.environ.get("TRANSCRIPT_DIR", HERE.parent.parent / "transcripts"))

MODEL = os.environ.get("EARSHOT_MODEL", "small.en")
DEVICE = os.environ.get("EARSHOT_DEVICE", "cpu")
COMPUTE = os.environ.get("EARSHOT_COMPUTE", "int8")

# Whisper will confidently invent speech in silence. These are the usual
# suspects it produces from room tone, and they poison the digest.
HALLUCINATIONS = {
    "you", "thank you", "thanks for watching", "bye", "thank you.",
    "thanks for watching!", "you.", ".", "okay", "bye.", "so",
}


def transcript_path() -> Path:
    TRANSCRIPTS.mkdir(parents=True, exist_ok=True)
    return TRANSCRIPTS / f"session-{datetime.now().strftime('%Y%m%d')}.jsonl"


def parse(name: str):
    """`1753312345678__Jacob.wav` -> (timestamp, speaker)."""
    stem = Path(name).stem
    epoch_ms, _, speaker = stem.partition("__")

    try:
        when = datetime.fromtimestamp(int(epoch_ms) / 1000, tz=timezone.utc)
    except ValueError:
        when = datetime.now(tz=timezone.utc)

    return when, (speaker or "unknown")


def main() -> None:
    QUEUE.mkdir(parents=True, exist_ok=True)

    print(f"[earshot] loading {MODEL} on {DEVICE} ({COMPUTE})...", flush=True)
    model = WhisperModel(MODEL, device=DEVICE, compute_type=COMPUTE)
    print(f"[earshot] ready, watching {QUEUE}", flush=True)

    while True:
        # Oldest first, so the transcript stays in the order things were said.
        files = sorted(QUEUE.glob("*.wav"), key=lambda p: p.name)

        if not files:
            time.sleep(0.5)
            continue

        for wav in files:
            try:
                segments, _ = model.transcribe(
                    str(wav),
                    beam_size=1,
                    vad_filter=True,
                    condition_on_previous_text=False,
                )
                text = " ".join(s.text.strip() for s in segments).strip()
            except Exception as error:  # noqa: BLE001 - a bad file must not kill the daemon
                print(f"[earshot] failed on {wav.name}: {error}", file=sys.stderr, flush=True)
                wav.unlink(missing_ok=True)
                continue

            wav.unlink(missing_ok=True)

            if not text or text.lower().strip(" .!?") in HALLUCINATIONS:
                continue

            when, speaker = parse(wav.name)
            line = {"t": when.isoformat(), "speaker": speaker, "text": text}

            with transcript_path().open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(line, ensure_ascii=False) + "\n")

            print(f"[earshot] {speaker}: {text}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[earshot] stopped")
