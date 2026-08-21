# iTranslate Realtime Translation MVP

Minimal local demo: mic → AssemblyAI realtime STT (Universal-3-5 Pro) → LLM Gateway translation → console "speak" output.

Two identical implementations are included since iTranslate is a Python/TypeScript shop — pick whichever matches who's in the room, or run both.

## Python

```bash
brew install portaudio
cd itranslate-mvp
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export ASSEMBLYAI_API_KEY=your_key_here
python translate_live.py --target es
```

## TypeScript

```bash
npm install
export ASSEMBLYAI_API_KEY=your_key_here
npm start -- --target es
```

`mic` (the Node package) shells out to `sox` for audio capture — install it first: `brew install sox` (macOS) or `apt install sox` (Linux).

Talk into your mic. Each time you pause, you'll see:

```
🎤 Where is the nearest train station?
  🔊 [es] ¿Dónde está la estación de tren más cercana?
```

## What this demonstrates

- **Realtime STT accuracy**: `universal-3-5-pro` model, `language_detection=True` (don't need to know the speaker's language ahead of time), `voice_focus="near-field"` (tuned for a handheld device held close to the mouth — noisy environments).
- **No GPU needed**: all inference (STT + translation) happens in AssemblyAI's cloud; the device only captures/streams audio and plays back audio. This matches iTranslate's hardware constraint directly.
- **Cloud round trip**: mic → WebSocket (realtime STT) → HTTP (LLM Gateway translation) → TTS. All calls are cloud API calls, nothing local except audio I/O.

## What's stubbed for MVP simplicity

- **TTS**: the `speak()` function just prints. On the real device, swap that function body for iTranslate's existing TTS call — everything upstream (transcription + translation) is unchanged.
- **Translation latency**: this MVP calls LLM Gateway as a separate HTTP request per finalized turn, for clarity/debuggability. Production should use the realtime WebSocket's inline `llm_gateway` connection param instead (translation returns as an `LLMGatewayResponse` event alongside the transcript, same socket, lower latency, no second round trip).
- **Auth**: uses the raw API key directly since this runs locally. On the real device, mint short-lived tokens (`GET /v3/token`) from iTranslate's backend so the raw key never lives on hardware — see the full recommendation doc for that pattern.

## Known limitation

Partial transcripts print but aren't translated (only `end_of_turn` transcripts are sent to LLM Gateway) — this keeps translation calls to one-per-utterance instead of one-per-partial. Fine for a demo; worth revisiting if the customer wants sub-utterance streaming translation.
