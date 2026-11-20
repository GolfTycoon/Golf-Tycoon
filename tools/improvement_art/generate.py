#!/usr/bin/env python3
"""Bake Golf Tycoon's Improvement sprites (the ornaments).

Run from the repository root:

    python3 tools/improvement_art/generate.py             # write every sprite
    python3 tools/improvement_art/generate.py --preview   # also draw a contact sheet
    python3 tools/improvement_art/generate.py --only park_bench --preview
    python3 tools/improvement_art/generate.py --check     # fail if the art is stale

The bench and the golfer are real 3D models (see ``props.py``), rendered
through the building art's 2:1 isometric pipeline
(``tools/building_art/render.py``) - the same projection, sun, quantised shading
and pixel-art outlines the trees, ground cover and facility sprites are baked
with.  The fountain, sundial, ball washer and the statue's pedestal are painted
in screen space (see ``paint2d.py``) in the same palette: a rim hides its own
water, a horizontal dial is only a few pixels tall, and a station or a round
plinth at this size collapses into shaded facets.  The statue is a composite -
the painted pedestal with the rendered figure standing on its top face.  One
PNG per drawing is written to ``assets/sprites/improvements/``:

    fountain_0.png
    golfer_statue_0.png
    park_bench_0.png .. park_bench_3.png          (front south, east, north, west)
    ball_washer_0.png
    sundial_0.png

The bench is laid beside a walk and turns to face it, so it ships four fronts;
the statue, the ball washer and the painted ornaments ship one drawing.  Every
drawing is cropped to the pixels it paints, so ``layout.json`` records the
normalized place where the prop's tile-centre foot lands in *its own* canvas.
The game positions a sprite from that ratio and its own texture size, so a
redrawn prop needs no code edit.

The generator is offline and is not part of the game build.  The PNGs and the
layer sidecar are committed, so the game and the tests need only Godot.

Dependencies: Pillow and NumPy (``pip install -r tools/tree_art/requirements.txt``).
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

import numpy as np
import render as _art  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

from render import OUTPUT_SCALE, render  # noqa: E402  (building_art on the path)
from paint2d import (  # noqa: E402
    paint_ball_washer, paint_fountain, paint_statue_plinth, paint_sundial,
)
from props import (  # noqa: E402
    DIRECTIONAL, ORNAMENT_KEYS, foot_ratios, prop_foot, variants_for,
)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "improvements")
PREVIEW_DIR = os.path.join(ROOT, "tmp_preview")
LAYOUT_FILE = "layout.json"

#: Transparent margin around a render before it is cropped to its pixels.  A
#: little headroom keeps the outline pass from shaving a hat or a club head on
#: the canvas edge; the renderer still crops to the painted pixels.
PAD = (10.0, 10.0, 8.0, 10.0)

#: The glassy, pixel-art-dense size the props are authored at: one source pixel
#: per world pixel, the same density as the buildings and trees.
SCALE = OUTPUT_SCALE

#: Colours in a baked improvement sprite.  Enough for stone, wood, iron, bronze,
#: brass, water, foliage and ink; small enough that the render's near-duplicate
#: facets collapse into the hand-painted tones the rest of the course uses.
PROP_PALETTE = 24


def _lift_prop_shade():
    """Brighten the shaded faces of a prop render.

    The building sun is deliberately high and directional, which is right for
    walls that face the course, but a bench, a post or a pedestal presents the
    camera with its *front* face.  At 0.52 exposure that face reads as grey mud
    next to the hand-painted tiles.  A gentle gamma on the lighting term keeps
    the facets and the ink while bringing the front planes up to the same key
    as the rest of the course.  Buildings call the untouched function.
    """
    original = _art.shade_factor

    def lifted(normal):
        return min(1.30, original(normal) ** 0.88)

    _art.shade_factor = lifted


_lift_prop_shade()


def file_name(key: str, suffix: str) -> str:
    return f"{key}_{suffix}.png"


def lift(image: Image.Image) -> Image.Image:
    """Lift the shadows of a one-tile prop.

    A facility is metres wide and four storeys tall, so the renderer's one warm
    sun and cool fill have room to model its walls.  A bench is two tile-pixels
    deep and a fountain's front wall faces away from that sun, so at native size
    the same light leaves their shadow sides reading as one muddy tone against
    the turf.  The lift is a gentle gamma on the painted pixels plus a little
    saturation: the model keeps its lighting and its ink creases, but the cool
    faces stay legible a metre from the player's eye.  Transparent pixels are
    left exactly transparent so the sprite still sits on its tile.
    """
    data = np.asarray(image, dtype=np.float32) / 255.0
    rgb, alpha = data[..., :3], data[..., 3:]
    rgb = np.power(np.clip(rgb, 0.0, 1.0), 0.80)
    luma = (rgb * np.array([0.299, 0.587, 0.114], dtype=np.float32)).sum(
        axis=2, keepdims=True)
    rgb = np.clip(luma + (rgb - luma) * 1.22, 0.0, 1.0)
    # Keep the ink silhouette: the darkest painted pixels stay dark rather than
    # being lifted into the stone.
    edge = alpha > 0.45
    rgb = np.where(edge & (luma < 0.12), rgb * 0.82, rgb)
    out = np.dstack([rgb, alpha])
    return Image.fromarray(np.clip(np.round(out * 255.0), 0, 255).astype(np.uint8),
                           mode="RGBA")


def enhance(image: Image.Image) -> Image.Image:
    """Lift a render, then reduce it to the shared prop palette.

    A prop is one or two tiles of art, and the renderer's facets, AO and
    supersampling can leave a dozen near-identical browns on a bench slat.
    Quantising to a compact palette is what turns that render back into a
    hand-painted sprite: the same few tones the trees and buildings use, with
    no dithering.  Transparent pixels are background black and keep no alpha,
    so they cannot steal a palette entry that the painted prop needs.
    """
    return quantise(lift(image))


#: Props painted straight onto the screen-space canvas instead of modelled.  A
#: basin and a dial are read from above; a 3D rim occludes its own water and a
#: horizontal face is only a few pixels tall, so the two radial ornaments are
#: drawn (``paint2d.py``) in the same palette and outline weight as the rest.
PAINTERS = {
    "fountain": paint_fountain,
    "ball_washer": paint_ball_washer,
    "sundial": paint_sundial,
}


def quantise(image: Image.Image) -> Image.Image:
    """Reduce a painted sprite to the shared prop palette, keeping its alpha."""
    data = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    rgb, alpha = data[..., :3], data[..., 3:]
    painted = Image.fromarray(
        np.clip(np.round(rgb * 255.0), 0, 255).astype(np.uint8), mode="RGB")
    palette = painted.quantize(colors=PROP_PALETTE, method=Image.MEDIANCUT,
                               dither=Image.NONE).convert("RGB")
    out = np.dstack([np.asarray(palette, dtype=np.float32) / 255.0, alpha])
    return Image.fromarray(np.clip(np.round(out * 255.0), 0, 255).astype(np.uint8),
                           mode="RGBA")


def paint_one(key: str):
    """Bake one hand-painted prop, cropped to its pixels like a render."""
    image, foot_x, foot_y = PAINTERS[key]()
    image = quantise(image)
    left, top, right, bottom = image.getbbox()
    crop = image.crop((left, top, right, bottom))
    ratios = ((foot_x - left) / max(crop.width, 1),
              (foot_y - top) / max(crop.height, 1))
    return crop, [left, top, crop.width, crop.height], ratios


def compose_statue():
    """The bronze golfer stood on the separately painted pedestal.

    The figure is rendered by the same pipeline as the bench; the pedestal is
    painted (``paint2d.paint_statue_plinth``) so its drum keeps straight sides
    and a shallow cap rim instead of the renderer's sloped-looking cap ellipse.
    The figure's tile-centre foot lands on the middle of that top face, and the
    anchor returned is the pedestal's foot, so the pedestal keeps standing on
    the tile centre.
    """
    plinth, foot, top = paint_statue_plinth()
    figure, rect = render(variants_for("golfer_statue")[0][1], 0,
                          scale=SCALE, pad=PAD)
    figure = lift(figure)
    box = figure.getbbox()
    figure = figure.crop(box)
    # The render's foot is in the node's draw space: take it into the crop the
    # renderer returned, then into the tighter crop taken here.
    fx, fy = prop_foot()
    fx -= rect[0] + box[0]
    fy -= rect[1] + box[1]
    ox = int(round(top[0] - fx))
    oy = int(round(top[1] - fy))
    left = min(0, ox)
    upper = min(0, oy)
    width = max(plinth.width, ox + figure.width) - left
    height = max(plinth.height, oy + figure.height) - upper
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(plinth, (-left, -upper))
    canvas.alpha_composite(figure, (ox - left, oy - upper))
    return canvas, (foot[0] - left, foot[1] - upper)


def render_one(key: str, suffix: str, model):
    image, rect = render(model, 0, scale=SCALE, pad=PAD)
    image = enhance(image)
    ratios = foot_ratios(rect)
    return image, rect, ratios


def build_all(only: str | None = None):
    """Every (key, suffix, image, rect, ratios) the generator will write."""
    keys = [only] if only else list(ORNAMENT_KEYS)
    out = []
    for key in keys:
        if key not in ORNAMENT_KEYS:
            raise SystemExit(f"unknown improvement {key!r}; choose from {', '.join(ORNAMENT_KEYS)}")
        if key in PAINTERS:
            image, rect, ratios = paint_one(key)
            out.append((key, "0", image, rect, ratios))
            continue
        if key == "golfer_statue":
            image, foot = compose_statue()
            image = quantise(image)
            left, top, right, bottom = image.getbbox()
            crop = image.crop((left, top, right, bottom))
            ratios = ((foot[0] - left) / max(crop.width, 1),
                      (foot[1] - top) / max(crop.height, 1))
            out.append((key, "0", crop,
                        [left, top, crop.width, crop.height], ratios))
            continue
        for suffix, model in variants_for(key):
            image, rect, ratios = render_one(key, suffix, model)
            out.append((key, suffix, image, rect, ratios))
    return out


def layout_for(built) -> dict:
    """The sidecar the game reads: per-prop scale and per-drawing foot anchor."""
    props = {}
    sprites = {}
    for key, suffix, image, _rect, ratios in built:
        if key not in props:
            props[key] = {
                "scale": 1.0,
                "drawings": 4 if key in DIRECTIONAL else 1,
            }
        sprites[f"{key}_{suffix}"] = {
            "foot_x_ratio": round(float(ratios[0]), 6),
            "foot_y_ratio": round(float(ratios[1]), 6),
            "width": image.width,
            "height": image.height,
        }
    return {"props": props, "sprites": sprites}


def write(built, check: bool) -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    layout = layout_for(built)
    changed = []

    if not check:
        for key, suffix, image, _rect, _ratios in built:
            path = os.path.join(OUT_DIR, file_name(key, suffix))
            image.save(path)
            changed.append(path)
        with open(os.path.join(OUT_DIR, LAYOUT_FILE), "w", encoding="utf-8") as fh:
            json.dump(layout, fh, indent="\t")
            fh.write("\n")
        return 0

    # --check: every committed PNG must decode to exactly the model's pixels,
    # and the sidecar must match the layout the models produce now.
    stale = []
    for key, suffix, image, _rect, _ratios in built:
        path = os.path.join(OUT_DIR, file_name(key, suffix))
        if not os.path.exists(path):
            stale.append(path)
            continue
        committed = Image.open(path).convert("RGBA")
        if committed.size != image.size or committed.tobytes() != image.tobytes():
            stale.append(path)
    layout_path = os.path.join(OUT_DIR, LAYOUT_FILE)
    if not os.path.exists(layout_path):
        stale.append(layout_path)
    else:
        with open(layout_path, encoding="utf-8") as fh:
            if json.load(fh) != layout:
                stale.append(layout_path)
    if stale:
        print("Stale improvement art (rerun tools/improvement_art/generate.py):")
        for path in stale:
            print("  " + os.path.relpath(path, ROOT))
        return 1
    print(f"Improvement art is current ({len(built)} drawings).")
    return 0


def preview(built) -> None:
    """A 4x contact sheet so the art can be judged at a glance."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scale = 4
    cell_w = max(image.width for _k, _s, image, _r, _p in built) * scale + 16
    cell_h = max(image.height for _k, _s, image, _r, _p in built) * scale + 34
    columns = 6
    rows = (len(built) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h), (54, 74, 56, 255))
    draw = ImageDraw.Draw(sheet)
    for i, (key, suffix, image, _rect, ratios) in enumerate(built):
        col, row = i % columns, i // columns
        x = col * cell_w
        y = row * cell_h
        big = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x + (cell_w - big.width) // 2,
                                    y + 22 + (cell_h - 34 - big.height) // 2))
        draw.text((x + 6, y + 4), f"{key}_{suffix}", fill=(240, 232, 204, 255))
        draw.text((x + 6, y + cell_h - 18),
                  f"{image.width}x{image.height}  foot {ratios[0]:.2f},{ratios[1]:.2f}",
                  fill=(190, 206, 172, 255))
    path = os.path.join(PREVIEW_DIR, "improvements_sheet.png")
    sheet.save(path)
    print("preview:", os.path.relpath(path, ROOT))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=ORNAMENT_KEYS, help="bake just one improvement")
    parser.add_argument("--preview", action="store_true", help="write a contact sheet")
    parser.add_argument("--check", action="store_true", help="fail if committed art is stale")
    args = parser.parse_args()
    built = build_all(args.only)
    status = write(built, args.check)
    if args.preview:
        preview(built)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
