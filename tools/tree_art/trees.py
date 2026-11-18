#!/usr/bin/env python3
"""3D models for every tree species that grows on the course.

Each species is a real 3D model in world-pixel space - ``x`` across the tile
(a tile is 64 wide), ``y`` down it (32 deep) and ``z`` up - standing on the
centre of a 1x1 footprint at ``(32, 16, 0)``.  The shared ``Builder`` from
``tools/building_art`` supplies the solids (boxes, cylinders, cones,
ellipsoids), and ``TreeBuilder`` adds the organic kit: tapered limbs,
layered foliage masses, grass blades, palm fronds and pebbles.

The renderer projects each model through the game's 2:1 isometric axes and
bakes one pixel sprite per view variant, exactly like the building art in
``tools/building_art``.  Every variant is its own seeded drawing of the same
species (``variant_seed()``), not a rotation of one model: the four views are
alternatives a woodland tile wears for life (see ``TreeOverlay.facing_at()``),
so a wood shows several different trees at once and they share one sun.

The models are built the way a tree grows: a root-flared trunk, gnarled
forking limbs, and a crown assembled in layers - a shadowed under-mass, lit
main clumps and a ring of small rim clumps that break the silhouette into
leaves.  One model pixel is one world pixel: a mature oak crown is about
85 px wide, a grass tuft 40 px, matching the draw sizes the layout scales
used to tune.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

from render import (  # noqa: E402  (path set up above)
    C, LEAF, LEAF_DARK, LEAF_LIGHT, Model, WOOD, WOOD_DARK, WOOD_LIGHT, mat,
)
from buildings import Builder  # noqa: E402


# ---------------------------------------------------------------------------
# palette: one course, one set of colours (the building palette plus bark)
# ---------------------------------------------------------------------------

BARK = mat(C("7c5232"), "bark")
BARK_DARK = mat(C("5a3a22"), "bark")
BIRCH_BARK = mat(C("e7e2d2"), "birch")
DEAD_BARK = mat(C("9a8470"), "bark")
CACTUS_SKIN = mat(C("5f8f4e"), "bark")
CACTUS_SKIN_LIGHT = mat(C("79a862"), "bark")
PALM_TRUNK = mat(C("c2a06c"), "bark")
PALM_TRUNK_DARK = mat(C("96744a"), "bark")
DEAD_FROND = mat(C("9a7a4a"), "hedge")

OAK_LEAF = mat(C("4f8f48"), "leaf")
OAK_LEAF_LIGHT = mat(C("6da85a"), "leaf")
OAK_LEAF_DARK = mat(C("35663a"), "leaf")
MAPLE_LEAF = mat(C("d9622f"), "leaf")
MAPLE_LEAF_LIGHT = mat(C("e2862f"), "leaf")
MAPLE_LEAF_DARK = mat(C("b03f28"), "leaf")
BIRCH_LEAF = mat(C("7fb050"), "leaf")
BIRCH_LEAF_LIGHT = mat(C("9cc768"), "leaf")
BIRCH_LEAF_DARK = mat(C("58883c"), "leaf")
PINE_NEEDLE = mat(C("3c6b46"), "leaf")
PINE_NEEDLE_LIGHT = mat(C("55895a"), "leaf")
PINE_NEEDLE_DARK = mat(C("2a4e36"), "leaf")
FROND = mat(C("5d9446"), "leaf")
FROND_LIGHT = mat(C("7cb45c"), "leaf")
FROND_DARK = mat(C("427038"), "leaf")
BUSH_LEAF = mat(C("4e8a42"), "leaf")
BUSH_LEAF_LIGHT = mat(C("6da857"), "leaf")
BUSH_LEAF_DARK = mat(C("35602c"), "leaf")
GRASS_BLADE = mat(C("b5c25a"), "grass")
GRASS_BLADE_LIGHT = mat(C("d0d473"), "grass")
GRASS_BLADE_DARK = mat(C("8a9745"), "grass")
DRY_BLADE = mat(C("d4c07a"), "grass")
HEATHER_LEAF = mat(C("4a6b3c"), "leaf")
HEATHER_BLOOM = mat(C("d06ab0"), "flat")
HEATHER_BLOOM_LIGHT = mat(C("e894cc"), "flat")
CATTAIL_LEAF = mat(C("7fa858"), "grass")
CATTAIL_LEAF_DARK = mat(C("5c8440"), "grass")
CATTAIL_HEAD = mat(C("8a5a30"), "thatch")
CATTAIL_HEAD_LIGHT = mat(C("a87040"), "thatch")
FLOWER_PINK = mat(C("e2658f"), "flat")
FLOWER_PINK_LIGHT = mat(C("f29ab8"), "flat")
STONE_PEBBLE = mat(C("a89c88"), "gravel")
COCONUT = mat(C("6e4a26"), "flat")

#: The four view variants a tree can wear, matching ``TreeOverlay.FACINGS``.
VARIANT_COUNT = 4


def variant_seed(species: str, variant: int) -> int:
    """A stable per-drawing seed: the same tree every time the tool runs."""
    return 0x5EED + variant * 7919 + sum(ord(c) for c in species) * 31


# ---------------------------------------------------------------------------
# organic builder
# ---------------------------------------------------------------------------

class TreeBuilder(Builder):
    """Organic primitives on top of the architectural solids."""

    def group(self) -> int:
        """A fresh crease group: quads sharing one are shaded as one surface."""
        return self.m.group()

    def limb(self, p0, p1, r0, r1, material, segments=8, group=None,
             ao0=0.82, ao1=1.0, cap=True) -> None:
        """A tapered branch between two points, thick at ``p0``, thin at ``p1``."""
        a = np.asarray(p0, dtype=float)
        b = np.asarray(p1, dtype=float)
        axis = b - a
        length = float(np.linalg.norm(axis))
        if length < 1e-6:
            return
        axis /= length
        helper = np.array([0.0, 0.0, 1.0])
        if abs(float(np.dot(axis, helper))) > 0.95:
            helper = np.array([1.0, 0.0, 0.0])
        u = np.cross(axis, helper)
        u /= np.linalg.norm(u)
        v = np.cross(axis, u)
        gid = self.m.group() if group is None else group
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            o0 = u * math.cos(a0) + v * math.sin(a0)
            o1 = u * math.cos(a1) + v * math.sin(a1)
            self.m.quad(tuple(a + o0 * r0), tuple(a + o1 * r0),
                        tuple(b + o1 * r1), tuple(b + o0 * r1), material,
                        uvs=((a0 * r0, 0.0), (a1 * r0, 0.0),
                             (a1 * r1, length), (a0 * r1, length)),
                        ao=(ao0, ao0, ao1, ao1), group=gid)
        if cap:
            for i in range(segments):
                a0 = 2 * math.pi * i / segments
                a1 = 2 * math.pi * (i + 1) / segments
                o0 = u * math.cos(a0) + v * math.sin(a0)
                o1 = u * math.cos(a1) + v * math.sin(a1)
                self.m.tri(tuple(b), tuple(b + o0 * r1), tuple(b + o1 * r1),
                           material, ao=(ao1, ao1, ao1), group=gid)

    def blob(self, cx, cy, cz, rx, ry, rz, material, ao_base=0.74,
             segments=10, rings=6, group=None) -> None:
        """A canopy clump: one shaded ellipsoid under a single crease group."""
        gid = self.m.group() if group is None else group

        def point(angle, lat):
            return (cx + rx * math.cos(lat) * math.cos(angle),
                    cy + ry * math.cos(lat) * math.sin(angle),
                    cz + rz * math.sin(lat))

        for j in range(rings):
            t0 = -math.pi / 2 + math.pi * j / rings
            t1 = -math.pi / 2 + math.pi * (j + 1) / rings
            for i in range(segments):
                a0 = 2 * math.pi * i / segments
                a1 = 2 * math.pi * (i + 1) / segments
                p00 = point(a0, t0)
                p10 = point(a1, t0)
                p11 = point(a1, t1)
                p01 = point(a0, t1)
                ao0 = ao_base + (1.0 - ao_base) * (j / rings)
                ao1 = ao_base + (1.0 - ao_base) * ((j + 1) / rings)
                if j == 0:
                    self.m.tri(p00, p11, p01, material,
                               ao=(ao0, ao1, ao1), group=gid)
                elif j == rings - 1:
                    self.m.tri(p00, p10, p01, material,
                               ao=(ao0, ao0, ao1), group=gid)
                else:
                    self.m.quad(p00, p10, p11, p01, material,
                                uvs=((a0 * rx, t0 * rz), (a1 * rx, t0 * rz),
                                     (a1 * rx, t1 * rz), (a0 * rx, t1 * rz)),
                                ao=(ao0, ao0, ao1, ao1), group=gid)

    def blade(self, x, y, z, yaw, length, width, material, rise=6.0,
              droop=8.0, width_end=None, segments=3, group=None):
        """A grass blade or leaf: a tapered ribbon rising and arching over."""
        width_end = width if width_end is None else width_end
        gid = self.m.group() if group is None else group
        dx, dy = math.cos(yaw), math.sin(yaw)
        px, py = -dy, dx
        spine = []
        for i in range(segments + 1):
            t = i / segments
            forward = length * t
            height = rise * math.sin(min(1.0, t * 1.35) * math.pi * 0.5) \
                - droop * t * t
            spine.append((x + dx * forward, y + dy * forward,
                          z + height, width * (1.0 - t) + width_end * t))
        for i in range(segments):
            x0, y0, z0, w0 = spine[i]
            x1, y1, z1, w1 = spine[i + 1]
            self.m.quad((x0 - px * w0 * 0.5, y0 - py * w0 * 0.5, z0),
                        (x0 + px * w0 * 0.5, y0 + py * w0 * 0.5, z0),
                        (x1 + px * w1 * 0.5, y1 + py * w1 * 0.5, z1),
                        (x1 - px * w1 * 0.5, y1 - py * w1 * 0.5, z1),
                        material,
                        uvs=((0.0, i * length / segments),
                             (w0, i * length / segments),
                             (w1, (i + 1) * length / segments),
                             (0.0, (i + 1) * length / segments)),
                        ao=(0.86, 0.86, 1.0, 1.0), group=gid)
        return spine[-1]

    def frond(self, x, y, z, yaw, length, material, droop=14.0, width=5.0,
              leaflets=3, group=None):
        """A palm frond: one broad arching blade, notched by a few leaflets,
        with a lighter midrib laid along its spine."""
        gid = self.m.group() if group is None else group
        dx, dy = math.cos(yaw), math.sin(yaw)
        px, py = -dy, dx
        segments = 5
        profile = (0.5, 1.0, 1.05, 0.82, 0.45, 0.08)

        def spine(t):
            return (x + dx * length * t, y + dy * length * t,
                    z + 4.5 * math.sin(min(1.0, t * 1.15) * math.pi * 0.8)
                    - droop * t * t)

        for i in range(segments):
            t0, t1 = i / segments, (i + 1) / segments
            x0, y0, z0 = spine(t0)
            x1, y1, z1 = spine(t1)
            w0, w1 = width * profile[i], width * profile[i + 1]
            self.m.quad((x0 - px * w0, y0 - py * w0, z0),
                        (x0 + px * w0, y0 + py * w0, z0),
                        (x1 + px * w1, y1 + py * w1, z1),
                        (x1 - px * w1, y1 - py * w1, z1), material,
                        uvs=((0.0, t0 * length), (w0 * 2, t0 * length),
                             (w1 * 2, t1 * length), (0.0, t1 * length)),
                        ao=(0.88, 0.88, 1.0, 1.0), group=gid)
        for i in range(segments):
            self.limb(spine(i / segments), spine((i + 1) / segments),
                      0.55 * (1.0 - i / 6.0), 0.55 * (1.0 - (i + 1) / 6.0),
                      FROND_LIGHT, segments=4, group=gid, ao0=0.92, ao1=1.0,
                      cap=False)
        for i in range(leaflets):
            t = 0.35 + 0.5 * i / max(1, leaflets - 1)
            bx, by, bz = spine(t)
            reach = width * 0.95 * (1.0 - 0.35 * t)
            for side in (1.0, -1.0):
                self.m.quad(
                    (bx, by, bz),
                    (bx + px * reach * side, by + py * reach * side,
                     bz - reach * 0.55),
                    (bx + px * reach * side + dx * 3.0,
                     by + py * reach * side + dy * 3.0,
                     bz - reach * 0.55 - 1.2),
                    (bx + dx * 3.0, by + dy * 3.0, bz - 0.6),
                    material,
                    ao=(1.0, 0.9, 0.9, 1.0), group=gid)
        return spine(1.0)

    def pebble(self, cx, cy, z, r, material) -> None:
        """A half-sunk stone at the foot of a clump."""
        self.blob(cx, cy, z + r * 0.45, r, r * 0.85, r * 0.55, material,
                  ao_base=0.8, segments=7, rings=4)

    def roots(self, x, y, z, radius, material, rng, count=4, group=None):
        """The root flare: a widened collar and toes reaching into the turf."""
        gid = self.m.group() if group is None else group
        self.limb((x, y, z - 1.5), (x, y, z + radius * 1.1),
                  radius * 1.35, radius * 0.92, material, segments=9,
                  group=gid)
        for i in range(count):
            yaw = math.tau * i / count + rng.uniform(-0.45, 0.45)
            reach = radius * rng.uniform(1.3, 1.9)
            tip = (x + math.cos(yaw) * reach,
                   y + math.sin(yaw) * reach * 0.85, z - 1.6)
            self.limb((x, y, z + radius * 0.55), tip,
                      radius * 0.5, radius * 0.14, material, segments=5,
                      group=gid)

    def gnarl(self, p0, yaw, pitch, length, r, material, depth, rng,
              group=None, wander=0.55):
        """A forking limb that wanders as it thins; returns its tips."""
        x, y, z = p0
        mid_yaw = yaw + rng.uniform(-wander, wander) * 0.5
        mid = (x + math.cos(mid_yaw) * length * 0.55,
               y + math.sin(mid_yaw) * length * 0.55 * 0.85,
               z + length * pitch * 0.62)
        end = (x + math.cos(yaw) * length,
               y + math.sin(yaw) * length * 0.85,
               z + length * pitch)
        self.limb(p0, mid, r, r * 0.78, material, segments=7, group=group)
        self.limb(mid, end, r * 0.78, r * 0.55, material, segments=6,
                  group=group)
        if depth <= 0:
            return [end]
        tips = []
        for _ in range(rng.randint(2, 3)):
            spread = rng.uniform(0.55, 1.15)
            child_yaw = yaw + rng.choice((-1.0, 1.0)) * spread
            child_pitch = pitch * rng.uniform(0.75, 1.15) + rng.uniform(0.1, 0.3)
            tips += self.gnarl(end, child_yaw, child_pitch,
                               length * rng.uniform(0.6, 0.78),
                               r * 0.55, material, depth - 1, rng,
                               group=group, wander=wander)
        return tips

    def ribbed_column(self, x, y, z0, z1, radius, skin, rib, ribs=9,
                      group=None):
        """A cactus column: a core with raised ribs running its length."""
        gid = self.m.group() if group is None else group
        self.cylinder(x, y, z0, z1, radius * 0.86, skin, segments=11,
                      cap=False, group=gid)
        for i in range(ribs):
            yaw = math.tau * i / ribs
            rx, ry = x + math.cos(yaw) * radius * 0.8, \
                y + math.sin(yaw) * radius * 0.8
            self.limb((rx, ry, z0), (rx, ry, z1), radius * 0.24,
                      radius * 0.2, rib, segments=4, group=gid, cap=False)
        self.blob(x, y, z1, radius, radius, radius * 0.8, rib,
                  ao_base=0.85, segments=9, rings=4, group=gid)


# ---------------------------------------------------------------------------
# layered foliage
# ---------------------------------------------------------------------------

def foliage_mass(builder: TreeBuilder, centre, spread, r, tones, rng,
                 ao=0.68, rim=12, height=0.34, roundness=(0.5, 0.66),
                 under=3, mains=5) -> None:
    """One crown, assembled the way a canopy catches light.

    A shadowed under-mass holds the shape, lit main clumps build a dome over
    it, and a ring of half-buried rim clumps breaks the silhouette into leaf
    clusters instead of one smooth ball.  ``tones`` is ``(shadow, mid, light)``;
    clumps nearer the sun take the lighter tone, so the crown shades itself.
    """
    shadow, mid, light = tones
    cx, cy, cz = centre

    def clump(x, y, z, rr, material, flat=1.0, seg=9, rings=5):
        builder.blob(x + rng.uniform(-1.4, 1.4), y + rng.uniform(-1.4, 1.4),
                     z + rng.uniform(-1.1, 1.1),
                     rr * rng.uniform(0.94, 1.1),
                     rr * rng.uniform(0.9, 1.05),
                     rr * rng.uniform(*roundness) * flat, material,
                     ao_base=ao, segments=seg, rings=rings)

    for _ in range(under):
        yaw = rng.uniform(0, math.tau)
        dist = spread * rng.uniform(0.15, 0.5)
        clump(cx + math.cos(yaw) * dist, cy + math.sin(yaw) * dist * 0.85,
              cz - r * rng.uniform(0.32, 0.48), r * rng.uniform(0.9, 1.05),
              shadow)
    for _ in range(mains):
        yaw = rng.uniform(0, math.tau)
        dist = spread * rng.uniform(0.1, 0.72)
        z = cz + rng.uniform(-0.15, height) * r
        clump(cx + math.cos(yaw) * dist, cy + math.sin(yaw) * dist * 0.85, z,
              r * rng.uniform(0.6, 0.82),
              light if z > cz + 0.15 * r else mid)
    clump(cx + rng.uniform(-2.0, 2.0), cy + rng.uniform(-2.0, 2.0),
          cz + r * (height + 0.12), r * rng.uniform(0.6, 0.75),
          light, flat=0.8)
    for _ in range(rim):
        yaw = rng.uniform(0, math.tau)
        dist = spread * rng.uniform(0.7, 0.95)
        z = cz + rng.uniform(-1.3, 1.3) * height * r
        tone = light if z > cz + 0.18 * r else (
            shadow if z < cz - 0.2 * r else mid)
        clump(cx + math.cos(yaw) * dist, cy + math.sin(yaw) * dist * 0.85, z,
              r * rng.uniform(0.4, 0.55), tone, flat=0.62, seg=7, rings=4)


# ---------------------------------------------------------------------------
# species models
# ---------------------------------------------------------------------------

def draw_oak(builder: TreeBuilder, rng) -> None:
    """A broadleaf oak: root-flared trunk, gnarled limbs, one wide crown."""
    trunk = builder.group()
    lean = rng.uniform(-2.5, 2.5)
    builder.roots(32, 16, 0.0, 5.6, BARK, rng, group=trunk)
    fork = (32 + lean, 16, rng.uniform(21.0, 25.0))
    builder.limb((32, 16, 2.0), fork, 5.8, 4.2, BARK, segments=9, group=trunk)
    for i in range(3):
        yaw = math.tau * i / 3 + rng.uniform(-0.5, 0.5)
        builder.gnarl(fork, yaw, rng.uniform(0.55, 0.85), rng.uniform(11.0, 15.0),
                      3.4, BARK, 1, rng)
    foliage_mass(builder, (32 + lean * 1.2, 16, 45.0), 28.0, 17.0,
                 (OAK_LEAF_DARK, OAK_LEAF, OAK_LEAF_LIGHT), rng,
                 rim=15, height=0.32)


def draw_maple(builder: TreeBuilder, rng) -> None:
    """A maple: slimmer upright trunk under a rounded ember crown."""
    trunk = builder.group()
    lean = rng.uniform(-1.5, 1.5)
    builder.roots(32, 16, 0.0, 4.2, BARK_DARK, rng, count=3, group=trunk)
    fork = (32 + lean, 16, rng.uniform(23.0, 27.0))
    builder.limb((32, 16, 2.0), fork, 4.4, 3.1, BARK_DARK, segments=9,
                 group=trunk)
    for i in range(3):
        yaw = math.tau * i / 3 + rng.uniform(-0.5, 0.5)
        builder.gnarl(fork, yaw, rng.uniform(0.6, 0.9), rng.uniform(9.0, 12.0),
                      2.6, BARK_DARK, 1, rng)
    foliage_mass(builder, (32 + lean * 1.2, 16, 42.0), 22.0, 15.5,
                 (MAPLE_LEAF_DARK, MAPLE_LEAF, MAPLE_LEAF_LIGHT), rng,
                 rim=14, height=0.32)


def draw_birch(builder: TreeBuilder, rng) -> None:
    """A birch: white paper bark flecked with lenticels, an airy crown."""
    trunk = builder.group()
    lean = rng.uniform(-3.0, 3.0)
    builder.roots(32, 16, 0.0, 3.2, BIRCH_BARK, rng, count=3, group=trunk)
    fork = (32 + lean, 16, rng.uniform(36.0, 40.0))
    builder.limb((32, 16, 1.0), fork, 3.4, 2.3, BIRCH_BARK, segments=8,
                 group=trunk)
    for i in range(2):
        yaw = math.tau * i / 2 + rng.uniform(-0.6, 0.6)
        builder.gnarl(fork, yaw, rng.uniform(0.7, 1.0), rng.uniform(7.0, 10.0),
                      1.9, BIRCH_BARK, 1, rng, wander=0.4)
    foliage_mass(builder, (32 + lean * 1.2, 16, 53.0), 21.0, 13.5,
                 (BIRCH_LEAF_DARK, BIRCH_LEAF, BIRCH_LEAF_LIGHT), rng,
                 rim=16, height=0.38, roundness=(0.45, 0.6), ao=0.72)


def draw_pine(builder: TreeBuilder, rng) -> None:
    """A conifer: one straight bole under tiers of drooping needle pads."""
    trunk = builder.group()
    builder.roots(32, 16, 0.0, 4.0, BARK_DARK, rng, count=3, group=trunk)
    builder.limb((32, 16, 1.0), (32, 16, 60), 4.2, 1.2, BARK_DARK,
                 segments=8, group=trunk, cap=False)
    tiers = 4
    base_z = 12.0
    for i in range(tiers):
        t = i / (tiers - 1.0)
        radius = 22.0 * (1.0 - 0.62 * t) * rng.uniform(0.94, 1.06)
        z0 = base_z + i * 12.5
        tone = (PINE_NEEDLE, PINE_NEEDLE_LIGHT, PINE_NEEDLE_DARK)[i % 3]
        builder.cone(32, 16, z0, z0 + 18.0, radius, tone, segments=10,
                     group=builder.group())
        for j in range(rng.randint(5, 7)):
            yaw = math.tau * j / 6 + rng.uniform(-0.3, 0.3)
            dist = radius * rng.uniform(0.68, 0.85)
            pad_tone = tone if rng.random() < 0.55 else (
                PINE_NEEDLE_DARK if tone is not PINE_NEEDLE_DARK
                else PINE_NEEDLE)
            builder.blob(32 + math.cos(yaw) * dist,
                         16 + math.sin(yaw) * dist,
                         z0 + rng.uniform(0.2, 1.6),
                         radius * rng.uniform(0.3, 0.42),
                         radius * rng.uniform(0.3, 0.42),
                         radius * rng.uniform(0.09, 0.15), pad_tone,
                         ao_base=0.82, segments=7, rings=3)
    builder.blob(32, 16, base_z + tiers * 12.5 + 1.5, 3.4, 3.4, 4.6,
                 PINE_NEEDLE_LIGHT, ao_base=0.85, segments=7, rings=4)
    for i in range(3):
        yaw = rng.uniform(0, math.tau)
        builder.limb((32, 16, 2.0),
                     (32 + math.cos(yaw) * 6.5, 16 + math.sin(yaw) * 6.5, -0.5),
                     2.4, 1.1, BARK_DARK, segments=5)


def draw_palm(builder: TreeBuilder, rng) -> None:
    """A coconut palm: a ringed leaning trunk under a crown of fronds."""
    trunk = builder.group()
    lean = rng.uniform(-5.0, 5.0)
    segments = 6
    rings = []
    for i in range(segments + 1):
        t = i / segments
        rings.append((32 + lean * t * t, 16 + lean * 0.4 * t * t,
                      -1 + 46.0 * t))
    builder.roots(32, 16, 0.0, 3.8, PALM_TRUNK_DARK, rng, count=3, group=trunk)
    for i in range(segments):
        material = PALM_TRUNK if i % 2 == 0 else PALM_TRUNK_DARK
        builder.limb(rings[i], rings[i + 1], 4.6 * (1.0 - i * 0.07),
                     4.6 * (1.0 - (i + 1) * 0.07), material, segments=8,
                     group=trunk)
        joint = rings[i + 1]
        builder.limb((joint[0], joint[1], joint[2] - 1.1),
                     (joint[0], joint[1], joint[2] + 1.1),
                     5.0 * (1.0 - (i + 1) * 0.07), 5.0 * (1.0 - (i + 1) * 0.07),
                     PALM_TRUNK_DARK, segments=8, group=trunk)
    top = rings[-1]
    fronds = 9
    yaw0 = rng.uniform(0, math.tau)
    for i in range(fronds):
        yaw = yaw0 + math.tau * i / fronds + rng.uniform(-0.18, 0.18)
        builder.frond(top[0], top[1], top[2] + 1.0, yaw,
                      rng.uniform(23.0, 28.0),
                      (FROND, FROND_LIGHT, FROND_DARK)[i % 3],
                      droop=rng.uniform(13.0, 18.0), width=6.2,
                      leaflets=0)
    # One spent frond hangs brown against the trunk, as palms wear them.
    builder.frond(top[0], top[1], top[2] - 1.0, yaw0 + math.pi * 0.6, 16.0,
                  DEAD_FROND, droop=26.0, width=3.8, leaflets=0)
    for i in range(4):
        yaw = rng.uniform(0, math.tau)
        builder.blob(top[0] + math.cos(yaw) * 2.8,
                     top[1] + math.sin(yaw) * 2.8, top[2] - 2.5,
                     2.3, 2.3, 2.3, COCONUT, ao_base=0.85, segments=6,
                     rings=4)


def draw_dead_tree(builder: TreeBuilder, rng) -> None:
    """A dead tree: bare forking limbs, a broken stub, no leaf at all."""
    trunk = builder.group()
    lean = rng.uniform(-2.5, 2.5)
    builder.roots(32, 16, 0.0, 5.2, DEAD_BARK, rng, group=trunk)
    fork = (32 + lean, 16, rng.uniform(14.0, 18.0))
    builder.limb((32, 16, 1.0), fork, 6.2, 4.6, DEAD_BARK, segments=8,
                 group=trunk)
    for i in range(3):
        yaw = math.tau * i / 3 + rng.uniform(-0.6, 0.6)
        tips = builder.gnarl(fork, yaw, rng.uniform(0.75, 1.05),
                             rng.uniform(13.0, 17.0), 3.8, DEAD_BARK, 1, rng,
                             wander=0.8)
        for tip in tips:
            twig_yaw = yaw + rng.uniform(-1.1, 1.1)
            builder.limb(tip, (tip[0] + math.cos(twig_yaw) * 6.0,
                               tip[1] + math.sin(twig_yaw) * 6.0,
                               tip[2] + rng.uniform(2.0, 6.0)),
                         1.1, 0.35, DEAD_BARK, segments=5)
    stub = (fork[0] + rng.uniform(-3.0, 3.0), fork[1] + rng.uniform(-3.0, 3.0),
            fork[2] + 7.0)
    builder.limb(fork, stub, 3.4, 2.7, DEAD_BARK, segments=6)
    builder.blob(fork[0], fork[1], fork[2] + 1.0, 3.2, 3.2, 2.4, DEAD_BARK,
                 ao_base=0.85, segments=6, rings=3)


def draw_cactus(builder: TreeBuilder, rng) -> None:
    """A saguaro: a ribbed column, raised arms, a pink crown flower."""
    trunk = builder.group()
    builder.ribbed_column(32, 16, -1.0, 42.0, 6.4, CACTUS_SKIN,
                          CACTUS_SKIN_LIGHT, ribs=10, group=trunk)
    arm_count = rng.randint(2, 3)
    for arm_index in range(arm_count):
        height = rng.uniform(13.0, 27.0)
        yaw = math.tau * arm_index / arm_count + rng.uniform(-0.4, 0.4)
        reach = rng.uniform(9.0, 12.5)
        elbow = (32 + math.cos(yaw) * reach, 16 + math.sin(yaw) * reach, height)
        up = rng.uniform(13.0, 19.0)
        tip = (elbow[0] + math.cos(yaw) * 1.8, elbow[1] + math.sin(yaw) * 1.8,
               height + up)
        arm = builder.group()
        builder.limb((32, 16, height), elbow, 4.0, 3.5, CACTUS_SKIN,
                     segments=8, group=arm, cap=False)
        builder.limb(elbow, tip, 3.5, 3.0, CACTUS_SKIN, segments=8,
                     group=arm, cap=False)
        builder.ribbed_column(tip[0], tip[1], tip[2] - 2.0, tip[2] + 1.5, 3.3,
                              CACTUS_SKIN, CACTUS_SKIN_LIGHT, ribs=6,
                              group=arm)
    builder.blob(32, 16, 47.0, 2.6, 2.6, 2.2, FLOWER_PINK, ao_base=0.9,
                 segments=6, rings=3)
    for i in range(5):
        yaw = math.tau * i / 5 + rng.uniform(-0.15, 0.15)
        builder.blob(32 + math.cos(yaw) * 2.8, 16 + math.sin(yaw) * 2.8,
                     47.6, 1.7, 1.7, 1.3, FLOWER_PINK_LIGHT, ao_base=0.9,
                     segments=5, rings=3)
    builder.blob(32 + rng.uniform(-2.0, 2.0), 16 + rng.uniform(-2.0, 2.0),
                 rng.uniform(27.0, 34.0), 1.9, 1.9, 1.5, FLOWER_PINK,
                 ao_base=0.9, segments=5, rings=3)


def draw_bush(builder: TreeBuilder, rng) -> None:
    """A low mound of leaves with a hint of twig and new light tips."""
    twig = builder.group()
    builder.roots(32, 16, 0.0, 2.4, BARK_DARK, rng, count=3, group=twig)
    for i in range(3):
        yaw = rng.uniform(0, math.tau)
        reach = rng.uniform(3.0, 7.0)
        builder.limb((32, 16, 0.5),
                     (32 + math.cos(yaw) * reach, 16 + math.sin(yaw) * reach,
                      rng.uniform(6.0, 10.0)),
                     1.8, 0.9, BARK_DARK, segments=5)
    foliage_mass(builder, (32, 16, 11.5), 9.0, 8.8,
                 (BUSH_LEAF_DARK, BUSH_LEAF, BUSH_LEAF_LIGHT), rng,
                 rim=10, height=0.34, roundness=(0.7, 0.92), under=2, mains=4)
    for i in range(3):
        yaw = rng.uniform(0, math.tau)
        builder.blob(32 + math.cos(yaw) * rng.uniform(2.0, 7.0),
                     16 + math.sin(yaw) * rng.uniform(2.0, 6.0),
                     rng.uniform(15.0, 18.5), 2.2, 2.2, 1.7,
                     BUSH_LEAF_LIGHT, ao_base=0.9, segments=5, rings=3)


def draw_fescue(builder: TreeBuilder, rng) -> None:
    """A fescue tussock: arching blades and a few seed stalks gone to hay."""
    for i in range(34):
        yaw = math.tau * i / 34 + rng.uniform(-0.22, 0.22)
        reach = rng.uniform(1.0, 4.5)
        material = (GRASS_BLADE, GRASS_BLADE_LIGHT, GRASS_BLADE_DARK,
                    DRY_BLADE)[i % 4 if rng.random() < 0.82 else 3]
        builder.blade(32 + math.cos(yaw) * reach,
                      16 + math.sin(yaw) * reach * 0.85,
                      rng.uniform(-0.5, 1.5), yaw,
                      rng.uniform(12.0, 17.0), rng.uniform(1.8, 2.7),
                      material, rise=rng.uniform(14.0, 19.0),
                      droop=rng.uniform(3.0, 6.5), width_end=0.25,
                      segments=3)
    for i in range(rng.randint(4, 6)):
        yaw = rng.uniform(0, math.tau)
        lean = rng.uniform(0.0, 0.35)
        stalk = (32 + math.cos(yaw) * rng.uniform(1.0, 3.5),
                 16 + math.sin(yaw) * rng.uniform(1.0, 3.0), 0.0)
        top = (stalk[0] + math.cos(yaw) * 6.0 * lean,
               stalk[1] + math.sin(yaw) * 6.0 * lean,
               rng.uniform(22.0, 31.0))
        builder.limb(stalk, top, 0.55, 0.35, GRASS_BLADE_DARK, segments=5)
        for k in range(3):
            t = 0.25 + k * 0.3
            builder.blob(top[0] * t + stalk[0] * (1 - t) + rng.uniform(-0.7, 0.7),
                         top[1] * t + stalk[1] * (1 - t) + rng.uniform(-0.7, 0.7),
                         top[2] * t + stalk[2] * (1 - t) + rng.uniform(-0.5, 0.5),
                         1.3, 1.3, 2.6, DRY_BLADE, ao_base=0.92,
                         segments=5, rings=3)


def draw_heather(builder: TreeBuilder, rng) -> None:
    """A heather sprig: fine dark foliage smothered in purple bloom."""
    foliage_mass(builder, (32, 16, 6.5), 7.5, 5.6,
                 (HEATHER_LEAF, HEATHER_LEAF, HEATHER_LEAF), rng,
                 rim=8, height=0.4, roundness=(0.7, 0.95), under=2, mains=3)
    for i in range(26):
        yaw = rng.uniform(0, math.tau)
        spread = rng.uniform(1.5, 11.5)
        builder.blob(32 + math.cos(yaw) * spread,
                     16 + math.sin(yaw) * spread * 0.85,
                     rng.uniform(7.0, 14.0), rng.uniform(1.2, 2.1),
                     rng.uniform(1.2, 2.1), rng.uniform(1.0, 1.7),
                     HEATHER_BLOOM_LIGHT if i % 3 == 0 else HEATHER_BLOOM,
                     ao_base=0.92, segments=5, rings=3)


def draw_cattails(builder: TreeBuilder, rng) -> None:
    """A cattail clump: blade leaves, velvet heads and a few wet stones."""
    for i in range(18):
        yaw = math.tau * i / 18 + rng.uniform(-0.25, 0.25)
        reach = rng.uniform(1.0, 3.5)
        builder.blade(32 + math.cos(yaw) * reach,
                      16 + math.sin(yaw) * reach * 0.85,
                      0.0, yaw, rng.uniform(12.0, 19.0),
                      rng.uniform(1.9, 2.8),
                      CATTAIL_LEAF if i % 3 else CATTAIL_LEAF_DARK,
                      rise=rng.uniform(14.0, 21.0), droop=rng.uniform(3.0, 7.0),
                      width_end=0.3, segments=3)
    for i in range(5):
        yaw = math.tau * i / 5 + rng.uniform(-0.5, 0.5)
        reach = rng.uniform(1.0, 4.5)
        x, y = 32 + math.cos(yaw) * reach, 16 + math.sin(yaw) * reach * 0.85
        top = rng.uniform(31.0, 41.0)
        head = 8.5
        builder.limb((x, y, 0.0), (x + rng.uniform(-1.2, 1.2),
                                   y + rng.uniform(-1.2, 1.2), top),
                     1.1, 0.75, CATTAIL_LEAF_DARK, segments=5)
        builder.cylinder(x, y, top - head, top, 1.8, CATTAIL_HEAD,
                         segments=7, cap=True, ao_base=0.9)
        builder.blob(x, y, top, 1.8, 1.8, 1.3, CATTAIL_HEAD_LIGHT,
                     ao_base=0.92, segments=5, rings=3)
        builder.limb((x, y, top + 1.0), (x + rng.uniform(-0.8, 0.8),
                                         y + rng.uniform(-0.8, 0.8), top + 5.5),
                     0.5, 0.18, CATTAIL_HEAD_LIGHT, segments=4)
    for i in range(3):
        yaw = rng.uniform(0, math.tau)
        builder.pebble(32 + math.cos(yaw) * rng.uniform(5.0, 9.0),
                       16 + math.sin(yaw) * rng.uniform(4.0, 7.0), 0.0,
                       rng.uniform(2.0, 3.2), STONE_PEBBLE)


# ---------------------------------------------------------------------------
# the catalogue: one draw function per species
# ---------------------------------------------------------------------------

#: ``scale`` is what ``layout.json`` hands the game: 1.0 when the art is baked
#: at one art pixel per world pixel (the building art's density), so a model's
#: world size is the tree's size on the course.  ``--scale`` at the generator
#: raises the texture density and writes ``1 / scale`` here instead.
TREES = {
    "oak": {"draw": draw_oak},
    "maple": {"draw": draw_maple},
    "birch": {"draw": draw_birch},
    "pine": {"draw": draw_pine},
    "palm": {"draw": draw_palm},
    "dead_tree": {"draw": draw_dead_tree},
    "cactus": {"draw": draw_cactus},
    "bush": {"draw": draw_bush},
    "fescue": {"draw": draw_fescue},
    "heather": {"draw": draw_heather},
    "cattails": {"draw": draw_cattails},
}
