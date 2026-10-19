#!/usr/bin/env python3
"""Pixel-art designs for every facility on the course.

Each building is authored in grid space (tiles across, tiles down, world pixels
up) with the shared primitives in `Builder`, so every sprite shares one palette,
one light direction and one pixel size. render.py turns them into PNGs for each
view rotation.

Scale: one art pixel is two world pixels; a tile is 64x32. A storey is about
46 world pixels (23 art pixels), a door 28 world pixels and a window 18.
"""

from __future__ import annotations

import math

from render import (
    ART_SCALE, TILE_H, TILE_W, project, rotate_uv, BUNKER, BLUE, CREAM, CREAM_DARK, GLASS, GLASS_LIGHT, GOLD, GRASS,
    GREEN_TURF, INK, LAMP, PINK, RED, ROOF_BROWN, ROOF_GREEN, ROOF_RED,
    ROOF_SLATE, SAND, SLATE, STONE, STONE_DARK, TARMAC, WATER, WATER_DEEP, WHITE,
    WOOD, WOOD_DARK, WOOD_LIGHT, YELLOW, mix, mul, rgb, shade,
)

# ---------------------------------------------------------------------------
# 3x5 pixel font for signs
# ---------------------------------------------------------------------------

FONT = {
    "A": ("010", "101", "111", "101", "101"),
    "B": ("110", "101", "110", "101", "110"),
    "C": ("011", "100", "100", "100", "011"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"),
    "G": ("011", "100", "101", "101", "011"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "J": ("001", "001", "001", "101", "010"),
    "K": ("101", "101", "110", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "N": ("101", "111", "111", "111", "101"),
    "O": ("010", "101", "101", "101", "010"),
    "P": ("110", "101", "110", "100", "100"),
    "Q": ("010", "101", "101", "110", "011"),
    "R": ("110", "101", "110", "101", "101"),
    "S": ("011", "100", "010", "001", "110"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "111"),
    "V": ("101", "101", "101", "101", "010"),
    "W": ("101", "101", "111", "111", "101"),
    "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"),
    "Z": ("111", "001", "010", "100", "111"),
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("110", "001", "010", "100", "111"),
    "3": ("110", "001", "010", "001", "110"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "110", "001", "110"),
    "6": ("011", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "110"),
    " ": ("000", "000", "000", "000", "000"),
    ".": ("000", "000", "000", "000", "010"),
    "-": ("000", "000", "111", "000", "000"),
}


def text_painter(text: str, fg, bg, scale: int = 1):
    """Paint `text` from the 3x5 font, each glyph pixel a `scale`-px block."""
    width = max(1, len(text) * 4 - 1) * scale
    height = 5 * scale

    def painter(x: int, y: int):
        if y < 0 or y >= height or x < 0:
            return bg
        x, y = x // scale, y // scale
        char_index, char_x = divmod(x, 4)
        if char_x >= 3 or char_index >= len(text):
            return bg
        glyph = FONT.get(text[char_index].upper(), FONT[" "])
        return fg if glyph[4 - y][char_x] == "1" else bg

    return painter, width, height


# ---------------------------------------------------------------------------
# builder
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self, scene, facing: int):
        self.scene = scene
        self.facing = facing

    # -- basic faces ------------------------------------------------------
    def ground(self, u0, v0, u1, v1, colour, pattern="flagstone", z=0.4,
               kerb=None, inset=0.0, bias=0.0):
        if kerb is not None:
            self.scene.add(("z", z * 0.5), self.scene.rect(u0, v0, u1, v1), kerb)
        self.scene.add(("z", z), self.scene.rect(u0 + inset, v0 + inset, u1 - inset, v1 - inset),
                       colour, pattern, bias)

    def box(self, u0, v0, u1, v1, z0, z1, colour, pattern="flat",
            top=True, top_colour=None, top_pattern="flat", skip=(),
            bias=0.0):
        faces = {
            "u+": (("u", u1), self.scene.rect(v0, z0, v1, z1), shade(colour, (1, 0))),
            "u-": (("u", u0), self.scene.rect(v0, z0, v1, z1), shade(colour, (-1, 0))),
            "v+": (("v", v1), self.scene.rect(u0, z0, u1, z1), shade(colour, (0, 1))),
            "v-": (("v", v0), self.scene.rect(u0, z0, u1, z1), shade(colour, (0, -1))),
        }
        for side, (plane, poly, tint) in faces.items():
            if side not in skip:
                self.scene.add(plane, poly, tint, pattern, bias)
        if top:
            self.scene.add(("z", z1), self.scene.rect(u0, v0, u1, v1),
                           top_colour or mul(colour, 1.12), top_pattern, bias)

    # -- roofs ------------------------------------------------------------
    def gable(self, u0, v0, u1, v1, z_eave, z_ridge, colour, axis="u",
              overhang=3.0, pattern="shingle", end_colour=None, fascia=None):
        ou = overhang / 64.0
        ov = overhang / 32.0
        U0, U1, V0, V1 = u0 - ou, u1 + ou, v0 - ov, v1 + ov
        if axis == "u":
            vm = (v0 + v1) * 0.5
            k = (z_ridge - z_eave) / max(vm - v0, 1e-6)
            self.scene.add(("slope", (0.0, k, z_eave - k * v0)),
                           self.scene.rect(U0, V0, U1, vm), colour, pattern, 0.03)
            self.scene.add(("slope", (0.0, -k, z_eave + k * v1)),
                           self.scene.rect(U0, vm, U1, V1), colour, pattern, 0.03)
            if end_colour is not None:
                self.scene.add(("u", u0), [(v0, z_eave), (v1, z_eave), (vm, z_ridge)],
                               shade(end_colour, (-1, 0)))
                self.scene.add(("u", u1), [(v0, z_eave), (v1, z_eave), (vm, z_ridge)],
                               shade(end_colour, (1, 0)))
            if fascia is not None:
                self.scene.add(("v", V0), self.scene.rect(U0, z_eave - 2.5, U1, z_eave), fascia)
                self.scene.add(("v", V1), self.scene.rect(U0, z_eave - 2.5, U1, z_eave), fascia)
        else:
            um = (u0 + u1) * 0.5
            k = (z_ridge - z_eave) / max(um - u0, 1e-6)
            self.scene.add(("slope", (k, 0.0, z_eave - k * u0)),
                           self.scene.rect(U0, V0, um, V1), colour, pattern, 0.03)
            self.scene.add(("slope", (-k, 0.0, z_eave + k * u1)),
                           self.scene.rect(um, V0, U1, V1), colour, pattern, 0.03)
            if end_colour is not None:
                self.scene.add(("v", v0), [(u0, z_eave), (u1, z_eave), (um, z_ridge)],
                               shade(end_colour, (0, -1)))
                self.scene.add(("v", v1), [(u0, z_eave), (u1, z_eave), (um, z_ridge)],
                               shade(end_colour, (0, 1)))
            if fascia is not None:
                self.scene.add(("u", U0), self.scene.rect(V0, z_eave - 2.5, V1, z_eave), fascia)
                self.scene.add(("u", U1), self.scene.rect(V0, z_eave - 2.5, V1, z_eave), fascia)

    def hip(self, u0, v0, u1, v1, z_eave, z_ridge, colour, overhang=3.0,
            pattern="shingle"):
        ou = overhang / 64.0
        ov = overhang / 32.0
        U0, U1, V0, V1 = u0 - ou, u1 + ou, v0 - ov, v1 + ov
        vm = (v0 + v1) * 0.5
        d = min((u1 - u0) * 0.5, (v1 - v0) * 0.6, 1.3)
        R0, R1 = u0 + d, u1 - d
        kv = (z_ridge - z_eave) / max(vm - v0, 1e-6)
        ku = (z_ridge - z_eave) / max(d, 1e-6)
        self.scene.add(("slope", (0.0, kv, z_eave - kv * v0)),
                       [(U0, V0), (U1, V0), (R1, vm), (R0, vm)], colour, pattern, 0.03)
        self.scene.add(("slope", (0.0, -kv, z_eave + kv * v1)),
                       [(U0, V1), (U1, V1), (R1, vm), (R0, vm)], colour, pattern, 0.03)
        self.scene.add(("slope", (ku, 0.0, z_eave - ku * u0)),
                       [(U0, V0), (R0, vm), (U0, V1)], colour, pattern, 0.03)
        self.scene.add(("slope", (-ku, 0.0, z_eave + ku * u1)),
                       [(U1, V0), (R1, vm), (U1, V1)], colour, pattern, 0.03)

    def pyramid(self, u0, v0, u1, v1, z_eave, z_ridge, colour, overhang=2.0,
                pattern="shingle"):
        ou = overhang / 64.0
        ov = overhang / 32.0
        U0, U1, V0, V1 = u0 - ou, u1 + ou, v0 - ov, v1 + ov
        um, vm = (u0 + u1) * 0.5, (v0 + v1) * 0.5
        ku = (z_ridge - z_eave) / max(um - u0, 1e-6)
        kv = (z_ridge - z_eave) / max(vm - v0, 1e-6)
        self.scene.add(("slope", (0.0, kv, z_eave - kv * v0)),
                       [(U0, V0), (U1, V0), (um, vm)], colour, pattern, 0.03)
        self.scene.add(("slope", (0.0, -kv, z_eave + kv * v1)),
                       [(U0, V1), (U1, V1), (um, vm)], colour, pattern, 0.03)
        self.scene.add(("slope", (ku, 0.0, z_eave - ku * u0)),
                       [(U0, V0), (um, vm), (U0, V1)], colour, pattern, 0.03)
        self.scene.add(("slope", (-ku, 0.0, z_eave + ku * u1)),
                       [(U1, V0), (um, vm), (U1, V1)], colour, pattern, 0.03)

    def shed(self, u0, v0, u1, v1, z_at_v0, z_at_v1, colour, along="v",
             overhang=2.0, pattern="shingle", fascia=None):
        """A mono-pitch roof: `z_at_v0` at the low edge's v0 (or u0)."""
        ou = overhang / 64.0
        ov = overhang / 32.0
        if along == "v":
            k = (z_at_v1 - z_at_v0) / max(v1 - v0, 1e-6)
            self.scene.add(("slope", (0.0, k, z_at_v0 - k * v0)),
                           self.scene.rect(u0 - ou, v0 - ov, u1 + ou, v1 + ov), colour, pattern, 0.03)
            if fascia:
                self.scene.add(("v", v1 + ov), self.scene.rect(u0 - ou, z_at_v1 - 2.5, u1 + ou, z_at_v1),
                               fascia)
        else:
            k = (z_at_v1 - z_at_v0) / max(u1 - u0, 1e-6)
            self.scene.add(("slope", (k, 0.0, z_at_v0 - k * u0)),
                           self.scene.rect(u0 - ou, v0 - ov, u1 + ou, v1 + ov), colour, pattern, 0.03)
            if fascia:
                self.scene.add(("u", u1 + ou), self.scene.rect(v0 - ov, z_at_v1 - 2.5, v1 + ov, z_at_v1),
                               fascia)

    # -- wall details -----------------------------------------------------
    def side_span(self, side, u0, v0, u1, v1, offset, width):
        """Plane, low/high plane coordinate and screen-left flip for a side."""
        if side == "u+":
            return ("u", u1), v1 - offset - width, v1 - offset, True
        if side == "u-":
            return ("u", u0), v0 + offset, v0 + offset + width, False
        if side == "v+":
            return ("v", v1), u0 + offset, u0 + offset + width, False
        return ("v", v0), u1 - offset - width, u1 - offset, True

    def panel(self, plane, lo, hi, z0, w_art, h_art, painter, flip, bias=0.04):
        z1 = z0 + h_art * ART_SCALE

        def fn(a, b):
            # `a` is a grid coordinate (a tile is 64 world px wide) and `b` is
            # height in world pixels; panels are painted in art pixels.
            t = (hi - a) if flip else (a - lo)
            px = int(math.floor(t * 64.0 / ART_SCALE + 1e-9))
            py = int(math.floor((b - z0) / ART_SCALE + 1e-9))
            if 0 <= px < w_art and 0 <= py < h_art:
                return painter(px, py)
            return None

        self.scene.add(plane, [(lo, z0), (hi, z0), (hi, z1), (lo, z1)], fn=fn, bias=bias)

    def window(self, side, u0, v0, u1, v1, offset, z0, w=10, h=13,
               frame=WOOD_DARK, glass=GLASS, lit=False, sill=True, bias=0.05):
        plane, lo, hi, flip = self.side_span(side, u0, v0, u1, v1, offset,
                                             w * ART_SCALE / 64.0)

        def painter(px, py):
            if px in (0, w - 1) or py == 0 or py == h - 1:
                return frame
            if py == h - 2:
                return mul(frame, 1.6)
            if px == w // 2 or py == h // 2:
                return frame
            c = LAMP if lit else glass
            if (px + py) % 7 < 2:
                return WHITE if lit else GLASS_LIGHT
            return c

        self.panel(plane, lo, hi, z0, w, h, painter, flip, bias)
        if sill:
            sill_w = w + 2
            plane, lo, hi, flip = self.side_span(
                side, u0, v0, u1, v1, offset - ART_SCALE / 64.0,
                sill_w * ART_SCALE / 64.0)
            self.panel(plane, lo, hi, z0 - ART_SCALE, sill_w, 1,
                       lambda px, py: mul(frame, 1.35), flip, bias + 0.01)

    def door(self, side, u0, v0, u1, v1, offset, z0, w=13, h=20,
             colour=WOOD, frame=CREAM, knob=GOLD, bias=0.05):
        plane, lo, hi, flip = self.side_span(side, u0, v0, u1, v1, offset,
                                             w * ART_SCALE / 64.0)

        def painter(px, py):
            if px in (0, w - 1) or py == h - 1:
                return frame
            if px == w - 3 and py == max(2, h // 2):
                return knob
            if px % 3 == 0:
                return mul(colour, 0.82)
            if py == 1:
                return mul(colour, 0.7)
            return colour

        self.panel(plane, lo, hi, z0, w, h, painter, flip, bias)
        step = 4.0
        if side == "v+":
            self.box(lo, v1, hi, v1 + step / 64.0, 0.0, 2.0, STONE_DARK, top=False)
        elif side == "v-":
            self.box(lo, v0 - step / 64.0, hi, v0, 0.0, 2.0, STONE_DARK, top=False)
        elif side == "u+":
            self.box(u1, lo, u1 + step / 64.0, hi, 0.0, 2.0, STONE_DARK, top=False)
        else:
            self.box(u0 - step / 64.0, lo, u0, hi, 0.0, 2.0, STONE_DARK, top=False)

    def sign(self, side, u0, v0, u1, v1, offset, z0, text, fg=CREAM, bg=ROOF_GREEN,
             padding=2, bias=0.06, text_scale=1):
        text_fn, text_w, text_h = text_painter(text, fg, bg, text_scale)
        w = text_w + padding * 2
        h = text_h + padding * 2
        plane, lo, hi, flip = self.side_span(side, u0, v0, u1, v1, offset,
                                             w * ART_SCALE / 64.0)

        def painter(px, py):
            if px == 0 or px == w - 1 or py == 0 or py == h - 1:
                return mul(bg, 0.7)
            return text_fn(px - padding, py - padding)

        self.panel(plane, lo, hi, z0, w, h, painter, flip, bias)


    def fascia_sign(self, side, u0, v0, u1, v1, offset, z0, text,
                    fg=CREAM, bg=ROOF_GREEN, padding=2, depth=5.0, bias=0.08,
                    text_scale=1):
        """A signboard standing proud of one wall, readable from the front."""
        text_fn, text_w, text_h = text_painter(text, fg, bg, text_scale)
        w = text_w + padding * 2
        h = text_h + padding * 2
        plane, lo, hi, flip = self.side_span(side, u0, v0, u1, v1, offset,
                                             w * ART_SCALE / 64.0)
        z1 = z0 + h * ART_SCALE
        outward = depth / 64.0
        zz = 1.2

        def painter(px, py):
            if px == 0 or px == w - 1 or py == 0 or py == h - 1:
                return mul(bg, 0.7)
            return text_fn(px - padding, py - padding)

        if side == "v+":
            self.box(lo, v1, hi, v1 + outward, z0 - zz, z1 - zz, bg, skip=("v+",),
                     top=False)
            self.panel(("v", v1 + outward), lo, hi, z0, w, h, painter, flip, bias)
        elif side == "v-":
            self.box(lo, v0 - outward, hi, v0, z0 - zz, z1 - zz, bg, skip=("v-",),
                     top=False)
            self.panel(("v", v0 - outward), lo, hi, z0, w, h, painter, flip, bias)
        elif side == "u+":
            self.box(u1, lo, u1 + outward, hi, z0 - zz, z1 - zz, bg, skip=("u+",),
                     top=False)
            self.panel(("u", u1 + outward), lo, hi, z0, w, h, painter, flip, bias)
        else:
            self.box(u0 - outward, lo, u0, hi, z0 - zz, z1 - zz, bg, skip=("u-",),
                     top=False)
            self.panel(("u", u0 - outward), lo, hi, z0, w, h, painter, flip, bias)

    def awning(self, side, u0, v0, u1, v1, offset, width, z_top,
               colour_a=ROOF_RED, colour_b=CREAM, depth=0.34, drop=5.0,
               valance=3.0, posts=False, bias=0.05, label=None,
               label_fg=CREAM, label_bg=ROOF_GREEN):
        """Striped awning sloping out from one wall."""
        stripe = 0.16  # tiles per stripe

        if side == "u+":
            lo, hi = v1 - offset - width, v1 - offset
            k = -drop / depth
            plane = ("slope", (k, 0.0, z_top + drop * u1 / depth))
            poly = [(lo, u1), (hi, u1), (hi, u1 + depth), (lo, u1 + depth)]
            outer, outer_plane = u1 + depth, ("u", u1 + depth)
            span = (lo, hi)
            val_lo, val_hi = lo, hi
            use_b = True
        elif side == "u-":
            lo, hi = v0 + offset, v0 + offset + width
            k = drop / depth
            plane = ("slope", (k, 0.0, z_top - drop * u0 / depth))
            poly = [(lo, u0), (hi, u0), (hi, u0 - depth), (lo, u0 - depth)]
            outer, outer_plane = u0 - depth, ("u", u0 - depth)
            span = (lo, hi)
            val_lo, val_hi = lo, hi
            use_b = True
        elif side == "v+":
            lo, hi = u0 + offset, u0 + offset + width
            k = -drop / depth
            plane = ("slope", (0.0, k, z_top + drop * v1 / depth))
            poly = [(lo, v1), (hi, v1), (hi, v1 + depth), (lo, v1 + depth)]
            outer, outer_plane = v1 + depth, ("v", v1 + depth)
            span = (lo, hi)
            val_lo, val_hi = lo, hi
            use_b = False
        else:
            lo, hi = u1 - offset - width, u1 - offset
            k = drop / depth
            plane = ("slope", (0.0, k, z_top - drop * v0 / depth))
            poly = [(lo, v0), (hi, v0), (hi, v0 - depth), (lo, v0 - depth)]
            outer, outer_plane = v0 - depth, ("v", v0 - depth)
            span = (lo, hi)
            val_lo, val_hi = lo, hi
            use_b = False

        start = val_lo

        def striped(a, b):
            return colour_a if int(math.floor((a - start) / stripe)) % 2 == 0 else colour_b

        self.scene.add(plane, poly, fn=striped, bias=bias)
        self.scene.add(outer_plane,
                       [(val_lo, z_top - drop - valance), (val_hi, z_top - drop - valance),
                        (val_hi, z_top - drop), (val_lo, z_top - drop)],
                       fn=striped, bias=bias + 0.05)
        if label:
            # Shop name on a board hanging from the awning's outer edge, so it
            # always sits in front of the wall and nothing can occlude it.
            text_fn, tw, th = text_painter(label, label_fg, label_bg)
            bw, bh = tw + 4, th + 4
            flip_along = side in ("u+", "v-")
            board_lo = lo + max(0.0, ((hi - lo) - bw / 64.0) * 0.5)

            def board(px, py):
                if px in (0, bw - 1) or py in (0, bh - 1):
                    return mul(label_bg, 0.7)
                return text_fn(px - 2, py - 2)

            self.panel(outer_plane, board_lo, board_lo + bw / 64.0,
                       z_top - drop - valance - bh, bw, bh, board, flip_along,
                       bias + 0.09)
        if posts:
            for along in (val_lo + 0.03, val_hi - 0.03):
                if side in ("u+", "u-"):
                    self.box(outer - 2.0 / 64.0, along - 1.5 / 64.0,
                             outer, along + 1.5 / 64.0, 0.0, z_top - drop, WOOD_LIGHT)
                else:
                    self.box(along - 1.5 / 64.0, outer - 2.0 / 32.0,
                             along + 1.5 / 64.0, outer, 0.0, z_top - drop, WOOD_LIGHT)

    # -- viewer-facing ornaments -----------------------------------------
    def billboard(self, u: float, v: float, z: float, points, colour=None, pattern="flat",
                  bias=0.0, fn=None):
        """A viewer-facing ornament: `points` are screen pixels from (u, v, z).

        A circle on a vertical grid plane shears with the 2:1 projection, so
        ornaments that must stay round (a ferris wheel) are authored in screen
        space instead. The anchor still sits in grid space, which fixes the
        ornament's depth against the rest of the building.
        """
        sx, sy = project(u, v, z, self.facing)
        ru, rv = rotate_uv(u, v, self.facing)
        depth = ru + rv + z / TILE_H
        self.scene.add(("screen", (sx, sy, depth)), points, colour, pattern, bias, fn)

    # -- scenery ----------------------------------------------------------
    def planter(self, u, v, z=0.0, size=0.20, colour=CREAM_DARK):
        self.box(u - size, v - size, u + size, v + size, z, z + 8.0, colour,
                 top_colour=rgb("6b4a33"))
        self.bush(u, v, z + 8.0, scale=0.55)

    def bush(self, u, v, z=0.0, scale=1.0, colour=None):
        colour = colour or rgb("4f8a45")
        w = 0.20 * scale
        d = 0.20 * scale
        self.box(u - w * 0.55, v - d * 0.55, u + w * 0.55, v + d * 0.55,
                 z, z + 8.0 * scale, WOOD)
        self.box(u - w, v - d, u + w, v + d, z + 7.0 * scale, z + 19.0 * scale,
                 colour, pattern="hedge")
        self.box(u - w * 0.55, v - d * 0.55, u + w * 0.55, v + d * 0.55,
                 z + 19.0 * scale, z + 26.0 * scale, mul(colour, 1.16), pattern="hedge")

    def palm(self, u, v, z=0.0, height=40.0, scale=1.0):
        w = 0.045
        self.box(u - w, v - w, u + w, v + w, z, z + height, WOOD, pattern="plank")
        top = z + height
        self.box(u - 0.10, v - 0.10, u + 0.10, v + 0.10, top, top + 5.0,
                 rgb("6d9e4c"), pattern="hedge")
        fronds = ((0.42, 0.0), (-0.42, 0.0), (0.0, 0.42), (0.0, -0.42),
                  (0.30, 0.30), (-0.30, -0.30))
        for du, dv in fronds:
            self.box(u + min(du, 0.0) - 0.035, v + min(dv, 0.0) - 0.035,
                     u + max(du, 0.0) + 0.035, v + max(dv, 0.0) + 0.035,
                     top + 1.0, top + 3.0, rgb("5f9c4a"), pattern="hedge")

    def fence(self, u0, v0, u1, v1, z0=0.0, height=12.0, spacing=0.34,
              colour=WOOD_LIGHT, axis="u"):
        if axis == "u":
            count = max(2, int(round((u1 - u0) / spacing)) + 1)
            for i in range(count):
                u = u0 + (u1 - u0) * i / (count - 1)
                self.box(u - 0.016, v0 - 0.016, u + 0.016, v0 + 0.016, z0, z0 + height, colour)
            for h in (height * 0.45, height * 0.82):
                self.box(u0, v0 - 0.012, u1, v0 + 0.012, z0 + h - 1.2, z0 + h, colour,
                         top=False)
        else:
            count = max(2, int(round((v1 - v0) / spacing)) + 1)
            for i in range(count):
                v = v0 + (v1 - v0) * i / (count - 1)
                self.box(u0 - 0.016, v - 0.016, u0 + 0.016, v + 0.016, z0, z0 + height, colour)
            for h in (height * 0.45, height * 0.82):
                self.box(u0 - 0.012, v0, u0 + 0.012, v1, z0 + h - 1.2, z0 + h, colour,
                         top=False)

    def flag(self, u, v, z0=0.0, height=34.0, colour=RED, plane_axis="v"):
        self.box(u - 0.012, v - 0.012, u + 0.012, v + 0.012, z0, z0 + height, WHITE)
        if plane_axis == "v":
            self.scene.add(("v", v), [(u, z0 + height - 2.0), (u + 0.34, z0 + height - 8.0),
                                      (u, z0 + height - 14.0)], colour)
        else:
            self.scene.add(("u", u), [(v, z0 + height - 2.0), (v + 0.34, z0 + height - 8.0),
                                      (v, z0 + height - 14.0)], colour)

    def ball(self, u, v, z=0.0):
        self.box(u - 0.026, v - 0.026, u + 0.026, v + 0.026, z, z + 3.2, WHITE)

    def lounger(self, u, v, along="u"):
        if along == "u":
            self.box(u, v, u + 0.55, v + 0.22, 0.0, 3.5, CREAM, top_colour=PINK)
            self.box(u - 0.02, v - 0.16, u + 0.12, v + 0.22, 0.0, 7.5, CREAM, top_colour=PINK)
        else:
            self.box(u, v, u + 0.22, v + 0.55, 0.0, 3.5, CREAM, top_colour=PINK)
            self.box(u - 0.16, v - 0.02, u + 0.22, v + 0.12, 0.0, 7.5, CREAM, top_colour=PINK)


# ---------------------------------------------------------------------------
# facility designs
# ---------------------------------------------------------------------------

def clubhouse(b: Builder, tier: int):
    wall = CREAM
    roof = {1: ROOF_RED, 2: ROOF_BROWN, 3: ROOF_SLATE}[tier]
    b.ground(0.10, 0.10, 3.90, 3.90, rgb("d8cba6"), "flagstone", z=0.4,
             kerb=rgb("b9ac88"), inset=0.16)

    if tier == 1:
        hall = (0.60, 0.50, 3.40, 2.55)
        wall_h = 56.0
        b.box(*hall, 0.0, wall_h, wall, pattern="plank")
        b.hip(hall[0], hall[1], hall[2], hall[3], wall_h, wall_h + 22.0, roof,
              overhang=4.0)
        # Stone stoop and the front door, with the club plaque over it.
        b.box(1.72, 2.55, 2.18, 2.76, 0.0, 4.0, rgb("cabd98"), top_colour=CREAM_DARK)
        b.door("v+", *hall, offset=1.28, z0=4.0, w=14, h=26)
        b.fascia_sign("v+", *hall, offset=1.28, z0=34.0, text="CLUB", fg=CREAM,
                      bg=ROOF_GREEN)
        b.flag(3.62, 3.30, 0.0, 54.0, ROOF_GREEN)
        b.ball(0.40, 3.30)
        b.window("v+", *hall, offset=0.24, z0=26.0, w=10, h=13)
        b.window("v+", *hall, offset=2.56, z0=26.0, w=10, h=13)
        b.window("u+", *hall, offset=0.22, z0=26.0, w=10, h=13)
        b.window("u+", *hall, offset=1.86, z0=26.0, w=10, h=13)
        b.window("u-", *hall, offset=0.70, z0=26.0, w=10, h=13)
        b.window("v-", *hall, offset=1.00, z0=26.0, w=10, h=13)
        b.box(2.72, 0.82, 3.12, 1.22, wall_h - 2.0, wall_h + 34.0, STONE, "brick")
        b.planter(0.45, 3.45)
        b.planter(3.55, 3.45)
    elif tier == 2:
        hall = (0.55, 0.50, 3.45, 2.30)
        wall_h = 68.0
        b.box(*hall, 0.0, wall_h, wall, pattern="plank")
        b.hip(hall[0], hall[1], hall[2], hall[3], wall_h, wall_h + 24.0, roof,
              overhang=4.0)
        # Pro-shop wing with its own awning.
        wing = (0.55, 2.30, 1.70, 3.20)
        b.box(*wing, 0.0, 42.0, wall, pattern="plank")
        b.shed(wing[0], wing[1], wing[2], wing[3], 42.0, 52.0, roof, along="u",
               overhang=2.0, fascia=ROOF_BROWN)
        b.awning("v+", *wing, offset=0.10, width=0.92, z_top=34.0,
                 colour_a=ROOF_GREEN, colour_b=CREAM, depth=0.24, drop=3.0,
                 posts=True, valance=2.0)
        b.window("v+", *wing, offset=0.16, z0=12.0, w=10, h=13)
        b.box(1.72, 2.30, 2.18, 2.50, 0.0, 4.0, rgb("cabd98"), top_colour=CREAM_DARK)
        b.door("v+", *hall, offset=1.30, z0=4.0, w=14, h=26)
        b.fascia_sign("v+", *hall, offset=1.30, z0=34.0, text="CLUB", fg=CREAM,
                      bg=ROOF_GREEN)
        b.flag(3.62, 3.40, 0.0, 62.0, ROOF_BROWN)
        b.window("v+", *hall, offset=0.24, z0=28.0, w=10, h=13)
        b.window("v+", *hall, offset=2.58, z0=28.0, w=10, h=13)
        b.window("u+", *hall, offset=0.22, z0=28.0, w=10, h=13)
        b.window("u+", *hall, offset=1.86, z0=28.0, w=10, h=13)
        b.window("u-", *hall, offset=0.70, z0=28.0, w=10, h=13)
        b.window("v-", *hall, offset=1.00, z0=28.0, w=10, h=13)
        b.box(2.72, 0.82, 3.12, 1.22, wall_h - 2.0, wall_h + 36.0, STONE, "brick")
        b.planter(2.80, 3.42)
        b.planter(3.55, 2.85)
    else:
        hall = (0.55, 0.45, 3.45, 2.25)
        wall_h = 104.0
        b.box(*hall, 0.0, wall_h, wall, pattern="plank")
        b.hip(hall[0], hall[1], hall[2], hall[3], wall_h, wall_h + 22.0, roof,
              overhang=4.5)
        # Ground-floor front range with a long canopy.
        front = (0.55, 2.25, 3.10, 3.25)
        b.box(*front, 0.0, 54.0, wall, pattern="plank")
        b.shed(front[0], front[1], front[2], front[3], 54.0, 64.0, roof, along="u",
               overhang=2.0, fascia=ROOF_BROWN)
        b.awning("v+", *front, offset=0.10, width=2.36, z_top=52.0,
                 colour_a=ROOF_GREEN, colour_b=CREAM, depth=0.24, drop=3.0,
                 posts=True, valance=2.0, label="CLUBHOUSE")
        b.door("v+", *front, offset=1.02, z0=6.0, w=13, h=23)
        b.window("v+", *front, offset=0.20, z0=12.0, w=10, h=13)
        b.window("v+", *front, offset=1.94, z0=12.0, w=10, h=13)
        for off in (0.28, 1.52, 2.72):
            b.window("v+", *hall, offset=off, z0=74.0, w=10, h=13)
        for off in (0.28, 1.84):
            b.window("u+", *hall, offset=off, z0=70.0, w=10, h=13)
        b.window("u+", *hall, offset=1.10, z0=30.0, w=10, h=13)
        b.window("u-", *hall, offset=0.95, z0=72.0, w=10, h=13)
        b.window("v-", *hall, offset=1.20, z0=72.0, w=10, h=13)
        # Clock tower at the north-west corner of the front range.
        tower = (0.60, 0.50, 1.40, 1.30)
        b.box(*tower, 0.0, 126.0, rgb("d9c9a2"), pattern="stone")
        b.pyramid(tower[0], tower[1], tower[2], tower[3], 126.0, 146.0, roof,
                  overhang=2.0)

        def clock(px, py):
            if px in (0, 10) or py in (0, 10):
                return mul(ROOF_SLATE, 1.15)
            if px == 5 and 2 <= py <= 5:
                return INK
            if 5 <= px <= 7 and py == 5:
                return INK
            return CREAM

        for side, u0, v0, u1, v1 in (("u+", *tower), ("v+", *tower)):
            plane, lo, hi, flip = b.side_span(side, u0, v0, u1, v1, 0.0,
                                              11 * ART_SCALE / 64.0)
            b.panel(plane, lo, hi, 100.0, 11, 11, clock, flip, 0.06)
        b.box(2.78, 0.82, 3.18, 1.22, wall_h - 2.0, wall_h + 36.0, STONE, "brick")
        b.planter(0.45, 3.45)
        b.planter(3.55, 3.30)
        b.planter(2.90, 3.55)


def putting_green(b: Builder, tier: int):
    b.ground(0.05, 0.05, 2.95, 2.95, rgb("66ae55"), "grass", z=0.3)
    b.scene.add(("z", 0.55), [(0.24, 0.24), (2.76, 0.24), (2.76, 2.76), (0.24, 2.76)],
                rgb("87ce6d"), "grass")
    b.scene.add(("z", 0.62), [(0.40, 0.40), (2.60, 0.40), (2.60, 2.60), (0.40, 2.60)],
                rgb("a3e084"), "grass")
    b.scene.add(("z", 0.66), b.scene.rect(1.66, 1.06, 1.78, 1.16), rgb("2c3a28"))
    b.flag(1.72, 1.11, z0=0.6, height=40.0, colour=RED)
    for u, v in ((0.78, 0.80), (0.98, 1.62), (2.10, 0.72), (1.15, 2.18), (2.24, 2.05)):
        b.ball(u, v, 0.6)
    b.box(2.02, 2.28, 2.62, 2.66, 0.6, 2.0, rgb("48703c"), top_colour=rgb("5c8c48"))
    b.box(0.35, 2.15, 0.80, 2.45, 0.6, 6.0, WOOD_LIGHT, top_colour=WOOD)


def snack_bar(b: Builder, tier: int):
    b.ground(0.08, 0.08, 1.92, 1.92, rgb("d6c9a4"), "flagstone", z=0.35,
             kerb=rgb("b3a684"))
    kiosk = (0.25, 0.30, 1.75, 1.30)
    b.box(*kiosk, 0.0, 42.0, rgb("f0e2c0"), pattern="plank")
    b.box(kiosk[0] - 0.04, kiosk[1] - 0.04, kiosk[2] + 0.04, kiosk[3] + 0.04, 42.0, 46.0,
          ROOF_RED, top_colour=mul(ROOF_RED, 1.15))
    # Serving hatch with a counter and a striped awning over it.
    b.window("v+", *kiosk, offset=0.26, z0=16.0, w=14, h=10,
             frame=WOOD_DARK, glass=rgb("3b2f26"))
    b.awning("v+", *kiosk, offset=0.16, width=1.28, z_top=40.0,
             colour_a=ROOF_RED, colour_b=CREAM, depth=0.26, drop=4.0, valance=2.0)
    b.box(0.40, 1.30, 1.62, 1.44, 0.0, 13.0, CREAM_DARK, top_colour=CREAM)
    # Menu board and a planter beside the kiosk.
    b.box(1.80, 1.32, 1.94, 1.40, 0.0, 15.0, WOOD_DARK)
    b.sign("v+", 1.78, 1.28, 1.96, 1.40, offset=0.0, z0=6.0, text="MENU",
           fg=WHITE, bg=WOOD, padding=1)
    b.planter(0.14, 1.74)


def pub(b: Builder, tier: int):
    b.ground(0.10, 0.08, 2.90, 1.92, rgb("cfc39c"), "stone", z=0.35,
             kerb=rgb("a99c78"), inset=0.10)
    inn = (0.30, 0.25, 2.70, 1.45)
    b.box(*inn, 0.0, 50.0, rgb("e2cda6"), pattern="stone")
    b.gable(*inn, 50.0, 76.0, ROOF_BROWN, axis="u", overhang=4.0,
            end_colour=rgb("e2cda6"), fascia=ROOF_BROWN)
    b.door("v+", *inn, offset=0.60, z0=2.0, w=10, h=15, colour=WOOD)
    b.box(0.52, 1.45, 0.58, 1.58, 34.0, 40.0, WOOD_DARK)
    b.box(0.54, 1.50, 0.56, 1.56, 38.0, 41.0, LAMP)
    b.window("v+", *inn, offset=1.34, z0=22.0, w=10, h=13)
    b.window("v+", *inn, offset=1.96, z0=22.0, w=10, h=13)
    b.window("u+", *inn, offset=0.28, z0=22.0, w=10, h=13)
    b.window("u+", *inn, offset=0.80, z0=22.0, w=10, h=13)
    b.window("u-", *inn, offset=0.50, z0=22.0, w=10, h=13)
    b.window("v-", *inn, offset=1.00, z0=22.0, w=10, h=13)
    b.fascia_sign("v+", *inn, offset=0.62, z0=19.0, text="PUB",
                  fg=CREAM, bg=ROOF_GREEN)
    # Hanging bracket sign beside the door.
    b.box(2.58, 1.45, 2.64, 1.62, 44.0, 46.0, WOOD_DARK)
    b.box(2.46, 1.58, 2.64, 1.62, 30.0, 31.0, WOOD_DARK)
    b.scene.add(("v", 1.62), [(2.46, 30.0), (2.64, 30.0), (2.64, 40.0), (2.46, 40.0)],
                fn=lambda a, x: ROOF_GREEN if 1 <= int((x - 30.0) / ART_SCALE) <= 8 else WOOD_DARK)
    b.box(0.95, 0.55, 1.35, 0.95, 50.0, 80.0, STONE_DARK, "brick")
    b.box(2.34, 1.58, 2.58, 1.82, 0.0, 12.0, WOOD, "plank", top_colour=WOOD_LIGHT)
    b.box(2.40, 1.64, 2.52, 1.76, 12.0, 13.5, WOOD_DARK)
    b.planter(0.16, 1.72)


def pro_shop(b: Builder, tier: int):
    b.ground(0.08, 0.08, 1.92, 1.92, rgb("d6c9a4"), "flagstone", z=0.35,
             kerb=rgb("b3a684"))
    shop = (0.22, 0.30, 1.78, 1.42)
    b.box(*shop, 0.0, 50.0, rgb("e3dcc0"), pattern="plank")
    b.gable(*shop, 50.0, 70.0, ROOF_GREEN, axis="u", overhang=3.0,
            end_colour=rgb("e3dcc0"), fascia=ROOF_GREEN)

    def display(px, py):
        if px in (0, 13) or py in (0, 10):
            return WOOD_DARK
        if py == 1:
            return GLASS_LIGHT
        if (px + py * 3) % 9 == 0:
            return GOLD
        if (px * 2 + py) % 7 == 0:
            return BLUE
        return GLASS

    plane, lo, hi, flip = b.side_span("v+", *shop, 0.12, 14 * ART_SCALE / 64.0)
    b.panel(plane, lo, hi, 14.0, 14, 11, display, flip, 0.05)
    b.awning("v+", *shop, offset=0.08, width=1.46, z_top=46.0,
             colour_a=ROOF_GREEN, colour_b=CREAM, depth=0.24, drop=3.0,
             posts=True, valance=2.0)
    b.door("v+", *shop, offset=1.28, z0=2.0, w=12, h=22)
    b.window("u+", *shop, offset=0.24, z0=26.0, w=10, h=13)
    b.window("u-", *shop, offset=0.42, z0=26.0, w=10, h=13)
    b.window("v-", *shop, offset=0.50, z0=26.0, w=10, h=13)
    for i in range(3):
        b.box(0.34 + i * 0.10, 1.56, 0.42 + i * 0.10, 1.65, 0.0, 15.0,
              [RED, BLUE, YELLOW][i])
        b.box(0.36 + i * 0.10, 1.58, 0.40 + i * 0.10, 1.63, 15.0, 18.0, WOOD_DARK)


def driving_range(b: Builder, tier: int):
    b.ground(0.05, 0.05, 5.95, 2.95, rgb("82b35c"), "grass", z=0.25)
    b.ground(0.20, 1.55, 5.80, 2.90, rgb("96c46c"), "grass", z=0.35)
    shed = (0.30, 0.35, 5.70, 1.75)
    b.box(shed[0], shed[1], shed[2], shed[3], 0.0, 38.0, rgb("dccfa8"),
          pattern="plank", top=False, skip=("v+",))
    b.shed(shed[0], shed[1], shed[2], shed[3], 40.0, 32.0, ROOF_GREEN, along="v",
           overhang=3.0, fascia=ROOF_BROWN)
    for i in range(6):
        u0 = shed[0] + 0.18 + i * 0.82
        u1 = u0 + 0.62
        b.scene.add(("v", shed[3] - 0.02), [(u0, 2.0), (u1, 2.0), (u1, 28.0), (u0, 28.0)],
                    rgb("2f2a26"))
        b.scene.add(("v", shed[3] - 0.03), [(u0, 2.0), (u1, 2.0), (u1, 6.0), (u0, 6.0)],
                    rgb("4a4038"))
        b.box(u0 - 0.04, shed[3] - 0.10, u0 + 0.04, shed[3] + 0.02, 0.0, 34.0, CREAM)
    b.box(shed[0] + 0.10, shed[3] - 0.10, shed[2] - 0.10, shed[3] + 0.02, 28.0, 34.0,
          CREAM, top_colour=CREAM_DARK)
    # Low kick wall under the counter so the bays are not floating.
    b.box(shed[0] + 0.06, shed[3] - 0.06, shed[2] - 0.06, shed[3] + 0.02, 0.0, 6.0,
          CREAM_DARK)
    b.fascia_sign("v+", *shed, offset=0.10, z0=34.0, text="RANGE", fg=CREAM,
                  bg=ROOF_GREEN)
    b.flag(5.30, 2.55, z0=0.4, height=30.0, colour=YELLOW, plane_axis="u")
    for u, v in ((1.05, 2.25), (1.35, 2.15), (2.55, 2.35), (3.85, 2.20), (4.65, 2.45)):
        b.ball(u, v, 0.4)
    b.box(0.55, 1.95, 0.75, 2.12, 0.4, 5.0, rgb("8a5a32"), top_colour=rgb("c8a060"))


def cart_garage(b: Builder, tier: int):
    b.ground(0.08, 0.08, 2.92, 1.92, rgb("c8bd98"), "gravel", z=0.35,
             kerb=rgb("a99d7c"))
    shed = (0.25, 0.30, 2.75, 1.55)
    b.box(shed[0], shed[1], shed[2], shed[3], 0.0, 36.0, rgb("dccfa8"),
          pattern="plank", top=False, skip=("v+",))
    b.shed(shed[0], shed[1], shed[2], shed[3], 38.0, 32.0, ROOF_GREEN, along="v",
           overhang=3.0, fascia=ROOF_BROWN)
    b.fascia_sign("v+", *shed, offset=0.10, z0=26.0, text="CARTS", fg=CREAM,
                  bg=ROOF_GREEN, depth=1.0)
    for u0 in (0.42, 1.62):
        u1 = u0 + 1.00
        b.scene.add(("v", shed[3] - 0.02), [(u0, 1.5), (u1, 1.5), (u1, 26.0), (u0, 26.0)],
                    rgb("35322c"))
        b.box(u0, 0.90, u1, shed[3] - 0.02, 0.0, 1.5, rgb("4a463e"))
        b.box(u0 + 0.12, 0.95, u1 - 0.16, 1.32, 0.0, 7.0, CREAM, top_colour=CREAM_DARK)
        b.box(u0 + 0.20, 1.00, u1 - 0.24, 1.14, 7.0, 15.0, rgb("5f6b58"))
        b.box(u0 + 0.16, 1.32, u0 + 0.23, 1.39, 0.0, 6.0, rgb("2f2a26"))
        b.box(u1 - 0.25, 1.32, u1 - 0.18, 1.39, 0.0, 6.0, rgb("2f2a26"))
        b.box(u0 - 0.04, shed[3] - 0.10, u0 + 0.04, shed[3] + 0.02, 0.0, 32.0, CREAM)
        b.box(u1 - 0.04, shed[3] - 0.10, u1 + 0.04, shed[3] + 0.02, 0.0, 32.0, CREAM)
    b.box(1.30, 0.72, 1.70, 1.10, 38.0, 44.0, STONE_DARK)


def tennis_court(b: Builder, tier: int):
    b.ground(0.05, 0.05, 3.95, 1.95, rgb("6f9e52"), "grass", z=0.25)
    b.scene.add(("z", 0.4), [(0.18, 0.18), (3.82, 0.18), (3.82, 1.82), (0.18, 1.82)],
                rgb("c96a52"), "flagstone")
    b.scene.add(("z", 0.5), [(0.30, 0.30), (3.70, 0.30), (3.70, 1.70), (0.30, 1.70)],
                rgb("4f7fbf"))
    line = 0.022
    for u0, v0, u1, v1 in ((0.42, 0.42, 3.58, 0.42 + line),
                           (0.42, 1.58 - line, 3.58, 1.58),
                           (0.42, 0.42, 0.42 + line, 1.58),
                           (3.58 - line, 0.42, 3.58, 1.58),
                           (2.00 - line * 0.5, 0.42, 2.00 + line * 0.5, 1.58),
                           (1.36, 0.42, 1.36 + line, 1.58),
                           (2.64 - line, 0.42, 2.64, 1.58),
                           (0.42, 1.00 - line * 0.5, 3.58, 1.00 + line * 0.5)):
        b.scene.add(("z", 0.58), b.scene.rect(u0, v0, u1, v1), WHITE)
    b.box(1.98, 0.34, 2.02, 0.40, 0.0, 13.0, WOOD_DARK)
    b.box(1.98, 1.60, 2.02, 1.66, 0.0, 13.0, WOOD_DARK)
    # The net itself, drawn as a mesh of single art-pixel threads.
    b.scene.add(("u", 2.0), [(0.40, 3.0), (1.60, 3.0), (1.60, 11.0), (0.40, 11.0)],
                fn=lambda a, z: WHITE if (int(a * 32) % 2 == 0 and int(z / 2) % 2 == 0)
                else None, bias=0.02)
    for u, v in ((0.10, 0.10), (3.90, 0.10), (0.10, 1.90), (3.90, 1.90)):
        b.box(u - 0.03, v - 0.03, u + 0.03, v + 0.03, 0.0, 10.0, CREAM_DARK)
    b.box(0.30, 1.90, 0.86, 2.04, 0.0, 5.0, WOOD_LIGHT, top_colour=WOOD)


def stable(b: Builder, tier: int):
    b.ground(0.06, 0.06, 2.94, 2.94, rgb("86ab58"), "grass", z=0.25)
    barn = (0.30, 0.35, 2.45, 1.75)
    b.box(*barn, 0.0, 46.0, rgb("c9a276"), pattern="plank")
    b.gable(*barn, 46.0, 76.0, ROOF_BROWN, axis="u", overhang=4.0,
            end_colour=rgb("c9a276"), fascia=ROOF_BROWN)
    b.door("v+", *barn, offset=0.72, z0=2.0, w=14, h=20, colour=rgb("8c5a37"),
           frame=WHITE)
    b.scene.add(("v", barn[3] + 0.03), [(1.30, 38.0), (1.62, 38.0), (1.62, 40.0), (1.30, 40.0)],
                WHITE)
    b.scene.add(("v", barn[3] + 0.04), [(1.38, 52.0), (1.70, 52.0), (1.70, 58.0), (1.38, 58.0)],
                rgb("3c2a1c"))
    b.scene.add(("v", barn[3] + 0.05), [(1.40, 52.4), (1.68, 52.4), (1.68, 53.4), (1.40, 53.4)],
                rgb("c8a45a"))
    b.window("u+", *barn, offset=0.30, z0=24.0, w=10, h=13)
    b.window("u-", *barn, offset=0.58, z0=24.0, w=10, h=13)
    b.window("v-", *barn, offset=0.92, z0=24.0, w=10, h=13)
    b.fence(0.35, 2.55, 2.75, 2.55, z0=0.0, height=12.0, axis="u")
    b.fence(2.75, 1.95, 2.75, 2.55, z0=0.0, height=12.0, axis="v")
    b.box(2.12, 2.08, 2.42, 2.34, 0.0, 9.0, rgb("d9c07a"), "brick",
          top_colour=rgb("e8d18c"))
    b.box(2.46, 2.14, 2.68, 2.36, 0.0, 7.0, rgb("d9c07a"), "brick",
          top_colour=rgb("e8d18c"))
    b.bush(0.18, 2.30, 0.0, 0.65)


def spa(b: Builder, tier: int):
    b.ground(0.06, 0.06, 2.94, 2.94, rgb("d9cba8"), "flagstone", z=0.3,
             kerb=rgb("b6a986"))
    hut = (0.30, 0.30, 1.75, 1.45)
    b.box(*hut, 0.0, 40.0, rgb("efe3c6"), pattern="plank")
    b.hip(hut[0], hut[1], hut[2], hut[3], 40.0, 58.0, rgb("7d6a86"), overhang=3.0)
    b.door("v+", *hut, offset=0.58, z0=2.0, w=9, h=15, colour=rgb("6c5a74"), frame=CREAM)
    b.window("v+", *hut, offset=1.16, z0=20.0, w=10, h=13)
    b.fascia_sign("v+", *hut, offset=0.52, z0=27.0, text="SPA", fg=CREAM,
                  bg=rgb("7d6a86"))
    b.scene.add(("z", 0.4), [(1.70, 1.36), (2.86, 1.36), (2.86, 2.72), (1.70, 2.72)],
                rgb("b9ab88"))
    b.scene.add(("z", 0.5), [(1.84, 1.48), (2.72, 1.48), (2.72, 2.58), (1.84, 2.58)],
                WATER, "water")
    b.scene.add(("z", 0.45), [(1.84, 1.48), (2.72, 1.48), (2.72, 1.62), (1.84, 1.62)],
                WATER_DEEP, "water")
    b.lounger(1.18, 1.95, "u")
    b.lounger(1.18, 2.40, "u")
    b.lounger(1.40, 2.72, "v")
    b.palm(2.55, 0.76, 0.0, 44.0, 0.9)
    b.planter(1.96, 2.80)


def swim_club(b: Builder, tier: int):
    b.ground(0.05, 0.05, 3.95, 2.95, rgb("d6c9a4"), "flagstone", z=0.3,
             kerb=rgb("b3a684"))
    hut = (0.25, 0.30, 1.45, 1.40)
    b.box(*hut, 0.0, 40.0, rgb("f1e7c6"), pattern="plank")
    b.shed(hut[0], hut[1], hut[2], hut[3], 48.0, 40.0, rgb("d98aa6"), along="v",
           overhang=2.5, fascia=rgb("b06d86"))
    b.door("v+", *hut, offset=0.32, z0=2.0, w=9, h=15, colour=rgb("4f7f8f"), frame=CREAM)
    b.fascia_sign("v+", *hut, offset=0.22, z0=26.0, text="SWIM", fg=CREAM,
                  bg=rgb("c46d8c"))
    b.window("u+", *hut, offset=0.28, z0=20.0, w=10, h=13)
    b.scene.add(("z", 0.4), [(1.58, 0.55), (3.80, 0.55), (3.80, 2.70), (1.58, 2.70)],
                rgb("cabd98"))
    b.scene.add(("z", 0.5), [(1.73, 0.70), (3.65, 0.70), (3.65, 2.55), (1.73, 2.55)],
                rgb("6fc0e0"), "water")
    b.scene.add(("z", 0.45), [(1.73, 0.70), (3.65, 0.70), (3.65, 1.02), (1.73, 1.02)],
                WATER_DEEP, "water")
    for v in (1.30, 1.90):
        b.scene.add(("z", 0.56), b.scene.rect(1.95, v, 3.45, v + 0.025),
                    fn=lambda a, b_: rgb("e9f6fb"))
    b.box(1.53, 1.42, 1.95, 1.72, 0.0, 18.0, CREAM, top_colour=CREAM_DARK)
    b.box(1.60, 0.95, 1.88, 1.42, 17.0, 20.0, rgb("e9f6fb"))
    b.box(3.52, 2.20, 3.64, 2.44, 0.0, 7.0, SLATE)
    b.box(3.48, 2.24, 3.70, 2.28, 7.0, 9.0, SLATE)
    b.lounger(2.00, 2.62, "u")
    b.lounger(2.75, 2.62, "u")
    b.fence(1.55, 2.90, 3.85, 2.90, z0=0.0, height=13.0, axis="u")
    b.bush(0.28, 2.60, 0.0, 0.75)


def resort_hotel(b: Builder, tier: int):
    b.ground(0.10, 0.10, 3.90, 3.90, rgb("d8cba6"), "flagstone", z=0.35,
             kerb=rgb("b6a986"), inset=0.14)
    block = (0.45, 0.45, 3.55, 2.25)
    b.box(*block, 0.0, 96.0, rgb("ead9b8"), pattern="plank")
    b.hip(block[0], block[1], block[2], block[3], 96.0, 116.0, rgb("6d7f8c"),
          overhang=4.0)
    for z0 in (64.0, 32.0):
        b.scene.add(("v", block[3] + 0.02),
                    [(block[0], z0 + 12.0), (block[2], z0 + 12.0),
                     (block[2], z0 + 13.5), (block[0], z0 + 13.5)], CREAM_DARK)
    for i in range(4):
        off = 0.18 + i * 0.78
        b.window("v+", *block, offset=off, z0=74.0, w=10, h=13)
        b.window("v+", *block, offset=off, z0=42.0, w=10, h=13)
    for i in range(3):
        off = 0.20 + i * 0.62
        b.window("u+", *block, offset=off, z0=74.0, w=10, h=13)
        b.window("u+", *block, offset=off, z0=42.0, w=10, h=13)
    for i in range(2):
        b.window("u-", *block, offset=0.35 + i * 0.70, z0=74.0, w=10, h=13)
        b.window("u-", *block, offset=0.35 + i * 0.70, z0=42.0, w=10, h=13)
    b.door("v+", *block, offset=1.30, z0=6.0, w=12, h=18, colour=WOOD_DARK, frame=GOLD)
    b.box(1.18, 2.25, 2.62, 2.85, 0.0, 6.0, rgb("cabd98"))
    b.shed(1.08, 2.20, 2.72, 2.92, 26.0, 18.0, rgb("5d6f7c"), along="v",
           overhang=1.0, fascia=CREAM)
    for u in (1.14, 2.66):
        b.box(u - 0.035, 2.84, u + 0.035, 2.92, 0.0, 18.0, CREAM)
    b.ground(1.55, 2.90, 2.25, 3.70, rgb("b0483f"), "flat", z=0.45)
    b.fascia_sign("v+", *block, offset=1.30, z0=27.0, text="HOTEL", fg=CREAM,
                  bg=rgb("5d6f7c"))
    b.palm(0.50, 3.45, 0.0, 46.0, 1.0)
    b.palm(3.50, 3.45, 0.0, 46.0, 1.0)
    b.planter(1.05, 3.28)
    b.planter(2.95, 3.28)


def airstrip(b: Builder, tier: int):
    b.ground(0.05, 0.05, 4.95, 2.95, TARMAC, "asphalt", z=0.3)
    b.scene.add(("z", 0.38), [(0.12, 0.12), (4.88, 0.12), (4.88, 2.88), (0.12, 2.88)],
                rgb("63686e"), "asphalt")
    for i in range(9):
        u0 = 0.35 + i * 0.48
        b.scene.add(("z", 0.46), b.scene.rect(u0, 1.47, u0 + 0.24, 1.53), WHITE)
    hangar = (0.30, 0.28, 1.55, 1.08)
    b.box(*hangar, 0.0, 30.0, rgb("b9b3a0"), pattern="plank", skip=("v+",))
    b.shed(hangar[0], hangar[1], hangar[2], hangar[3], 34.0, 28.0, rgb("6d7f8c"),
           along="v", overhang=2.5, fascia=SLATE)
    b.scene.add(("v", hangar[3] + 0.02), [(0.55, 0.0), (1.30, 0.0), (1.30, 22.0), (0.55, 22.0)],
                rgb("3a3f45"))
    b.fascia_sign("v+", *hangar, offset=0.26, z0=20.0, text="AIR", fg=CREAM,
                  bg=rgb("5d6f7c"))
    plane_u, plane_v = 3.55, 1.95
    b.box(plane_u - 0.62, plane_v - 0.14, plane_u + 0.62, plane_v + 0.14, 3.0, 13.0,
          WHITE, top_colour=rgb("e8e6dc"))
    b.box(plane_u - 0.08, plane_v - 0.78, plane_u + 0.26, plane_v + 0.78, 9.0, 12.0,
          rgb("dfe4e8"))
    b.box(plane_u - 0.62, plane_v - 0.05, plane_u - 0.42, plane_v + 0.05, 13.0, 22.0,
          WHITE)
    b.box(plane_u - 0.66, plane_v - 0.30, plane_u - 0.50, plane_v + 0.30, 20.0, 22.0,
          WHITE)
    b.box(plane_u + 0.58, plane_v - 0.09, plane_u + 0.66, plane_v + 0.09, 9.0, 13.0,
          rgb("3a3f45"))
    b.box(plane_u + 0.26, plane_v - 0.02, plane_u + 0.62, plane_v + 0.02, 9.0, 10.0,
          rgb("e8e6dc"))
    b.box(4.55, 0.55, 4.59, 0.59, 0.0, 30.0, WHITE)
    b.scene.add(("v", 0.59), [(4.55, 26.0), (4.85, 24.0), (4.85, 29.0), (4.55, 30.0)],
                RED)
    b.flag(4.20, 2.55, z0=0.4, height=22.0, colour=YELLOW)


def castle(b: Builder, tier: int):
    b.ground(0.10, 0.10, 4.90, 3.90, rgb("b8ad92"), "gravel", z=0.3,
             kerb=rgb("948a70"), inset=0.12)
    stone = rgb("b9b3a0")
    dark = rgb("98927f")
    keep = (1.15, 0.85, 3.85, 2.95)
    b.box(*keep, 0.0, 64.0, stone, pattern="stone")
    b.scene.add(("z", 66.0), b.scene.rect(keep[0] + 0.05, keep[1] + 0.05,
                                          keep[2] - 0.05, keep[3] - 0.05), dark)
    u = keep[0] + 0.05
    while u + 0.18 < keep[2]:
        b.box(u, keep[3] - 0.22, min(u + 0.18, keep[2] - 0.05), keep[3] - 0.03,
              64.0, 74.0, stone, pattern="stone")
        b.box(u, keep[1] + 0.03, min(u + 0.18, keep[2] - 0.05), keep[1] + 0.22,
              64.0, 74.0, stone, pattern="stone")
        u += 0.34
    gate = (2.05, 2.60, 2.95, 3.15)
    b.box(*gate, 0.0, 44.0, dark, pattern="stone")
    b.scene.add(("v", gate[3] + 0.02), [(2.22, 0.0), (2.78, 0.0), (2.78, 30.0), (2.22, 30.0)],
                rgb("2f2a26"))
    for i in range(4):
        b.box(2.24 + i * 0.14, gate[3] + 0.03, 2.27 + i * 0.14, gate[3] + 0.07,
              0.0, 30.0, rgb("6a6255"))
    b.scene.add(("v", gate[3] + 0.05), [(2.22, 28.0), (2.78, 28.0), (2.78, 30.0), (2.22, 30.0)],
                stone)
    for i, (cu, cv) in enumerate(((1.15, 0.85), (3.85, 0.85), (1.15, 2.95), (3.85, 2.95))):
        t = (cu - 0.34, cv - 0.34, cu + 0.34, cv + 0.34)
        h = 88.0 if i == 0 else 80.0
        b.box(*t, 0.0, h, stone, pattern="stone")
        b.box(t[0] - 0.06, t[1] - 0.06, t[2] + 0.06, t[3] + 0.06, h, h + 3.0, dark)
        for du, dv in ((-0.26, -0.26), (0.0, -0.26), (0.26, -0.26),
                       (-0.26, 0.26), (0.0, 0.26), (0.26, 0.26)):
            b.box(cu + du - 0.09, cv + dv - 0.09, cu + du + 0.09, cv + dv + 0.09,
                  h + 3.0, h + 10.0, stone, pattern="stone")
        b.window("v+", *t, offset=0.12, z0=h - 26.0, w=6, h=9, frame=dark,
                 glass=rgb("3a3a44"))
        b.window("u+", *t, offset=0.12, z0=h - 26.0, w=6, h=9, frame=dark,
                 glass=rgb("3a3a44"))
    b.flag(1.15, 0.85, z0=99.0, height=28.0, colour=RED, plane_axis="u")
    for u in (1.95, 3.05):
        b.box(u - 0.02, gate[3] + 0.06, u + 0.02, gate[3] + 0.10, 20.0, 26.0, WOOD_DARK)
        b.box(u - 0.04, gate[3] + 0.04, u + 0.04, gate[3] + 0.12, 26.0, 30.0, LAMP)


def casino(b: Builder, tier: int):
    b.ground(0.08, 0.08, 3.92, 2.92, rgb("cbbf9c"), "flagstone", z=0.3,
             kerb=rgb("a89c7c"), inset=0.12)
    hall = (0.35, 0.40, 3.65, 2.10)
    b.box(*hall, 0.0, 52.0, rgb("e8d3ac"), pattern="plank")
    b.box(hall[0] - 0.08, hall[1] - 0.08, hall[2] + 0.08, hall[3] + 0.08, 52.0, 57.0,
          rgb("7a3b45"))
    b.scene.add(("z", 57.2), b.scene.rect(hall[0] + 0.10, hall[1] + 0.10,
                                          hall[2] - 0.10, hall[3] - 0.10), rgb("5b2b33"))
    marquee_w = int(round((hall[2] - hall[0] - 0.30) * 32))
    plane, lo, hi, flip = b.side_span("v+", *hall, 0.15, (marquee_w * 2) / 64.0)
    b.panel(("v", hall[3] + 0.03), lo, hi, 46.0, marquee_w, 6,
            lambda px, py: GOLD if (px % 4 == 0 and py in (1, 4)) or py in (0, 5)
            else rgb("7a3b45"), flip, 0.06)
    b.fascia_sign("v+", *hall, offset=0.20, z0=26.0, text="CASINO", fg=GOLD,
                  bg=rgb("5b2b33"))
    b.door("v+", *hall, offset=1.48, z0=5.0, w=14, h=17, colour=rgb("5b2b33"), frame=GOLD)
    b.box(1.28, 2.10, 2.72, 2.70, 0.0, 5.0, rgb("b0483f"), top_colour=rgb("c85a4c"))
    for u in (1.30, 2.70):
        b.box(u - 0.05, 2.62, u + 0.05, 2.72, 0.0, 38.0, GOLD, top_colour=mul(GOLD, 1.2))
    b.box(1.26, 2.70, 2.74, 2.90, 36.0, 40.0, rgb("7a3b45"), top_colour=GOLD)
    for i in range(3):
        b.window("u+", *hall, offset=0.25 + i * 0.55, z0=24.0, w=10, h=13,
                 frame=GOLD, lit=True)
    for i in range(2):
        b.window("u-", *hall, offset=0.30 + i * 0.60, z0=24.0, w=10, h=13,
                 frame=GOLD, lit=True)
    b.window("v-", *hall, offset=0.80, z0=24.0, w=10, h=13, frame=GOLD, lit=True)
    b.palm(0.32, 2.74, 0.0, 40.0, 0.9)
    b.palm(3.68, 2.74, 0.0, 40.0, 0.9)
    b.ground(1.62, 2.70, 2.38, 2.95, rgb("a8433c"), "flat", z=0.45)


def theme_park(b: Builder, tier: int):
    b.ground(0.08, 0.08, 4.92, 3.92, rgb("8fb75f"), "grass", z=0.25)
    b.ground(0.20, 1.20, 4.80, 3.80, rgb("cdbf99"), "flagstone", z=0.4,
             kerb=rgb("a89a76"), inset=0.10)
    tent = (3.45, 1.35, 4.75, 2.55)
    b.box(*tent, 0.0, 28.0, CREAM, pattern="plank")
    b.pyramid(tent[0], tent[1], tent[2], tent[3], 28.0, 54.0, rgb("c85a4c"),
              overhang=3.0)
    b.scene.add(("v", tent[3] + 0.02), [(3.68, 0.0), (4.52, 0.0), (4.52, 20.0), (3.68, 20.0)],
                rgb("3c3430"))
    b.fascia_sign("v+", *tent, offset=0.16, z0=16.0, text="PARK", fg=CREAM,
                  bg=rgb("c85a4c"))

    wheel_u, wheel_v = 1.75, 2.55
    centre_z = 84.0
    radius = 30.0

    def disc(points, colour, bias=0.1):
        b.billboard(wheel_u, wheel_v, centre_z, points, colour, bias=bias)

    # The wheel always faces the viewer, so it is drawn in screen space: a
    # circle would shear if it were laid on a grid plane.
    segments = 16
    def at(angle, r):
        # Screen pixels: x right, y up from the hub.
        return (math.cos(angle) * r, math.sin(angle) * r)

    for i in range(segments):
        a0 = 2 * math.pi * i / segments
        a1 = 2 * math.pi * (i + 1) / segments
        disc([at(a0, radius + 3.0), at(a1, radius + 3.0),
              at(a1, radius - 3.0), at(a0, radius - 3.0)], rgb("d7d2c4"))
        if i % 2 == 0:
            c = at((a0 + a1) * 0.5, radius)
            disc([(c[0] - 5, c[1] - 4), (c[0] + 5, c[1] - 4),
                  (c[0] + 5, c[1] + 4), (c[0] - 5, c[1] + 4)],
                 [RED, BLUE, YELLOW, PINK][(i // 2) % 4], bias=0.3)
    for i in range(8):
        a = 2 * math.pi * i / 8
        disc([(0.0, 0.0), at(a + 0.05, radius), at(a - 0.05, radius)],
             rgb("b9b3a4"), bias=0.2)
    disc([(-3.5, -3.5), (3.5, -3.5), (3.5, 3.5), (-3.5, 3.5)], GOLD, bias=0.4)
    # A-frame legs standing on the midway, splayed in both directions so they
    # read from any rotation.
    for du in (-0.50, 0.50):
        for dv in (-0.30, 0.30):
            b.box(wheel_u + du - 0.05, wheel_v + dv - 0.05,
                  wheel_u + du + 0.05, wheel_v + dv + 0.05,
                  0.0, centre_z - 26.0, rgb("8a8578"))
    for i in range(7):
        u = 0.55 + i * 0.62
        b.box(u, 3.55, u + 0.03, 3.58, 0.0, 18.0, WOOD_LIGHT)
        b.box(u - 0.02, 3.53, u + 0.05, 3.60, 18.0, 20.0, LAMP)
    b.planter(0.45, 1.55)
    b.planter(2.60, 3.20)
    b.bush(4.55, 3.45, 0.0, 0.8)


BUILDINGS = {
    "clubhouse": {"tiles": (4, 4), "tiers": 3, "height": 180.0, "draw": clubhouse},
    "putting_green": {"tiles": (3, 3), "tiers": 1, "height": 70.0, "draw": putting_green},
    "snack_bar": {"tiles": (2, 2), "tiers": 1, "height": 70.0, "draw": snack_bar},
    "pub": {"tiles": (3, 2), "tiers": 1, "height": 110.0, "draw": pub},
    "pro_shop": {"tiles": (2, 2), "tiers": 1, "height": 90.0, "draw": pro_shop},
    "driving_range": {"tiles": (6, 3), "tiers": 1, "height": 90.0, "draw": driving_range},
    "cart_garage": {"tiles": (3, 2), "tiers": 1, "height": 80.0, "draw": cart_garage},
    "tennis_court": {"tiles": (4, 2), "tiers": 1, "height": 50.0, "draw": tennis_court},
    "stable": {"tiles": (3, 3), "tiers": 1, "height": 110.0, "draw": stable},
    "spa": {"tiles": (3, 3), "tiers": 1, "height": 90.0, "draw": spa},
    "swim_club": {"tiles": (4, 3), "tiers": 1, "height": 80.0, "draw": swim_club},
    "resort_hotel": {"tiles": (4, 4), "tiers": 1, "height": 160.0, "draw": resort_hotel},
    "airstrip": {"tiles": (5, 3), "tiers": 1, "height": 80.0, "draw": airstrip},
    "castle": {"tiles": (5, 4), "tiers": 1, "height": 160.0, "draw": castle},
    "casino": {"tiles": (4, 3), "tiers": 1, "height": 100.0, "draw": casino},
    "theme_park": {"tiles": (5, 4), "tiers": 1, "height": 130.0, "draw": theme_park},
}
