#!/usr/bin/env python3
"""3D models for the improvements that read in the round.

The Park Bench, Golfer Statue and Ball Washer are small objects a player buys
to dress a hole.  Like the trees, ground cover and facilities, they are
authored here as real little 3D models and baked to pixel art through the
buildings' isometric renderer (``tools/building_art/render.py``) by
``tools/improvement_art/generate.py``.  One pixel of the PNG is one world
pixel, so an improvement stands on its tile at every view rotation without a
scale factor.

The Fountain and Sundial are **not** modelled here: they are read from above,
and a 3D basin rim occludes its own water while a horizontal dial face is only
a few pixels tall.  Both are painted in screen space in ``paint2d.py`` instead,
in the same palette and outline weight.

Art direction
-------------
* **One afternoon, one palette.**  The props borrow the buildings' cream stone,
  warm timber, slate iron and brass, so a bench under the clubhouse windows
  belongs to the same course.  Bronze sculpture is the one deliberate new
  family: warm bronze with a green patina in its lee.
* **Silhouette first.**  A bench reads as a bench at one pixel per world pixel:
  open slats, a visible backrest, wrought-iron legs and curled arms.  A statue
  reads as a golfer mid-swing, not a post.  A washer reads as the tee-side
  station it is: post, housing, lid and towel.
* **Grounded and detailed.**  Every prop meets the turf at a real foot: a stone
  apron, iron feet or a brass base plate.
* **Four fronts, one bench.**  The bench is laid *beside* a walk and turns to
  face it, so it is modelled once facing south and rotated around the tile
  centre for the four cardinal fronts.  The statue and ball washer stand in the
  open and are drawn once.

Model space
-----------
A prop stands on the centre of its 1x1 tile at ``(32, 16, 0)`` in the same
world-pixel space the trees and buildings use (64 px across the tile, 32 px
deep, z up).  It is not clipped to the diamond: a tall statue may rise above
the tile, and a bench's seat may overhang the tile's edge, exactly as a canopy
does.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

from render import (  # noqa: E402  (building_art on the path)
    C, GOLD, GOLD_DARK, GRASS_LIGHT, INK, Model, STONE, STONE_DARK, STONE_LIGHT,
    TILE_H, TILE_W, WHITE, WOOD, WOOD_DARK, WOOD_LIGHT, mat,
    text_texture,
)
from buildings import Builder  # noqa: E402

#: The tile centre every prop is modelled around.
BASE_X, BASE_Y = 32.0, 16.0

#: A prop's four fronts, matching ``PathFurniture``'s cardinal vectors.  The
#: order is also the file suffix: 0 south (the authored model), 1 east,
#: 2 north, 3 west.  Rotating the authored model one quarter turn clockwise in
#: grid space turns its front from south to east.
FRONTS = ("down", "right", "up", "left")

#: How many quarter turns of the authored model each front needs.
FRONT_TURNS = {"down": 0, "right": 1, "up": 2, "left": 3}

#: Props that are laid beside a walk and turn to face it.  The rest stand in
#: the open and have one drawing.
DIRECTIONAL = ("park_bench",)

#: Every improvement key, in the order the generator bakes them.
PROP_KEYS = ("path", "park_bench", "ball_washer", "fountain", "golfer_statue", "sundial")

#: The fountain and sundial are painted in screen space (``paint2d.py``); the
#: Path is ground art (``tools/path_art``), so neither has a model here.  The
#: rest are modelled and rendered.
ORNAMENT_KEYS = ("fountain", "golfer_statue", "ball_washer", "park_bench", "sundial")


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

CREAM = C("efe2c2")
CREAM_DARK = C("cdbc97")
GRANITE = mat(C("8b8377"), "stone")
#: Cool granite for the statue's round pedestal, flat so the drum keeps one tone.
PLINTH_STONE = mat(C("8f9597"), "flat", emissive=0.05)
PLINTH_STONE_LIGHT = mat(C("b9bfc1"), "flat", emissive=0.07)
GRANITE_LIGHT = mat(C("a49b8c"), "stone")
GRANITE_DARK = mat(C("6b6459"), "stone")
STONE_WARM = mat(C("d2c3a0"), "stone")
STONE_WARM_LIGHT = mat(C("e2d5b6"), "stone")
STONE_WARM_DARK = mat(C("b3a486"), "stone")
STONE_PALE = mat(C("e8ddc2"), "flat", emissive=0.07)
STONE_PALE_LIGHT = mat(C("f8efdb"), "flat", emissive=0.09)
STONE_CLEAN = mat(C("dccfae"), "flat", emissive=0.06)
STONE_CLEAN_LIGHT = mat(C("efe4c8"), "flat", emissive=0.08)
STONE_CLEAN_DARK = mat(C("b8a987"), "flat", emissive=0.04)
MOSS = mat(C("5b7a43"), "hedge")
MOSS_LIGHT = mat(C("73944f"), "hedge")
IRON = mat(C("58665d"), "flat", emissive=0.10)
IRON_LIGHT = mat(C("7d8c80"), "flat", emissive=0.12)
IRON_DARK = mat(C("394640"), "flat", emissive=0.08)
BRONZE = mat(C("a67d48"), "flat", specular=0.35, emissive=0.09)
BRONZE_LIGHT = mat(C("c59a5e"), "flat", specular=0.45, emissive=0.10)
BRONZE_DARK = mat(C("74562f"), "flat", emissive=0.07)
PATINA = mat(C("5f8a72"), "flat")
PATINA_LIGHT = mat(C("7fae8e"), "flat")
BRASS = mat(C("d9b75e"), "flat", specular=0.5, emissive=0.12)
BRASS_DARK = mat(C("a4823a"), "flat", emissive=0.08)
WATER = mat(C("73c4e6"), "flat", specular=0.45, emissive=0.10)
WATER_LIGHT = mat(C("b7e8f9"), "flat", specular=0.4, emissive=0.14)
WATER_DARK = mat(C("4f9cc4"), "flat", emissive=0.08)
TIMBER = mat(C("bd7f4b"), "flat", emissive=0.10)
TIMBER_LIGHT = mat(C("dba368"), "flat", emissive=0.12)
TIMBER_DARK = mat(C("87582f"), "flat", emissive=0.08)
TOWEL = mat(C("eee9d9"), "plank")
TERRACOTTA = mat(C("b4664a"), "flat")
LEAF = mat(C("4d7f43"), "leaf_fine")
LEAF_LIGHT = mat(C("6fa452"), "leaf_fine")
FLOWER = mat(C("e7c85f"), "bloom")
SHADOW = mat(C("2f3d28"), alpha=0.22, unlit=True)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def ring(b: Builder, cx: float, cy: float, z0: float, z1: float,
         outer: float, inner: float, material, segments: int = 16,
         top_material=None, inner_material=None) -> None:
    """A lathed stone ring: outer wall, inner wall, rim and soffit.

    ``Builder.cylinder()`` would cap the middle; a fountain basin has to stay
    open so its water plane shows.
    """
    top_material = material if top_material is None else top_material
    inner_material = material if inner_material is None else inner_material
    gid = b.m.group()
    for i in range(segments):
        a0 = 2.0 * math.pi * i / segments
        a1 = 2.0 * math.pi * (i + 1) / segments
        c0, s0 = math.cos(a0), math.sin(a0)
        c1, s1 = math.cos(a1), math.sin(a1)
        # Outer wall.
        b.m.quad((cx + outer * c0, cy + outer * s0, z0),
                 (cx + outer * c1, cy + outer * s1, z0),
                 (cx + outer * c1, cy + outer * s1, z1),
                 (cx + outer * c0, cy + outer * s0, z1),
                 material, uvs=((a0 * outer, z0), (a1 * outer, z0),
                                (a1 * outer, z1), (a0 * outer, z1)),
                 ao=(0.94, 0.94, 1.0, 1.0), group=gid)
        # Inner wall, seen from inside the basin.
        b.m.quad((cx + inner * c1, cy + inner * s1, z0),
                 (cx + inner * c0, cy + inner * s0, z0),
                 (cx + inner * c0, cy + inner * s0, z1),
                 (cx + inner * c1, cy + inner * s1, z1),
                 inner_material, uvs=((a1 * inner, z0), (a0 * inner, z0),
                                      (a0 * inner, z1), (a1 * inner, z1)),
                 ao=(0.84, 0.84, 0.96, 0.96), group=gid)
        # Rim.
        b.m.quad((cx + inner * c0, cy + inner * s0, z1),
                 (cx + inner * c1, cy + inner * s1, z1),
                 (cx + outer * c1, cy + outer * s1, z1),
                 (cx + outer * c0, cy + outer * s0, z1),
                 top_material, uvs=((a0 * outer, inner), (a1 * outer, inner),
                                    (a1 * outer, outer), (a0 * outer, outer)),
                 ao=(1.0, 1.0, 1.0, 1.0), group=gid)
        # Soffit / underside so the ring never reads hollow from a low view.
        b.m.quad((cx + outer * c0, cy + outer * s0, z0),
                 (cx + outer * c1, cy + outer * s1, z0),
                 (cx + inner * c1, cy + inner * s1, z0),
                 (cx + inner * c0, cy + inner * s0, z0),
                 material, uvs=((a0 * outer, 0.0), (a1 * outer, 0.0),
                                (a1 * outer, 1.0), (a0 * outer, 1.0)),
                 ao=(0.45, 0.45, 0.45, 0.45), group=gid)


def frustum(b: Builder, cx: float, cy: float, z0: float, z1: float,
            r0: float, r1: float, material, segments: int = 16,
            cap: bool = True, cap_material=None) -> None:
    """A tapered round plinth: a cylinder whose two rings differ in radius."""
    cap_material = material if cap_material is None else cap_material
    gid = b.m.group()
    for i in range(segments):
        a0 = 2.0 * math.pi * i / segments
        a1 = 2.0 * math.pi * (i + 1) / segments
        c0, s0 = math.cos(a0), math.sin(a0)
        c1, s1 = math.cos(a1), math.sin(a1)
        b.m.quad((cx + r0 * c0, cy + r0 * s0, z0),
                 (cx + r0 * c1, cy + r0 * s1, z0),
                 (cx + r1 * c1, cy + r1 * s1, z1),
                 (cx + r1 * c0, cy + r1 * s0, z1),
                 material, uvs=((a0 * r0, z0), (a1 * r0, z0),
                                (a1 * r1, z1), (a0 * r1, z1)),
                 ao=(0.94, 0.94, 1.0, 1.0), group=gid)
    if cap:
        for i in range(segments):
            a0 = 2.0 * math.pi * i / segments
            a1 = 2.0 * math.pi * (i + 1) / segments
            b.m.tri((cx, cy, z1),
                    (cx + r1 * math.cos(a0), cy + r1 * math.sin(a0), z1),
                    (cx + r1 * math.cos(a1), cy + r1 * math.sin(a1), z1),
                    cap_material, ao=(1.0, 1.0, 1.0), group=gid)


def panel(b: Builder, x0: float, y0: float, x1: float, y1: float,
          z0: float, z1: float, material, top=None) -> None:
    """A thin upright slab with a lit top edge, used for plaques and signs."""
    b.box(x0, y0, x1, y1, z0, z1, material, top=top if top is not None else material)


def _plaque_text(text: str, fg=CREAM, bg=None, scale: int = 1):
    if bg is None:
        bg = BRONZE_DARK.color
    return text_texture(text, fg, bg, scale=scale, padding=1)[0]


def leaf_clump(b: Builder, cx: float, cy: float, cz: float, rx: float,
               ry: float, rz: float, material=LEAF, light=LEAF_LIGHT) -> None:
    """A low garden clump: a dark mass with a sunlit shoulder."""
    b.ellipsoid(cx, cy, cz, rx, ry, rz, material, segments=8, rings=5,
                ao_base=0.72)
    b.ellipsoid(cx + rx * 0.45, cy + ry * 0.1, cz + rz * 0.45,
                rx * 0.62, ry * 0.58, rz * 0.55, light, segments=7, rings=4,
                ao_base=0.78)


def stone_scatter(b: Builder, cx: float, cy: float, z: float, rng,
                  count: int = 5, spread: float = 13.0) -> None:
    """A few chippings and a tuft of moss where a heavy prop meets the turf."""
    for i in range(count):
        angle = rng.uniform(0.0, math.tau)
        dist = rng.uniform(spread * 0.55, spread)
        px = cx + math.cos(angle) * dist
        py = cy + math.sin(angle) * dist * 0.55
        size = rng.uniform(1.1, 2.3)
        b.ellipsoid(px, py, z + size * 0.55, size, size * 0.7, size * 0.55,
                    GRANITE_LIGHT if i % 2 == 0 else GRANITE_DARK,
                    segments=5, rings=3, ao_base=0.7)
    leaf_clump(b, cx + spread * 0.75, cy + spread * 0.35, z + 1.2,
               4.4, 3.2, 2.4, MOSS, MOSS_LIGHT)


# ---------------------------------------------------------------------------
# the props
# ---------------------------------------------------------------------------

def park_bench(b: Builder) -> None:
    """A slatted timber bench with wrought-iron legs, arms and a brass plaque.

    Authored facing south: the seat runs along x and the back stands on the -y
    side, toward the top of the screen at the default view.
    """
    cx = BASE_X
    # The seat: three open boards with a visible gap between them, long enough
    # to read as a bench from above.
    for y in (12.0, 15.6, 19.2):
        b.box(cx - 20.0, y, cx + 20.0, y + 3.0, 9.4, 11.6,
              TIMBER, top=TIMBER_LIGHT)
        for sx in (-20.0, 19.2):
            b.box(cx + sx, y - 0.2, cx + sx + 0.8, y + 3.2, 9.4, 11.6,
                  TIMBER_DARK, top=TIMBER)
    # Wrought-iron legs: four slim posts with little cast feet.
    for x in (-17.4, 15.0):
        for y in (12.5, 18.8):
            b.box(cx + x, y, cx + x + 2.4, y + 2.4, 0.0, 9.6, IRON,
                  top=IRON_LIGHT)
            b.box(cx + x - 0.5, y - 0.5, cx + x + 2.9, y + 2.9, 0.0, 1.0,
                  IRON_DARK)
        # A cross brace under the seat.
        b.cylinder_between((cx + x + 1.2, 12.6, 7.8),
                           (cx + x + 1.2, 20.6, 7.8), 0.7, IRON_DARK,
                           segments=6)
    # Armrests: a bar over the seat and a post down to the front foot.
    for x in (-16.2, 16.2):
        b.cylinder_between((cx + x, 12.4, 13.6), (cx + x, 20.2, 13.6),
                           0.9, IRON, segments=6)
        b.cylinder_between((cx + x, 20.2, 13.6), (cx + x, 20.2, 9.4),
                           0.9, IRON, segments=6)
        b.ellipsoid(cx + x, 20.2, 13.8, 1.1, 1.1, 0.8, IRON_LIGHT,
                    segments=5, rings=3)
    # The back: two iron stiles and three boards, leaning back a little.
    for x in (-16.2, 16.2):
        b.cylinder_between((cx + x, 12.9, 11.0),
                           (cx + x, 10.9, 23.0), 1.0, IRON, segments=6)
    for z in (13.2, 16.8, 20.4):
        y0 = 12.4 - (z - 11.0) * 0.10
        b.box(cx - 18.4, y0 - 0.9, cx + 18.4, y0 + 2.1, z, z + 3.0,
              TIMBER, top=TIMBER_LIGHT)
    # A curved top rail, a brass plaque and coach bolts at the seat ends.
    b.cylinder_between((cx - 18.0, 10.4, 23.8), (cx + 18.0, 10.4, 23.8),
                       1.1, TIMBER_LIGHT, segments=6)
    b.box(cx - 5.6, 10.2, cx + 5.6, 10.7, 17.6, 20.2, BRASS_DARK,
          top=BRASS)
    b.m.decal((cx - 4.8, 10.14, 19.8), (cx + 4.8, 10.14, 19.8),
              (cx + 4.8, 10.14, 18.0), (cx - 4.8, 10.14, 18.0),
              mat(C("ffffff"), texture=_plaque_text("GT", scale=1)),
              (10, 2), bias=0.08)
    for x in (-18.4, 17.0):
        b.cylinder(cx + x, 13.6, 11.6, 12.4, 0.85, BRASS, segments=6)
    # A clump of grass and a daisy pushing up by a front foot.
    leaf_clump(b, cx + 24.0, 21.0, 0.8, 3.2, 2.4, 1.8, MOSS, MOSS_LIGHT)
    b.ellipsoid(cx + 23.5, 13.0, 2.2, 1.2, 1.1, 1.0, FLOWER,
                segments=5, rings=3)


def ball_washer(b: Builder) -> None:
    """A tee-side ball washer: base plate, post, brush drum, lid and towel.

    Authored facing south; the towel bar and the enamel sign face the walk.
    """
    cx, cy = BASE_X, BASE_Y
    post = mat(C("d9d4c2"), "flat", emissive=0.10)
    enamel = mat(C("b65a45"), "flat", emissive=0.10)
    enamel_dark = mat(C("8d4134"), "flat", emissive=0.08)
    # A cast base plate bolted to the turf.
    b.cylinder(cx, cy, 0.0, 1.4, 7.0, IRON_DARK, segments=12,
               cap_material=IRON)
    for a in (0.35, 1.9, 3.5, 5.1):
        b.cylinder(cx + math.cos(a) * 5.0, cy + math.sin(a) * 5.0, 1.4, 2.1,
                   0.8, BRASS, segments=5)
    # The post: pale enamel with brass collars.
    b.cylinder(cx, cy, 1.4, 20.0, 2.1, post, segments=10)
    for z in (4.0, 10.5, 16.0):
        b.cylinder(cx, cy, z, z + 1.0, 2.6, BRASS_DARK, segments=10,
                   cap=False)
    b.cylinder(cx, cy, 19.2, 20.6, 3.2, IRON, segments=10)
    # The drum: a fat enamelled housing with three brass hoops and a domed lid.
    gid = b.m.group()
    frustum(b, cx, cy, z if False else 20.0, 30.4, 6.2, 5.4, enamel,
            segments=12, cap=False)
    b.cylinder(cx, cy, 20.0, 20.8, 6.3, enamel_dark, segments=12,
               cap=False)
    for z in (23.0, 26.0, 29.0):
        b.cylinder(cx, cy, z, z + 0.9, 6.35, BRASS_DARK, segments=12,
                   cap=False)
    b.cylinder(cx, cy, 30.4, 31.8, 5.9, BRASS, segments=12,
               cap_material=BRASS)
    b.ellipsoid(cx, cy, 32.6, 3.8, 3.7, 1.9, BRASS_DARK, segments=10,
                rings=4)
    b.cylinder(cx, cy, 32.8, 34.4, 1.0, BRASS, segments=6)
    # The brush pokes out of the open top, with a little drip.
    b.cylinder(cx, cy, 31.0, 31.8, 3.6, WHITE, segments=10, cap=True,
               cap_material=WHITE)
    b.m.quad((cx - 1.2, cy - 1.2, 31.7), (cx + 1.2, cy - 0.8, 31.7),
             (cx + 1.0, cy + 1.0, 20.6), (cx - 1.4, cy + 0.6, 20.6),
             WATER_LIGHT, uvs=((0, 0), (1, 0), (1, 10), (0, 10)),
             ao=(1.0, 1.0, 0.8, 0.8), bias=0.06)
    # The water tank slung on the back of the post, with a brass tap.
    b.box(cx - 3.8, cy - 7.2, cx + 3.8, cy - 3.4, 11.0, 19.0, IRON_DARK,
          top=IRON)
    b.cylinder(cx + 3.8, cy - 5.2, 13.5, 14.5, 0.9, BRASS, segments=6)
    b.cylinder(cx + 4.7, cy - 5.2, 12.0, 15.0, 0.4, BRASS_DARK, segments=5)
    # A towel bar on the front, a folded cream towel over it.
    b.cylinder_between((cx - 5.4, cy + 4.0, 16.0), (cx + 5.4, cy + 4.0, 16.0),
                       0.7, BRASS, segments=6)
    b.box(cx - 4.2, cy + 3.6, cx + 4.2, cy + 4.5, 9.2, 16.2, TOWEL,
          top=WHITE)
    b.box(cx - 4.2, cy + 3.9, cx + 4.2, cy + 4.8, 9.2, 10.2,
          mat(C("d8d2c0"), "flat"), top=TOWEL)
    # A big enamel sign on the drum's front, so the station announces itself.
    b.box(cx - 5.2, cy + 6.0, cx + 5.2, cy + 6.9, 21.6, 27.2,
          mat(C("f6efdc"), "flat"), top=WHITE)
    b.m.decal((cx - 4.8, cy + 6.92, 26.8), (cx + 4.8, cy + 6.92, 26.8),
              (cx + 4.8, cy + 6.92, 22.0), (cx - 4.8, cy + 6.92, 22.0),
              mat(C("ffffff"), texture=text_texture(
                  "WASH", C("2f5c48"), C("f6efdc"), scale=1, padding=1)[0]),
              (10, (28 if False else 4)), bias=0.08)
    # Moss and a pebble at the plate.
    leaf_clump(b, cx + 8.5, cy + 3.0, 0.6, 3.0, 2.2, 1.6, MOSS, MOSS_LIGHT)
    b.ellipsoid(cx - 8.0, cy + 3.4, 0.9, 1.7, 1.3, 1.0, GRANITE_LIGHT,
                segments=5, rings=3)


def golfer_statue(b: Builder) -> None:
    """A bronze golfer mid-swing on a stepped stone plinth."""
    cx, cy = BASE_X, BASE_Y
    z = 0.0
    # Three round steps and a turned plinth, so the memorial reads as a
    # circular stone drum rather than a square packing crate.
    # One round drum on a round footing: a memorial pedestal, not a stack of
    # square slabs with the corners knocked off.
    b.cylinder(cx, cy, z, z + 1.6, 9.4, PLINTH_STONE, segments=10,
               cap_material=PLINTH_STONE_LIGHT)
    b.cylinder(cx, cy, z + 1.6, z + 11.8, 7.4, PLINTH_STONE, segments=10,
               cap=False)
    b.cylinder(cx, cy, z + 11.8, z + 12.6, 8.4, PLINTH_STONE_LIGHT,
               segments=10, cap_material=STONE_PALE_LIGHT)
    b.cylinder(cx, cy, z + 12.6, z + 13.2, 6.0, PLINTH_STONE,
               segments=10, cap_material=STONE_PALE_LIGHT)
    # A slim bronze band around the drum, in place of a flat plaque.
    b.cylinder(cx, cy, z + 7.4, z + 8.2, 7.6, BRASS_DARK, segments=10,
               cap=False)
    # The figure: a wide, braced stance, a turned torso and a driver held at
    # the top of the backswing.  Each limb is one crease group, so its facets
    # shade as a cast bronze limb rather than a stack of segments.
    base_z = z + 13.2
    for (fx, fy, knee_x, knee_y, hip_x, hip_y) in (
            (-6.0, 3.0, -7.2, 1.8, -3.0, 0.3),
            (6.0, -1.8, 6.8, -0.8, 3.0, 0.3)):
        gid = b.m.group()
        b.ellipsoid(cx + fx, cy + fy, base_z + 1.2, 2.8, 1.9, 1.4,
                    BRONZE_DARK, segments=7, rings=4, group=gid)
        b.cylinder_between((cx + fx, cy + fy, base_z + 0.9),
                           (cx + knee_x, cy + knee_y, base_z + 6.6),
                           2.6, BRONZE, segments=7, group=gid)
        b.ellipsoid(cx + knee_x, cy + knee_y, base_z + 6.6, 2.6, 2.3, 2.4,
                    BRONZE_DARK, segments=6, rings=4, group=gid)
        b.cylinder_between((cx + knee_x, cy + knee_y, base_z + 6.6),
                           (cx + hip_x, cy + hip_y, base_z + 12.4),
                           2.9, BRONZE, segments=7, group=gid)
    # Hips, torso and shoulders, with the lit shoulder and the shadowed back
    # separated so the turn of the body reads.
    gid = b.m.group()
    b.ellipsoid(cx, cy, base_z + 13.0, 5.8, 4.0, 3.7, BRONZE, segments=8,
                rings=5, group=gid)
    b.cylinder_between((cx, cy, base_z + 13.4),
                       (cx + 1.8, cy - 0.5, base_z + 21.0),
                       5.4, BRONZE, segments=8, group=gid)
    b.ellipsoid(cx + 1.8, cy - 0.5, base_z + 21.6, 5.6, 3.4, 3.3,
                BRONZE_LIGHT, segments=8, rings=5, group=gid)
    # Arms: the left reaches across the chest, the right is high on the grip.
    gid = b.m.group()
    b.cylinder_between((cx - 3.4, cy - 1.4, base_z + 22.0),
                       (cx + 4.6, cy - 3.6, base_z + 26.4),
                       2.3, BRONZE, segments=6, group=gid)
    b.cylinder_between((cx + 3.8, cy - 0.6, base_z + 22.6),
                       (cx + 5.8, cy - 3.4, base_z + 24.6),
                       2.3, BRONZE_LIGHT, segments=6, group=gid)
    b.ellipsoid(cx + 5.6, cy - 3.6, base_z + 25.2, 2.6, 2.3, 2.4,
                BRONZE_DARK, segments=6, rings=4, group=gid)
    # Head, a cap brim and a short ponytail.
    gid = b.m.group()
    b.ellipsoid(cx + 1.5, cy - 1.6, base_z + 25.6, 3.5, 3.1, 3.7,
                BRONZE_LIGHT, segments=8, rings=5, group=gid)
    b.ellipsoid(cx + 1.5, cy - 3.0, base_z + 26.8, 3.6, 2.3, 1.0,
                BRONZE_DARK, segments=7, rings=3, group=gid)
    b.ellipsoid(cx - 1.0, cy - 1.8, base_z + 25.2, 1.6, 2.0, 2.7,
                BRONZE, segments=6, rings=4, group=gid)
    # The club: a long shaft from the hands to a driver head behind the
    # shoulders, with a leather grip.
    gid = b.m.group()
    hand = (cx + 5.6, cy - 3.6, base_z + 25.4)
    shaft = (cx - 12.0, cy - 5.8, base_z + 30.4)
    b.cylinder_between(hand, shaft, 1.0, BRONZE_DARK, segments=5, group=gid)
    b.cylinder_between(hand, (cx + 6.6, cy - 3.8, base_z + 23.0), 1.1,
                       BRONZE_DARK, segments=5, group=gid)
    b.box(cx - 14.4, cy - 6.6, cx - 10.2, cy - 4.0, base_z + 29.0,
          base_z + 32.0, BRONZE, top=BRONZE_LIGHT)
    # Flowers and moss at the plinth's foot.
    stone_scatter(b, cx, cy, z, np.random.default_rng(0x57A7E), count=5,
                  spread=18.0)
    for px, py, col in ((-14.0, 7.0, FLOWER), (13.0, 6.0, mat(C("e3a1bf"), "bloom")),
                        (16.0, -3.0, FLOWER)):
        b.ellipsoid(cx + px, cy + py, z + 1.2, 1.5, 1.3, 1.2, col,
                    segments=5, rings=3)


# ---------------------------------------------------------------------------
# model assembly
# ---------------------------------------------------------------------------

def build_prop(key: str) -> Model:
    """One authored model, facing south, on the centre of its tile."""
    model = Model(1, 1)
    b = Builder(model)
    b.facing = 0
    {
        "park_bench": park_bench,
        "ball_washer": ball_washer,
        "golfer_statue": golfer_statue,
    }[key](b)
    scale = MODEL_SCALE.get(key, 1.0)
    if abs(scale - 1.0) > 1e-6:
        model = scale_model(model, scale)
    return model


#: Props whose authored model is a little small for a 64x32 tile.  Scaling the
#: model (rather than the render) keeps every output pixel an output pixel.
MODEL_SCALE = {
    "ball_washer": 0.88,
}


def _rescaled(model: Model, point) -> Model:
    """Rebuild a model from a per-vertex mapping, recomputing crease normals."""
    out = Model(*model.tiles)
    for tri in model.tris:
        pts = tuple(point(x, y, z) for x, y, z in tri.p)
        a, b, c = (np.asarray(p, dtype=float) for p in pts)
        n = np.cross(b - a, c - a)
        length = float(np.linalg.norm(n))
        normal = (n / length).astype(np.float32) if length > 1e-9 \
            else np.array([0.0, 0.0, 1.0], dtype=np.float32)
        out.tris.append(type(tri)(pts, tri.uv, tri.ao, normal,
                                  tri.material, tri.group, tri.bias))
    return out


def scale_model(model: Model, factor: float) -> Model:
    """Uniformly scale a model about its tile centre on the ground plane."""
    cx, cy = BASE_X, BASE_Y
    return _rescaled(model, lambda x, y, z: (
        cx + (x - cx) * factor, cy + (y - cy) * factor, z * factor))


def rotate_model(model: Model, turns: int) -> Model:
    """Rotate a model around the tile centre by `turns` quarter turns clockwise."""
    turns %= 4
    if turns == 0:
        return model
    cx, cy = BASE_X, BASE_Y

    def turn(x, y, z):
        dx, dy = x - cx, y - cy
        for _ in range(turns):
            dx, dy = dy, -dx
        return (cx + dx, cy + dy, z)

    return _rescaled(model, turn)


def variants_for(key: str) -> list[tuple[str, Model]]:
    """Every drawing of a prop: (suffix, model), in file order."""
    if key in DIRECTIONAL:
        return [(str(i), rotate_model(build_prop(key), i))
                for i in range(4)]
    return [("0", build_prop(key))]


def prop_foot() -> tuple[float, float]:
    """The tile centre's projected foot in the renderer's local draw space."""
    from render import grid_origin_offset, project
    origin = grid_origin_offset(1, 1, 0)
    px, py = project(BASE_X, BASE_Y, 0.0, 0)
    return (origin[0] + px, origin[1] + py)


def foot_ratios(rect) -> tuple[float, float]:
    """Where the tile centre lands inside a cropped render, normalized."""
    fx, fy = prop_foot()
    return ((fx - rect[0]) / max(rect[2], 1e-6),
            (fy - rect[1]) / max(rect[3], 1e-6))
