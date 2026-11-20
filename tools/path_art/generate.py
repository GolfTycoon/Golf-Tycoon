#!/usr/bin/env python3
"""Bake the walking-path surface textures.

The Path is one canvas mesh of tinted bands (see ``WalkingPathOverlay``): a
dirt trail with a polished crown and grass verges, or a paved promenade with
kerbs and flag joints.  Those bands carry the shape and the colour; what they
lack is *grain* -- at one tile per 64x32 pixels a flat brown ribbon reads as
paint next to the pebbled terrain tiles.

This tool bakes two small, seamlessly tiling **detail maps** that the overlay
multiplies over its vertex colours:

    assets/sprites/paths/dirt.png     packed earth, grit, pebbles
    assets/sprites/paths/paved.png    dressed stone, chips, fine joints

Both are mostly near-white, so the trail keeps the tint the draw commands
chose, and dark specks only add the grit.  The textures are committed, so the
game and the tests need only Godot.

Run from the repository root:

    python3 tools/path_art/generate.py
    python3 tools/path_art/generate.py --check
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "paths")
SIZE = 64


def _wrap(x: float, y: float, r: int, size: int = SIZE):
    """Every wrapped copy of a small square stamp, so the tile is seamless."""
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            px = int(round(x)) + dx
            py = int(round(y)) + dy
            if -r <= px < size + r and -r <= py < size + r:
                yield px, py


def _stamp(canvas: np.ndarray, x, y, r, colour, alpha=1.0):
    for px, py in _wrap(x, y, r):
        x0, x1 = max(0, px - r), min(SIZE, px + r + 1)
        y0, y1 = max(0, py - r), min(SIZE, py + r + 1)
        if x0 >= x1 or y0 >= y1:
            continue
        patch = canvas[y0:y1, x0:x1]
        patch[:] = patch * (1.0 - alpha) + np.array(colour) * alpha


def _blade(canvas: np.ndarray, x, y, length, lean, colour):
    for i in range(length):
        px = int(round(x + lean * i))
        py = int(round(y - i))
        for wx, wy in _wrap(px, py, 0):
            if 0 <= wx < SIZE and 0 <= wy < SIZE:
                canvas[wy, wx] = np.minimum(1.0, canvas[wy, wx] * 0.85 + np.array(colour) * 0.15)


def _grain(canvas: np.ndarray, rng, amount: float, low: float, high: float):
    noise = rng.normal(0.0, amount, (SIZE, SIZE, 1))
    return np.clip(canvas * (1.0 + noise), low, high)


def dirt() -> np.ndarray:
    rng = np.random.default_rng(0xD17A)
    canvas = np.ones((SIZE, SIZE, 3), dtype=np.float32)
    canvas[:] = np.array([0.98, 0.95, 0.89])
    # Broad trodden patches, wrapped, to break up the repeat.
    for _ in range(14):
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), 5,
               (0.93, 0.88, 0.80), 0.16)
    # Grit: dark packed-earth specks.
    for _ in range(150):
        r = 0 if rng.random() < 0.72 else 1
        tone = rng.uniform(0.62, 0.82)
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), r,
               (tone, tone * 0.94, tone * 0.84), rng.uniform(0.45, 0.9))
    # Loose pebbles with a lit top edge.
    for _ in range(26):
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE)
        tone = rng.uniform(0.80, 1.0)
        _stamp(canvas, x, y, 1, (tone * 0.96, tone * 0.92, tone * 0.84), 0.95)
        _stamp(canvas, x - 0.5, y - 0.5, 0, (1.0, 0.98, 0.92), 0.85)
    # A few blades of grass creeping onto the earth.
    for _ in range(12):
        _blade(canvas, rng.uniform(0, SIZE), rng.uniform(2, SIZE),
               int(rng.integers(2, 4)), rng.uniform(-0.4, 0.4),
               (0.80, 0.92, 0.66))
    canvas = _grain(canvas, rng, 0.035, 0.55, 1.0)
    return canvas


def paved() -> np.ndarray:
    rng = np.random.default_rng(0xFA7E)
    canvas = np.ones((SIZE, SIZE, 3), dtype=np.float32)
    canvas[:] = np.array([0.99, 0.98, 0.95])
    # Dressed slabs: subtle mottling and a few darker courses.
    for _ in range(10):
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), 6,
               (0.92, 0.91, 0.87), 0.26)
    for y in (10, 31, 52):
        for x in range(0, SIZE, 4):
            _stamp(canvas, x + rng.uniform(0, 2), y + rng.uniform(-0.6, 0.6),
                   0, (0.78, 0.77, 0.73), 0.75)
    # Chips and stone grain, never strong enough to read as a hole.
    for _ in range(110):
        r = 0 if rng.random() < 0.8 else 1
        tone = rng.uniform(0.70, 0.88)
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), r,
               (tone, tone, tone * 0.97), rng.uniform(0.35, 0.7))
    for _ in range(30):
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), 0,
               (1.0, 1.0, 0.98), 0.7)
    # A little moss in the joints.
    for _ in range(8):
        _stamp(canvas, rng.uniform(0, SIZE), rng.uniform(0, SIZE), 1,
               (0.82, 0.90, 0.72), 0.35)
    canvas = _grain(canvas, rng, 0.02, 0.65, 1.0)
    return canvas


TEXTURES = {
    "dirt": dirt,
    "paved": paved,
}


def build() -> dict[str, Image.Image]:
    out = {}
    for name, paint in TEXTURES.items():
        data = np.clip(np.round(paint() * 255.0), 0, 255).astype(np.uint8)
        out[name] = Image.fromarray(data, mode="RGB")
    return out


def write(check: bool) -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    built = build()
    stale = []
    for name, image in built.items():
        path = os.path.join(OUT_DIR, f"{name}.png")
        if check:
            if not os.path.exists(path):
                stale.append(path)
                continue
            committed = Image.open(path)
            if committed.size != image.size or committed.tobytes() != image.tobytes():
                stale.append(path)
        else:
            image.save(path)
            print("wrote", os.path.relpath(path, ROOT))
    if not check:
        return 0
    if stale:
        print("Stale path art (rerun tools/path_art/generate.py):")
        for path in stale:
            print("  " + os.path.relpath(path, ROOT))
        return 1
    print(f"Path art is current ({len(built)} textures).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if committed art is stale")
    args = parser.parse_args()
    return write(args.check)


if __name__ == "__main__":
    raise SystemExit(main())
