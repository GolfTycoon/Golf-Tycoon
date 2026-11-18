#!/usr/bin/env python3
"""A small orthographic 3D renderer that bakes Golf Tycoon's building sprites.

The game is 2D and draws one pixel sprite per facility, upgrade tier and view
rotation.  The art itself is built as a real 3D model: boxes, prisms, roofs,
cylinders, spheres and lathed props standing on the course's grid.  This module
renders those models through the game's own 2:1 isometric projection, with a
z-buffer, sun and fill lighting, per-vertex ambient occlusion, translucent
decals, water and shadows, then downsamples the result to crisp pixel art.

One model pixel is one world pixel, matching ``CourseArchitecture``: a tile is
64 x 32 world pixels, grid ``x`` runs across the footprint, ``y`` down it and
``z`` up.  ``render()`` returns the image and the rectangle it covers in the
local draw space of a ``Building`` node, so the sprite lands on exactly the
tiles the building occupies at every rotation.

The renderer is deliberately dependency-light: NumPy for the buffered maths and
Pillow for the PNGs and procedural decals.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# projection constants (must match CourseArchitecture)
# ---------------------------------------------------------------------------

TILE_W = 64.0
TILE_H = 32.0
HALF_W = TILE_W * 0.5
HALF_H = TILE_H * 0.5

#: Source-art pixels per world pixel.  Since the game now ships one sprite per
#: 15-degree view step, the committed art is baked 1:1 and the game draws it at
#: its native size.  ``--scale`` raises this for the optional high-resolution
#: art pack, whose PNGs use the old 2.5 px/world-pixel density.
OUTPUT_SCALE = 1.0
#: View steps around a full turn: 24 at 15 degrees, so a sprite exists for
#: every angle a building can face.
FACING_COUNT = 24
#: Sub-samples per source pixel, averaged down for clean pixel-art edges.
SUPERSAMPLE = 2


def rotate_uv(u: float, v: float, facing: int):
    """Rotate grid coordinates into the view at a 1/24-turn facing index.

    Quarter turns keep the exact integer forms the old four-facing art used;
    everything between them rotates by the same cosine/sine transform as
    ``GridProjection``, so sprites and footprint stay on the terrain at 15
    degree steps.
    """
    facing %= FACING_COUNT
    if facing % (FACING_COUNT // 4) == 0:
        quarter = facing // (FACING_COUNT // 4)
        if quarter == 1:
            return (-v, u)
        if quarter == 2:
            return (-u, -v)
        if quarter == 3:
            return (v, -u)
        return (u, v)
    angle = math.tau * facing / FACING_COUNT
    c, s = math.cos(angle), math.sin(angle)
    return (u * c - v * s, u * s + v * c)


def project(x: float, y: float, z: float, facing: int):
    """World-pixel point (x across, y down, z up) to local draw space."""
    u, v = x / TILE_W, y / TILE_H
    ru, rv = rotate_uv(u, v, facing)
    return ((ru - rv) * HALF_W, (ru + rv) * HALF_H - z)


def grid_origin_offset(tiles_x: float, tiles_y: float, facing: int):
    """Where grid (0, 0) falls in the local space of a Building node."""
    size_x = tiles_x * TILE_W
    size_y = tiles_y * TILE_H
    cx, cy = tiles_x * 0.5, tiles_y * 0.5
    ru, rv = rotate_uv(cx, cy, facing)
    return (size_x * 0.5 - (ru - rv) * HALF_W,
            size_y - (ru + rv) * HALF_H)


def footprint_corners(tiles_x: float, tiles_y: float, facing: int):
    origin = grid_origin_offset(tiles_x, tiles_y, facing)
    corners = []
    for x, y in ((0, 0), (tiles_x * TILE_W, 0),
                 (tiles_x * TILE_W, tiles_y * TILE_H), (0, tiles_y * TILE_H)):
        px, py = project(x, y, 0.0, facing)
        corners.append((origin[0] + px, origin[1] + py))
    return corners


# ---------------------------------------------------------------------------
# colour
# ---------------------------------------------------------------------------

def C(value: str, alpha: float = 1.0) -> np.ndarray:
    """Hex colour to a float RGB(A) vector."""
    value = value.lstrip("#")
    rgb = np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)],
                   dtype=np.float32)
    if alpha >= 1.0:
        return rgb
    return np.array([rgb[0], rgb[1], rgb[2], alpha], dtype=np.float32)


INK = C("241d29")
CREAM = C("f4e7c6")
CREAM_DARK = C("d9c69c")
STONE = C("cfc3a1")
STONE_DARK = C("9d9478")
STONE_LIGHT = C("e5dcc0")
SLATE = C("68717f")
SLATE_DARK = C("4c5561")
WOOD = C("9a6238")
WOOD_LIGHT = C("c08850")
WOOD_DARK = C("5c3820")
GLASS = C("79b9d6")
GLASS_LIGHT = C("c4edf7")
GLASS_DARK = C("3f7d9e")
ROOF_RED = C("bb5b42")
ROOF_RED_DARK = C("8f3f2f")
ROOF_BROWN = C("87503a")
ROOF_BROWN_DARK = C("613426")
ROOF_GREEN = C("4e7456")
ROOF_GREEN_DARK = C("36543d")
ROOF_SLATE = C("5e6977")
ROOF_SLATE_DARK = C("414b57")
GOLD = C("efc04f")
GOLD_DARK = C("b3842e")
WATER = C("51a8d8")
WATER_DEEP = C("2f7bae")
WATER_LIGHT = C("9adcf2")
SAND = C("e6d39a")
GRASS = C("77ab58")
GRASS_LIGHT = C("95c96c")
GREEN_TURF = C("7fd070")
BUNKER = C("eadcb0")
TARMAC = C("555b62")
TARMAC_LIGHT = C("686f77")
WHITE = C("f7f4e7")
RED = C("cf4f3c")
BLUE = C("4d7dc2")
PINK = C("e092ad")
YELLOW = C("f0d463")
LAMP = C("ffe49a")
NEON_PINK = C("ff5fa2")
NEON_CYAN = C("5ff0ff")
MAROON = C("71323d")
MAROON_DARK = C("4e2028")
LEAF = C("4c8a45")
LEAF_DARK = C("35673a")
LEAF_LIGHT = C("6dab55")
HAY = C("d9b95c")


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Material:
    """A surface: base colour, optional procedural pattern or decal texture."""
    color: np.ndarray
    pattern: str = "flat"
    color2: np.ndarray | None = None
    texture: np.ndarray | None = None
    alpha: float = 1.0
    unlit: bool = False
    specular: float = 0.0
    emissive: float = 0.0
    label: str = ""


def mat(color, pattern: str = "flat", color2=None, **kwargs) -> Material:
    if isinstance(color, Material):
        color = color.color
    if color2 is not None and isinstance(color2, Material):
        color2 = color2.color
    if not isinstance(color, np.ndarray):
        color = C(color)
    if color2 is not None and not isinstance(color2, np.ndarray):
        color2 = C(color2)
    return Material(color=color, pattern=pattern, color2=color2, **kwargs)


# Common materials, shared by every facility so the course keeps one palette.
PLASTER = mat(CREAM, "plank")
PLASTER_PALE = mat(C("efe2c2"), "plank")
PLASTER_WARM = mat(C("e6d1a7"), "stone")
STONE_WALL = mat(STONE, "stone")
STONE_WALL_DARK = mat(STONE_DARK, "stone")
BRICK = mat(C("b9866c"), "brick")
TIMBER = mat(WOOD, "plank")
TIMBER_LIGHT = mat(WOOD_LIGHT, "plank")
TIMBER_DARK = mat(WOOD_DARK, "plank")
PLANK_WHITE = mat(C("e9dfc7"), "plank")
ROOF_RED_MAT = mat(ROOF_RED, "shingle")
ROOF_BROWN_MAT = mat(ROOF_BROWN, "shingle")
ROOF_GREEN_MAT = mat(ROOF_GREEN, "shingle")
ROOF_SLATE_MAT = mat(ROOF_SLATE, "slate")
THATCH = mat(C("c9a45e"), "thatch")
PAVE = mat(C("d7c9a2"), "flagstone")
PAVE_DARK = mat(C("b6a882"), "flagstone")
KERB = mat(C("c2b58f"))
GRAVEL = mat(C("c4b795"), "gravel")
ASPHALT = mat(TARMAC, "asphalt")
ASPHALT_LIGHT = mat(TARMAC_LIGHT, "asphalt")
GRASS_MAT = mat(GRASS, "grass")
GRASS_LIGHT_MAT = mat(GRASS_LIGHT, "grass")
GREEN_MAT = mat(GREEN_TURF, "grass")
BUNKER_MAT = mat(BUNKER, "sand")
SAND_MAT = mat(SAND, "sand")
HEDGE = mat(LEAF, "hedge")
HEDGE_DARK = mat(LEAF_DARK, "hedge")
HEDGE_LIGHT = mat(LEAF_LIGHT, "hedge")
GLASS_MAT = mat(GLASS, "glass", specular=0.55)
GLASS_DARK_MAT = mat(GLASS_DARK, "glass", specular=0.4)
WINDOW_MAT = mat(GLASS, "glass", specular=0.5, unlit=False)
WATER_MAT = mat(WATER, "water", specular=0.4, alpha=0.82)
WATER_DEEP_MAT = mat(WATER_DEEP, "water", specular=0.35, alpha=0.9)
GOLD_MAT = mat(GOLD, "flat", specular=0.3)
GOLD_DARK_MAT = mat(GOLD_DARK)
WHITE_MAT = mat(WHITE)
CREAM_MAT = mat(CREAM)
STONE_MAT = mat(STONE)
STONE_DARK_MAT = mat(STONE_DARK)
SLATE_MAT = mat(SLATE)
SLATE_DARK_MAT = mat(SLATE_DARK)
WOOD_MAT = mat(WOOD, "plank")
WOOD_LIGHT_MAT = mat(WOOD_LIGHT, "plank")
WOOD_DARK_MAT = mat(WOOD_DARK, "plank")
RED_MAT = mat(RED)
BLUE_MAT = mat(BLUE)
PINK_MAT = mat(PINK)
YELLOW_MAT = mat(YELLOW)
LAMP_MAT = mat(LAMP, unlit=True, emissive=0.35)
HAY_MAT = mat(HAY, "thatch")
INK_MAT = mat(INK)
SHADOW_MAT = mat(C("2f3d28"), alpha=0.34, unlit=True)
SHADOW_SOFT = mat(C("34432b"), alpha=0.17, unlit=True)
SMOKE = mat(C("e8e6df"), alpha=0.20, unlit=True)
STEAM = mat(C("f2f7f5"), alpha=0.26, unlit=True)
ROPE = mat(C("d8c9a6"))


# ---------------------------------------------------------------------------
# procedural patterns (coordinates in world pixels)
# ---------------------------------------------------------------------------

def _hash01(ix: np.ndarray, iy: np.ndarray) -> np.ndarray:
    n = (ix.astype(np.int64) * 73856093) ^ (iy.astype(np.int64) * 19349663)
    return ((n & 0xFFFF).astype(np.float32) / 65535.0)


def _mix(a: np.ndarray, b: np.ndarray, t):
    return a + (b - a) * t


def _rgb_array(color: np.ndarray, n: int):
    return np.broadcast_to(color.reshape(1, 3), (n, 3))


def pattern_rgb(m: Material, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Evaluate a material's procedural pattern for arrays of world-pixel UVs."""
    color = m.color.reshape(1, 3)
    n = u.shape[0]
    name = m.pattern
    if name == "flat" or name == "":
        return np.broadcast_to(color, (n, 3))

    if name == "plaster":
        h = _hash01(np.floor(u / 3).astype(np.int64), np.floor(v / 3).astype(np.int64))
        return np.broadcast_to(color, (n, 3)) * (0.96 + h[:, None] * 0.06)

    if name == "brick":
        row = np.floor(v / 4.0).astype(np.int64)
        x = u + np.where(row % 2 == 0, 0.0, 4.5)
        course = np.abs(v - (row * 4.0)) < 0.9
        joint = np.abs(x - np.floor(x / 9.0) * 9.0) < 0.85
        tone = _hash01(np.floor(x / 9.0).astype(np.int64), row)
        out = color * (0.91 + tone[:, None] * 0.16)
        return np.where((course | joint)[:, None], color * 0.78, out)

    if name == "stone":
        row = np.floor(v / 5.0).astype(np.int64)
        x = u + np.where(row % 2 == 0, 0.0, 5.5)
        course = np.abs(v - row * 5.0) < 0.8
        joint = np.abs(x - np.floor(x / 11.0) * 11.0) < 0.8
        tone = _hash01(np.floor(x / 11.0).astype(np.int64), row)
        out = color * (0.9 + tone[:, None] * 0.18)
        return np.where((course | joint)[:, None], color * 0.76, out)

    if name == "plank":
        board = np.floor(u / 6.0).astype(np.int64)
        edge = np.abs(u - board * 6.0) < 0.9
        grain = np.sin(u * 1.7 + v * 0.11) * 0.035
        tone = _hash01(board, np.zeros_like(board))[:, None]
        out = color * (0.96 + grain[:, None] + tone * 0.05)
        return np.where(edge[:, None], color * 0.78, out)

    if name == "bark":
        # Deep vertical grooves that meander only slightly, crossed by short
        # horizontal checks and a fine grain: oak and pine bark, not a snake.
        warp = np.sin(v * 0.16 + np.sin(v * 0.05) * 1.3) * 0.07
        groove = np.sin(u * 1.55 + warp) * 0.65 \
            + np.sin(u * 3.30 + 0.7) * 0.35
        grain = _hash01(np.floor(u / 1.3).astype(np.int64),
                        np.floor(v / 2.8).astype(np.int64))
        check = _hash01(np.floor(u / 2.5).astype(np.int64),
                        np.floor(v / 7.0).astype(np.int64))
        fleck = _hash01(np.floor(u / 4.0).astype(np.int64),
                        np.floor(v / 11.0).astype(np.int64))
        out = color * (0.93 + groove[:, None] * 0.07
                       + grain[:, None] * 0.08)
        out = np.where((groove > 0.80)[:, None], out * 0.68, out)
        out = np.where((groove < -0.86)[:, None], out * 1.07, out)
        out = np.where((check < 0.10)[:, None], out * 0.82, out)
        out = np.where((fleck > 0.992)[:, None],
                       _mix(out, np.clip(color * 1.30 + 0.05, 0, 1), 0.3), out)
        return np.clip(out, 0, 1)

    if name == "birch":
        # White paper bark with lenticels scattered over the surface, not laid
        # out in rings: each 2.6 px cell has a chance of carrying one short
        # dark dash, so the marks wander the way real birch markings do.
        cell = 2.6
        cu = np.floor(u / cell).astype(np.int64)
        cv = np.floor(v / cell).astype(np.int64)
        present = _hash01(cu * 7 + 3, cv * 11 + 5) > 0.66
        du = np.mod(u, cell)
        dv = np.mod(v, cell)
        dash_w = 1.2 + _hash01(cu * 13 + 1, cv * 3 + 9) * 1.6
        dash = present & (dv < 1.0) & (du < dash_w)
        # A few longer peeled scars, also laid across the grain.
        scar = ((_hash01(np.floor(u / 7.0).astype(np.int64) * 5 + 2,
                         np.floor(v / 13.0).astype(np.int64) * 3 + 7) > 0.88)
                & (np.mod(v, 13.0) < 1.2))
        grain = _hash01(np.floor(u / 1.6).astype(np.int64),
                        np.floor(v / 2.4).astype(np.int64))
        out = color * (0.955 + grain[:, None] * 0.06)
        out = np.where(dash[:, None], out * 0.18, out)
        out = np.where(scar[:, None], out * 0.40, out)
        return np.clip(out, 0, 1)

    if name == "leaf":
        # Dappled foliage: soft flecks of light and shade at leaf scale, so a
        # canopy clump reads as leaves rather than a smooth ball - kept gentle
        # enough to stay one mass up close.
        fine = _hash01(np.floor(u / 4.0).astype(np.int64),
                       np.floor(v / 4.0).astype(np.int64))
        coarse = _hash01(np.floor(u / 9.0).astype(np.int64),
                         np.floor(v / 9.0).astype(np.int64))
        out = color * (0.90 + fine[:, None] * 0.14 + coarse[:, None] * 0.10)
        return np.clip(out, 0, 1)

    if name == "leaf_fine":
        # The tree art's foliage surface: leaf-scale dapple with a little
        # sparkle where the sun catches an upper leaf.  Two fleck scales keep
        # a clump reading as a cluster of leaves instead of a shaded ball, and
        # the sparse glints give the canopy its sunlit, hand-painted feel.
        fine = _hash01(np.floor(u / 2.5).astype(np.int64),
                       np.floor(v / 2.5).astype(np.int64))
        flake = _hash01(np.floor(u / 6.0).astype(np.int64),
                        np.floor(v / 5.0).astype(np.int64))
        depth = _hash01(np.floor(u / 11.0).astype(np.int64),
                        np.floor(v / 13.0).astype(np.int64))
        out = color * (0.86 + fine[:, None] * 0.12
                       + flake[:, None] * 0.09 + depth[:, None] * 0.05)
        glint = (fine > 0.88) & (flake > 0.52) & (depth > 0.35)
        sunlit = np.clip(color * 1.18 + 0.03, 0, 1)
        out = np.where(glint[:, None], _mix(out, sunlit, 0.55), out)
        return np.clip(out, 0, 1)

    if name == "needle":
        # Conifer needles: short diagonal strokes rather than round leaves,
        # so a pine's pads and boughs read as brush, not broccoli.
        stroke = (np.sin(u * 1.35 + v * 2.10) * 0.5
                  + np.sin(u * 2.05 - v * 0.65) * 0.5)
        fleck = _hash01(np.floor(u / 2.0).astype(np.int64),
                        np.floor(v / 2.0).astype(np.int64))
        out = color * (0.89 + stroke[:, None] * 0.07 + fleck[:, None] * 0.09)
        return np.clip(out, 0, 1)

    if name == "bloom":
        # Heather and flower heads: dense little baubles, with brighter tips.
        bauble = _hash01(np.floor(u / 1.5).astype(np.int64),
                         np.floor(v / 1.5).astype(np.int64))
        patch = _hash01(np.floor(u / 4.0).astype(np.int64),
                        np.floor(v / 4.0).astype(np.int64))
        out = color * (0.86 + bauble[:, None] * 0.18 + patch[:, None] * 0.10)
        bright = (bauble > 0.76) & (patch > 0.42)
        lifted = np.clip(color * 1.22 + 0.02, 0, 1)
        out = np.where(bright[:, None], _mix(out, lifted, 0.5), out)
        return np.clip(out, 0, 1)

    if name == "reed":
        # Grass and reed blades: long vertical fibres with a pale edge.
        fibre = (np.sin(u * 2.6 + v * 0.06) * 0.5
                 + np.sin(u * 5.1 + v * 0.03) * 0.5)
        fleck = _hash01(np.floor(u / 2.0).astype(np.int64),
                        np.floor(v / 3.0).astype(np.int64))
        out = color * (0.90 + fibre[:, None] * 0.09 + fleck[:, None] * 0.07)
        return np.clip(out, 0, 1)

    if name == "shingle":
        row = np.floor(v / 4.0).astype(np.int64)
        x = u + np.where(row % 2 == 0, 0.0, 4.0)
        tile = np.floor(x / 8.0).astype(np.int64)
        edge = (np.abs(v - row * 4.0) < 0.85) | (np.abs(x - tile * 8.0) < 0.8)
        tone = _hash01(tile, row)
        lit = np.clip(1.02 + (tone[:, None] - 0.5) * 0.14, 0.82, 1.13)
        out = color * lit
        out = np.where((np.abs(v - row * 4.0 - 1.2) < 0.8)[:, None],
                       out * 1.08, out)
        return np.where(edge[:, None], color * 0.72, out)

    if name == "slate":
        row = np.floor(v / 3.5).astype(np.int64)
        x = u + np.where(row % 2 == 0, 0.0, 5.0)
        tile = np.floor(x / 10.0).astype(np.int64)
        edge = (np.abs(v - row * 3.5) < 0.7) | (np.abs(x - tile * 10.0) < 0.7)
        tone = _hash01(tile, row)
        out = color * (0.92 + (tone[:, None] - 0.5) * 0.15)
        return np.where(edge[:, None], color * 0.74, out)

    if name == "thatch":
        strand = np.sin(u * 2.1 + v * 0.9) * 0.06 + np.sin(v * 3.0) * 0.03
        h = _hash01(np.floor(u / 2).astype(np.int64), np.floor(v / 2).astype(np.int64))
        out = color * (0.92 + strand[:, None] + h[:, None] * 0.1)
        return np.clip(out, 0, 1)

    if name == "flagstone":
        row = np.floor(v / 7.0).astype(np.int64)
        x = u + np.where(row % 2 == 0, 0.0, 6.0)
        tile = np.floor(x / 12.0).astype(np.int64)
        edge = (np.abs(v - row * 7.0) < 0.8) | (np.abs(x - tile * 12.0) < 0.8)
        tone = _hash01(tile, row)
        out = color * (0.92 + (tone[:, None] - 0.5) * 0.13)
        return np.where(edge[:, None], color * 0.8, out)

    if name == "gravel":
        h = _hash01(np.floor(u).astype(np.int64), np.floor(v).astype(np.int64))
        h2 = _hash01(np.floor(u / 2).astype(np.int64), np.floor(v / 2).astype(np.int64))
        out = color * (0.88 + h[:, None] * 0.2 + h2[:, None] * 0.05)
        return np.clip(out, 0, 1)

    if name == "asphalt":
        h = _hash01(np.floor(u).astype(np.int64), np.floor(v).astype(np.int64))
        out = color * (0.9 + h[:, None] * 0.18)
        return out

    if name == "grass":
        h = _hash01(np.floor(u / 2).astype(np.int64), np.floor(v / 2).astype(np.int64))
        h2 = _hash01(np.floor(u / 5).astype(np.int64), np.floor(v / 5).astype(np.int64))
        out = color * (0.9 + h[:, None] * 0.12 + h2[:, None] * 0.08)
        return np.clip(out, 0, 1)

    if name == "sand":
        h = _hash01(np.floor(u / 2).astype(np.int64), np.floor(v / 2).astype(np.int64))
        return color * (0.94 + h[:, None] * 0.1)

    if name == "hedge":
        h = _hash01(np.floor(u / 3).astype(np.int64), np.floor(v / 3).astype(np.int64))
        h2 = _hash01(np.floor(u / 6).astype(np.int64), np.floor(v / 6).astype(np.int64))
        out = color * (0.82 + h[:, None] * 0.26 + h2[:, None] * 0.1)
        return np.clip(out, 0, 1)

    if name == "water":
        wave = np.sin(u * 0.32 + v * 0.18) * 0.5 + np.sin(u * 0.12 - v * 0.29) * 0.5
        sparkle = _hash01(np.floor(u / 7).astype(np.int64), np.floor(v / 5).astype(np.int64))
        out = color * (0.9 + wave[:, None] * 0.09)
        glint = (wave > 0.74) & (sparkle > 0.45)
        out = np.where(glint[:, None], _mix(out, WATER_LIGHT, 0.55), out)
        return np.clip(out, 0, 1)

    if name == "glass":
        grad = np.clip((v * 0.045) % 1.0, 0, 1)
        out = _mix(color, GLASS_LIGHT, (0.18 + grad * 0.38)[:, None])
        streak = (np.sin((u + v) * 0.55) > 0.72) & (np.sin((u - v) * 0.18) > 0.2)
        out = np.where(streak[:, None], _mix(out, WHITE, 0.35), out)
        return np.clip(out, 0, 1)

    if name == "stripe":
        second = m.color2 if m.color2 is not None else WHITE
        sel = (np.floor(u / 8.0) % 2).astype(bool)
        return np.where(sel[:, None], second.reshape(1, 3), color)

    if name == "canvas":
        weave = (np.sin(u * 3.0) * np.sin(v * 3.0))[:, None] * 0.04
        return np.clip(color + weave, 0, 1)

    if name == "lamp":
        pulse = 0.85 + 0.15 * np.sin(u * 0.5)
        return color * pulse[:, None]

    return np.broadcast_to(color, (n, 3))


# ---------------------------------------------------------------------------
# lighting
# ---------------------------------------------------------------------------

#: Sun from the warm +x / -y side, high over the course.
SUN = np.array([0.60, -0.36, 0.72], dtype=np.float32)
SUN = SUN / np.linalg.norm(SUN)
#: Cool bounce light from the opposite side, so shaded walls stay readable.
FILL = np.array([-0.42, 0.55, 0.38], dtype=np.float32)
FILL = FILL / np.linalg.norm(FILL)
#: Direction of increasing camera depth (towards the viewer) in world pixels.
VIEW = np.array([1.0, 2.0, 2.0], dtype=np.float32)
VIEW = VIEW / np.linalg.norm(VIEW)

#: Quantised sun exposure keeps the flat pixel-art look.
SHADE_LEVELS = np.array(
    [0.44, 0.52, 0.60, 0.68, 0.76, 0.84, 0.92, 1.00, 1.08, 1.16, 1.24],
    dtype=np.float32)


def shade_factor(normal: np.ndarray) -> float:
    unit = normal / max(float(np.linalg.norm(normal)), 1e-9)
    diffuse = max(0.0, float(np.dot(unit, SUN)))
    fill = max(0.0, float(np.dot(unit, FILL)))
    up = max(0.0, float(unit[2]))
    raw = 0.40 + 0.68 * diffuse + 0.22 * fill + 0.08 * up
    raw = min(max(raw, 0.0), 1.3)
    index = int(np.argmin(np.abs(SHADE_LEVELS - raw)))
    return float(SHADE_LEVELS[index])


def specular_factor(normal: np.ndarray, strength: float) -> float:
    if strength <= 0.0:
        return 0.0
    unit = normal / max(float(np.linalg.norm(normal)), 1e-9)
    half = SUN + VIEW
    half = half / max(float(np.linalg.norm(half)), 1e-9)
    return float(max(0.0, np.dot(unit, half)) ** 18) * strength


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

@dataclass
class Tri:
    p: tuple
    uv: tuple
    ao: tuple
    normal: np.ndarray
    material: Material
    group: int
    bias: float = 0.0


class Model:
    """A building model in world-pixel space: x across, y down, z up."""

    def __init__(self, tiles_x: float, tiles_y: float):
        self.tiles = (tiles_x, tiles_y)
        self.width = tiles_x * TILE_W
        self.depth = tiles_y * TILE_H
        self.tris: list[Tri] = []
        self._group = 0

    # -- bookkeeping ------------------------------------------------------
    def group(self) -> int:
        self._group += 1
        return self._group

    def _normal(self, a, b, c) -> np.ndarray:
        n = np.cross(np.asarray(b) - np.asarray(a), np.asarray(c) - np.asarray(a))
        length = float(np.linalg.norm(n))
        if length < 1e-9:
            return np.array([0.0, 0.0, 1.0], dtype=np.float32)
        return (n / length).astype(np.float32)

    def tri(self, p0, p1, p2, material, uvs=None, ao=(1.0, 1.0, 1.0),
            group: int | None = None, bias: float = 0.0) -> None:
        if not isinstance(material, Material):
            material = mat(material)
        normal = self._normal(p0, p1, p2)
        if uvs is None:
            uvs = tuple(auto_uv(p, normal) for p in (p0, p1, p2))
        gid = self.group() if group is None else group
        self.tris.append(Tri((tuple(p0), tuple(p1), tuple(p2)),
                             (tuple(uvs[0]), tuple(uvs[1]), tuple(uvs[2])),
                             tuple(float(a) for a in ao), normal, material, gid, bias))

    def quad(self, p0, p1, p2, p3, material, uvs=None,
             ao=(1.0, 1.0, 1.0, 1.0), group: int | None = None,
             bias: float = 0.0) -> None:
        if not isinstance(material, Material):
            material = mat(material)
        if uvs is None:
            normal = self._normal(p0, p1, p2)
            uvs = tuple(auto_uv(p, normal) for p in (p0, p1, p2, p3))
        gid = self.group() if group is None else group
        self.tri(p0, p1, p2, material, (uvs[0], uvs[1], uvs[2]),
                 (ao[0], ao[1], ao[2]), gid, bias)
        self.tri(p0, p2, p3, material, (uvs[0], uvs[2], uvs[3]),
                 (ao[0], ao[2], ao[3]), gid, bias)

    # -- decals -----------------------------------------------------------
    def decal(self, p0, p1, p2, p3, material: Material, size_px,
              bias: float = 0.12) -> None:
        """A textured rectangle. ``p0`` is its top-left as the decal reads."""
        w, h = size_px
        uvs = ((0.0, 0.0), (w, 0.0), (w, h), (0.0, h))
        self.quad(p0, p1, p2, p3, material, uvs,
                  group=self.group(), bias=bias)


def auto_uv(p, normal) -> tuple:
    """World-pixel UVs along a face, chosen from its dominant axis."""
    x, y, z = p
    nx, ny, nz = abs(normal[0]), abs(normal[1]), abs(normal[2])
    if nz >= nx and nz >= ny:
        return (x, y)
    if nx >= ny:
        return (y, z)
    return (x, z)


# ---------------------------------------------------------------------------
# procedural decal textures
# ---------------------------------------------------------------------------

_FONT = {
    "A": ("010", "101", "111", "101", "101"), "B": ("110", "101", "110", "101", "110"),
    "C": ("011", "100", "100", "100", "011"), "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"), "F": ("111", "100", "110", "100", "100"),
    "G": ("011", "100", "101", "101", "011"), "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"), "J": ("001", "001", "001", "101", "010"),
    "K": ("101", "101", "110", "101", "101"), "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"), "N": ("101", "111", "111", "111", "101"),
    "O": ("010", "101", "101", "101", "010"), "P": ("110", "101", "110", "100", "100"),
    "Q": ("010", "101", "101", "110", "011"), "R": ("110", "101", "110", "101", "101"),
    "S": ("011", "100", "010", "001", "110"), "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"), "V": ("101", "101", "101", "101", "010"),
    "W": ("101", "101", "111", "111", "101"), "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"), "Z": ("111", "001", "010", "100", "111"),
    "0": ("111", "101", "101", "101", "111"), "1": ("010", "110", "010", "010", "111"),
    "2": ("110", "001", "010", "100", "111"), "3": ("110", "001", "010", "001", "110"),
    "4": ("101", "101", "111", "001", "001"), "5": ("111", "100", "110", "001", "110"),
    "6": ("011", "100", "111", "101", "111"), "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"), "9": ("111", "101", "111", "001", "110"),
    " ": ("000", "000", "000", "000", "000"), ".": ("000", "000", "000", "000", "010"),
    "-": ("000", "000", "111", "000", "000"), "&": ("010", "101", "010", "101", "011"),
    "": ("000", "000", "000", "000", "000"),
}


def _to_array(image: Image.Image) -> np.ndarray:
    arr = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    return arr


def text_texture(text: str, fg, bg=None, scale: int = 1, padding: int = 2,
                 border=None) -> tuple[np.ndarray, tuple[int, int]]:
    """A crisp 3x5 pixel-font sign, returned with its pixel size."""
    fg255 = tuple(int(round(float(c) * 255)) for c in fg[:3])
    bg255 = None if bg is None else tuple(int(round(float(c) * 255)) for c in bg[:3])
    border255 = None if border is None else tuple(int(round(float(c) * 255)) for c in border[:3])
    glyph_w = max(1, len(text) * 4 - 1) * scale
    glyph_h = 5 * scale
    width = glyph_w + padding * 2
    height = glyph_h + padding * 2
    image = Image.new("RGBA", (width, height), (*bg255, 255) if bg255 else (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if border255 is not None:
        draw.rectangle([0, 0, width - 1, height - 1], outline=(*border255, 255), width=1)
    for index, char in enumerate(text.upper()):
        glyph = _FONT.get(char, _FONT[" "])
        for row, bits in enumerate(glyph):
            for col, bit in enumerate(bits):
                if bit != "1":
                    continue
                x = padding + (index * 4 + col) * scale
                y = padding + row * scale
                draw.rectangle([x, y, x + scale - 1, y + scale - 1], fill=(*fg255, 255))
    return _to_array(image), (width, height)


def simple_texture(draw_fn, width: int, height: int) -> tuple[np.ndarray, tuple[int, int]]:
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(image), width, height)
    return _to_array(image), (width, height)


def _rgb255(colour) -> tuple[int, int, int]:
    """Colour palette name, rgb tuple, ndarray or Material to 0..255 tuple."""
    if isinstance(colour, Material):
        colour = colour.color
    if isinstance(colour, str):
        colour = C(colour)
    return tuple(int(round(float(c) * 255)) for c in colour[:3])


def window_texture(width=14, height=18, frame=None, glass=None, lit=False,
                   mullions=True, reflection=True):
    """A window decal painted at one texel per world pixel."""
    frame = frame if frame is not None else WOOD_DARK
    glass = glass if glass is not None else (LAMP if lit else GLASS)
    fg = _rgb255(frame)
    gg = _rgb255(glass)
    light = _rgb255(LAMP if lit else GLASS_LIGHT)
    white = _rgb255(WHITE if lit else GLASS_LIGHT)

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=fg)
        draw.rectangle([2, 2, w - 3, h - 3], fill=gg)
        draw.rectangle([2, 2, w - 3, 3], fill=light)
        if mullions:
            midx = w // 2
            midy = h // 2
            draw.rectangle([midx, 2, midx, h - 3], fill=fg)
            draw.rectangle([2, midy, w - 3, midy], fill=fg)
        if reflection:
            draw.line([(3, h - 5), (w - 5, 4)], fill=white, width=1)
            draw.line([(4, h - 4), (w - 4, 5)], fill=light, width=1)

    return simple_texture(paint, width, height)


def door_texture(width=16, height=24, colour=None, frame=None, knob=None,
                 panels=True):
    colour = colour if colour is not None else WOOD
    frame = frame if frame is not None else CREAM
    knob = knob if knob is not None else GOLD
    cc = _rgb255(colour)
    fc = _rgb255(frame)
    kc = _rgb255(knob)

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=fc)
        draw.rectangle([1, 1, w - 2, h - 2], fill=cc)
        if panels:
            draw.rectangle([2, 2, w - 3, h // 2 - 2], outline=tuple(int(c * 0.75) for c in cc))
            draw.rectangle([2, h // 2 + 1, w - 3, h - 3], outline=tuple(int(c * 0.75) for c in cc))
        draw.rectangle([w - 4, h // 2, w - 3, h // 2 + 1], fill=kc)
        draw.line([(2, 1), (2, h - 2)], fill=tuple(min(255, int(c * 1.2)) for c in cc))

    return simple_texture(paint, width, height)


def clock_texture(size=11):
    cream = tuple(int(c * 255) for c in CREAM[:3])
    ink = tuple(int(c * 255) for c in INK[:3])
    gold = tuple(int(c * 255) for c in GOLD[:3])

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=gold)
        draw.rectangle([1, 1, w - 2, h - 2], fill=cream)
        for i in range(w):
            draw.point((i, 0), fill=gold)
            draw.point((i, h - 1), fill=gold)
        draw.line([(w // 2, h // 2), (w // 2, 2)], fill=ink)
        draw.line([(w // 2, h // 2), (w - 3, h // 2 + 1)], fill=ink)
        draw.point((w // 2, h // 2), fill=ink)

    return simple_texture(paint, size, size)


def display_texture(width=18, height=12, frame=None, glass=None):
    frame = frame if frame is not None else WOOD_DARK
    glass = glass if glass is not None else GLASS_DARK
    fc = tuple(int(c * 255) for c in frame[:3])
    gc = tuple(int(c * 255) for c in glass[:3])

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=fc)
        draw.rectangle([1, 1, w - 2, h - 2], fill=gc)
        draw.line([(2, h - 3), (w - 4, 2)], fill=tuple(int(c * 255) for c in GLASS_LIGHT[:3]))
        draw.line([(3, h - 2), (w - 3, 3)], fill=tuple(int(c * 255) for c in GLASS_LIGHT[:3]))
        draw.rectangle([3, h - 6, 5, h - 4], fill=tuple(int(c * 255) for c in RED[:3]))
        draw.rectangle([6, h - 6, 8, h - 3], fill=tuple(int(c * 255) for c in BLUE[:3]))
        draw.rectangle([9, h - 6, 11, h - 4], fill=tuple(int(c * 255) for c in GOLD[:3]))

    return simple_texture(paint, width, height)


def menu_texture(width=22, height=16):
    board = tuple(int(c * 255) for c in WOOD_DARK[:3])
    paper = tuple(int(c * 255) for c in CREAM[:3])
    ink = tuple(int(c * 255) for c in INK[:3])

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=board)
        draw.rectangle([2, 2, w - 3, h - 3], fill=paper)
        for y in range(5, h - 4, 3):
            draw.line([(4, y), (w - 5, y)], fill=ink)

    return simple_texture(paint, width, height)


def marquee_texture(width=60, height=8):
    maroon = tuple(int(c * 255) for c in MAROON[:3])
    gold = tuple(int(c * 255) for c in GOLD[:3])
    bright = tuple(int(c * 255) for c in LAMP[:3])

    def paint(draw, w, h):
        draw.rectangle([0, 0, w - 1, h - 1], fill=maroon)
        for x in range(1, w - 1, 3):
            draw.rectangle([x, 1, x + 1, 2], fill=gold)
            draw.rectangle([x, h - 3, x + 1, h - 2], fill=gold)
        for x in range(2, w - 2, 6):
            draw.point((x, h // 2), fill=bright)

    return simple_texture(paint, width, height)


def net_texture(width=64, height=14):
    white = tuple(int(c * 255) for c in WHITE[:3])

    def paint(draw, w, h):
        for x in range(0, w, 2):
            draw.line([(x, 0), (x, h - 1)], fill=(*white, 190))
        for y in range(0, h, 2):
            draw.line([(0, y), (w - 1, y)], fill=(*white, 190))
        draw.line([(0, 0), (w - 1, 0)], fill=(*white, 255), width=1)
        draw.line([(0, h - 1), (w - 1, h - 1)], fill=(*white, 255), width=1)

    return simple_texture(paint, width, height)


# ---------------------------------------------------------------------------
# renderer
# ---------------------------------------------------------------------------

def _sample_texture(tex: np.ndarray, u: np.ndarray, v: np.ndarray,
                    texel_scale: float = 1.0) -> np.ndarray:
    h, w = tex.shape[:2]
    tx = np.clip(np.floor(u * texel_scale).astype(np.int32), 0, w - 1)
    ty = np.clip(np.floor(v * texel_scale).astype(np.int32), 0, h - 1)
    return tex[ty, tx]


def _triangle_raster(sx, sy, depth, inside_args, w, h, out, zbuf,
                     shade, extra=None):
    """Rasterise one triangle. Returns the boolean mask of written pixels."""
    x0, x1, x2 = sx
    y0, y1, y2 = sy
    area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
    if abs(area) < 1e-9:
        return None
    minx = max(0, int(math.floor(min(x0, x1, x2))))
    maxx = min(w - 1, int(math.ceil(max(x0, x1, x2))))
    miny = max(0, int(math.floor(min(y0, y1, y2))))
    maxy = min(h - 1, int(math.ceil(max(y0, y1, y2))))
    if minx > maxx or miny > maxy:
        return None
    xs = np.arange(minx, maxx + 1, dtype=np.float32) + 0.5
    ys = np.arange(miny, maxy + 1, dtype=np.float32) + 0.5
    X = xs[None, :]
    Y = ys[:, None]
    e0 = (x2 - x1) * (Y - y1) - (y2 - y1) * (X - x1)
    e1 = (x0 - x2) * (Y - y2) - (y0 - y2) * (X - x2)
    e2 = (x1 - x0) * (Y - y0) - (y1 - y0) * (X - x0)
    if area > 0:
        inside = (e0 >= -0.001) & (e1 >= -0.001) & (e2 >= -0.001)
    else:
        inside = (e0 <= 0.001) & (e1 <= 0.001) & (e2 <= 0.001)
    if not inside.any():
        return None
    l0 = e0 / area
    l1 = e1 / area
    l2 = e2 / area
    d = l0 * depth[0] + l1 * depth[1] + l2 * depth[2]
    mask = inside & (d > zbuf[miny:maxy + 1, minx:maxx + 1])
    if not mask.any():
        return None
    rows, cols = np.nonzero(mask)
    pr = rows + miny
    pc = cols + minx
    l0m = l0[mask]
    l1m = l1[mask]
    l2m = l2[mask]
    dm = d[mask]
    result = {
        "rows": pr, "cols": pc, "depth": dm,
        "bary": (l0m, l1m, l2m),
    }
    return result


def render(model: Model, facing: int, scale: float = OUTPUT_SCALE,
           supersample: int = SUPERSAMPLE, pad=(10.0, 10.0, 4.0, 10.0),
           outline: bool = True):
    """Rasterise a model for one view rotation.

    Returns ``(PIL.Image, rect)`` where ``rect`` is ``(x, y, width, height)`` in
    the local draw space of the building node, in world pixels.
    """
    tiles_x, tiles_y = model.tiles
    origin = grid_origin_offset(tiles_x, tiles_y, facing)

    # -- project all vertices to find the canvas -------------------------
    projected = []
    for tri in model.tris:
        for x, y, z in tri.p:
            px, py = project(x, y, z, facing)
            projected.append((origin[0] + px, origin[1] + py))
    if not projected:
        raise ValueError("model has no faces")
    min_x = min(p[0] for p in projected)
    max_x = max(p[0] for p in projected)
    min_y = min(p[1] for p in projected)
    max_y = max(p[1] for p in projected)
    pl, pr, pb, pt = pad
    left = min_x - pl
    right = max_x + pr
    top = min_y - pt
    bottom = max_y + pb

    factor = float(scale) * int(supersample)
    width = max(1, int(math.ceil((right - left) * factor)))
    height = max(1, int(math.ceil((bottom - top) * factor)))

    premult = np.zeros((height, width, 3), dtype=np.float32)
    alpha = np.zeros((height, width), dtype=np.float32)
    zbuf = np.full((height, width), -1e18, dtype=np.float32)
    groups = np.zeros((height, width), dtype=np.int32)

    # -- prepare triangles ------------------------------------------------
    prepared = []
    for tri in model.tris:
        pts = []
        uvs = []
        aos = []
        depth = []
        for (x, y, z), (tu, tv), ao in zip(tri.p, tri.uv, tri.ao):
            px, py = project(x, y, z, facing)
            pts.append(((origin[0] + px - left) * factor,
                        (origin[1] + py - top) * factor))
            uvs.append((tu, tv))
            aos.append(ao)
            u, v = x / TILE_W, y / TILE_H
            ru, rv = rotate_uv(u, v, facing)
            depth.append(ru + rv + z / TILE_H + tri.bias)
        prepared.append((tri, pts, uvs, aos, depth))

    # -- opaque pass ------------------------------------------------------
    for tri, pts, uvs, aos, depth in prepared:
        if tri.material.alpha < 0.999:
            continue
        sx = [p[0] for p in pts]
        sy = [p[1] for p in pts]
        result = _triangle_raster(sx, sy, depth, None, width, height, premult, zbuf, 1.0)
        if result is None:
            continue
        rows, cols = result["rows"], result["cols"]
        l0, l1, l2 = result["bary"]
        u = l0 * uvs[0][0] + l1 * uvs[1][0] + l2 * uvs[2][0]
        v = l0 * uvs[0][1] + l1 * uvs[1][1] + l2 * uvs[2][1]
        ao = l0 * aos[0] + l1 * aos[1] + l2 * aos[2]
        material = tri.material
        if material.texture is not None:
            base = _sample_texture(material.texture, u, v)[:, :3]
            tex_alpha = _sample_texture(material.texture, u, v)[:, 3:4]
        else:
            base = pattern_rgb(material, u, v)
            tex_alpha = None
        if material.unlit:
            light = np.ones_like(ao)
        else:
            light = np.full_like(ao, shade_factor(tri.normal))
            spec = specular_factor(tri.normal, material.specular)
            if spec > 0:
                base = np.clip(base + spec * 0.8, 0, 1)
        colour = np.clip(base * (light * ao)[:, None], 0, 1)
        if material.emissive:
            colour = np.clip(colour + material.color.reshape(1, 3) * material.emissive, 0, 1)
        if tex_alpha is not None:
            a = tex_alpha[:, 0]
            # Decal textures with alpha on an opaque pass: drop transparent
            # texels by leaving the previous surface untouched.
            solid = a > 0.5
            rows, cols, colour = rows[solid], cols[solid], colour[solid]
            if rows.size == 0:
                continue
        premult[rows, cols] = colour
        alpha[rows, cols] = 1.0
        # Write depths for the pixels that survived any texture alpha trim.
        # (rows/cols may have been filtered, so recompute the matching values.)
        if tex_alpha is not None:
            dm = result["depth"][solid]
        else:
            dm = result["depth"]
        zbuf[rows, cols] = dm
        groups[rows, cols] = tri.group

    # -- translucent pass (decals, water, shadows, smoke) -----------------
    transparent = [p for p in prepared if p[0].material.alpha < 0.999]
    transparent.sort(key=lambda item: float(sum(item[4])) / 3.0)
    for tri, pts, uvs, aos, depth in transparent:
        sx = [p[0] for p in pts]
        sy = [p[1] for p in pts]
        result = _triangle_raster(sx, sy, depth, None, width, height, premult, zbuf, 1.0)
        if result is None:
            continue
        rows, cols = result["rows"], result["cols"]
        l0, l1, l2 = result["bary"]
        u = l0 * uvs[0][0] + l1 * uvs[1][0] + l2 * uvs[2][0]
        v = l0 * uvs[0][1] + l1 * uvs[1][1] + l2 * uvs[2][1]
        ao = l0 * aos[0] + l1 * aos[1] + l2 * aos[2]
        material = tri.material
        if material.texture is not None:
            texel = _sample_texture(material.texture, u, v)
            base = texel[:, :3]
            a = texel[:, 3] * material.alpha
        else:
            base = pattern_rgb(material, u, v)
            a = np.full_like(ao, material.alpha)
        if material.unlit:
            colour = base
        else:
            light = np.full_like(ao, shade_factor(tri.normal))
            colour = np.clip(base * (light * ao)[:, None], 0, 1)
        keep = a > 0.002
        rows, cols, colour, a = rows[keep], cols[keep], colour[keep], a[keep]
        if rows.size == 0:
            continue
        dst = premult[rows, cols]
        dst_a = alpha[rows, cols]
        premult[rows, cols] = colour * a[:, None] + dst * (1.0 - a[:, None])
        alpha[rows, cols] = a + dst_a * (1.0 - a)

    # -- downsample -------------------------------------------------------
    ss = int(supersample)
    if ss > 1:
        h2, w2 = height // ss, width // ss
        original_alpha = alpha[:h2 * ss, :w2 * ss].reshape(h2, ss, w2, ss)
        group_block = groups[:h2 * ss, :w2 * ss].reshape(h2, ss, w2, ss)
        premult = premult[:h2 * ss, :w2 * ss].reshape(h2, ss, w2, ss, 3).mean(axis=(1, 3))
        alpha = original_alpha.mean(axis=(1, 3))
        # Pick the group of the most opaque sub-sample, not just the centre,
        # so a face that fills only part of a pixel still keeps its edge.
        a_flat = original_alpha.transpose(0, 2, 1, 3).reshape(h2, w2, ss * ss)
        g_flat = group_block.transpose(0, 2, 1, 3).reshape(h2, w2, ss * ss)
        choice = a_flat.argmax(axis=2)[:, :, None]
        groups = np.take_along_axis(g_flat, choice, axis=2)[:, :, 0]
        height, width = h2, w2

    opaque = alpha > 0.45
    painted = alpha > 0.002
    rgb = np.zeros((height, width, 3), dtype=np.float32)
    rgb[painted] = np.clip(premult[painted] / alpha[painted, None], 0, 1)

    # -- pixel-art outlining ---------------------------------------------
    if outline and opaque.any():
        ink = INK
        # Crease lines where a different face begins.
        different = np.zeros_like(opaque)
        diff_right = opaque[:, 1:] & opaque[:, :-1] & (groups[:, 1:] != groups[:, :-1])
        diff_down = opaque[1:, :] & opaque[:-1, :] & (groups[1:, :] != groups[:-1, :])
        different[:, 1:] |= diff_right
        different[:, :-1] |= diff_right
        different[1:, :] |= diff_down
        different[:-1, :] |= diff_down
        rgb[different] = rgb[different] * 0.66 + ink * 0.34
        # Darker silhouette all round.
        edge = np.zeros_like(opaque)
        edge[:, 1:] |= opaque[:, 1:] & ~opaque[:, :-1]
        edge[:, :-1] |= opaque[:, :-1] & ~opaque[:, 1:]
        edge[1:, :] |= opaque[1:, :] & ~opaque[:-1, :]
        edge[:-1, :] |= opaque[:-1, :] & ~opaque[1:, :]
        edge[0, :] |= opaque[0, :]
        edge[-1, :] |= opaque[-1, :]
        edge[:, 0] |= opaque[:, 0]
        edge[:, -1] |= opaque[:, -1]
        rgb[edge] = rgb[edge] * 0.50 + ink * 0.50

    # -- crop to painted pixels ------------------------------------------
    rows = np.where(painted.any(axis=1))[0]
    cols = np.where(painted.any(axis=0))[0]
    if rows.size == 0 or cols.size == 0:
        raise ValueError("model drew nothing")
    r0, r1 = int(rows[0]), int(rows[-1]) + 1
    c0, c1 = int(cols[0]), int(cols[-1]) + 1
    rgb = rgb[r0:r1, c0:c1]
    out_alpha = np.clip(np.round(alpha[r0:r1, c0:c1] * 255), 0, 255).astype(np.uint8)

    image = Image.fromarray(
        np.dstack([np.clip(rgb * 255, 0, 255).astype(np.uint8), out_alpha]),
        mode="RGBA")

    rect = (left + c0 / scale, top + r0 / scale,
            (c1 - c0) / scale, (r1 - r0) / scale)
    return image, rect
