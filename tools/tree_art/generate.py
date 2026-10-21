#!/usr/bin/env python3
"""Generate the four-angle (N / E / S / W) views of Golf Tycoon's tree sprites.

Run from the repository root:

    python3 tools/tree_art/generate.py            # write every view
    python3 tools/tree_art/generate.py --preview  # also draw a contact sheet
    python3 tools/tree_art/generate.py --check    # fail if a view is stale

Every species in `assets/sprites/trees/` (including the `spring/`, `fall/`
and `winter/` seasonal variants) is authored once, as the unsuffixed
`<species>.png`. That drawing is the tree seen from the north - the course's
default view orientation - and it is the source the other three angles are
derived from here:

    _n  the authored drawing, copied unchanged;
    _e  the east side: the crown foreshortened (squashed toward the trunk)
        and leaned a few pixels, lit from the right;
    _s  the south (back) side: mirrored, as a tree's east and west swap
        places when it is seen from behind, and shaded as the side away
        from the sun;
    _w  the west side: mirrored and foreshortened like the east, leaned
        and lit the opposite way.

Trees are close to radially symmetric, so four redraws would mostly repeat
the same silhouette; what changes between angles is where the asymmetric
limbs, highlights and lean fall, which is exactly what these derivations
move. Every view keeps its source's canvas size and ground line, so the
trunk stays planted on the same spot of its tile at every rotation and
`TreeOverlay.SPRITE_BASE_OFFSETS` needs no per-facing entry.

The `_n/_e/_s/_w` PNGs are generated art, like the building sprites: edit
the unsuffixed source and re-run this tool rather than editing a view by
hand. TreeOverlay picks the view matching the course's view orientation
and falls back to the unsuffixed source if a view is ever missing, so a
new species is playable the moment its north drawing lands.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITE_DIR = os.path.join(ROOT, "assets", "sprites", "trees")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")

# View orientations 0..3, in the order TreeOverlay.FACINGS lists them:
# the course compass (main.gd's VIEW_ORIENTATION_LABELS).
FACINGS = ("n", "e", "s", "w")

# How each angle is derived from the authored north view:
#   flip    mirror left-right (the back views: east and west swap places)
#   squash  horizontal foreshortening toward the trunk (the side views)
#   shear   crown lean in pixels at the crown's top for a 64px canvas,
#           scaled by each sprite's width; 0 at the ground line so the
#           trunk stays planted
#   light   (overall, gradient) brightness: a pixel is scaled by
#           overall + gradient * u, u being its offset from the trunk in
#           [-1, 1], quantised to 1/20 steps so the shading bands like
#           pixel art instead of washing the palette out
PROFILES = {
    "n": {"flip": False, "squash": 1.0, "shear": 0.0, "light": (1.0, 0.0)},
    "e": {"flip": False, "squash": 0.82, "shear": 3.0, "light": (0.98, 0.11)},
    "s": {"flip": True, "squash": 1.0, "shear": 0.0, "light": (0.88, -0.05)},
    "w": {"flip": True, "squash": 0.82, "shear": -3.0, "light": (0.98, -0.11)},
}


def source_sprites() -> list[str]:
    """Every authored (unsuffixed) tree sprite, seasonal folders included."""
    sources = []
    for dirpath, _dirs, files in os.walk(SPRITE_DIR):
        for name in sorted(files):
            if not name.endswith(".png"):
                continue
            stem = name[:-len(".png")]
            if any(stem.endswith("_" + facing) for facing in FACINGS):
                continue  # A generated view, not a source.
            sources.append(os.path.join(dirpath, name))
    return sorted(sources)


def view_path(source: str, facing: str) -> str:
    stem = source[:-len(".png")]
    return f"{stem}_{facing}.png"


def render_view(image: Image.Image, facing: str) -> Image.Image:
    """One angle of `image`, derived per PROFILES on the source's canvas."""
    profile = PROFILES[facing]
    drawn = image.convert("RGBA")
    if profile["flip"]:
        drawn = drawn.transpose(Image.FLIP_LEFT_RIGHT)
    width, height = drawn.size
    pixels = drawn.load()
    bbox = drawn.getchannel("A").getbbox() or (0, 0, width, height)
    crown_top, ground = bbox[1], bbox[3] - 1
    # The authored sprites stand their trunk on the canvas centre (that is
    # where TreeOverlay anchors them), so every derivation turns about it.
    centre_x = (width - 1) / 2.0
    squash = profile["squash"]
    shear_px = profile["shear"] * width / 64.0
    overall, gradient = profile["light"]

    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    target = out.load()
    for y in range(height):
        rise = 0.0 if ground == crown_top else max(
            0.0, min(1.0, (ground - y) / max(1, ground - crown_top)))
        shift = round(shear_px * rise)
        for x in range(width):
            # The source columns this destination pixel covers. Sampling
            # the nearest *opaque* one keeps 1px stems and twigs alive
            # under the side views' foreshortening, where plain nearest
            # sampling would skip a thin column and delete it whole.
            lo = centre_x + (x - 0.5 - shift - centre_x) / squash
            hi = centre_x + (x + 0.5 - shift - centre_x) / squash
            middle = (lo + hi) / 2.0
            best = None
            best_gap = math.inf
            for sx in range(math.floor(min(lo, hi)), math.ceil(max(lo, hi)) + 1):
                if 0 <= sx < width and pixels[sx, y][3] > 0 and abs(sx - middle) < best_gap:
                    best = pixels[sx, y]
                    best_gap = abs(sx - middle)
            if best is None:
                continue
            u = max(-1.0, min(1.0, (x - centre_x) / (width / 2.0)))
            factor = round((overall + gradient * u) * 20) / 20
            target[x, y] = tuple(
                max(0, min(255, round(channel * factor))) for channel in best[:3]
            ) + (best[3],)
    return out


def generate(preview: bool) -> None:
    sheet_rows = []
    for source in source_sprites():
        image = Image.open(source)
        views = []
        for facing in FACINGS:
            if facing == "n":
                # The north view is the authored drawing itself, byte for
                # byte: the default view of the course must not change.
                shutil.copyfile(source, view_path(source, facing))
                views.append(Image.open(source).convert("RGBA"))
                continue
            view = render_view(image, facing)
            view.save(view_path(source, facing))
            views.append(view)
        sheet_rows.append((os.path.relpath(source, SPRITE_DIR), views))
        print(f"{os.path.relpath(source, ROOT)} -> " +
              " ".join("_" + facing for facing in FACINGS))
    if preview:
        draw_preview(sheet_rows)


def check() -> int:
    """Fail when a committed view differs from what its source generates."""
    stale = []
    for source in source_sprites():
        image = Image.open(source).convert("RGBA")
        for facing in FACINGS:
            path = view_path(source, facing)
            if not os.path.exists(path):
                stale.append(f"{path} is missing")
                continue
            expected = image if facing == "n" else render_view(image, facing)
            actual = Image.open(path).convert("RGBA")
            if actual.size != expected.size or actual.tobytes() != expected.tobytes():
                stale.append(f"{path} does not match its source")
                continue
            if facing != "n" and actual.tobytes() == image.tobytes():
                stale.append(f"{path} is only a copy of the north view")
    if stale:
        for problem in stale:
            print(f"STALE: {problem}", file=sys.stderr)
        print("Re-run tools/tree_art/generate.py", file=sys.stderr)
        return 1
    print(f"All {len(source_sprites()) * len(FACINGS)} tree views are up to date.")
    return 0


def draw_preview(sheet_rows) -> None:
    """A contact sheet: one row per source, the four angles along it."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    cell_w, cell_h, scale = 170, 190, 2
    sheet = Image.new("RGBA", (cell_w * len(FACINGS), cell_h * len(sheet_rows)),
                      (70, 107, 52, 255))
    for row, (_name, views) in enumerate(sheet_rows):
        for col, view in enumerate(views):
            enlarged = view.resize((view.width * scale, view.height * scale),
                                   Image.NEAREST)
            sheet.alpha_composite(enlarged, (
                col * cell_w + (cell_w - enlarged.width) // 2,
                row * cell_h + (cell_h - enlarged.height) // 2))
    path = os.path.join(PREVIEW_DIR, "tree_facings.png")
    sheet.save(path)
    print(f"preview: {os.path.relpath(path, ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", action="store_true",
                        help="also draw tmp_preview/tree_facings.png")
    parser.add_argument("--check", action="store_true",
                        help="only verify the committed views, writing nothing")
    args = parser.parse_args()
    if args.check:
        return check()
    generate(args.preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
