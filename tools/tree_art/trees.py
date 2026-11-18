#!/usr/bin/env python3
"""3D models for every tree species that grows on the course.

Art direction
-------------
The trees are painted as sunlit storybook woodland that belongs beside the
cream-and-terracotta clubhouses: chunky pixel silhouettes, ink outlines, one
warm afternoon sun from the upper right, and foliage built from leaf-scale
clusters rather than smooth balls.  Every species obeys the same rules:

* **Silhouette before surface.**  A species is recognisable as a solid black
  shape at one pixel per world pixel - the oak's broad goblet, the pine's
  scalloped spire, the birch's airy clump, the palm's wheel of notched
  fronds, the dead tree's splintered crown.
* **One light.**  The renderer's sun (``render.SUN``, +x / -y / up) is the only
  light.  Foliage is chosen in four tones - deep shadow, mass, lit face and a
  warm sun rim - by where a cluster sits on the crown, so the canopy shades
  itself consistently in every species.
* **Leaf-scale detail.**  Crowns are clouds of small clusters (2-7 world px),
  each dappled with the ``leaf_fine`` surface pattern; a scalloped ring of
  little leaf tufts breaks every silhouette.  The cluster, not the species,
  sets the detail scale, so a 24 px heather cushion and a 70 px oak carry the
  same visual grain.
* **Wood shows.**  A root-flared, tapered trunk and real forking limbs carry the
  canopy.  Bark is bark, not a brown post: the ``bark`` pattern cuts
  vertical ridges into a warm lit side and a shadowed lee, and buttress roots
  spread the load into the turf.
* **Four drawings, one tree.**  The four view variants are independent seeded
  drawings of the species (``variant_seed()``), not rotations: a wood wears
  several different trees at once and they share one sun.

Species notes
-------------
Silhouettes are species-specific rather than one cloud on a stick.  Oaks fork
into three shoulders; maples keep two low boughs visible under a broad ember
crown; birches are a clump of paper trunks; pines stack needle boughs with
drooping tips; palms carry a curved, ringed trunk, a green crownshaft, coconuts
and ranks of solid, notched fronds; dead trees grow hair-fine second-generation
twigs around a hollow; cacti are a ribbed, domed column with curved arms;
shrubs are thin woody stems with separate leaf clouds; fescue, heather and
cattails are ground-layer plants with their own bloom or seed heads.

Model space
-----------
A species is a real 3D model in world-pixel space - ``x`` across the tile
(a tile is 64 wide), ``y`` down it (32 deep) and ``z`` up - standing on the
centre of a 1x1 footprint at ``(32, 16, 0)``.  The shared ``Builder`` from
``tools/building_art`` supplies the architectural solids; ``TreeBuilder`` adds
the organic kit: tapered limbs, oriented leaf clusters, palm fronds, bloom
sprays, grass blades and pebbles.

``tools/tree_art/generate.py`` projects each model through the game's 2:1
isometric axes and bakes one pixel sprite per view variant, exactly like the
building art.  One model pixel is one world pixel: a mature oak crown is about
68 px wide, a grass tuft 44 px, matching the draw sizes the layout scales were
tuned for.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

from render import C, mat  # noqa: E402  (path set up above)
from buildings import Builder  # noqa: E402


# ---------------------------------------------------------------------------
# palette: one course, one set of colours
# ---------------------------------------------------------------------------

# Wood.  Bark is warm and readable in shadow; the root flare and lit side use
# the lighter tones so a trunk never becomes a silhouette itself.
BARK = mat(C("7b5334"), "bark")
BARK_DARK = mat(C("54351d"), "bark")
BARK_LIGHT = mat(C("a2744a"), "bark")
BARK_WARM = mat(C("b98a58"), "bark")
MAPLE_BARK = mat(C("6c4b36"), "bark")
MAPLE_BARK_DARK = mat(C("4c3324"), "bark")
MAPLE_BARK_LIGHT = mat(C("8d674a"), "bark")
BIRCH_BARK = mat(C("fffdf2"), "birch", emissive=0.30)
BIRCH_BARK_SHADE = mat(C("cfcdb8"), "birch", emissive=0.16)
DEAD_BARK = mat(C("a08f7c"), "bark", emissive=0.06)
DEAD_BARK_DARK = mat(C("7d6f5e"), "bark", emissive=0.05)
DEAD_BARK_LIGHT = mat(C("c6b49a"), "bark")
PALM_BARK = mat(C("b18e5f"), "bark")
PALM_BARK_DARK = mat(C("86653d"), "bark")
PALM_BARK_LIGHT = mat(C("d2b181"), "bark")
CACTUS_SKIN = mat(C("4d7f4e"), "bark")
CACTUS_SKIN_DARK = mat(C("2f5a3a"), "bark")
CACTUS_SKIN_LIGHT = mat(C("6fa25f"), "bark")

# Foliage: (deep shadow, mass, lit face, warm sun rim).  The rim is the tone
# that touches the sky on the sun side; it is what makes a wood glow.
OAK_LEAF_DARK = mat(C("2c5030"), "leaf_fine")
OAK_LEAF = mat(C("3d7038"), "leaf_fine")
OAK_LEAF_LIGHT = mat(C("58943f"), "leaf_fine")
OAK_LEAF_SUN = mat(C("8bc25d"), "leaf_fine")

MAPLE_LEAF_DARK = mat(C("74281d"), "leaf_fine")
MAPLE_LEAF = mat(C("a83a24"), "leaf_fine")
MAPLE_LEAF_LIGHT = mat(C("d2662b"), "leaf_fine")
MAPLE_LEAF_SUN = mat(C("e39a48"), "leaf_fine")

BIRCH_LEAF_DARK = mat(C("466d35"), "leaf_fine")
BIRCH_LEAF = mat(C("63954a"), "leaf_fine")
BIRCH_LEAF_LIGHT = mat(C("88bb5d"), "leaf_fine")
BIRCH_LEAF_SUN = mat(C("a6d07a"), "leaf_fine")

PINE_NEEDLE_DARK = mat(C("2b5238"), "needle", emissive=0.07)
PINE_NEEDLE = mat(C("3f7850"), "needle", emissive=0.07)
PINE_NEEDLE_LIGHT = mat(C("5a9463"), "needle", emissive=0.07)
PINE_NEEDLE_SUN = mat(C("88b47b"), "needle", emissive=0.09)
PINE_BARK = mat(C("3b3d31"), "bark")
PINE_BARK_DARK = mat(C("282a22"), "bark")

PALM_FROND_DARK = mat(C("477a41"), "leaf_fine", emissive=0.13)
PALM_FROND = mat(C("4f8a46"), "leaf_fine", emissive=0.10)
PALM_FROND_LIGHT = mat(C("70a854"), "leaf_fine", emissive=0.10)
PALM_FROND_SUN = mat(C("9aca70"), "leaf_fine", emissive=0.10)
DEAD_FROND = mat(C("8f6f3f"), "reed")
DEAD_FROND_DARK = mat(C("6f5230"), "reed")

BUSH_LEAF_DARK = mat(C("2c5230"), "leaf_fine")
BUSH_LEAF = mat(C("3e763d"), "leaf_fine")
BUSH_LEAF_LIGHT = mat(C("5c9c4c"), "leaf_fine")
BUSH_LEAF_SUN = mat(C("8ec36c"), "leaf_fine")
BUSH_BERRY = mat(C("b34a58"), "flat")
BUSH_BERRY_LIGHT = mat(C("d8737c"), "flat")

GRASS_DARK = mat(C("56774a"), "reed", emissive=0.12)
GRASS = mat(C("7a9c58"), "reed", emissive=0.12)
GRASS_LIGHT = mat(C("9dbb6c"), "reed", emissive=0.12)
GRASS_SUN = mat(C("c5d98a"), "reed", emissive=0.14)
STRAW = mat(C("c9b56f"), "reed", emissive=0.06)
STRAW_LIGHT = mat(C("e2d493"), "reed", emissive=0.06)

HEATHER_LEAF_DARK = mat(C("34472f"), "leaf_fine")
HEATHER_LEAF = mat(C("4c6439"), "leaf_fine")
HEATHER_LEAF_LIGHT = mat(C("647d48"), "leaf_fine")
HEATHER_BLOOM_DARK = mat(C("783770"), "bloom")
HEATHER_BLOOM = mat(C("a64f91"), "bloom")
HEATHER_BLOOM_LIGHT = mat(C("c96eae"), "bloom")
HEATHER_BLOOM_SUN = mat(C("e79bc8"), "bloom")

CATTAIL_LEAF_DARK = mat(C("3f6a3a"), "reed", emissive=0.07)
CATTAIL_LEAF = mat(C("55864a"), "reed", emissive=0.07)
CATTAIL_LEAF_LIGHT = mat(C("6f9f55"), "reed", emissive=0.07)
CATTAIL_LEAF_SUN = mat(C("8fbd6e"), "reed", emissive=0.07)
CATTAIL_HEAD_DARK = mat(C("5a3a1d"), "reed", emissive=0.04)
CATTAIL_HEAD = mat(C("7d5228"), "reed", emissive=0.04)
CATTAIL_HEAD_LIGHT = mat(C("a06d36"), "reed", emissive=0.04)

FLOWER_PINK = mat(C("d95f8c"), "bloom")
FLOWER_PINK_LIGHT = mat(C("f095b5"), "bloom")
CACTUS_SPINE = mat(C("f0e8c0"), "flat")
STONE_PEBBLE = mat(C("a89c88"), "gravel")
STONE_PEBBLE_DARK = mat(C("8b8070"), "gravel")
COCONUT = mat(C("6e4a26"), "flat")
COCONUT_LIGHT = mat(C("94683a"), "flat")

#: The four view variants a tree can wear, matching ``TreeOverlay.FACINGS``.
VARIANT_COUNT = 4


def variant_seed(species: str, variant: int) -> int:
    """A stable per-drawing seed: the same tree every time the tool runs."""
    return 0x5EED + variant * 7919 + sum(ord(c) for c in species) * 31


# ---------------------------------------------------------------------------
# light
# ---------------------------------------------------------------------------

#: The renderer's sun, in model space.  Foliage tones are chosen against this
#: direction so every species is lit from the same corner of the sky.
SUN_DIR = (0.60, -0.36, 0.72)


def exposure(dx: float, dy: float, dz: float) -> float:
    """How squarely a crown direction faces the sun: about -0.75 .. 1.0."""
    sx, sy, sz = SUN_DIR
    return 0.62 * (dx * sx + dy * sy + dz * sz) + 0.30 * dz + 0.06


def tone_for(tones, dx: float, dy: float, dz: float, rng, bias: float = 0.0,
             jitter: float = 0.07):
    """Pick one of ``(shadow, mass, lit, sun)`` for a sun-facing direction."""
    e = exposure(dx, dy, dz) + bias + rng.uniform(-jitter, jitter)
    if e > 0.72:
        return tones[3]
    if e > 0.34:
        return tones[2]
    if e > -0.10:
        return tones[1]
    return tones[0]


def _mix(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------------------
# organic builder
# ---------------------------------------------------------------------------

class TreeBuilder(Builder):
    """Organic primitives on top of the architectural solids."""

    # Which of the four seeded drawings this builder is making.  generate.py
    # sets it before drawing, so a species can vary its stance per variant
    # without widening every draw function's signature.
    variant = 0

    def group(self) -> int:
        """A fresh crease group: quads sharing one are shaded as one surface."""
        return self.m.group()

    # -- wood -------------------------------------------------------------
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

    def taper_path(self, points, r0, r1, material, group=None, segments=8,
                   ao0=0.8, ao1=1.0) -> None:
        """A curved trunk or limb through ``points``, tapering root to tip."""
        count = len(points) - 1
        for i in range(count):
            t0, t1 = i / count, (i + 1) / count
            self.limb(points[i], points[i + 1],
                      _mix(r0, r1, t0), _mix(r0, r1, t1), material,
                      segments=segments, group=group,
                      ao0=_mix(ao0, ao1, t0), ao1=_mix(ao0, ao1, t1))

    # -- foliage ----------------------------------------------------------
    def blob(self, cx, cy, cz, rx, ry, rz, material, ao_base=0.72,
             segments=9, rings=5, group=None, yaw=0.0, tilt=0.0,
             wobble=0.0, phase=0.0) -> None:
        """A leaf cluster: a shaded ellipsoid, optionally turned in space.

        ``yaw`` turns the long (x) axis to a compass direction and ``tilt``
        lifts its far end, which is how leaf pads lie along a pine bough or a
        palm frond.  ``wobble`` gives the rim an organic, uneven edge so a
        clump never reads as a marble.
        """
        gid = self.m.group() if group is None else group
        ct, st = math.cos(tilt), math.sin(tilt)
        cy_, sy_ = math.cos(yaw), math.sin(yaw)

        def point(angle, lat):
            x = rx * math.cos(lat) * math.cos(angle)
            y = ry * math.cos(lat) * math.sin(angle)
            z = rz * math.sin(lat)
            if wobble:
                k = 1.0 + wobble * math.sin(angle * 3.0 + phase) \
                    * math.cos(lat * 1.7 + phase * 0.6)
                x *= k
                y *= k
                z *= 1.0 + wobble * 0.6 * math.sin(angle * 2.0 + phase)
            x, z = x * ct + z * st, -x * st + z * ct
            return (cx + x * cy_ - y * sy_,
                    cy + x * sy_ + y * cy_,
                    cz + z)

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
              droop=8.0, width_end=None, segments=3, group=None,
              phase=0.0, cross=False):
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
            width_here = width * (1.0 - t) + width_end * t
            if phase:
                forward += math.sin(t * 4.0 + phase) * 0.6
            spine.append((x + dx * forward, y + dy * forward,
                          z + height, width_here))
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
        if cross:
            # A second vane standing on edge: grass blades are thin planes,
            # and one plane can vanish when it turns edge-on to the camera.
            # Crossing two keeps every blade visible in every view.
            for i in range(segments):
                x0, y0, z0, w0 = spine[i]
                x1, y1, z1, w1 = spine[i + 1]
                h0, h1 = w0 * 0.34, w1 * 0.34
                self.m.quad((x0, y0, z0 - h0), (x0, y0, z0 + h0),
                            (x1, y1, z1 + h1), (x1, y1, z1 - h1),
                            material,
                            uvs=((0.0, i * length / segments),
                                 (w0, i * length / segments),
                                 (w1, (i + 1) * length / segments),
                                 (0.0, (i + 1) * length / segments)),
                            ao=(0.78, 0.84, 1.0, 0.96), group=gid)
        return spine[-1]

    def leaf_tuft(self, x, y, z, material, rng, size=2.2, spread=1.4,
                  group=None, count=3) -> None:
        """A handful of little leaves breaking a canopy's rim."""
        gid = self.m.group() if group is None else group
        for _ in range(count):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(0.2, 1.0) * spread
            rr = size * rng.uniform(0.65, 1.0)
            self.blob(x + math.cos(a) * d, y + math.sin(a) * d * 0.8,
                      z + rng.uniform(-0.5, 0.7) * size,
                      rr, rr * rng.uniform(0.8, 1.0),
                      rr * rng.uniform(0.55, 0.8), material,
                      ao_base=0.8, segments=6, rings=4, group=gid,
                      wobble=0.18, phase=a * 2.0)

    def pebble(self, cx, cy, z, r, material) -> None:
        """A half-sunk stone at the foot of a clump."""
        self.blob(cx, cy, z + r * 0.42, r, r * 0.82, r * 0.55, material,
                  ao_base=0.78, segments=7, rings=4, wobble=0.12,
                  phase=cx * 0.7)

    # -- roots and branches ----------------------------------------------
    def roots(self, x, y, z, radius, material, rng, count=4, group=None,
              dark=None, spread=1.0) -> None:
        """The root flare: a buttressed collar and toes that grip the turf.

        Each toe leaves the trunk high, bows outward and dives into the ground,
        so the flare reads as roots prising the soil apart rather than as a
        wider cylinder.  Alternating tones break the ring into separate roots.
        """
        gid = self.m.group() if group is None else group
        dark = material if dark is None else dark
        self.limb((x, y, z - 1.8), (x, y, z + radius * 1.18),
                  radius * 1.26, radius * 0.95, material, segments=10,
                  group=gid, ao0=0.72, ao1=0.98)
        for i in range(count):
            yaw = math.tau * i / count + rng.uniform(-0.26, 0.26)
            reach = radius * rng.uniform(2.0, 2.8) * spread
            sx, sy = math.cos(yaw), math.sin(yaw) * 0.86
            base = (x + sx * radius * 0.55, y + sy * radius * 0.55,
                    z + radius * 0.95)
            mid = (x + sx * reach * 0.58, y + sy * reach * 0.58,
                   z + radius * 0.52)
            tip = (x + sx * reach, y + sy * reach, z - 1.3)
            self.limb(base, mid, radius * 0.62, radius * 0.42,
                      material if i % 2 else dark, segments=6, group=gid,
                      ao0=0.86, ao1=0.99)
            self.limb(mid, tip, radius * 0.42, radius * 0.10,
                      dark if i % 2 else material, segments=5, group=gid,
                      ao0=0.99, ao1=0.84, cap=False)

    def gnarl(self, p0, yaw, pitch, length, r, material, depth, rng,
              group=None, wander=0.55, light=None):
        """A forking limb that wanders as it thins; returns its tips."""
        x, y, z = p0
        light = material if light is None else light
        mid_yaw = yaw + rng.uniform(-wander, wander) * 0.55
        mid = (x + math.cos(mid_yaw) * length * 0.52,
               y + math.sin(mid_yaw) * length * 0.52 * 0.82,
               z + length * pitch * 0.58)
        end = (x + math.cos(yaw) * length,
               y + math.sin(yaw) * length * 0.82,
               z + length * pitch)
        self.limb(p0, mid, r, r * 0.78, material, segments=7,
                  group=group)
        self.limb(mid, end, r * 0.78, r * 0.52,
                  light if pitch > 0.55 else material, segments=6,
                  group=group, cap=False)
        if depth <= 0:
            return [end]
        tips = []
        for _ in range(rng.randint(2, 3)):
            spread = rng.uniform(0.5, 1.0)
            child_yaw = yaw + rng.choice((-1.0, 1.0)) * spread
            child_pitch = pitch * rng.uniform(0.8, 1.15) \
                + rng.uniform(0.1, 0.28)
            tips += self.gnarl(end, child_yaw, child_pitch,
                               length * rng.uniform(0.62, 0.78),
                               r * 0.52, material, depth - 1, rng,
                               group=group, wander=wander, light=light)
        return tips

    def ribbed_column(self, x, y, z0, z1, radius, dark, mid, light,
                      ribs=9, group=None, rng=None, spines=0,
                      spine_mat=None, dome=True) -> None:
        """A cactus column: a shaded core with raised, sun-caught ribs."""
        gid = self.m.group() if group is None else group
        self.cylinder(x, y, z0, z1, radius * 0.88, mid, segments=16,
                      cap=False, group=gid)
        for i in range(ribs):
            yaw = math.tau * i / ribs
            dx, dy = math.cos(yaw), math.sin(yaw)
            band = tone_for((dark, mid, light, light), dx, dy, 0.0,
                            rng or _NullRng(), jitter=0.0)
            rx, ry = x + dx * radius * 0.80, y + dy * radius * 0.80
            self.limb((rx, ry, z0), (rx, ry, z1), radius * 0.24,
                      radius * 0.20, band, segments=4, group=gid,
                      cap=False)
            if dome:
                # The ribs carry over the rounded top instead of stopping at
                # a flat lid.
                self.limb((rx, ry, z1),
                          (x + dx * radius * 0.40, y + dy * radius * 0.34,
                           z1 + radius * 0.52), radius * 0.20,
                          radius * 0.08, band, segments=3, group=gid,
                          cap=False)
        if dome:
            self.blob(x, y, z1, radius * 0.92, radius * 0.88,
                      radius * 0.62, light, ao_base=0.88, segments=12,
                      rings=5, group=gid, wobble=0.03)
        if spines and rng is not None:
            spine_mat = light if spine_mat is None else spine_mat
            for rib in range(ribs):
                yaw = math.tau * rib / ribs
                for k in range(spines):
                    z = z0 + (z1 - z0) * (0.10 + 0.80 * k / max(1, spines - 1))
                    z += rng.uniform(-0.7, 0.7)
                    self.blob(x + math.cos(yaw) * radius * 0.98,
                              y + math.sin(yaw) * radius * 0.98, z,
                              0.62, 0.62, 0.45, spine_mat, ao_base=0.98,
                              segments=5, rings=3, group=gid)


class _NullRng:
    """A do-nothing rng for optional jitter."""

    def uniform(self, _a, _b):
        return 0.0


# ---------------------------------------------------------------------------
# crowns
# ---------------------------------------------------------------------------

def canopy(builder: TreeBuilder, centre, radii, tones, rng, group=None,
           count=30, cluster=5.0, tips=16, underside=3, ao=0.72,
           shell=0.9, tip_size=1.35, bias=0.0, spread=1.0,
           fillers=3, shoulders=True) -> None:
    """One crown, assembled the way a canopy catches the light.

    A dark under-mass holds the silhouette, leaf clusters are distributed over
    a Fibonacci sphere so the crown is evenly full rather than a few big lobes,
    and a ring of small tufts frays the rim into leaves.  Every cluster takes
    its tone from the direction it faces the shared sun, so the whole crown
    shades as one object.  Pass one ``group`` for the mass so the interior has
    no crease lines and reads as foliage; the tufts share it.
    """
    shadow, mid, light, sun = tones
    cx, cy, cz = centre
    rx, ry, rz = radii
    gid = builder.m.group() if group is None else group

    # The shadowed heart of the crown: a few broad dark masses under the
    # leaf clusters, so gaps never show sky through the middle of a tree.
    for k in range(underside):
        a = math.tau * k / max(1, underside) + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.12, 0.4)
        builder.blob(cx + math.cos(a) * rx * d,
                     cy + math.sin(a) * ry * d,
                     cz - rz * rng.uniform(0.30, 0.48),
                     rx * rng.uniform(0.38, 0.52),
                     ry * rng.uniform(0.36, 0.5),
                     rz * rng.uniform(0.34, 0.46), shadow,
                     ao_base=0.56, segments=9, rings=5, group=gid,
                     wobble=0.12, phase=a)

    golden = math.pi * (3.0 - math.sqrt(5.0))
    placed = []
    for i in range(count):
        z0 = 1.0 - 2.0 * (i + 0.5) / count
        z0 = max(-0.92, min(0.96, z0 * shell))
        rr = math.sqrt(max(0.0, 1.0 - z0 * z0))
        a = i * golden + rng.uniform(-0.16, 0.16)
        dx, dy = rr * math.cos(a), rr * math.sin(a)
        dz = z0
        # Most clusters sit on the shell where they shape the silhouette; the
        # rest fill the inside so the crown is solid, not hollow.
        if dz > 0.42:
            # High clusters stay near the shell so the crown's top is a
            # continuous cap, not one leaf ball above a gap.
            f = rng.uniform(0.84, 0.94)
        elif i % 4 == 3:
            f = rng.uniform(0.30, 0.55)
        else:
            f = rng.uniform(0.62, 0.94)
        ox = cx + dx * rx * f * spread
        oy = cy + dy * ry * f * spread
        oz = cz + dz * rz * f
        rad = cluster * (rng.uniform(0.72, 1.12) if rng.random() < 0.80
                         else rng.uniform(1.32, 1.72))
        if abs(dz) < 0.35:
            rad *= 1.08
        tone = tone_for(tones, dx, dy, dz, rng,
                        bias=bias - (0.12 if f < 0.55 else 0.0))
        builder.blob(ox, oy, oz, rad * rng.uniform(0.9, 1.12),
                     rad * rng.uniform(0.82, 1.02),
                     rad * rng.uniform(0.72, 0.94), tone,
                     ao_base=ao, segments=8, rings=5, group=gid,
                     wobble=0.12, phase=a * 1.7)
        if dz > 0.32 and shoulders:
            # Shoulders under a high cluster: the top of a crown is the
            # easiest place for a leaf ball to look detached, so each high
            # cluster hangs two overlapping masses beneath it.
            for k, drop in enumerate((0.72, 1.42)):
                builder.blob(ox, oy, oz - rad * drop,
                             rad * (0.86 - 0.14 * k),
                             rad * (0.80 - 0.12 * k),
                             rad * 0.62, tone,
                             ao_base=ao + 0.02, segments=7, rings=4,
                             group=gid, wobble=0.14, phase=a * 2.4 + k)
        if f > 0.58:
            placed.append((ox, oy, oz, rad, tone, dx, dy, dz))
        # A shoulder lobe on half the clusters: the little secondary bump that
        # makes a cloud of leaves look gathered rather than spheres in a bag.
        if i % 3 == 0:
            builder.blob(ox + dx * rad * 0.52, oy + dy * rad * 0.52,
                         oz + rad * rng.uniform(0.1, 0.45),
                         rad * 0.58, rad * 0.55, rad * 0.45, tone,
                         ao_base=ao + 0.03, segments=7, rings=4,
                         group=gid, wobble=0.17, phase=a * 2.3)

    # Filler caps inside the shell: a knot at the top and two shoulder masses
    # that close the gaps between Fibonacci clusters, so no rim tuft reads as
    # a leaf floating free of the crown.
    for fx, fy, fz, rr in ((0.0, 0.0, 0.64, 0.96),
                           (0.42, 0.12, 0.40, 0.84),
                           (-0.42, -0.10, 0.36, 0.80))[:fillers]:
        builder.blob(cx + fx * rx, cy + fy * ry, cz + fz * rz,
                     cluster * rr, cluster * rr * 0.9,
                     cluster * rr * 0.76,
                     tone_for(tones, fx, fy, fz, rng, bias=bias - 0.06,
                              jitter=0.02),
                     ao_base=ao + 0.03, segments=8, rings=5, group=gid,
                     wobble=0.10, phase=fx * 3.0 + fz)

    # Frayed rim: each tuft grows out of a real leaf cluster, never floating
    # free of the crown in screen space.
    for i in range(tips):
        if placed:
            bx, by, bz, rad, _tone, dx, dy, dz = rng.choice(placed)
            f = rng.uniform(0.45, 0.8)
            ox = bx + dx * rad * f
            oy = by + dy * rad * f
            oz = bz + dz * rad * f + rad * 0.18
            tone = tone_for(tones, dx, dy, dz, rng, bias=bias + 0.05,
                            jitter=0.05)
        else:
            a = i * golden * 0.9
            dz = rng.uniform(-0.3, 0.6)
            rr = math.sqrt(max(0.0, 1.0 - dz * dz))
            dx, dy = rr * math.cos(a), rr * math.sin(a)
            ox, oy, oz = cx + dx * rx, cy + dy * ry, cz + dz * rz
            tone = tone_for(tones, dx, dy, dz, rng, bias=bias)
        builder.blob(ox, oy, oz, tip_size * rng.uniform(0.7, 1.1),
                     tip_size * rng.uniform(0.65, 1.0),
                     tip_size * rng.uniform(0.5, 0.8), tone,
                     ao_base=0.8, segments=6, rings=4, group=gid,
                     wobble=0.2, phase=i * 1.7)


def shrub_canopy(builder: TreeBuilder, centre, radii, tones, rng,
                 group=None, **kwargs) -> None:
    """A low, wide crown for bushes and heather: same rules, closer to earth."""
    canopy(builder, centre, radii, tones, rng, group=group, **kwargs)


# ---------------------------------------------------------------------------
# species models
# ---------------------------------------------------------------------------

def draw_oak(builder: TreeBuilder, rng) -> None:
    """A broadleaf oak: a goblet of gnarled boughs under a wide, clouded crown."""
    trunk = builder.group()
    lean = rng.uniform(-2.4, 2.4)
    builder.roots(32, 16, 0.0, 5.6, BARK, rng, count=5,
                  group=trunk, dark=BARK_DARK, spread=1.04)
    fork = (32 + lean * 0.55, 16, rng.uniform(21.0, 25.0))
    builder.taper_path([(32, 16, 0.4),
                        (32 + lean * 0.10, 16, fork[2] * 0.30),
                        (32 + lean * 0.46, 16, fork[2] * 0.68),
                        fork], 7.8, 4.3, BARK, group=trunk, segments=11,
                       ao0=0.76, ao1=0.94)
    # Four heavy boughs, two reaching wide and two lifting into the crown.
    # Their twigs stay short so no bare spike escapes the leaf mass.
    boughs = ((-0.95, 0.55, 15.0, 12.0), (0.98, 0.45, 15.0, 11.0),
              (-0.35, -0.9, 12.0, 14.0), (0.55, -0.75, 13.0, 13.0))
    for bx, by, reach, lift in boughs:
        end = (fork[0] + bx * reach, fork[1] + by * reach * 0.7,
               fork[2] + lift)
        builder.limb(fork, end, 3.6, 1.6, BARK, segments=6, group=trunk)
        builder.gnarl(end, math.atan2(by, bx), rng.uniform(0.7, 0.95),
                      rng.uniform(6.5, 8.0), 1.5, BARK_LIGHT, 1, rng,
                      group=trunk, light=BARK_WARM)
    # One old oak is a broad, lobed crown: a high dome with shoulders that
    # break the outline into clouds.  All four lobes share one crease group so
    # the canopy reads as one mass of leaves, and each lobe is built from
    # small clusters rather than broad grape-like balls.
    lift = (0.0, 1.5, 0.7, 2.2)[getattr(builder, "variant", 0) % 4]
    oak_tones = (OAK_LEAF_DARK, OAK_LEAF, OAK_LEAF_LIGHT, OAK_LEAF_SUN)
    crown = builder.group()
    shrub_canopy(builder, (31.0 + lean, 16.0, 54.0 + lift),
                 (46.0, 21.0, 13.0), oak_tones, rng, group=crown,
                 count=150, cluster=3.9, tips=46, tip_size=1.6,
                 ao=0.66, underside=4, shell=0.92)
    for cx, cy, cz, rx, ry, rz, count in (
            (9.0, 14.5, 44.5 + lift, 17.0, 10.0, 9.5, 32),
            (53.0, 16.5, 45.5 + lift, 18.0, 10.5, 10.0, 34)):
        shrub_canopy(builder, (cx, cy, cz), (rx, ry, rz), oak_tones,
                     rng, group=crown, count=count, cluster=3.6, tips=15,
                     tip_size=1.5, ao=0.66, underside=2, shell=0.94)


def draw_maple(builder: TreeBuilder, rng) -> None:
    """A maple: a slender forked trunk under a broad crown of ember lobes."""
    trunk = builder.group()
    lean = rng.uniform(-2.2, 2.2)
    builder.roots(32, 16, 0.0, 4.6, MAPLE_BARK_DARK, rng, count=4,
                  group=trunk, dark=MAPLE_BARK_DARK, spread=0.92)
    fork = (32 + lean * 0.6, 16, rng.uniform(26.0, 30.0))
    builder.taper_path([(32, 16, 0.4),
                        (32 + lean * 0.08, 16, fork[2] * 0.34),
                        (32 + lean * 0.44, 16, fork[2] * 0.70),
                        fork], 5.8, 2.9, MAPLE_BARK, group=trunk,
                       segments=11, ao0=0.78, ao1=0.94)
    # Five limbs fan out of the fork; two low ones stay visible beneath the
    # crown, so the maple does not read as a ball balanced on a stick.
    for i in range(5):
        yaw = math.tau * i / 5 + rng.uniform(-0.34, 0.34)
        low = i < 2
        reach = rng.uniform(11.0, 14.0) if low else rng.uniform(8.0, 11.0)
        lift = rng.uniform(-1.0, 2.0) if low else rng.uniform(7.0, 12.0)
        end = (fork[0] + math.cos(yaw) * reach,
               fork[1] + math.sin(yaw) * reach * 0.8, fork[2] + lift)
        builder.limb(fork, end, 2.6, 1.15, MAPLE_BARK, segments=6,
                     group=trunk)
        builder.gnarl(end, yaw, rng.uniform(0.55, 0.9) if low
                      else rng.uniform(0.75, 1.0),
                      rng.uniform(5.0, 7.0), 1.0, MAPLE_BARK_LIGHT, 1, rng,
                      group=trunk, light=MAPLE_BARK_LIGHT)
    maple_tones = (MAPLE_LEAF_DARK, MAPLE_LEAF, MAPLE_LEAF_LIGHT,
                   MAPLE_LEAF_SUN)
    crown = builder.group()
    main_z = rng.uniform(48.0, 51.0)
    shrub_canopy(builder, (32.0 + lean, 16.0, main_z),
                 (38.0, 18.0, 16.0), maple_tones, rng, group=crown,
                 count=132, cluster=3.6, tips=40, tip_size=1.45,
                 ao=0.66, underside=3, fillers=2, shell=0.92)
    for side in (-1.0, 1.0):
        cx = 32.0 + lean + side * rng.uniform(16.0, 19.5)
        cy = 16.0 + side * rng.uniform(0.0, 3.0)
        cz = main_z - rng.uniform(4.5, 7.0)
        shrub_canopy(builder, (cx, cy, cz),
                     (rng.uniform(15.0, 18.0), rng.uniform(9.5, 11.0),
                      rng.uniform(9.5, 11.5)), maple_tones, rng,
                     group=crown, count=30, cluster=3.3, tips=14,
                     tip_size=1.35, ao=0.66, underside=2, fillers=1,
                     shell=0.93)


def draw_birch(builder: TreeBuilder, rng) -> None:
    """A birch: a clump of white paper trunks under an airy, broken crown."""
    stems = ((-8.0, -1.5, -3.6, 46.0, 2.45),
             (0.5, 2.8, 1.2, 41.0, 2.00),
             (8.5, -0.8, 5.4, 37.0, 1.55))
    for stem, (dx, dy, lean, height, thick) in enumerate(stems):
        trunk = builder.group()
        base_x, base_y = 32 + dx, 16 + dy
        builder.roots(base_x, base_y, 0.0, thick, BIRCH_BARK, rng,
                      count=3, group=trunk, dark=BIRCH_BARK_SHADE,
                      spread=0.62)
        top = (base_x + lean, base_y + rng.uniform(-0.9, 0.9), height)
        points = [(base_x, base_y, 0.4),
                  (base_x + lean * 0.22, base_y + lean * 0.05,
                   height * 0.36),
                  (base_x + lean * 0.60, base_y + lean * 0.1,
                   height * 0.72),
                  top]
        builder.taper_path(points, thick, 0.42, BIRCH_BARK, group=trunk,
                           segments=8, ao0=0.80, ao1=0.96)
        # A couple of small branch scars add depth without fighting the
        # lenticel bars painted by the bark pattern.
        for _ in range(2):
            z = rng.uniform(height * 0.25, height * 0.7)
            a = rng.uniform(0, math.tau)
            rr = thick * (1.0 - 0.45 * z / height)
            builder.blob(base_x + lean * (z / height) + math.cos(a) * rr,
                         base_y + math.sin(a) * rr, z, 0.72, 0.62, 0.48,
                         BIRCH_BARK_SHADE, ao_base=0.95, segments=5,
                         rings=3, group=trunk)
        # Two thin branches per stem, kept inside the crown so the clump reads
        # as one tree rather than a bundle of poles.
        for k in range(2):
            yaw = math.tau * k / 2 + rng.uniform(-0.5, 0.5) + stem * 0.8
            start_z = height * rng.uniform(0.60, 0.84)
            start = (base_x + lean * (start_z / height),
                     base_y + rng.uniform(-0.6, 0.6), start_z)
            end = (start[0] + math.cos(yaw) * rng.uniform(6.0, 9.5),
                   start[1] + math.sin(yaw) * rng.uniform(4.0, 7.0),
                   start_z + rng.uniform(8.0, 13.0))
            builder.limb(start, end, 0.78, 0.26, BIRCH_BARK, segments=4,
                         group=trunk)
            fork_yaw = yaw + rng.choice((-0.55, 0.55))
            tip = (end[0] + math.cos(fork_yaw) * rng.uniform(3.0, 5.5),
                   end[1] + math.sin(fork_yaw) * rng.uniform(2.0, 4.0),
                   end[2] + rng.uniform(2.0, 4.0))
            builder.limb(end, tip, 0.28, 0.09, BIRCH_BARK_SHADE,
                         segments=3, group=trunk, cap=False)
    # One loose, rounded crown over the whole clump, built from overlapping
    # clouds so the clump shares a single canopy with sky between the edges.
    crown = builder.group()
    birch_tones = (BIRCH_LEAF_DARK, BIRCH_LEAF, BIRCH_LEAF_LIGHT,
                   BIRCH_LEAF_SUN)
    for cx, cy, cz, rx, ry, rz, count, tips, fill in (
            (33.0, 16.0, 56.0, 30.0, 18.0, 10.5, 58, 22, 1),
            (10.0, 11.5, 48.0, 15.0, 10.0, 8.5, 22, 10, 1),
            (55.5, 17.5, 50.0, 16.5, 10.5, 9.0, 24, 11, 1),
            (36.0, 15.0, 60.5, 13.0, 7.5, 7.0, 14, 7, 0)):
        shrub_canopy(builder, (cx, cy, cz), (rx, ry, rz), birch_tones,
                     rng, group=crown, count=count, cluster=2.95,
                     tips=tips, tip_size=1.2, ao=0.68, underside=1,
                     shell=0.94, fillers=fill, shoulders=False)


def draw_pine(builder: TreeBuilder, rng) -> None:
    """A conifer: a visible bole under spiralling tiers of feathered boughs."""
    trunk = builder.group()
    builder.roots(32, 16, 0.0, 4.3, PINE_BARK_DARK, rng, count=4,
                  group=trunk, dark=PINE_BARK_DARK, spread=0.85)
    builder.taper_path([(32, 16, 0.3), (32, 16, 18.0), (32, 16, 42.0),
                        (32, 16, 64.0)], 4.9, 0.7, PINE_BARK, group=trunk,
                       segments=9, ao0=0.76, ao1=0.96)
    tones = (PINE_NEEDLE_DARK, PINE_NEEDLE, PINE_NEEDLE_LIGHT,
             PINE_NEEDLE_SUN)

    def needle_pad(px, py, pz, wide, deep, thick, yaw, material, tilt=-0.35,
                   wobble=0.16, ao=0.74):
        builder.blob(px, py, pz, wide, deep, thick, material, ao_base=ao,
                     segments=7, rings=4, yaw=yaw, tilt=tilt,
                     wobble=wobble, phase=yaw * 2.3 + pz * 0.17)

    tiers = 6
    for tier in range(tiers):
        t = tier / (tiers - 1.0)
        z0 = 14.0 + t * 39.0
        radius = 25.5 * (1.0 - 0.62 * t) * rng.uniform(0.94, 1.06)
        count = 6 if tier < 3 else (5 if tier < 5 else 4)
        for k in range(count):
            yaw = (math.tau * k / count + tier * 0.82
                   + getattr(builder, "variant", 0) * 0.42
                   + rng.uniform(-0.12, 0.12))
            dx, dy = math.cos(yaw), math.sin(yaw)
            droop = 2.2 + 2.6 * t
            # The woody bough: a gentle lift off the trunk, then a droop.
            p0 = (32, 16, z0)
            p1 = (32 + dx * radius * 0.52, 16 + dy * radius * 0.46,
                  z0 + 0.7)
            p2 = (32 + dx * radius, 16 + dy * radius * 0.82,
                  z0 - droop)
            # Bough wood is dark green: anything visible between the pads
            # must read as shadowed needle, never as a red-brown plank.
            builder.limb(p0, p1, 1.65, 1.05, PINE_NEEDLE_DARK, segments=6,
                         group=trunk)
            builder.limb(p1, p2, 1.05, 0.26, PINE_NEEDLE_DARK, segments=6,
                         group=trunk, cap=False)
            tone = tone_for(tones, dx, dy, 0.16, rng, jitter=0.05)
            top_tone = tone_for(tones, dx, dy, 0.55, rng, bias=0.20,
                                jitter=0.06)
            # A dark collar hides the naked bough base, so no warm trunk
            # shows through the needle mass as a red-brown hole.
            needle_pad(32 + dx * radius * 0.10,
                       16 + dy * radius * 0.08, z0 + 0.4,
                       radius * 0.34, radius * 0.27, 2.0, yaw,
                       PINE_NEEDLE_DARK, ao=0.60)
            # Four overlapping needle pads down the bough, shrinking outward;
            # a lit top pad and a dark underside give each bough a feathered
            # edge rather than one flat pancake.
            for step in range(4):
                q = 0.24 + 0.24 * step
                px = 32 + dx * radius * q
                py = 16 + dy * radius * q * 0.82
                pz = z0 - droop * q * q + 0.7
                wide = radius * (0.31 - 0.045 * q)
                deep = radius * (0.24 - 0.035 * q)
                needle_pad(px, py, pz, wide, deep, 1.9, yaw, tone)
                needle_pad(px, py, pz + 1.0, wide * 0.52, deep * 0.48,
                           1.1, yaw, top_tone, tilt=-0.22,
                           wobble=0.2, ao=0.84)
                needle_pad(px, py, pz - 1.5, wide * 0.62, deep * 0.52,
                           1.0, yaw, PINE_NEEDLE_DARK, tilt=-0.5,
                           wobble=0.18, ao=0.66)
            # Needle tips hang below the end of the bough.
            for j in range(2):
                ox = rng.uniform(-1.2, 1.2)
                oy = rng.uniform(-1.0, 1.0)
                needle_pad(p2[0] + ox, p2[1] + oy, p2[2] - 1.6 - j * 1.3,
                           radius * 0.11, radius * 0.09, 2.6, yaw, tone,
                           tilt=-0.55, wobble=0.24, ao=0.76)

    # The leader: a slim spire of small needle whorls, not a smooth cone.
    builder.limb((32, 16, 52.0), (32, 16, 68.0), 1.4, 0.25,
                 PINE_NEEDLE_DARK, segments=6, group=trunk, cap=False)
    for i in range(7):
        t = i / 6.0
        z = 53.0 + 14.0 * t
        reach = (4.2 * (1.0 - t) + 0.5) * 0.9
        a = i * 1.9 + 0.4
        for side in (-1.0, 1.0):
            yaw = a + (0.0 if side > 0 else math.pi)
            needle_pad(32 + math.cos(yaw) * reach,
                       16 + math.sin(yaw) * reach * 0.8, z,
                       (2.1 * (1.0 - 0.55 * t) + 0.5),
                       (1.7 * (1.0 - 0.55 * t) + 0.4),
                       (2.2 * (1.0 - 0.5 * t) + 0.5), yaw,
                       PINE_NEEDLE_SUN if i % 2 else PINE_NEEDLE_LIGHT,
                       tilt=-0.2, wobble=0.22, ao=0.86)
    builder.blob(32, 16, 69.0, 1.0, 0.9, 1.6, PINE_NEEDLE_SUN,
                 ao_base=0.9, segments=6, rings=3, group=trunk,
                 wobble=0.2)


def draw_palm(builder: TreeBuilder, rng) -> None:
    """A coconut palm: a leaning ringed trunk under a radial crown of feathers."""
    trunk = builder.group()
    lean = rng.uniform(-9.0, 9.0)
    height = rng.uniform(44.0, 48.0)
    builder.roots(32, 16, 0.0, 4.4, PALM_BARK_DARK, rng, count=4,
                  group=trunk, dark=PALM_BARK_DARK, spread=0.78)
    points = [(32, 16, 0.2),
              (32 + lean * 0.04, 16, height * 0.24),
              (32 + lean * 0.20, 16, height * 0.50),
              (32 + lean * 0.52, 16, height * 0.76),
              (32 + lean, 16, height)]
    for i in range(len(points) - 1):
        t0 = i / (len(points) - 1)
        t1 = (i + 1) / (len(points) - 1)
        builder.limb(points[i], points[i + 1],
                     4.6 * (1.0 - 0.40 * t0), 4.6 * (1.0 - 0.40 * t1),
                     PALM_BARK, segments=10, group=trunk, ao0=0.8, ao1=0.98)
    # Leaf-scar rings: thin raised bands, slightly proud of the bark.
    for k in range(1, 14):
        t = k / 14.0
        z = height * t
        x = 32 + lean * (math.pow(t, 1.8) * 0.9 + t * 0.1)
        r = 4.6 * (1.0 - 0.40 * t) * 1.04
        builder.limb((x, 16, z - 0.28), (x, 16, z + 0.28),
                     r, r, PALM_BARK_DARK, segments=10, group=trunk,
                     cap=False, ao0=1.0, ao1=1.0)
    # The green crownshaft where the trunk ends and the fronds begin.
    top_x = 32 + lean * 0.985
    builder.limb((top_x, 16, height - 5.5), (top_x, 16, height + 1.0),
                 3.5, 2.9, PALM_FROND_DARK, segments=10, group=trunk,
                 ao0=0.92, ao1=1.0)
    top = (32 + lean, 16, height)
    # The fibrous boot where the fronds spring, with a few hanging fibres.
    boot = builder.group()
    builder.limb((top[0], top[1], top[2] - 4.2),
                 (top[0], top[1], top[2] + 0.4), 3.3, 2.6,
                 PALM_BARK_DARK, segments=8, group=boot)
    for i in range(7):
        a = math.tau * i / 7 + rng.uniform(-0.2, 0.2)
        builder.limb((top[0] + math.cos(a) * 2.7,
                      top[1] + math.sin(a) * 2.2, top[2] - 1.0),
                     (top[0] + math.cos(a) * 3.1,
                      top[1] + math.sin(a) * 2.5, top[2] - rng.uniform(4.0, 7.0)),
                     0.45, 0.12, DEAD_FROND_DARK, segments=3, group=boot,
                     cap=False)
    # Three coconuts tucked under the crown, on the camera side where they
    # read as the palm's fruit rather than a brown knot.
    for i in range(3):
        x = top[0] + (i - 1) * 2.2 + rng.uniform(-0.3, 0.3)
        y = top[1] + 2.8 + rng.uniform(-0.3, 0.4)
        z = top[2] - 3.2 + (0.5 if i == 1 else 0.0)
        builder.blob(x, y, z, 2.1, 2.0, 2.2,
                     COCONUT_LIGHT if i % 2 else COCONUT,
                     ao_base=0.84, segments=7, rings=4, group=boot,
                     wobble=0.1, phase=i * 1.7)
    # Nine feathers make the wheel: three uplifted, four spreading, two
    # drooping, plus two young spears and one spent brown frond.
    tones = (PALM_FROND_DARK, PALM_FROND, PALM_FROND_LIGHT,
             PALM_FROND_SUN)
    yaw0 = rng.uniform(0, math.tau)
    ranks = ((3, 21.0, 25.0, 14.0, 18.0, 3.0, 5.0, 4, 7.2, 2.4),
             (4, 24.0, 29.0, 6.0, 9.0, 8.0, 11.0, 5, 8.2, 1.4),
             (3, 16.0, 20.0, 9.0, 12.0, 5.0, 7.0, 3, 6.2, 1.9))
    for rank, (count, len0, len1, lift0, lift1, droop0, droop1,
               leaflets, width, tone_index) in enumerate(ranks):
        for i in range(count):
            yaw = yaw0 + math.tau * i / count + rank * 0.50 \
                + rng.uniform(-0.08, 0.08)
            tone = tones[min(3, int(tone_index + rng.uniform(0, 1.0)))]
            # Each rank springs from a slightly different point on the
            # crownshaft, so the fronds do not all knot at one pixel.
            sx = top[0] + math.cos(yaw) * (1.0 + rank * 0.8)
            sy = top[1] + math.sin(yaw) * (0.8 + rank * 0.6)
            _palm_frond(builder, sx, sy, top[2] + 1.0 - rank * 1.2, yaw,
                        rng.uniform(len0, len1), rng.uniform(lift0, lift1),
                        rng.uniform(droop0, droop1), tone,
                        leaflets=leaflets,
                        width=rng.uniform(width, width + 0.6))
    # A young heart of short, broad fronds closes the top of the crown and
    # hides the dark boot between the longer ranks.
    for i in range(5):
        yaw = yaw0 + math.tau * i / 5 + 0.3
        _palm_frond(builder, top[0], top[1], top[2] + 1.6, yaw,
                    rng.uniform(5.0, 7.5), rng.uniform(7.0, 10.0), 2.0,
                    PALM_FROND_LIGHT if i % 2 else PALM_FROND,
                    leaflets=2, width=3.8)
    # A tight green heart at the growth point covers the brown boot.
    for i in range(4):
        a = math.tau * i / 4 + 0.5
        builder.blob(top[0] + math.cos(a) * 1.1,
                     top[1] + math.sin(a) * 0.9, top[2] + 1.0,
                     2.0, 1.9, 2.0,
                     PALM_FROND_DARK if i % 2 else PALM_FROND,
                     ao_base=0.94, segments=6, rings=4, group=boot,
                     wobble=0.26, phase=a * 1.7)
    builder.blob(top[0], top[1], top[2] + 2.6, 1.7, 1.6, 2.1,
                 PALM_FROND_LIGHT, ao_base=0.96, segments=6, rings=4,
                 group=boot, wobble=0.24, phase=1.1)
    for i in range(2):
        yaw = yaw0 + math.tau * i / 2 + 0.8
        _palm_frond(builder, top[0], top[1], top[2] + 2.2, yaw,
                    rng.uniform(9.0, 12.0), rng.uniform(13.0, 16.0), 2.0,
                    PALM_FROND_SUN, leaflets=3, width=5.0)
    _palm_frond(builder, top[0], top[1], top[2] - 2.2,
                yaw0 + math.pi * 0.4, 12.0, 2.0, 12.0, DEAD_FROND,
                leaflets=5, width=2.4)


def _palm_frond(builder: TreeBuilder, x, y, z, yaw, length, lift, droop,
                tone, leaflets=5, width=5.0) -> None:
    """One feather: a solid, notched lance with a lit rim and a dark underside.

    A palm frond at pixel-art scale reads as one broad leaf with a handful of
    deep notches along its edge.  The rim catches the sun, the rib runs down
    the middle, and the shaded underside stops the crown looking like a paper
    cut-out.
    """
    gid = builder.group()
    dx, dy = math.cos(yaw), math.sin(yaw)
    px, py = -dy, dx
    def spine(t):
        return (x + dx * length * t, y + dy * length * t,
                z + lift * math.sin(min(1.0, t * 1.25) * math.pi * 0.55)
                - droop * t * t)

    # The rib.
    previous = spine(0.0)
    for i in range(6):
        t = (i + 1) / 6.0
        point = spine(t)
        builder.limb(previous, point, 0.64 * (1.0 - i * 0.11),
                     0.64 * (1.0 - (i + 1) * 0.11), tone, segments=4,
                     group=gid, cap=False, ao0=0.9, ao1=1.0)
        previous = point

    def half_width(t):
        w = width * 0.55 * math.sin(math.pi * (0.07 + 0.88 * t)) ** 0.70
        for notch in (0.22, 0.42, 0.62, 0.80):
            w *= 1.0 - 0.34 * math.exp(-((t - notch) / 0.05) ** 2)
        return max(0.0, w)

    segments = 12
    for i in range(segments):
        t0, t1 = i / segments, (i + 1) / segments
        a, b = spine(t0), spine(t1)
        w0, w1 = half_width(t0), half_width(t1)
        for side in (-1.0, 1.0):
            edge_a = (a[0] + px * side * w0, a[1] + py * side * w0,
                      a[2] - w0 * 0.22)
            edge_b = (b[0] + px * side * w1, b[1] + py * side * w1,
                      b[2] - w1 * 0.22)
            _leaf_quad(builder, a, edge_a, edge_b, b, tone, gid)
            # A one-pixel lit rim along the edge, brighter on the sun side.
            rim = PALM_FROND_LIGHT if (dx * -side < 0.2) else PALM_FROND
            inset_a = (a[0] + px * side * w0 * 0.72,
                       a[1] + py * side * w0 * 0.72, a[2] - w0 * 0.10)
            inset_b = (b[0] + px * side * w1 * 0.72,
                       b[1] + py * side * w1 * 0.72, b[2] - w1 * 0.10)
            _leaf_quad(builder, edge_a, inset_a, inset_b, edge_b, rim, gid)
            # Shaded underside.
            builder.m.quad((a[0], a[1], a[2] - 0.42),
                           (b[0], b[1], b[2] - 0.42),
                           (edge_b[0], edge_b[1], edge_b[2] - 0.42),
                           (edge_a[0], edge_a[1], edge_a[2] - 0.42),
                           PALM_FROND_DARK,
                           uvs=((0, 0), (1, 0), (1, 1), (0, 1)),
                           ao=(0.9, 0.9, 0.9, 0.9), group=gid)
    terminal = spine(1.0)
    _leaf_quad(builder, spine(0.92), terminal,
               (terminal[0] + px * 0.6, terminal[1] + py * 0.6,
                terminal[2] - 0.4),
               (terminal[0] + dx * 2.8, terminal[1] + dy * 2.8,
                terminal[2] - 1.4), tone, gid)


def _leaf_quad(builder: TreeBuilder, a, b, c, d, material, group) -> None:
    """A leaf quad, wound so its face looks at the sky and catches the sun."""
    # Newell's normal for the quad; flip the winding if it faces down.
    nx = (a[1] - c[1]) * (b[2] + d[2]) + (b[1] - d[1]) * (c[2] + a[2])
    ny = (a[2] - c[2]) * (b[0] + d[0]) + (b[2] - d[2]) * (c[0] + a[0])
    nz = (a[0] - c[0]) * (b[1] + d[1]) + (b[0] - d[0]) * (c[1] + a[1])
    if nz < 0.0:
        b, d = d, b
    builder.m.quad(a, b, c, d, material, uvs=((0, 0), (1, 0), (1, 1), (0, 1)),
                   ao=(1.0, 1.0, 1.0, 1.0), group=group)


def draw_dead_tree(builder: TreeBuilder, rng) -> None:
    """A dead tree: a forked skeleton, twisted limbs and fine bare twigs."""
    trunk = builder.group()
    lean = rng.uniform(-2.5, 2.5)
    builder.roots(32, 16, 0.0, 5.6, DEAD_BARK_DARK, rng, count=5,
                  group=trunk, dark=DEAD_BARK_DARK, spread=1.0)
    fork = (32 + lean, 16, rng.uniform(13.0, 16.0))
    builder.taper_path([(32, 16, 0.4), (32 + lean * 0.18, 16, fork[2] * 0.35),
                        (32 + lean * 0.55, 16, fork[2] * 0.7),
                        fork], 7.0, 4.2,
                       DEAD_BARK, group=trunk, segments=8,
                       ao0=0.76, ao1=0.9)
    # A codominant second stem splits off low on the trunk: the old tree is
    # two leaders fighting for the sky, not a single pole with arms.
    split_yaw = rng.uniform(0, math.tau)
    split = (fork[0] + math.cos(split_yaw) * 3.5,
             fork[1] + math.sin(split_yaw) * 2.8, fork[2] + 9.0)
    builder.limb(fork, split, 4.2, 2.9, DEAD_BARK, segments=7,
                 group=trunk)
    builders = ((fork, 2, 1.0), (split, 2, 0.85))
    for origin, depth, pitch_scale in builders:
        for i in range(2):
            yaw = math.tau * i / 2 + rng.uniform(-0.5, 0.5) + split_yaw
            pitch = rng.uniform(0.7, 1.05) * pitch_scale
            tips = builder.gnarl(origin, yaw, pitch,
                                 rng.uniform(12.0, 17.0), 3.4,
                                 DEAD_BARK, depth, rng, group=trunk,
                                 wander=0.85, light=DEAD_BARK_LIGHT)
            for tip in tips:
                for _ in range(2):
                    twig_yaw = yaw + rng.uniform(-1.2, 1.2)
                    end = (tip[0] + math.cos(twig_yaw) * rng.uniform(4.0, 7.0),
                           tip[1] + math.sin(twig_yaw) * rng.uniform(3.0, 5.5),
                           tip[2] + rng.uniform(1.0, 5.0))
                    builder.limb(tip, end, 0.9, 0.24,
                                 DEAD_BARK_LIGHT if rng.random() < 0.4
                                 else DEAD_BARK, segments=4,
                                 group=trunk, cap=False)
                    # A last generation of hair-fine twigs frays the silhouette.
                    fine_yaw = twig_yaw + rng.uniform(-0.8, 0.8)
                    builder.limb(end, (end[0] + math.cos(fine_yaw)
                                       * rng.uniform(2.0, 4.0),
                                       end[1] + math.sin(fine_yaw)
                                       * rng.uniform(1.5, 3.2),
                                       end[2] + rng.uniform(0.5, 2.5)),
                                 0.30, 0.07, DEAD_BARK_LIGHT,
                                 segments=3, group=trunk, cap=False)
    # A low limb reaches out sideways, dead before it ever carried a crown.
    low_yaw = split_yaw + math.pi * 0.5 + rng.uniform(-0.4, 0.4)
    low_end = (fork[0] + math.cos(low_yaw) * rng.uniform(11.0, 14.0),
               fork[1] + math.sin(low_yaw) * rng.uniform(8.0, 11.0),
               fork[2] - rng.uniform(3.0, 6.0))
    builder.limb(fork, low_end, 2.8, 1.0, DEAD_BARK, segments=5,
                 group=trunk)
    builder.limb(low_end, (low_end[0] + math.cos(low_yaw + 0.8) * 5.0,
                           low_end[1] + math.sin(low_yaw + 0.8) * 4.0,
                           low_end[2] + 2.5), 0.8, 0.2, DEAD_BARK,
                 segments=3, group=trunk, cap=False)
    # A snapped bough: a thick stub with a pale, splintered end.
    stub_yaw = rng.uniform(0, math.tau)
    stub_end = (split[0] + math.cos(stub_yaw) * 6.0,
                split[1] + math.sin(stub_yaw) * 5.0,
                split[2] + rng.uniform(3.0, 6.0))
    builder.limb(split, stub_end, 2.9, 2.0, DEAD_BARK, segments=6,
                 group=trunk)
    builder.blob(stub_end[0], stub_end[1], stub_end[2], 2.0, 1.9, 1.4,
                 DEAD_BARK_LIGHT, ao_base=0.86, segments=6, rings=4,
                 group=trunk, wobble=0.2, phase=stub_yaw)
    # The hollow where the two leaders split: a dark mouth with a pale lip.
    builder.blob(fork[0] - 0.8, fork[1] - 3.2, fork[2] + 3.0,
                 2.6, 1.6, 3.0, DEAD_BARK_DARK, ao_base=0.42,
                 segments=7, rings=4, group=trunk, wobble=0.12)
    # Knots and old wounds on the trunk, dark as a hollow.
    for _ in range(2):
        z = rng.uniform(4.0, fork[2] - 2.0)
        a = rng.uniform(0, math.tau)
        builder.blob(32 + math.cos(a) * 4.4, 16 + math.sin(a) * 3.6, z,
                     1.7, 1.5, 2.1, DEAD_BARK_DARK, ao_base=0.88,
                     segments=6, rings=4, group=trunk, wobble=0.16)


def draw_cactus(builder: TreeBuilder, rng) -> None:
    """A saguaro: a ribbed column, curved raised arms, and pink bloom."""
    trunk = builder.group()
    builder.roots(32, 16, 0.0, 6.0, CACTUS_SKIN_DARK, rng, count=4,
                  group=trunk, dark=CACTUS_SKIN_DARK, spread=0.75)
    column_top = rng.uniform(44.0, 48.0)
    builder.ribbed_column(32, 16, -1.0, column_top, 7.2,
                          CACTUS_SKIN_DARK, CACTUS_SKIN,
                          CACTUS_SKIN_LIGHT, ribs=10, group=trunk,
                          rng=rng, spines=11, spine_mat=CACTUS_SPINE)
    arm_count = rng.randint(2, 3)
    arm_yaws = (-0.62, 2.42, 1.15)
    for arm_index in range(arm_count):
        height = rng.uniform(17.0, 31.0)
        yaw = arm_yaws[arm_index] + rng.uniform(-0.20, 0.20)
        reach = rng.uniform(11.0, 14.0)
        up = rng.uniform(12.0, 17.0)
        dx, dy = math.cos(yaw), math.sin(yaw)
        arm = builder.group()
        # A smooth elbow: shoulder, out, curve, then up.  One hard corner is
        # what makes a cactus look like a plumbing fitting.
        p0 = (32, 16, height)
        p1 = (32 + dx * reach * 0.55, 16 + dy * reach * 0.44, height - 0.6)
        p2 = (32 + dx * reach, 16 + dy * reach * 0.80, height + 1.8)
        p3 = (p2[0] + dx * 1.2, p2[1] + dy * 1.0, height + up * 0.45)
        p4 = (p3[0] + dx * 0.8, p3[1] + dy * 0.7, height + up)
        path = (p0, p1, p2, p3, p4)
        for i in range(4):
            builder.limb(path[i], path[i + 1],
                         4.2 - i * 0.20, 4.0 - i * 0.20,
                         CACTUS_SKIN, segments=12, group=arm, cap=False,
                         ao0=0.82, ao1=0.98)
        # Rib lines along the raised part of the arm, plus its pale spines.
        for rib in range(6):
            a = math.tau * rib / 6
            ox, oy = math.cos(a) * 3.1, math.sin(a) * 2.7
            builder.limb((p2[0] + ox, p2[1] + oy, p2[2]),
                         (p4[0] + ox, p4[1] + oy, p4[2]),
                         0.55, 0.42,
                         CACTUS_SKIN_LIGHT if rib % 3 else CACTUS_SKIN_DARK,
                         segments=4, group=arm, cap=False)
        builder.blob(p4[0], p4[1], p4[2] + 0.4, 3.4, 3.1, 2.4,
                     CACTUS_SKIN_LIGHT, ao_base=0.9, segments=12, rings=5,
                     group=arm, wobble=0.04)
        for rib in range(6):
            a = math.tau * rib / 6
            for k in range(4):
                z = p2[2] + (p4[2] - p2[2]) * (0.1 + 0.8 * k / 3)
                builder.blob(p2[0] + math.cos(a) * 3.3,
                             p2[1] + math.sin(a) * 2.9, z,
                             0.55, 0.55, 0.4, CACTUS_SPINE, ao_base=0.98,
                             segments=4, rings=3, group=arm)
        if rng.random() < 0.9:
            for k in range(3):
                a = math.tau * k / 3 + rng.uniform(-0.2, 0.2)
                builder.blob(p4[0] + math.cos(a) * 1.7,
                             p4[1] + math.sin(a) * 1.5,
                             p4[2] + 3.0, 1.4, 1.4, 1.2,
                             FLOWER_PINK if k % 2 else FLOWER_PINK_LIGHT,
                             ao_base=0.92, segments=6, rings=3, group=arm)
    # The crown flower: a ring of petals round a warm heart.
    for i in range(7):
        a = math.tau * i / 7 + rng.uniform(-0.10, 0.10)
        builder.blob(32 + math.cos(a) * 2.9, 16 + math.sin(a) * 2.7,
                     column_top + 2.2, 2.2, 2.1, 1.7,
                     FLOWER_PINK_LIGHT if i % 2 else FLOWER_PINK,
                     ao_base=0.92, segments=6, rings=3, group=trunk)
    builder.blob(32, 16, column_top + 3.3, 1.9, 1.8, 1.5,
                 FLOWER_PINK, ao_base=0.94, segments=6, rings=3,
                 group=trunk)
    builder.blob(32, 16, column_top + 3.9, 0.8, 0.8, 0.7,
                 STRAW_LIGHT, ao_base=0.98, segments=5, rings=3,
                 group=trunk)
    # Desert gravel and a young bud at the foot.
    for _ in range(4):
        a = rng.uniform(0, math.tau)
        builder.pebble(32 + math.cos(a) * rng.uniform(8.0, 11.0),
                       16 + math.sin(a) * rng.uniform(5.0, 8.0), 0.0,
                       rng.uniform(1.8, 2.8), STONE_PEBBLE)
    builder.blob(32 + rng.uniform(-8.0, 8.0), 16 + rng.uniform(-5.0, 5.0),
                 2.0, 1.6, 1.5, 3.6, CACTUS_SKIN, ao_base=0.86,
                 segments=10, rings=4, group=trunk, wobble=0.05)


def draw_bush(builder: TreeBuilder, rng) -> None:
    """A garden shrub: woody stems carrying separate clouds of leaves."""
    twig = builder.group()
    builder.roots(32, 16, 0.0, 1.5, BARK_DARK, rng, count=2, group=twig,
                  dark=BARK_DARK, spread=0.5)
    tips = []
    for i in range(4):
        yaw = math.tau * i / 4 + rng.uniform(-0.35, 0.35)
        reach = rng.uniform(4.0, 7.0)
        base = (32 + math.cos(yaw) * 1.5,
                16 + math.sin(yaw) * 1.2, 0.2)
        top = (32 + math.cos(yaw) * reach,
               16 + math.sin(yaw) * reach * 0.8, rng.uniform(9.0, 14.0))
        builder.limb(base, top, 1.05, 0.45, BARK,
                     segments=5, group=twig)
        # Two twigs fork from each stem; their tips carry the leaf clouds.
        for side in (-0.55, 0.55):
            tyaw = yaw + side + rng.uniform(-0.15, 0.15)
            tip = (top[0] + math.cos(tyaw) * rng.uniform(3.5, 6.0),
                   top[1] + math.sin(tyaw) * rng.uniform(2.5, 4.5),
                   top[2] + rng.uniform(1.0, 3.0))
            builder.limb(top, tip, 0.62, 0.22, BARK_DARK, segments=4,
                         group=twig, cap=False)
            tips.append(tip)
    bush_tones = (BUSH_LEAF_DARK, BUSH_LEAF, BUSH_LEAF_LIGHT,
                  BUSH_LEAF_SUN)
    crown = builder.group()
    # A low central cushion, then one cloud at each branch tip: separate
    # masses with stems showing between them, not one green boulder.
    shrub_canopy(builder, (32, 16, 16.0), (15.0, 12.0, 5.8), bush_tones,
                 rng, group=crown, count=28, cluster=3.0, tips=12,
                 tip_size=1.2, ao=0.66, underside=2, fillers=1,
                 shoulders=False)
    for index, (tx, ty, tz) in enumerate(tips):
        shrub_canopy(builder, (tx, ty, tz + 1.6),
                     (rng.uniform(9.0, 11.5), rng.uniform(7.0, 8.5),
                      rng.uniform(4.0, 5.5)), bush_tones, rng,
                     group=crown, count=17, cluster=2.8, tips=8,
                     tip_size=1.1, ao=0.68, underside=1, fillers=1,
                     shoulders=False)
    # A few low sprays trail onto the turf, so the shrub is rooted.
    for _ in range(4):
        a = rng.uniform(0, math.tau)
        builder.leaf_tuft(32 + math.cos(a) * rng.uniform(11.0, 15.0),
                          16 + math.sin(a) * rng.uniform(8.0, 11.0),
                          rng.uniform(2.0, 5.0), BUSH_LEAF, rng,
                          size=1.9, spread=1.1, group=crown, count=3)
    # Berries hang in little clusters, mostly on the sun side.
    if rng.random() < 0.55:
        for cluster in range(2):
            cx = 32 + rng.uniform(4.0, 12.0)
            cy = 16 + rng.uniform(-6.0, 3.0)
            cz = rng.uniform(12.0, 20.0)
            for _ in range(4):
                builder.blob(cx + rng.uniform(-1.6, 1.6),
                             cy + rng.uniform(-1.3, 1.3),
                             cz + rng.uniform(-1.6, 1.2), 0.95, 0.95, 0.95,
                             BUSH_BERRY_LIGHT if rng.random() < 0.4
                             else BUSH_BERRY, ao_base=0.94,
                             segments=5, rings=3, group=crown)


def draw_fescue(builder: TreeBuilder, rng) -> None:
    """A fescue tussock: a low skirt and a tall fountain of arching blades."""
    clump = builder.group()
    tones = (GRASS_DARK, GRASS, GRASS_LIGHT, GRASS_SUN)

    def blade(x, y, yaw, length, width, rise, droop, tone, phase):
        builder.blade(x, y, rng.uniform(-0.6, 1.0), yaw, length, width,
                      tone, rise=rise, droop=droop, width_end=0.28,
                      segments=3, group=clump, phase=phase, cross=True)

    # A dense, low button of broad blades gives the tuft a solid centre
    # before the longer arcs open out of it.
    for _ in range(9):
        yaw = rng.uniform(0, math.tau)
        reach = rng.uniform(0.4, 2.4)
        blade(32 + math.cos(yaw) * reach,
              16 + math.sin(yaw) * reach * 0.72, yaw,
              rng.uniform(8.0, 12.0), rng.uniform(3.4, 4.4),
              rng.uniform(3.0, 8.0), rng.uniform(1.0, 3.5),
              rng.choice((GRASS, GRASS_LIGHT)),
              rng.uniform(0, math.tau))

    # The low skirt: wide blades that fall away from the tuft's crown.
    for i in range(20):
        yaw = math.tau * i / 20 + rng.uniform(-0.16, 0.16)
        reach = rng.uniform(1.8, 4.6)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(tones, dx, dy, -0.1, rng, jitter=0.16)
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(12.0, 18.0), rng.uniform(3.0, 4.0),
              rng.uniform(14.0, 19.0), rng.uniform(5.0, 9.0), tone,
              rng.uniform(0, math.tau))

    # The heart of the tuft: short upright blades that close the gap between
    # the spreading skirt and keep the tussock from reading as loose wires.
    for _ in range(16):
        yaw = rng.uniform(0, math.tau)
        reach = rng.uniform(0.2, 2.0)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = (GRASS_LIGHT if rng.random() < 0.55 else GRASS_SUN)
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(6.0, 11.0), rng.uniform(2.8, 3.6),
              rng.uniform(4.0, 12.0), rng.uniform(2.0, 5.0), tone,
              rng.uniform(0, math.tau))

    # The fountain: tall arcs rising between the skirt blades.
    for i in range(18):
        yaw = math.tau * i / 18 * 1.7 + 0.5 + rng.uniform(-0.2, 0.2)
        reach = rng.uniform(0.6, 2.6)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(tones, dx, dy, 0.35, rng, jitter=0.16)
        if rng.random() < 0.18:
            tone = STRAW_LIGHT if rng.random() < 0.5 else STRAW
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(10.0, 15.0), rng.uniform(2.6, 3.4),
              rng.uniform(26.0, 32.0), rng.uniform(10.0, 15.0), tone,
              rng.uniform(0, math.tau))

    # A few tall flag blades lift the crown of the tussock.
    for _ in range(6):
        yaw = rng.uniform(0, math.tau)
        blade(32 + math.cos(yaw) * rng.uniform(0.4, 1.6),
              16 + math.sin(yaw) * rng.uniform(0.4, 1.2), yaw,
              rng.uniform(9.0, 13.0), rng.uniform(2.4, 3.0),
              rng.uniform(32.0, 38.0), rng.uniform(16.0, 22.0),
              rng.choice((GRASS_LIGHT, GRASS_SUN)),
              rng.uniform(0, math.tau))

    # A bright apron of short blades at the front hides the shadowed base.
    for _ in range(8):
        yaw = math.pi * 0.5 + rng.uniform(-1.2, 1.2)
        reach = rng.uniform(2.0, 4.5)
        dx, dy = math.cos(yaw), math.sin(yaw)
        blade(32 + dx * reach, 16 + dy * reach * 0.8, yaw,
              rng.uniform(5.0, 9.0), rng.uniform(2.8, 3.6),
              rng.uniform(3.0, 7.0), rng.uniform(1.0, 3.0),
              GRASS_LIGHT if rng.random() < 0.5 else GRASS_SUN,
              rng.uniform(0, math.tau))

    # Seed stalks: fine stems with a slim, beaded head that catches the sun.
    for _ in range(7):
        yaw = rng.uniform(0, math.tau)
        base = (32 + math.cos(yaw) * rng.uniform(0.8, 3.0),
                16 + math.sin(yaw) * rng.uniform(0.6, 2.4), 0.0)
        top_z = rng.uniform(28.0, 37.0)
        top = (base[0] + math.cos(yaw) * rng.uniform(3.0, 6.0),
               base[1] + math.sin(yaw) * rng.uniform(2.0, 4.0), top_z)
        builder.limb(base, top, 0.45, 0.24, GRASS_DARK, segments=4,
                     group=clump, cap=False)
        for k in range(2):
            t = 0.88 + 0.12 * k
            builder.blob(base[0] + (top[0] - base[0]) * t,
                         base[1] + (top[1] - base[1]) * t,
                         base[2] + (top[2] - base[2]) * t
                         + rng.uniform(-0.3, 0.3),
                         0.85, 0.85, 1.5,
                         STRAW_LIGHT if k else STRAW,
                         ao_base=0.94, segments=5, rings=3,
                         group=clump, wobble=0.12, phase=k * 1.7)


def draw_heather(builder: TreeBuilder, rng) -> None:
    """A heather cushion: fine dark foliage under a haze of purple spikes."""
    cushion = builder.group()
    heather_tones = (HEATHER_LEAF_DARK, HEATHER_LEAF, HEATHER_LEAF_LIGHT,
                     HEATHER_LEAF_LIGHT)
    shrub_canopy(builder, (32, 16, 7.0), (15.0, 12.0, 6.5),
                 heather_tones, rng, group=cushion, count=42,
                 cluster=2.6, tips=16, tip_size=1.05, ao=0.64,
                 underside=2, bias=-0.10, fillers=2)
    # Two low shoulders break the cushion into an irregular mound.
    for sx, sy, sz, rx, ry, rz in ((-8.5, 3.0, 6.0, 7.5, 5.5, 4.5),
                                   (8.0, -2.5, 6.5, 7.0, 5.0, 4.0)):
        shrub_canopy(builder, (32 + sx, 16 + sy, sz), (rx, ry, rz),
                     heather_tones, rng, group=cushion, count=14,
                     cluster=2.4, tips=6, tip_size=1.0, ao=0.66,
                     underside=1, bias=-0.08, fillers=1)
    tones = (HEATHER_BLOOM_DARK, HEATHER_BLOOM, HEATHER_BLOOM_LIGHT,
             HEATHER_BLOOM_SUN)
    # Bloom spikes: a stem carries a ladder of little bells, pale at the tip.
    sprays = 24
    for i in range(sprays):
        yaw = math.tau * i / sprays * 3.7 + rng.uniform(-0.30, 0.30)
        reach = rng.uniform(0.5, 11.5)
        x = 32 + math.cos(yaw) * reach
        y = 16 + math.sin(yaw) * reach * 0.78
        base_z = rng.uniform(6.0, 10.0)
        height = rng.uniform(4.0, 10.0)
        tip_x = x + math.cos(yaw) * rng.uniform(0.2, 1.2)
        tip_y = y + math.sin(yaw) * rng.uniform(0.2, 1.2)
        builder.limb((x, y, base_z), (tip_x, tip_y, base_z + height),
                     0.28, 0.16, HEATHER_LEAF_DARK, segments=3,
                     group=cushion, cap=False)
        count = 4
        for k in range(count):
            t = 0.35 + 0.65 * (k + 1) / count
            bx = x + (tip_x - x) * t + rng.uniform(-0.35, 0.35)
            by = y + (tip_y - y) * t + rng.uniform(-0.30, 0.30)
            bz = base_z + height * t + rng.uniform(-0.2, 0.3)
            tone = tones[min(3, int(t * 2.4 + rng.uniform(0, 0.9)))]
            builder.blob(bx, by, bz, rng.uniform(0.95, 1.30),
                         rng.uniform(0.90, 1.20), rng.uniform(0.75, 1.05),
                         tone, ao_base=0.94, segments=5, rings=3,
                         group=cushion, wobble=0.2, phase=yaw * 2.0 + k)
    # Low sprays fray the rim into individual shoots.
    for _ in range(7):
        a = rng.uniform(0, math.tau)
        builder.leaf_tuft(32 + math.cos(a) * rng.uniform(10.0, 14.0),
                          16 + math.sin(a) * rng.uniform(8.0, 11.0),
                          rng.uniform(1.5, 4.0), HEATHER_LEAF_LIGHT, rng,
                          size=1.3, spread=1.0, group=cushion, count=2)
    # A handful of taller sprigs lift the silhouette out of a flat dome.
    for _ in range(6):
        yaw = rng.uniform(0, math.tau)
        x = 32 + math.cos(yaw) * rng.uniform(2.0, 9.0)
        y = 16 + math.sin(yaw) * rng.uniform(1.5, 7.0)
        builder.limb((x, y, 10.0), (x, y, rng.uniform(15.0, 19.0)),
                     0.24, 0.12, HEATHER_LEAF_DARK, segments=3,
                     group=cushion, cap=False)
        for k in range(2):
            builder.blob(x + rng.uniform(-0.3, 0.3),
                         y + rng.uniform(-0.3, 0.3),
                         rng.uniform(14.5, 18.0) + k * 0.5,
                         rng.uniform(1.0, 1.4), rng.uniform(1.0, 1.4),
                         rng.uniform(0.8, 1.1), HEATHER_BLOOM_LIGHT,
                         ao_base=0.96, segments=5, rings=3,
                         group=cushion, wobble=0.2)


def draw_cattails(builder: TreeBuilder, rng) -> None:
    """A cattail clump: slender ribbon leaves framing chocolate-cigar heads."""
    clump = builder.group()
    leaf_tones = (CATTAIL_LEAF_DARK, CATTAIL_LEAF, CATTAIL_LEAF_LIGHT,
                  CATTAIL_LEAF_SUN)

    # Back leaves first: tall ribbons that make the clump's frame.
    for i in range(9):
        yaw = math.tau * i / 9 + rng.uniform(-0.2, 0.2)
        reach = rng.uniform(0.8, 3.2)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(leaf_tones, dx, dy, 0.45, rng, jitter=0.14)
        builder.blade(32 + dx * reach, 16 + dy * reach * 0.75,
                      rng.uniform(-0.4, 0.6), yaw,
                      rng.uniform(8.0, 14.0), rng.uniform(2.2, 3.0),
                      tone, rise=rng.uniform(31.0, 43.0),
                      droop=rng.uniform(10.0, 20.0), width_end=0.12,
                      segments=3, group=clump,
                      phase=rng.uniform(0, math.tau), cross=True)
    # Front leaves: shorter and wider, arching away over the waterline.
    for i in range(7):
        yaw = math.tau * i / 7 + 0.4 + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(2.0, 5.0)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(leaf_tones, dx, dy, 0.1, rng, jitter=0.16)
        if rng.random() < 0.14:
            tone = DEAD_FROND
        builder.blade(32 + dx * reach, 16 + dy * reach * 0.75,
                      0.0, yaw, rng.uniform(11.0, 18.0),
                      rng.uniform(2.4, 3.2), tone,
                      rise=rng.uniform(18.0, 29.0),
                      droop=rng.uniform(7.0, 15.0), width_end=0.14,
                      segments=3, group=clump,
                      phase=rng.uniform(0, math.tau), cross=True)
    # The heads: slender cigars on fine stalks, fanned apart above the leaves.
    for i in range(6):
        yaw = math.tau * i / 6 + rng.uniform(-0.45, 0.45) + 0.4
        reach = rng.uniform(2.2, 5.6)
        x = 32 + math.cos(yaw) * reach
        y = 16 + math.sin(yaw) * reach * 0.8
        top_z = rng.uniform(34.0, 45.0) + i * 0.7
        lean_x = math.cos(yaw) * rng.uniform(0.4, 1.8)
        lean_y = math.sin(yaw) * rng.uniform(0.4, 1.4)
        head = rng.uniform(6.0, 8.0)
        stalk_material = CATTAIL_LEAF_DARK if i % 2 else CATTAIL_LEAF
        builder.limb((x, y, 0.0), (x + lean_x, y + lean_y, top_z),
                     0.55, 0.32, stalk_material, segments=4, group=clump,
                     cap=False)
        builder.cylinder(x + lean_x, y + lean_y, top_z - head, top_z, 1.25,
                         CATTAIL_HEAD, segments=7, cap=True, group=clump)
        builder.blob(x + lean_x, y + lean_y, top_z - 0.2, 1.2, 1.2, 0.8,
                     CATTAIL_HEAD_LIGHT, ao_base=0.94, segments=5,
                     rings=3, group=clump)
        builder.limb((x + lean_x, y + lean_y, top_z),
                     (x + lean_x * 1.25, y + lean_y * 1.25,
                      top_z + rng.uniform(3.0, 5.0)),
                     0.3, 0.1, CATTAIL_HEAD_LIGHT, segments=4,
                     group=clump, cap=False)
    # Two dried blades have fallen over at the water's edge.
    for _ in range(2):
        yaw = rng.uniform(0, math.tau)
        builder.blade(32 + math.cos(yaw) * rng.uniform(1.0, 3.0),
                      16 + math.sin(yaw) * rng.uniform(1.0, 2.5),
                      0.0, yaw, rng.uniform(10.0, 16.0),
                      rng.uniform(1.6, 2.2), DEAD_FROND,
                      rise=rng.uniform(7.0, 14.0),
                      droop=rng.uniform(8.0, 15.0),
                      width_end=0.18, segments=3, group=clump)
    for _ in range(2):
        yaw = rng.uniform(0, math.tau)
        builder.pebble(32 + math.cos(yaw) * rng.uniform(5.0, 8.0),
                       16 + math.sin(yaw) * rng.uniform(4.0, 6.5), 0.0,
                       rng.uniform(1.8, 2.6),
                       STONE_PEBBLE if rng.random() < 0.6
                       else STONE_PEBBLE_DARK)


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
