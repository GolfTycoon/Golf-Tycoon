#!/usr/bin/env python3
"""Generate Golf Tycoon's 3D-baked pixel-art building sprites.

Run from the repository root:

    python3 tools/building_art/generate.py            # write every sprite
    python3 tools/building_art/generate.py --preview  # also draw contact sheets
    python3 tools/building_art/generate.py --only clubhouse,castle --preview
    python3 tools/building_art/generate.py --scale 2.5 --out-dir /tmp/hd

Every facility is a real 3D model (see ``buildings.py``).  The renderer bakes
each model through the game's 2:1 isometric projection for all four view
rotations, saving one PNG per building, upgrade tier and angle next to
``sprites.json``.  The manifest records the rectangle each PNG covers in the
local draw space of the building node, in world pixels, so the same image is
used by the placed building, the placement ghost and the Buildings tab.

After rendering, the manifest is checked against the invariants the game's
tests rely on: sprites sit on their tiles at every rotation, rise no higher
than a building may, and stay inside their catalogue button.

The generator is offline and is not part of the game build.  The PNGs and the
manifest are committed, so the game and the tests need only Godot.

Dependencies: Pillow and NumPy (``pip install -r tools/building_art/requirements.txt``).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw

from buildings import BUILDINGS, Builder
from render import (
    FACING_COUNT, OUTPUT_SCALE, Model, grid_origin_offset, footprint_corners,
    project, render,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "buildings")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")

FACINGS = tuple(f"{i:02d}" for i in range(FACING_COUNT))


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def build_model(kind: str, tier: int, facing: int) -> Model:
    info = BUILDINGS[kind]
    model = Model(info["tiles"][0], info["tiles"][1])
    builder = Builder(model)
    builder.facing = facing
    info["draw"](builder, tier)
    return model


def render_one(args) -> dict:
    kind, tier, facing, scale, out_dir = args
    model = build_model(kind, tier, facing)
    image, rect = render(model, facing, scale=scale)
    name = f"{kind}_{tier}_{FACINGS[facing]}.png"
    image.save(os.path.join(out_dir, name), optimize=True)
    return {
        "kind": kind,
        "tier": tier,
        "facing": facing,
        "file": name,
        "rect": [round(v, 2) for v in rect],
        "tris": len(model.tris),
        "size": image.size,
    }


# ---------------------------------------------------------------------------
# validation (mirrors tests/unit/course_design/test_isometric_architecture.gd
#            and tests/unit/ui_and_controls/test_building_tile_art.gd)
# ---------------------------------------------------------------------------

TILE = (120.0, 60.0)
TILE_V_SEPARATION = 20.0
BELOW_TILE_ALLOWANCE = 8.0

# A building turned 15 degrees projects its roof and props a little further
# sideways/up than the cardinal views the first four-facing art was checked
# against. These stay tight enough to catch art floating off its footprint
# while accepting that legitimate diagonal overhang.
TOP_ALLOWANCE = 145.0
BOTTOM_ALLOWANCE = 6.0
SIDE_ALLOWANCE = 20.0


def validate(manifest: dict) -> list[str]:
    problems: list[str] = []
    for kind, entry in manifest["buildings"].items():
        tiles = BUILDINGS[kind]["tiles"]
        size_x = tiles[0] * 64.0
        size_y = tiles[1] * 32.0
        footprint_y = size_y
        preview_scale = min(0.34, 60.0 / size_x) * (TILE[0] / 84.0)
        for tier, tier_entry in entry["tiers"].items():
            for facing, face in enumerate(tier_entry["facings"]):
                x, y, w, h = face["rect"]
                right = x + w
                bottom = y + h
                corners = footprint_corners(tiles[0], tiles[1], facing)
                left = min(p[0] for p in corners)
                east = max(p[0] for p in corners)
                back = min(p[1] for p in corners)
                front = max(p[1] for p in corners)
                where = f"{kind} tier {tier} facing {FACINGS[facing]}"
                if not (back - TOP_ALLOWANCE <= y <= back + 2.0):
                    problems.append(f"{where}: top {y:.1f} outside {back - TOP_ALLOWANCE:.1f}..{back + 2.0:.1f}")
                if not (front - 14.0 <= bottom <= front + BOTTOM_ALLOWANCE):
                    problems.append(f"{where}: bottom {bottom:.1f} outside {front - 14.0:.1f}..{front + BOTTOM_ALLOWANCE:.1f}")
                if not (left - SIDE_ALLOWANCE <= x <= left + 12.0):
                    problems.append(f"{where}: left {x:.1f} outside {left - SIDE_ALLOWANCE:.1f}..{left + 12.0:.1f}")
                if not (east - 12.0 <= right <= east + SIDE_ALLOWANCE):
                    problems.append(f"{where}: right {right:.1f} outside {east - 12.0:.1f}..{east + SIDE_ALLOWANCE:.1f}")
                centre = project(size_x * 0.5, size_y * 0.5, 0.0, facing)
                origin = grid_origin_offset(tiles[0], tiles[1], facing)
                cx, cy = origin[0] + centre[0], origin[1] + centre[1]
                if not (x <= cx <= right and y <= cy <= bottom):
                    problems.append(f"{where}: footprint centre {cx:.1f},{cy:.1f} is not covered")
                if tier == "1" and facing == 0:
                    top_px = TILE[1] * 0.5 + preview_scale * (y - footprint_y)
                    bottom_px = TILE[1] * 0.5 + preview_scale * (bottom - footprint_y)
                    if top_px < -TILE_V_SEPARATION:
                        problems.append(f"{where}: catalogue preview top {top_px:.1f} above the notch")
                    if bottom_px > TILE[1] + BELOW_TILE_ALLOWANCE:
                        problems.append(f"{where}: catalogue preview bottom {bottom_px:.1f} below the tile")
                    if w * preview_scale > TILE[0] + 0.5:
                        problems.append(f"{where}: catalogue preview is {w * preview_scale:.1f} wide")
        heights = []
        for tier in sorted(entry["tiers"], key=int):
            heights.append(entry["tiers"][tier]["height"])
        if kind == "clubhouse":
            if not (heights[0] < heights[1] < heights[2]):
                problems.append(f"clubhouse tiers do not grow: {heights}")
    return problems


# ---------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------

def _tile_diamond(draw, cx, cy, w, h, fill):
    draw.polygon([(cx, cy - h / 2), (cx + w / 2, cy),
                  (cx, cy + h / 2), (cx - w / 2, cy)], fill=fill)


def draw_preview(manifest: dict, out_dir: str = OUT_DIR) -> None:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # One contact sheet of every facility's default angle on the course grass.
    cell_w, cell_h = 360, 300
    kinds = list(BUILDINGS)
    cols = 4
    rows = (len(kinds) + cols - 1) // cols
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * rows), (60, 96, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for index, kind in enumerate(kinds):
        cx = (index % cols) * cell_w + cell_w // 2
        cy = (index // cols) * cell_h + cell_h // 2
        draw.ellipse([cx - 110, cy + 62, cx + 110, cy + 112],
                     fill=(46, 78, 42, 255))
        info = BUILDINGS[kind]
        tiles = info["tiles"]
        image = Image.open(os.path.join(
            out_dir, manifest["buildings"][kind]["tiers"]["1"]["facings"][0]["file"])).convert("RGBA")
        scale = min(300.0 / image.width, 226.0 / image.height)
        if scale < 1.0:
            image = image.resize((max(1, int(image.width * scale)),
                                  max(1, int(image.height * scale))),
                                 Image.LANCZOS)
        sheet.alpha_composite(image, (cx - image.width // 2,
                                      cy + 50 - image.height))
        label = f"{kind}  {tiles[0]}x{tiles[1]}"
        tw = draw.textlength(label)
        draw.rectangle([cx - tw / 2 - 5, cy + 104, cx + tw / 2 + 5, cy + 120],
                       fill=(36, 58, 34, 230))
        draw.text((cx - tw / 2, cy + 106), label, fill=(240, 240, 220))
    sheet.convert("RGB").save(os.path.join(PREVIEW_DIR, "buildings_sheet.png"))

    # A clean turntable for the landmark buildings: every third 15-degree step.
    for kind in ("clubhouse", "resort_hotel", "castle", "theme_park"):
        entry = manifest["buildings"][kind]
        tier = max(int(t) for t in entry["tiers"])
        images = []
        for facing in range(0, FACING_COUNT, 3):
            name = entry["tiers"][str(tier)]["facings"][facing]["file"]
            images.append(Image.open(os.path.join(out_dir, name)))
        width = sum(im.width for im in images) + 50
        height = max(im.height for im in images) + 30
        strip = Image.new("RGBA", (width, height), (60, 96, 52, 255))
        x = 10
        for image in images:
            strip.alpha_composite(image, (x, height - 10 - image.height))
            x += image.width + 10
        strip.convert("RGB").save(os.path.join(PREVIEW_DIR, f"rotations_{kind}.png"))


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true",
                        help="also write contact sheets to tmp_preview/")
    parser.add_argument("--only", default="",
                        help="comma-separated building ids to render")
    parser.add_argument("--scale", type=float, default=OUTPUT_SCALE,
                        help="source-art pixels per world pixel")
    parser.add_argument("--out-dir", default=OUT_DIR,
                        help="directory for the PNGs and sprites.json")
    parser.add_argument("--jobs", type=int, default=1,
                        help="parallel render workers")
    parser.add_argument("--no-validate", action="store_true",
                        help="skip the manifest invariant checks")
    args = parser.parse_args()

    kinds = [k.strip() for k in args.only.split(",") if k.strip()] or list(BUILDINGS)
    missing = [k for k in kinds if k not in BUILDINGS]
    if missing:
        parser.error(f"unknown buildings: {', '.join(missing)}")

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    manifest = {"tile": [64, 32], "pixel_scale": round(args.scale, 3),
                "buildings": {}}

    jobs = []
    for kind in kinds:
        manifest["buildings"][kind] = {"tiers": {}}
        for tier in range(1, BUILDINGS[kind]["tiers"] + 1):
            manifest["buildings"][kind]["tiers"][str(tier)] = {"facings": []}
            for facing in range(FACING_COUNT):
                jobs.append((kind, tier, facing, args.scale, out_dir))

    if args.jobs > 1:
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(render_one, jobs))
    else:
        results = [render_one(job) for job in jobs]

    by_key = {(r["kind"], r["tier"], r["facing"]): r for r in results}
    for kind in kinds:
        info = BUILDINGS[kind]
        heights = []
        for tier in range(1, info["tiers"] + 1):
            tier_entry = manifest["buildings"][kind]["tiers"][str(tier)]
            tier_heights = []
            for facing in range(FACING_COUNT):
                result = by_key[(kind, tier, facing)]
                tier_entry["facings"].append({
                    "file": result["file"],
                    "rect": result["rect"],
                })
                back = min(p[1] for p in footprint_corners(info["tiles"][0], info["tiles"][1], facing))
                tier_heights.append(round(back - result["rect"][1], 2))
            tier_entry["height"] = round(max(tier_heights), 2)
            heights.append(tier_entry["height"])
        manifest["buildings"][kind]["sprite_height"] = round(max(heights), 2)

    # Keep entries for buildings not re-rendered by --only.
    manifest_path = os.path.join(out_dir, "sprites.json")
    if os.path.exists(manifest_path) and len(kinds) != len(BUILDINGS):
        with open(manifest_path) as handle:
            old = json.load(handle)
        for kind, entry in old.get("buildings", {}).items():
            manifest["buildings"].setdefault(kind, entry)

    with open(manifest_path, "w") as handle:
        json.dump(manifest, handle, indent="\t", sort_keys=True)
        handle.write("\n")

    print(f"Rendered {len(results)} sprites at {args.scale:g} px/world pixel:")
    for kind in kinds:
        arts = sorted({r["size"] for r in results if r["kind"] == kind})
        tris = max(r["tris"] for r in results if r["kind"] == kind)
        print(f"  {kind:14s} {BUILDINGS[kind]['tiers']} tier(s)  {tris} triangles  {arts[0][0]}x{arts[0][1]}")

    if not args.no_validate:
        problems = validate(manifest)
        if problems:
            print("\nManifest invariant problems:", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
            return 1
        print("Manifest invariants: OK")

    if args.preview:
        draw_preview(manifest, out_dir)
        print(f"Previews written to {os.path.relpath(PREVIEW_DIR, ROOT)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
