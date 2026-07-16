#!/usr/bin/env bash
set -euo pipefail

# Regenerate k8s/nginx/static/stars.gif (~5s seamless loop).
# Run on the Mac (needs python3). apply-app does not call this; the GIF is a
# checked-in static asset so destroy/recreate keeps working via /vagrant sync.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ROOT}/k8s/nginx/static/stars.gif"
FRAMES="${FRAMES:-50}"
DURATION_MS="${DURATION_MS:-100}"  # 50*100ms = 5s

VENV="${TMPDIR:-/tmp}/gifvenv"
if [[ ! -x "${VENV}/bin/python" ]]; then
  python3 -m venv "${VENV}"
  "${VENV}/bin/pip" install -q Pillow
fi

"${VENV}/bin/python" - <<PY
import random
from pathlib import Path
from PIL import Image, ImageDraw

W, H = 400, 225
BG = (15, 77, 143)
FRAMES = ${FRAMES}
DURATION_MS = ${DURATION_MS}
N_STARS = 90
OUT = Path("${OUT}")

rng = random.Random(42)
stars = []
for _ in range(N_STARS):
    stars.append({
        "x": rng.uniform(0, W),
        "y": rng.uniform(0, H),
        "r": rng.choice([1, 1, 1, 2, 2, 3]),
        "c": rng.choice([(255, 255, 255), (220, 235, 255), (180, 210, 255), (255, 255, 200)]),
    })

frames = []
for i in range(FRAMES):
    ox = (i * W) / FRAMES
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    for s in stars:
        x = (s["x"] - ox) % W
        y = s["y"]
        r = s["r"]
        c = s["c"]
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
        if x < r:
            d.ellipse([x - r + W, y - r, x + r + W, y + r], fill=c)
        if x > W - r:
            d.ellipse([x - r - W, y - r, x + r - W, y + r], fill=c)
    frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=32))

OUT.parent.mkdir(parents=True, exist_ok=True)
frames[0].save(
    OUT,
    save_all=True,
    append_images=frames[1:],
    duration=DURATION_MS,
    loop=0,
    optimize=True,
)
print(f"wrote {OUT} size={OUT.stat().st_size} cycle_ms={FRAMES * DURATION_MS}")
PY
