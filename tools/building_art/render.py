#!/usr/bin/env python3
"""Tiny isometric pixel-art renderer for Golf Tycoon's building sprites.

The game projects grid space (u across, v down, z up in world pixels) through
2:1 isometric axes; this module renders the same projection onto an art-pixel
canvas (ART_SCALE world pixels per art pixel) with a z-buffer, so every sprite
sits on exactly the tiles it occupies at every view rotation.

A scene is a list of planar faces: a vertical wall (u or v fixed), a flat face
(z fixed), or a slope (z = a*u + b*v + c). Each face is rasterised by solving
the projection backwards for every art pixel, testing the pixel against the
face's polygon and writing the colour if the face is the nearest one seen.
That gives crisp pixel art with correct occlusion and no anti-aliasing.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

TILE_W = 64.0
TILE_H = 32.0
HALF_W = TILE_W * 0.5
HALF_H = TILE_H * 0.5
ART_SCALE = 1.0  # world pixels per art pixel


# ---------------------------------------------------------------------------
# colours
# ---------------------------------------------------------------------------

def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def mul(colour, factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(channel * factor)))) for channel in colour)


def mix(a, b, t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(colour, normal) -> tuple[int, int, int]:
    """Sun over the course's +u side, as CourseArchitecture used to draw it."""
    nx, ny = normal
    if nx > 0.5:
        return mul(colour, 1.0)
    if nx < -0.5:
        return mul(colour, 0.74)
    if ny > 0.5:
        return mul(colour, 0.84)
    return mul(colour, 0.93)


INK = rgb("2a2330")
CREAM = rgb("efe3c4")
CREAM_DARK = rgb("d6c6a0")
STONE = rgb("c3b795")
STONE_DARK = rgb("968c72")
SLATE = rgb("6a7280")
WOOD = rgb("8c5a37")
WOOD_LIGHT = rgb("b17a4a")
WOOD_DARK = rgb("57341f")
GLASS = rgb("8fc8dd")
GLASS_LIGHT = rgb("c9ecf4")
ROOF_RED = rgb("a8543f")
ROOF_BROWN = rgb("7d4a38")
ROOF_GREEN = rgb("4f6d52")
ROOF_SLATE = rgb("5b6470")
GOLD = rgb("e0b64a")
WATER = rgb("54a8d6")
WATER_DEEP = rgb("3b82b4")
SAND = rgb("e2d29a")
GRASS = rgb("77a955")
GREEN_TURF = rgb("79c96b")
BUNKER = rgb("e7d9ae")
TARMAC = rgb("585d63")
WHITE = rgb("f4f1e2")
RED = rgb("c8503f")
BLUE = rgb("4f7fbf")
PINK = rgb("d98aa6")
YELLOW = rgb("e8cf6a")
LAMP = rgb("ffd984")


# ---------------------------------------------------------------------------
# projection
# ---------------------------------------------------------------------------

def rotate_uv(u: float, v: float, facing: int):
    facing %= 4
    if facing == 1:
        return (-v, u)
    if facing == 2:
        return (-u, -v)
    if facing == 3:
        return (v, -u)
    return (u, v)


def projection_matrix(facing: int):
    """Rows of the 2x2 grid-space -> rotated-space matrix."""
    return {
        0: ((1.0, 0.0), (0.0, 1.0)),
        1: ((0.0, -1.0), (1.0, 0.0)),
        2: ((-1.0, 0.0), (0.0, -1.0)),
        3: ((0.0, 1.0), (-1.0, 0.0)),
    }[facing % 4]


def project(u: float, v: float, z: float, facing: int):
    ru, rv = rotate_uv(u, v, facing)
    return ((ru - rv) * HALF_W, (ru + rv) * HALF_H - z)


def grid_origin_offset(tiles_x: float, tiles_y: float, facing: int):
    """Where grid (0, 0) falls in the local space of a Building node.

    Mirrors CourseArchitecture.grid_origin_offset: the node sits at the
    footprint centre minus (size.x * 0.5, size.y).
    """
    size_x = tiles_x * TILE_W
    size_y = tiles_y * TILE_H
    cx, cy = tiles_x * 0.5, tiles_y * 0.5
    ru, rv = rotate_uv(cx, cy, facing)
    return (size_x * 0.5 - (ru - rv) * HALF_W,
            size_y - (ru + rv) * HALF_H)


# ---------------------------------------------------------------------------
# faces
# ---------------------------------------------------------------------------

@dataclass
class Face:
    # ('u', x) | ('v', x) | ('z', x) | ('slope', (a, b, c))
    # | ('screen', (anchor_x, anchor_y, depth)) for a viewer-facing billboard
    plane: tuple
    poly: list              # convex polygon in the plane's own 2D coordinates
    colour: tuple | None = None
    pattern: str = "flat"
    bias: float = 0.0
    fn: object = None       # callable(a, b) -> colour rgb | None
    outline: bool = True


def _inverse3(m):
    """Inverse of a 3x3 matrix, or None when it is singular."""
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if abs(det) < 1e-12:
        return None
    return (
        ((e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det),
        ((f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det),
        ((d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det),
    )


class Scene:
    def __init__(self, facing: int):
        self.facing = facing % 4
        self.faces: list[Face] = []

    def add(self, plane, poly, colour=None, pattern="flat", bias=0.0, fn=None):
        self.faces.append(Face(plane, list(poly), colour, pattern, bias, fn))

    # -- rectangles in a plane -------------------------------------------
    @staticmethod
    def rect(a0, b0, a1, b1):
        return [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]


# ---------------------------------------------------------------------------
# patterns (all coordinates in art pixels)
# ---------------------------------------------------------------------------

def _hash(x: int, y: int) -> float:
    n = (x * 73856093) ^ (y * 19349663)
    return ((n & 0xFFFF) / 65535.0)


def pattern_colour(name: str, colour, a: float, b: float):
    ai = int(math.floor(a))
    bi = int(math.floor(b))
    if name == "flat":
        return colour
    if name == "brick":
        if bi % 5 == 0:
            return mul(colour, 0.80)
        if (ai + (5 if (bi // 5) % 2 else 0)) % 11 == 0:
            return mul(colour, 0.84)
        return colour
    if name == "stone":
        if bi % 6 == 0:
            return mul(colour, 0.78)
        row = bi // 6
        if (ai + (6 if row % 2 else 0)) % 13 == 0:
            return mul(colour, 0.82)
        return mul(colour, 0.94 + _hash(ai // 13, row) * 0.10)
    if name == "plank":
        if ai % 7 == 0:
            return mul(colour, 0.76)
        if ai % 7 == 2:
            return mul(colour, 1.07)
        return colour
    if name == "shingle":
        if bi % 3 == 0:
            return mul(colour, 0.80)
        if (ai + (2 if (bi // 3) % 2 else 0)) % 5 == 0:
            return mul(colour, 0.87)
        return mul(colour, 0.96 + _hash(ai // 5, bi // 3) * 0.08)
    if name == "flagstone":
        if bi % 4 == 0 or ai % 8 == 0:
            return mul(colour, 0.86)
        return mul(colour, 0.95 + _hash(ai // 8, bi // 4) * 0.1)
    if name == "gravel":
        h = _hash(ai, bi)
        if h < 0.16:
            return mul(colour, 0.8)
        if h > 0.9:
            return mul(colour, 1.1)
        return colour
    if name == "grass":
        h = _hash(ai // 2, bi // 2)
        if h < 0.2:
            return mul(colour, 0.88)
        if h > 0.88:
            return mul(colour, 1.08)
        return colour
    if name == "water":
        if bi % 6 == 0 and _hash(ai // 4, bi // 6) > 0.45:
            return mix(colour, WHITE, 0.35)
        if bi % 6 == 3 and _hash(ai // 5, bi // 6) > 0.6:
            return mul(colour, 0.9)
        return colour
    if name == "asphalt":
        h = _hash(ai, bi)
        if h < 0.1:
            return mul(colour, 0.82)
        if h > 0.94:
            return mul(colour, 1.12)
        return colour
    if name == "hedge":
        h = _hash(ai, bi)
        if h < 0.18:
            return mul(colour, 0.82)
        if h > 0.86:
            return mul(colour, 1.12)
        return colour
    if name == "glass":
        if (ai + bi) % 9 < 2:
            return mix(colour, WHITE, 0.5)
        if bi % 7 == 0:
            return mul(colour, 0.9)
        return colour
    return colour


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def _draw_screen_face(face, anchor, origin, left, top, width, height, colours, depths):
    """A viewer-facing billboard: a polygon authored in screen pixels.

    Ferris wheels and other ornaments that always face the camera cannot live
    on a grid plane — a circle on a vertical grid plane shears with the 2:1
    projection. This face is authored directly in screen space around an
    anchor, at a fixed depth, so it stays round from every rotation.
    """
    anchor_x, anchor_y, depth = anchor
    ax = anchor_x + origin[0]
    ay = anchor_y + origin[1]
    poly = face.poly
    # A billboard's polygon is authored in art pixels measured from the anchor:
    # x right, y up (the way the design reads). The canvas works in world
    # pixels with y down, so convert at the anchor.
    verts = [(ax + dx * ART_SCALE, ay - dy * ART_SCALE) for dx, dy in poly]
    # Normalise the winding: the inside test wants screen-space (y down)
    # counter-clockwise polygons, and the design is authored y up.
    area = 0.0
    for i, (x0, y0) in enumerate(verts):
        x1, y1 = verts[(i + 1) % len(verts)]
        area += x0 * y1 - x1 * y0
    if area < 0:
        verts = list(reversed(verts))
    edges = []
    for i, (x0, y0) in enumerate(verts):
        x1, y1 = verts[(i + 1) % len(verts)]
        edges.append((x1 - x0, y1 - y0, x0, y0))
    minx = min(p[0] for p in verts)
    maxx = max(p[0] for p in verts)
    miny = min(p[1] for p in verts)
    maxy = max(p[1] for p in verts)
    i0 = max(0, int(math.floor((minx - left) / ART_SCALE)) - 1)
    i1 = min(width - 1, int(math.ceil((maxx - left) / ART_SCALE)) + 1)
    j0 = max(0, int(math.floor((miny - top) / ART_SCALE)) - 1)
    j1 = min(height - 1, int(math.ceil((maxy - top) / ART_SCALE)) + 1)
    for j in range(j0, j1 + 1):
        wy = top + (j + 0.5) * ART_SCALE
        for i in range(i0, i1 + 1):
            wx = left + (i + 0.5) * ART_SCALE
            inside = True
            for ex, ey, x0, y0 in edges:
                if ex * (wy - y0) - ey * (wx - x0) < -1e-6:
                    inside = False
                    break
            if not inside:
                continue
            idx = j * width + i
            if depth + face.bias <= depths[idx]:
                continue
                    # Patterns are measured in art pixels from the billboard anchor.
            if face.fn is not None:
                colour = face.fn((wx - ax) / ART_SCALE, (ay - wy) / ART_SCALE)
            else:
                colour = pattern_colour(face.pattern, face.colour,
                                        (wx - ax) / ART_SCALE, (ay - wy) / ART_SCALE)
            if colour is None:
                continue
            depths[idx] = depth + face.bias
            colours[idx] = colour


def render(scene: Scene, size_tiles, max_height: float, pad_left=10.0, pad_right=10.0,
           pad_bottom=4.0, pad_top=10.0):
    """Rasterise a scene into an RGBA image.

    Returns (PIL.Image, rect) where rect is (x, y, w, h) in the local space of
    the building node, in world pixels.
    """
    from PIL import Image

    facing = scene.facing
    gx0 = gy0 = gx1 = gy1 = None
    origin = grid_origin_offset(size_tiles[0], size_tiles[1], facing)
    for u in (0.0, size_tiles[0]):
        for v in (0.0, size_tiles[1]):
            sx, sy = project(u, v, 0.0, facing)
            sx += origin[0]
            sy += origin[1]
            if gx0 is None:
                gx0 = gx1 = sx
                gy0 = gy1 = sy
            gx0, gx1 = min(gx0, sx), max(gx1, sx)
            gy0, gy1 = min(gy0, sy), max(gy1, sy)

    # Viewer-facing ornaments are authored in screen space, so fold their
    # extents into the canvas too.
    for face in scene.faces:
        if face.plane[0] != "screen":
            continue
        ax, ay, _depth = face.plane[1]
        for dx, dy in face.poly:
            sx = ax + dx * ART_SCALE + origin[0]
            sy = ay - dy * ART_SCALE + origin[1]
            gx0, gx1 = min(gx0, sx), max(gx1, sx)
            gy0, gy1 = min(gy0, sy), max(gy1, sy)

    left = gx0 - pad_left
    right = gx1 + pad_right
    top = gy0 - max_height - pad_top
    bottom = gy1 + pad_bottom
    width = int(math.ceil((right - left) / ART_SCALE))
    height = int(math.ceil((bottom - top) / ART_SCALE))
    colours = [None] * (width * height)
    depths = [-1e30] * (width * height)

    rot = projection_matrix(facing)
    r00, r01 = rot[0]
    r10, r11 = rot[1]
    srow1 = ((r00 - r10) * HALF_W, (r01 - r11) * HALF_W, 0.0)
    srow2 = ((r00 + r10) * HALF_H, (r01 + r11) * HALF_H, -1.0)

    for face in scene.faces:
        kind = face.plane[0]
        value = face.plane[1]
        if kind == "screen":
            _draw_screen_face(face, value, origin, left, top, width, height, colours, depths)
            continue
        if kind == "u":
            prow, prhs = (1.0, 0.0, 0.0), value
            plane_to_art = lambda a, b: (a * TILE_W / ART_SCALE, b / ART_SCALE)
        elif kind == "v":
            prow, prhs = (0.0, 1.0, 0.0), value
            plane_to_art = lambda a, b: (a * TILE_W / ART_SCALE, b / ART_SCALE)
        elif kind == "z":
            prow, prhs = (0.0, 0.0, 1.0), value
            plane_to_art = lambda a, b: (a * TILE_W / ART_SCALE, b * TILE_W / ART_SCALE)
        else:  # slope
            sa, sb, sc = value
            prow, prhs = (sa, sb, -1.0), -sc
            plane_to_art = lambda a, b: (a * TILE_W / ART_SCALE, b * TILE_W / ART_SCALE)

        # Reject degenerate polygons and normalise the winding.
        poly = face.poly
        if len(poly) < 3:
            continue
        area = 0.0
        for i in range(len(poly)):
            a0, b0 = poly[i]
            a1, b1 = poly[(i + 1) % len(poly)]
            area += a0 * b1 - a1 * b0
        if abs(area) < 1e-9:
            continue
        if area < 0:
            poly = list(reversed(poly))

        # Project the polygon's vertices for the screen bounding box.
        verts = []
        for a, b in poly:
            if kind == "u":
                u, v, z = value, a, b
            elif kind == "v":
                u, v, z = a, value, b
            elif kind == "z":
                u, v, z = a, b, value
            else:
                sa, sb, sc = value
                u, v, z = a, b, sa * a + sb * b + sc
            sx, sy = project(u, v, z, facing)
            verts.append((sx + origin[0], sy + origin[1]))
        minx = min(p[0] for p in verts)
        maxx = max(p[0] for p in verts)
        miny = min(p[1] for p in verts)
        maxy = max(p[1] for p in verts)
        i0 = max(0, int(math.floor((minx - left) / ART_SCALE)) - 1)
        i1 = min(width - 1, int(math.ceil((maxx - left) / ART_SCALE)) + 1)
        j0 = max(0, int(math.floor((miny - top) / ART_SCALE)) - 1)
        j1 = min(height - 1, int(math.ceil((maxy - top) / ART_SCALE)) + 1)
        if i1 < i0 or j1 < j0:
            continue

        # p = A^-1 * (x, y, plane_rhs) gives (u, v, z) for a screen pixel.
        inv = _inverse3((srow1, srow2, prow))
        if inv is None:
            continue
        inv0, inv1, inv2 = inv

        edges = []
        for i, (a0, b0) in enumerate(poly):
            a1, b1 = poly[(i + 1) % len(poly)]
            edges.append((a1 - a0, b1 - b0, a0, b0))

        ox, oy = origin
        for j in range(j0, j1 + 1):
            wy = top + (j + 0.5) * ART_SCALE - oy
            for i in range(i0, i1 + 1):
                wx = left + (i + 0.5) * ART_SCALE - ox
                u = inv0[0] * wx + inv0[1] * wy + inv0[2] * prhs
                v = inv1[0] * wx + inv1[1] * wy + inv1[2] * prhs
                z = inv2[0] * wx + inv2[1] * wy + inv2[2] * prhs
                a, b = (v, z) if kind == "u" else ((u, z) if kind == "v" else (u, v))
                inside = True
                for ea, eb, a0, b0 in edges:
                    if ea * (b - b0) - eb * (a - a0) < -1e-6:
                        inside = False
                        break
                if not inside:
                    continue
                ru, rv = rotate_uv(u, v, facing)
                depth = ru + rv + z / TILE_H + face.bias
                idx = j * width + i
                if depth <= depths[idx]:
                    continue
                pa, pb = plane_to_art(a, b)
                if face.fn is not None:
                    colour = face.fn(a, b)
                else:
                    colour = pattern_colour(face.pattern, face.colour, pa, pb)
                if colour is None:
                    continue
                depths[idx] = depth
                colours[idx] = colour

    # Silhouette outline: darken every outer ring pixel.
    outlined = list(colours)
    for j in range(height):
        for i in range(width):
            idx = j * width + i
            c = colours[idx]
            if c is None:
                continue
            edge = False
            if i == 0 or colours[idx - 1] is None:
                edge = True
            elif i == width - 1 or colours[idx + 1] is None:
                edge = True
            elif j == 0 or colours[idx - width] is None:
                edge = True
            elif j == height - 1 or colours[idx + width] is None:
                edge = True
            if edge:
                outlined[idx] = mix(c, INK, 0.45)

    # Crop to the drawn pixels.
    min_i, min_j, max_i, max_j = width, height, -1, -1
    for j in range(height):
        row = j * width
        for i in range(width):
            if outlined[row + i] is not None:
                min_i = min(min_i, i)
                max_i = max(max_i, i)
                min_j = min(min_j, j)
                max_j = max(max_j, j)
    if max_i < 0:
        raise ValueError("scene drew nothing")

    image = Image.new("RGBA", (max_i - min_i + 1, max_j - min_j + 1), (0, 0, 0, 0))
    pixels = image.load()
    for j in range(min_j, max_j + 1):
        for i in range(min_i, max_i + 1):
            c = outlined[j * width + i]
            if c is not None:
                pixels[i - min_i, j - min_j] = (c[0], c[1], c[2], 255)

    rect = (left + min_i * ART_SCALE, top + min_j * ART_SCALE,
            (max_i - min_i + 1) * ART_SCALE, (max_j - min_j + 1) * ART_SCALE)
    return image, rect
