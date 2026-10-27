#!/usr/bin/env python3
"""Generate Golf Tycoon's pixel-art building sprites.

Run from the repository root:

    python3 tools/building_art/generate.py            # write every sprite
    python3 tools/building_art/generate.py --preview  # also draw a preview sheet

The sprites land in assets/sprites/buildings/ next to a sprites.json manifest
that records, for every building, tier and view rotation, the PNG file and the
rectangle it occupies in the local draw space of the building node (world
pixels). BuildingSprites in the game reads that manifest and draws the texture
1:1, so the same image is used on the course, in the placement ghost and on the
Buildings tab.

This generator writes one art pixel per world pixel. Sprites replaced with
higher-resolution art need no manifest change: BuildingSprites.texture()
resamples the source PNG into its manifest rect once, at load time.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw

from buildings import BUILDINGS, Builder
from render import ART_SCALE, TILE_H, TILE_W, grid_origin_offset, project, render, Scene

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "buildings")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")

FACINGS = ("e", "s", "w", "n")


def render_building(kind: str, tier: int, facing: int):
    scene = Scene(facing)
    builder = Builder(scene, facing)
    BUILDINGS[kind]["draw"](builder, tier)
    size = BUILDINGS[kind]["tiles"]
    return render(scene, size, BUILDINGS[kind]["height"])


def generate(preview: bool) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = {"tile": [64, 32], "pixel_scale": ART_SCALE, "buildings": {}}
    sheet_rows = []
    for kind, info in BUILDINGS.items():
        entry = {"tiers": {}}
        sprites = []
        for tier in range(1, info["tiers"] + 1):
            tier_entry = {"facings": []}
            for facing in range(4):
                image, rect = render_building(kind, tier, facing)
                name = f"{kind}_{tier}_{FACINGS[facing]}.png"
                image.save(os.path.join(OUT_DIR, name))
                tier_entry["facings"].append({
                    "file": name,
                    "rect": [round(v, 2) for v in rect],
                })
                if facing == 0:
                    sprites.append(image)
            entry["tiers"][str(tier)] = tier_entry
            tier_entry["height"] = 0.0
        manifest["buildings"][kind] = entry
        # How far the art rises above the footprint's highest ground corner,
        # in world pixels. Recorded per tier so the clubhouse's growth can be
        # checked, and once per building for menu copy.
        heights = []
        for tier in range(1, info["tiers"] + 1):
            tier_heights = []
            for facing in range(4):
                rect = manifest["buildings"][kind]["tiers"][str(tier)]["facings"][facing]["rect"]
                origin = grid_origin_offset(info["tiles"][0], info["tiles"][1], facing)
                ground = [origin[1] + project(info["tiles"][0] * u, info["tiles"][1] * v,
                                             0.0, facing)[1]
                          for u in (0, 1) for v in (0, 1)]
                tier_heights.append(min(ground) - rect[1])
            entry["tiers"][str(tier)]["height"] = round(max(tier_heights), 2)
            heights.append(entry["tiers"][str(tier)]["height"])
        entry["sprite_height"] = round(max(heights), 2)
        sheet_rows.append((kind, sprites))

    with open(os.path.join(OUT_DIR, "sprites.json"), "w") as handle:
        json.dump(manifest, handle, indent="\t", sort_keys=True)
        handle.write("\n")

    if preview:
        draw_preview(sheet_rows, manifest)


def _tile_diamond(draw, cx, cy, w, h, fill, outline=None):
    draw.polygon([(cx, cy - h / 2), (cx + w / 2, cy), (cx, cy + h / 2), (cx - w / 2, cy)],
                 fill=fill, outline=outline)


def draw_preview(sheet_rows, manifest) -> None:
    """A contact sheet on the course's grass, plus one rotation strip."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    cell_w, cell_h = 380, 300
    cols = 4
    rows = (len(sheet_rows) + cols - 1) // cols
    sheet = Image.new("RGBA", (cell_w * cols, cell_h * rows), (60, 96, 52, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (kind, sprites) in enumerate(sheet_rows):
        cx = (index % cols) * cell_w + cell_w // 2
        cy = (index // cols) * cell_h + cell_h // 2 + 30
        for ring in range(3):
            size = 300 - ring * 44
            shade = 0.36 + ring * 0.045
            _tile_diamond(draw, cx, cy, size, size / 2,
                          (int(255 * shade), int(255 * (shade + 0.16)),
                           int(255 * (shade - 0.05)), 255))
        info = BUILDINGS[kind]
        tiles = info["tiles"]
        tf = ART_SCALE
        image = sprites[0]
        # The sprite is authored in local draw space; find the tile diamond's
        # centre there and place the image by its manifest rect.
        rect = manifest["buildings"][kind]["tiers"]["1"]["facings"][0]["rect"]
        ox, oy = grid_origin_offset(tiles[0], tiles[1], 0)
        fx, fy = project(tiles[0] * 0.5, tiles[1] * 0.5, 0.0, 0)
        sheet.alpha_composite(image, (int(cx + ox + fx - rect[0] - rect[2] / 2),
                                      int(cy + oy + fy - rect[1] - rect[3] / 2)))
        draw.text((cx - 40, cy + 120), f"{kind} {tiles[0]}x{tiles[1]}", fill=(240, 240, 220))
    sheet.convert("RGB").save(os.path.join(PREVIEW_DIR, "buildings_sheet.png"))

    # Rotation strip for the clubhouse and the resort hotel.
    for kind in ("clubhouse", "resort_hotel", "castle"):
        info = BUILDINGS[kind]
        tiles = info["tiles"]
        images = []
        for facing in range(4):
            image, rect = render_building(kind, info["tiers"], facing)
            images.append((image, rect))
        width = sum(im.width for im, _ in images) + 40
        height = max(im.height for im, _ in images) + 40
        strip = Image.new("RGBA", (width, height), (60, 96, 52, 255))
        x = 10
        for facing, (image, rect) in enumerate(images):
            strip.alpha_composite(image, (x, height - 10 - image.height))
            x += image.width + 10
        strip.convert("RGB").save(os.path.join(PREVIEW_DIR, f"rotations_{kind}.png"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true",
                        help="also write contact sheets to tmp_preview/")
    args = parser.parse_args()
    generate(args.preview)


if __name__ == "__main__":
    main()
