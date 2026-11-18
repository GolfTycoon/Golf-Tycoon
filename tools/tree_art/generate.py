#!/usr/bin/env python3
"""Generate Golf Tycoon's 3D-baked pixel-art tree sprites.

Run from the repository root:

    python3 tools/tree_art/generate.py            # write every sprite
    python3 tools/tree_art/generate.py --preview  # also draw contact sheets
    python3 tools/tree_art/generate.py --only oak,pine --preview
    python3 tools/tree_art/generate.py --check    # fail if the art is stale

Every species is a real 3D model (see ``trees.py``), rendered through the
building art's 2:1 isometric pipeline (``tools/building_art/render.py``) - the
same projection, sun, quantised shading and pixel-art outlines the facility
sprites are baked with.  One PNG per species and view variant is written to
``assets/sprites/trees/`` as ``<species>_<variant>.png``, matching the files
``TreeOverlay`` loads.

Each variant is its own designed model, not a rotation or a jitter of one
model: a woodland tile wears one variant for the life of the course
(``TreeOverlay.facing_at()``), so the four drawings are alternatives shown
side by side in one wood, they share one sun direction, and each is posed
for the single angle it will ever be seen from (``screen_shift()`` in
``trees.py`` composes leans and crown offsets in screen pixels).  Every
sprite is cropped so the trunk's ground point sits at the bottom-centre of
its canvas, which is what the layout anchors assume.

``layout.json`` is written next to the PNGs and records, per species, the draw
scale (``1 / --scale``) under the normalized ground anchor the renderer
guarantees (``ground_x_ratio`` 0.5, ``ground_y_ratio`` 1.0).  The game then
positions each texture from its own canvas size, so variants may differ in
dimensions without a code edit.

After rendering, the set is checked against the invariants the game's tests
rely on: every species has four distinct, individually-sized variants (the
oak's included), and each canvas carries its ground point.

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
from trees import TREES, VARIANT_COUNT, TreeBuilder, variant_seed  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "trees")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")
LAYOUT_FILE = "layout.json"

#: The footprint every tree stands on: one tile, trunk at its centre.
TILES_X, TILES_Y = 1, 1
BASE_X, BASE_Y, BASE_Z = 32.0, 16.0, 0.0


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def build_model(species: str, variant: int) -> Model:
    """One variant of the species: its own designed model, seeded per variant.

    Every variant is a distinct design (see ``TREES[species]["designs"]``) -
    posed for the single angle the game will always view it from - with the
    seed adding the small jitter that keeps two runs identical and two trees
    from looking stamped.
    """
    model = Model(TILES_X, TILES_Y)
    builder = TreeBuilder(model)
    rng = random.Random(variant_seed(species, variant))
    designs = TREES[species]["designs"]
    TREES[species]["draw"](builder, rng, designs[variant % len(designs)])
    return model


def ground_point(facing: int = 0) -> tuple[float, float]:
    """The trunk's foot in the local draw space ``render()`` reports in."""
    origin = grid_origin_offset(TILES_X, TILES_Y, facing)
    px, py = project(BASE_X, BASE_Y, BASE_Z, facing)
    return (origin[0] + px, origin[1] + py)


def anchor_to_ground(image: Image.Image, rect, scale: float) -> Image.Image:
    """Re-crop a render so the ground point is the canvas's bottom-centre.

    ``layout.json`` anchors every sprite at ``ground_x_ratio`` 0.5 and
    ``ground_y_ratio`` 1.0 - the trunk's foot at the bottom edge, horizontally
    centred - so the game can position any canvas by its own size.  Content
    below the ground line (the front rim of the root flare) is cut away the way
    a drawn tree is cut flat where it meets the turf.
    """
    ground = ground_point()
    gx = (ground[0] - rect[0]) * scale
    gy = (ground[1] - rect[1]) * scale
    width, height = image.size
    rows = max(1, min(height, int(round(gy))))
    half = max(gx, width - gx)
    out_w = max(2, int(math.ceil(half * 2.0)))
    shift = int(round(out_w * 0.5 - gx))
    out = Image.new("RGBA", (out_w, rows), (0, 0, 0, 0))
    out.paste(image.crop((0, 0, width, rows)), (shift, 0),
              image.crop((0, 0, width, rows)))
    return out


def render_one(species: str, variant: int, scale: float) -> Image.Image:
    model = build_model(species, variant)
    image, rect = render(model, 0, scale=scale)
    return anchor_to_ground(image, rect, scale)


def file_name(species: str, variant: int) -> str:
    return f"{species}_{variant}.png"


def layout_text(scale: float, species_scales: dict[str, float] | None = None) -> str:
    """The layout sidecar: draw scales under the anchors the art is cut to."""
    species_scales = species_scales or {}
    layout = {
        "ground_x_ratio": 0.5,
        "ground_y_ratio": 1.0,
        "species": {
            species: {"scale": round(species_scales.get(species, 1.0 / scale), 3)}
            for species in sorted(TREES)
        },
    }
    return json.dumps(layout, indent="\t", sort_keys=True) + "\n"


# ---------------------------------------------------------------------------
# validation (mirrors tests/unit/course_design/test_tree_sprites.gd)
# ---------------------------------------------------------------------------

def validate(images: dict[tuple[str, int], Image.Image]) -> list[str]:
    problems: list[str] = []
    for species in TREES:
        variants = [images[(species, v)] for v in range(VARIANT_COUNT)]
        if len({v.tobytes() for v in variants}) != VARIANT_COUNT:
            problems.append(f"{species}: the four variants are not four drawings")
        for variant, image in enumerate(variants):
            where = f"{species}_{variant}"
            if image.width < 4 or image.height < 4:
                problems.append(f"{where}: canvas {image.size} is too small")
            alpha = image.getchannel("A")
            bbox = alpha.getbbox()
            if bbox is None:
                problems.append(f"{where}: the canvas is empty")
                continue
            if bbox[3] != image.height:
                problems.append(f"{where}: content does not meet the bottom edge "
                                f"the ground anchor needs")
            if bbox[0] != 0 and bbox[2] != image.width:
                problems.append(f"{where}: the canvas is padded on both sides, "
                                f"so the trunk is not at its centre")
    # The tests pin that the oak's views are independently sized drawings.
    oak = {images[("oak", v)].size for v in range(VARIANT_COUNT)}
    if len(oak) < 2:
        problems.append("oak: the variants share one canvas size; the layout "
                        "has nothing to adapt to")
    return problems


# ---------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------

def _tile_diamond(draw, cx, cy, w, h, fill):
    draw.polygon([(cx, cy - h / 2), (cx + w / 2, cy),
                  (cx, cy + h / 2), (cx - w / 2, cy)], fill=fill)


def draw_preview(images: dict[tuple[str, int], Image.Image]) -> None:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # One contact sheet: a row per species, its four variants along it.
    cell_w, cell_h, scale = 190, 180, 2
    rows = len(TREES)
    sheet = Image.new("RGBA", (cell_w * VARIANT_COUNT, cell_h * rows),
                      (70, 107, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for row, species in enumerate(TREES):
        for col in range(VARIANT_COUNT):
            view = images[(species, col)]
            enlarged = view.resize((view.width * scale, view.height * scale),
                                   Image.NEAREST)
            sheet.alpha_composite(enlarged, (
                col * cell_w + (cell_w - enlarged.width) // 2,
                row * cell_h + (cell_h - 24 - enlarged.height) // 2 + 12))
        draw.text((8, row * cell_h + 6), species, fill=(240, 240, 220))
    sheet.convert("RGB").save(os.path.join(PREVIEW_DIR, "trees_sheet.png"))

    # Each variant standing on its tile, the way the course draws it: the
    # sprite's bottom-centre planted on the tile's centre.
    cell_w, cell_h, scale = 240, 190, 2
    cols = 3
    rows = (len(TREES) + cols - 1) // cols
    scene = Image.new("RGBA", (cell_w * cols, cell_h * rows), (60, 96, 52, 255))
    draw = ImageDraw.Draw(scene)
    for index, species in enumerate(TREES):
        cx = (index % cols) * cell_w + cell_w // 2
        cy = (index // cols) * cell_h + cell_h - 36
        _tile_diamond(draw, cx, cy, 128, 64, (77, 115, 64, 255))
        view = images[(species, index % VARIANT_COUNT)]
        enlarged = view.resize((view.width * scale, view.height * scale),
                               Image.NEAREST)
        scene.alpha_composite(enlarged,
                              (cx - enlarged.width // 2, cy - enlarged.height))
        draw.text((cx - 20, cy + 22), species, fill=(240, 240, 220))
    scene.convert("RGB").save(os.path.join(PREVIEW_DIR, "trees_on_course.png"))


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

def generate(args) -> int:
    species_list = [s.strip() for s in args.only.split(",") if s.strip()] \
        or list(TREES)
    missing = [s for s in species_list if s not in TREES]
    if missing:
        print(f"unknown species: {', '.join(missing)}", file=sys.stderr)
        return 2

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    images: dict[tuple[str, int], Image.Image] = {}
    for species in species_list:
        for variant in range(VARIANT_COUNT):
            image = render_one(species, variant, args.scale)
            images[(species, variant)] = image
            if not args.check:
                image.save(os.path.join(out_dir, file_name(species, variant)),
                           optimize=True)

    if args.check:
        return check(images, out_dir, args.scale)

    if not args.no_validate:
        problems = validate(images)
        if problems:
            print("\nSprite invariant problems:", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
            return 1
        print("Sprite invariants: OK")

    # Keep the scales of species this run did not re-render.
    scales = {s: 1.0 / args.scale for s in species_list}
    layout_path = os.path.join(out_dir, LAYOUT_FILE)
    if os.path.exists(layout_path) and len(species_list) != len(TREES):
        try:
            with open(layout_path) as handle:
                old = json.load(handle)
            for species, entry in old.get("species", {}).items():
                if species not in scales and isinstance(entry, dict):
                    value = entry.get("scale")
                    if isinstance(value, (int, float)):
                        scales[species] = float(value)
        except (OSError, ValueError):
            pass
    with open(layout_path, "w") as handle:
        handle.write(layout_text(args.scale, scales))

    print(f"Rendered {len(images)} sprites at {args.scale:g} px/world pixel:")
    for species in species_list:
        sizes = sorted({images[(species, v)].size for v in range(VARIANT_COUNT)})
        shown = ", ".join(f"{w}x{h}" for w, h in sizes)
        print(f"  {species:10s} {VARIANT_COUNT} variants  {shown}")
    print(f"Layout written to {os.path.relpath(layout_path, ROOT)}")

    if args.preview:
        draw_preview(images)
        print(f"Previews written to {os.path.relpath(PREVIEW_DIR, ROOT)}/")
    return 0


def check(images: dict[tuple[str, int], Image.Image], out_dir: str,
          scale: float) -> int:
    """Fail when the committed art differs from what the models generate."""
    stale = []
    for (species, variant), image in sorted(images.items()):
        path = os.path.join(out_dir, file_name(species, variant))
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
        if layout.get("ground_x_ratio") != 0.5 or layout.get("ground_y_ratio") != 1.0:
            stale.append(f"{layout_path} no longer anchors at the bottom-centre")
        entries = layout.get("species", {})
        for species in sorted({s for s, _v in images}):
            want = round(1.0 / scale, 3)
            got = entries.get(species, {}).get("scale")
            if got != want:
                stale.append(f"{layout_path}: {species} scale {got} != {want}")
    if stale:
        for problem in stale:
            print(f"STALE: {problem}", file=sys.stderr)
        print("Re-run tools/tree_art/generate.py", file=sys.stderr)
        return 1
    print(f"All {len(images)} tree sprites are up to date.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", action="store_true",
                        help="also write contact sheets to tmp_preview/")
    parser.add_argument("--only", default="",
                        help="comma-separated species ids to render")
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
