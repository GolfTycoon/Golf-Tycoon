#!/usr/bin/env python3
"""Generate Golf Tycoon's sprite art for Brush, Rocks and Boulder tiles.

Run from the repository root:

    python3 tools/terrain_art/generate.py             # write every sprite
    python3 tools/terrain_art/generate.py --preview   # also draw contact sheets
    python3 tools/terrain_art/generate.py --only boulder --preview
    python3 tools/terrain_art/generate.py --check     # fail if the art is stale

Each feature is a real 3D model (see ``features.py``), rendered through the
building art's 2:1 isometric pipeline (``tools/building_art/render.py``) - the
same projection, sun, quantised shading and pixel-art outlines the trees and
facility sprites are baked with.  One PNG per feature and view variant is
written to ``assets/sprites/terrain/`` as ``<feature>_<variant>.png``, matching
the files ``TerrainFeatureOverlay`` loads.

The eight variants are independent seeded drawings of the feature, not
rotations of one model: each tile wears one of them for the life of the course
(``TerrainFeatureOverlay.facing_at()``), so a rocky stretch shows several
different outcrops at once.  The extra Rocks drawings also give a tile enough
different stones to scatter five to eight of them without a repeat.

``layout.json`` is written next to the PNGs.  Unlike a tree, a ground-cover
feature is anchored to its *tile centre* rather than to a trunk foot, and the
point differs per drawing because the outcrop's silhouette is what the canvas
was cropped to.  The layout therefore records, per file, the normalized
``ground_x_ratio`` / ``ground_y_ratio`` the renderer measured, plus a draw
scale.  The game positions each texture from its own canvas size, so a redrawn
outcrop needs no code edit.

The generator is offline and is not part of the game build.  The PNGs and the
layout are committed, so the game and the tests need only Godot.

Dependencies: Pillow and NumPy (``pip install -r tools/tree_art/requirements.txt``).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

from PIL import Image, ImageDraw  # noqa: E402

from render import (  # noqa: E402  (building_art on the path)
    OUTPUT_SCALE, Model, grid_origin_offset, project, render,
)
from features import (  # noqa: E402
    BASE_X, BASE_Y, FEATURES, VARIANT_COUNT, TreeBuilder, feature_draw_scale,
    feature_seed,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "terrain")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")
LAYOUT_FILE = "layout.json"

#: The footprint a feature stands on: one tile, rooted at its centre.
TILES_X, TILES_Y = 1, 1

#: Transparent margin around the render before it is cropped to its content.
#: A little headroom keeps the outline pass from shaving a crown on the canvas
#: edge; the renderer still crops to the painted pixels.
PAD = (8.0, 8.0, 6.0, 8.0)


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def build_model(feature: str, variant: int) -> Model:
    """One seeded drawing of the feature, standing on the tile's centre."""
    model = Model(TILES_X, TILES_Y)
    builder = TreeBuilder(model)
    builder.variant = variant
    rng = random.Random(feature_seed(feature, variant))
    FEATURES[feature]["draw"](builder, rng)
    return model


def ground_point() -> tuple[float, float]:
    """The tile centre's foot in the local draw space ``render()`` reports in."""
    origin = grid_origin_offset(TILES_X, TILES_Y, 0)
    px, py = project(BASE_X, BASE_Y, 0.0, 0)
    return (origin[0] + px, origin[1] + py)


def anchor_ratios(rect) -> tuple[float, float]:
    """Where the tile centre sits inside the rendered canvas, normalized.

    ``render()`` already cropped the image to the pixels it painted and reports
    ``rect`` (x, y, width, height) in world pixels, so the ground point's
    position relative to that rectangle is what the game needs: the overlay
    places the ratio point on the tile centre.  Ratios, unlike source pixels,
    survive a redraw at a different size.
    """
    ground_x, ground_y = ground_point()
    width = max(rect[2], 1e-6)
    height = max(rect[3], 1e-6)
    return ((ground_x - rect[0]) / width, (ground_y - rect[1]) / height)


def render_one(feature: str, variant: int, scale: float):
    model = build_model(feature, variant)
    return render(model, 0, scale=scale, pad=PAD)


def file_name(feature: str, variant: int) -> str:
    return f"{feature}_{variant}.png"


def draw_scale_for(feature: str, render_scale: float) -> float:
    """The draw scale the layout records for a feature.

    The renderer bakes at ``render_scale`` pixels per world pixel, so the game
    undoes that with ``1 / render_scale``.  A feature can also ask to be drawn
    smaller (Rocks does) via ``features.py``'s ``FEATURE_DRAW_SCALE``; both
    live in the sidecar so the art and its placement stay in one place.
    """
    return round(feature_draw_scale(feature) / render_scale, 3)


def layout_text(scale: float, ratios: dict[str, dict[str, float]],
                feature_scales: dict[str, float] | None = None) -> str:
    """The layout sidecar: per-file anchors under per-feature draw scales."""
    feature_scales = feature_scales or {}
    layout = {
        "features": {
            feature: {
                "scale": round(feature_scales.get(
                    feature, draw_scale_for(feature, scale)), 3)
            }
            for feature in sorted(FEATURES)
        },
        "sprites": {
            name: {
                "ground_x_ratio": round(values["ground_x_ratio"], 4),
                "ground_y_ratio": round(values["ground_y_ratio"], 4),
            }
            for name, values in sorted(ratios.items())
        },
    }
    return json.dumps(layout, indent="\t", sort_keys=True) + "\n"


# ---------------------------------------------------------------------------
# validation (mirrors tests/unit/course_design/test_terrain_feature_sprites.gd)
# ---------------------------------------------------------------------------

def validate(images: dict[tuple[str, int], Image.Image],
             ratios: dict[str, dict[str, float]],
             feature_list=None) -> list[str]:
    problems: list[str] = []
    for feature in (feature_list or FEATURES):
        variants = [images[(feature, v)] for v in range(VARIANT_COUNT)]
        if len({v.tobytes() for v in variants}) != VARIANT_COUNT:
            problems.append(f"{feature}: the {VARIANT_COUNT} variants are not "
                            f"{VARIANT_COUNT} different drawings")
        for variant, image in enumerate(variants):
            where = f"{feature}_{variant}"
            if image.width < 4 or image.height < 4:
                problems.append(f"{where}: canvas {image.size} is too small")
            if image.width > 128 or image.height > 128:
                problems.append(f"{where}: canvas {image.size} is far larger "
                                f"than its tile")
            if image.getchannel("A").getbbox() is None:
                problems.append(f"{where}: the canvas is empty")
            values = ratios.get(where, {})
            for axis in ("ground_x_ratio", "ground_y_ratio"):
                value = float(values.get(axis, -1.0))
                if not 0.0 <= value <= 1.0:
                    problems.append(f"{where}: {axis} {value} is off the canvas")
    # A feature's ground line may move between variants (the canvases differ),
    # but the tile centre must stay well inside every drawing: an anchor on the
    # very edge means the outcrop drifted off its tile.
    for name, values in sorted(ratios.items()):
        for axis, value in values.items():
            if value < 0.02 or value > 0.98:
                problems.append(f"{name}: {axis} {value:.3f} sits on the canvas "
                                f"edge, so the tile centre is not inside the art")
    return problems


# ---------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------

def _tile_diamond(draw, cx, cy, w, h, fill):
    draw.polygon([(cx, cy - h / 2), (cx + w / 2, cy),
                  (cx, cy + h / 2), (cx - w / 2, cy)], fill=fill)


def draw_preview(images: dict[tuple[str, int], Image.Image],
                 ratios: dict[str, dict[str, float]]) -> None:
    os.makedirs(PREVIEW_DIR, exist_ok=True)

    # One contact sheet: a row per feature, all of its variants along it.
    # 4x is deliberate - these sprites ship at ~12-24 px, and an artist needs
    # to see every crack, blossom and rim pixel when tuning a model.
    cell_w, cell_h, scale = 190, 150, 4
    sheet = Image.new("RGBA", (cell_w * VARIANT_COUNT, cell_h * len(FEATURES)),
                      (70, 107, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for row, feature in enumerate(FEATURES):
        for col in range(VARIANT_COUNT):
            view = images[(feature, col)]
            enlarged = view.resize((view.width * scale, view.height * scale),
                                   Image.NEAREST)
            sheet.alpha_composite(enlarged, (
                col * cell_w + (cell_w - enlarged.width) // 2,
                row * cell_h + (cell_h - 20 - enlarged.height) // 2 + 12))
        draw.text((8, row * cell_h + 6), feature, fill=(240, 240, 220))
    sheet.convert("RGB").save(os.path.join(PREVIEW_DIR, "terrain_sheet.png"))

    # Each variant on its own course tile, positioned exactly as the overlay
    # places it: the layout's anchor ratios on the diamond's centre.
    cell_w, cell_h, scale = 230, 170, 2
    cols = 4
    rows = (len(FEATURES) * VARIANT_COUNT + cols - 1) // cols
    scene = Image.new("RGBA", (cell_w * cols, cell_h * rows), (52, 88, 46, 255))
    draw = ImageDraw.Draw(scene)
    for index, (feature, variant) in enumerate(
            (f, v) for f in FEATURES for v in range(VARIANT_COUNT)):
        cx = (index % cols) * cell_w + cell_w // 2
        cy = (index // cols) * cell_h + cell_h - 34
        _tile_diamond(draw, cx, cy, 128, 64, (77, 115, 64, 255))
        _tile_diamond(draw, cx, cy, 124, 62, (86, 126, 70, 255))
        view = images[(feature, variant)]
        enlarged = view.resize((view.width * scale, view.height * scale),
                               Image.NEAREST)
        values = ratios[f"{feature}_{variant}"]
        anchor_x = values["ground_x_ratio"] * enlarged.width
        anchor_y = values["ground_y_ratio"] * enlarged.height
        scene.alpha_composite(enlarged, (int(round(cx - anchor_x)),
                                         int(round(cy - anchor_y))))
        draw.text((cx - 32, cy + 22), f"{feature}_{variant}",
                  fill=(240, 240, 220))
    scene.convert("RGB").save(os.path.join(PREVIEW_DIR, "terrain_on_course.png"))


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

def generate(args) -> int:
    feature_list = [s.strip() for s in args.only.split(",") if s.strip()] \
        or list(FEATURES)
    missing = [s for s in feature_list if s not in FEATURES]
    if missing:
        print(f"unknown features: {', '.join(missing)}", file=sys.stderr)
        return 2

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    images: dict[tuple[str, int], Image.Image] = {}
    ratios: dict[str, dict[str, float]] = {}
    for feature in feature_list:
        for variant in range(VARIANT_COUNT):
            image, rect = render_one(feature, variant, args.scale)
            images[(feature, variant)] = image
            gx, gy = anchor_ratios(rect)
            ratios[file_name(feature, variant).removesuffix(".png")] = {
                "ground_x_ratio": gx, "ground_y_ratio": gy}
            if not args.check:
                image.save(os.path.join(out_dir, file_name(feature, variant)),
                           optimize=True)

    if args.check:
        return check(images, ratios, out_dir, args.scale)

    if not args.no_validate:
        problems = validate(images, ratios, feature_list)
        if problems:
            print("\nSprite invariant problems:", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
            return 1
        print("Sprite invariants: OK")

    # Keep the entries of features this run did not re-render.
    layout_path = os.path.join(out_dir, LAYOUT_FILE)
    feature_scales = {f: draw_scale_for(f, args.scale) for f in feature_list}
    sprite_ratios = dict(ratios)
    if os.path.exists(layout_path) and len(feature_list) != len(FEATURES):
        try:
            with open(layout_path) as handle:
                old = json.load(handle)
            for feature, entry in old.get("features", {}).items():
                if feature not in feature_scales and isinstance(entry, dict):
                    value = entry.get("scale")
                    if isinstance(value, (int, float)):
                        feature_scales[feature] = float(value)
            for name, entry in old.get("sprites", {}).items():
                if name not in sprite_ratios and isinstance(entry, dict):
                    sprite_ratios[name] = entry
        except (OSError, ValueError):
            pass
    with open(layout_path, "w") as handle:
        handle.write(layout_text(args.scale, sprite_ratios, feature_scales))

    print(f"Rendered {len(images)} sprites at {args.scale:g} px/world pixel:")
    for feature in feature_list:
        sizes = sorted({images[(feature, v)].size for v in range(VARIANT_COUNT)})
        shown = ", ".join(f"{w}x{h}" for w, h in sizes)
        print(f"  {feature:10s} {VARIANT_COUNT} variants  {shown}")
    print(f"Layout written to {os.path.relpath(layout_path, ROOT)}")

    if args.preview:
        draw_preview(images, ratios)
        print(f"Previews written to {os.path.relpath(PREVIEW_DIR, ROOT)}/")
    return 0


def check(images: dict[tuple[str, int], Image.Image],
          ratios: dict[str, dict[str, float]], out_dir: str,
          scale: float) -> int:
    """Fail when the committed art differs from what the models generate."""
    stale = []
    for (feature, variant), image in sorted(images.items()):
        path = os.path.join(out_dir, file_name(feature, variant))
        if not os.path.exists(path):
            stale.append(f"{path} is missing")
            continue
        committed = Image.open(path).convert("RGBA")
        if committed.size != image.size or committed.tobytes() != image.tobytes():
            stale.append(f"{path} does not match its model")
    layout_path = os.path.join(out_dir, LAYOUT_FILE)
    if not os.path.exists(layout_path):
        stale.append(f"{layout_path} is missing")
    else:
        try:
            with open(layout_path) as handle:
                layout = json.load(handle)
        except ValueError:
            layout = {}
        entries = layout.get("features", {})
        sprite_ratios = layout.get("sprites", {})
        for feature in sorted({f for f, _v in images}):
            want = draw_scale_for(feature, scale)
            got = entries.get(feature, {}).get("scale")
            if got != want:
                stale.append(f"{layout_path}: {feature} scale {got} != {want}")
        for name, values in sorted(ratios.items()):
            stored = sprite_ratios.get(name, {})
            for axis, value in values.items():
                got = stored.get(axis)
                if got is None or abs(float(got) - value) > 5e-4:
                    stale.append(f"{layout_path}: {name} {axis} {got} != "
                                 f"{round(value, 4)}")
    if stale:
        for problem in stale:
            print(f"STALE: {problem}", file=sys.stderr)
        print("Re-run tools/terrain_art/generate.py", file=sys.stderr)
        return 1
    print(f"All {len(images)} terrain sprites are up to date.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", action="store_true",
                        help="also write contact sheets to tmp_preview/")
    parser.add_argument("--only", default="",
                        help="comma-separated feature ids to render")
    parser.add_argument("--scale", type=float, default=OUTPUT_SCALE,
                        help="source-art pixels per world pixel")
    parser.add_argument("--out-dir", default=OUT_DIR,
                        help="directory for the PNGs and layout.json")
    parser.add_argument("--check", action="store_true",
                        help="only verify the committed art, writing nothing")
    parser.add_argument("--no-validate", action="store_true",
                        help="skip the sprite invariant checks")
    args = parser.parse_args()
    return generate(args)


if __name__ == "__main__":
    raise SystemExit(main())
