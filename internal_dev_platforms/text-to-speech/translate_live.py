"""
iTranslate MVP — realtime speech translation demo.

Pipeline:
  mic (PCM16 16kHz) -> AssemblyAI realtime STT (universal-3-5-pro)
                     -> on each finalized Turn, translate via LLM Gateway
                     -> print translated text (TTS hookup is a stub — see speak())

Run:
  pip install assemblyai sounddevice numpy requests
  export ASSEMBLYAI_API_KEY=your_key_here
  python translate_live.py --target es
"""

import argparse
import os
import queue
import sys

import numpy as np
import requests
import sounddevice as sd
from assemblyai.streaming.v3 import (
    StreamingClient,
    StreamingClientOptions,
    StreamingError,
    StreamingEvents,
    StreamingParameters,
    TurnEvent,
)

API_KEY = os.environ.get("ASSEMBLYAI_API_KEY")
if not API_KEY:
    sys.exit("Set ASSEMBLYAI_API_KEY in your environment first.")

SAMPLE_RATE = 16000
LLM_GATEWAY_URL = "https://llm-gateway.assemblyai.com/v1/chat/completions"

# Simple in-process queue: mic callback (audio thread) -> streaming client (main thread)
audio_q: "queue.Queue[bytes]" = queue.Queue()


def translate_text(text: str, target_lang: str) -> str:
    """One call to LLM Gateway for translation. Kept separate from the
    realtime `llm_gateway` connection param for MVP simplicity/visibility —
    swap to the inline per-turn config later if you want lower latency."""
    resp = requests.post(
        LLM_GATEWAY_URL,
        headers={
            "Authorization": API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": "qwen3.5-4b-32k-fast",
            "messages": [
                {
                    "role": "system",
                    "content": (
                        f"Translate the user's message into {target_lang}. "
                        "Reply with ONLY the translation, no notes."
                    ),
                },
                {"role": "user", "content": text},
            ],
            "max_tokens": 200,
        },
        timeout=10,
    )
    if not resp.ok:
        print(f"  [LLM Gateway response body]: {resp.text}")
    resp.raise_for_status()
    # LLM Gateway is OpenAI-compatible: choices[0].message.content, not
    # Anthropic-native content[0].text.
    return resp.json()["choices"][0]["message"]["content"].strip()


def speak(text: str, target_lang: str) -> None:
    """TTS stub. iTranslate already owns a TTS vendor/model on the real
    device — plug that call in here. For this MVP we just print."""
    print(f"  🔊 [{target_lang}] {text}")


def on_turn(client: StreamingClient, event: TurnEvent, target_lang: str):
    if not event.end_of_turn:
        print(f"  … {event.transcript}", end="\r")
        return

    print(f"\n🎤 {event.transcript}")
    try:
        translated = translate_text(event.transcript, target_lang)
    except Exception as e:
        print(f"  ⚠ translation failed: {e}")
        return
    speak(translated, target_lang)


def on_error(client: StreamingClient, error: StreamingError):
    print(f"⚠ streaming error: {error}")


def mic_callback(indata, frames, time_info, status):
    if status:
        print(status, file=sys.stderr)
    audio_q.put(bytes(indata))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="es", help="Target language, e.g. es, fr, ja")
    args = parser.parse_args()

    client = StreamingClient(StreamingClientOptions(api_key=API_KEY))
    client.on(StreamingEvents.Turn, lambda c, e: on_turn(c, e, args.target))
    client.on(StreamingEvents.Error, on_error)

    client.connect(
        StreamingParameters(
            sample_rate=SAMPLE_RATE,
            speech_model="universal-3-5-pro",
            mode="balanced",
            language_detection=True,
            voice_focus="near-field",
        )
    )

    print(f"Listening... translating to '{args.target}'. Ctrl+C to stop.\n")

    stream = sd.RawInputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="int16",
        blocksize=int(SAMPLE_RATE * 0.1),  # 100ms chunks
        callback=mic_callback,
    )

    try:
        with stream:
            while True:
                chunk = audio_q.get()
                client.stream(chunk)
    except KeyboardInterrupt:
        pass
    finally:
        print("\nClosing session...")
        client.disconnect(terminate=True)


if __name__ == "__main__":
    main()