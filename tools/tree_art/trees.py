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
  scalloped spire, the birch's airy clump, the palm's radial crown.
* **One light.**  The renderer's sun (``render.SUN``, +x / -y / up) is the only
  light.  Foliage is chosen in four tones - deep shadow, mass, lit face and a
  warm sun rim - by where a cluster sits on the crown, so the canopy shades
  itself consistently in every species.
* **Leaf-scale detail.**  Crowns are clouds of small clusters (2-7 world px),
  each dappled with the ``leaf_fine`` surface pattern; a scalloped ring of
  little leaf tufts breaks every silhouette.  The cluster, not the species,
  sets the detail scale, so a 20 px heather cushion and a 75 px oak carry the
  same visual grain.
* **Wood shows.**  A root-flared, tapered trunk and real forking limbs carry the
  canopy.  Bark is bark, not a brown post: vertical ridges, warm lit side,
  shadowed lee.
* **Four drawings, one tree.**  The four view variants are independent seeded
  drawings of the species (``variant_seed()``), not rotations: a wood wears
  several different trees at once and they share one sun.

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
BIRCH_BARK = mat(C("f4f3e7"), "birch", emissive=0.12)
BIRCH_BARK_SHADE = mat(C("d2d0bc"), "birch", emissive=0.06)
DEAD_BARK = mat(C("9a8a78"), "bark")
DEAD_BARK_DARK = mat(C("74685a"), "bark")
DEAD_BARK_LIGHT = mat(C("c2b29c"), "bark")
PALM_BARK = mat(C("b18e5f"), "bark")
PALM_BARK_DARK = mat(C("86653d"), "bark")
PALM_BARK_LIGHT = mat(C("d2b181"), "bark")
CACTUS_SKIN = mat(C("5b8a4e"), "bark")
CACTUS_SKIN_DARK = mat(C("3f6b3c"), "bark")
CACTUS_SKIN_LIGHT = mat(C("77a862"), "bark")

# Foliage: (deep shadow, mass, lit face, warm sun rim).  The rim is the tone
# that touches the sky on the sun side; it is what makes a wood glow.
OAK_LEAF_DARK = mat(C("2c5030"), "leaf_fine")
OAK_LEAF = mat(C("3d7038"), "leaf_fine")
OAK_LEAF_LIGHT = mat(C("58943f"), "leaf_fine")
OAK_LEAF_SUN = mat(C("8bc25d"), "leaf_fine")

MAPLE_LEAF_DARK = mat(C("74281d"), "leaf_fine")
MAPLE_LEAF = mat(C("a83a24"), "leaf_fine")
MAPLE_LEAF_LIGHT = mat(C("d2662b"), "leaf_fine")
MAPLE_LEAF_SUN = mat(C("d97a34"), "leaf_fine")

BIRCH_LEAF_DARK = mat(C("466d35"), "leaf_fine")
BIRCH_LEAF = mat(C("63954a"), "leaf_fine")
BIRCH_LEAF_LIGHT = mat(C("88bb5d"), "leaf_fine")
BIRCH_LEAF_SUN = mat(C("a6d07a"), "leaf_fine")

PINE_NEEDLE_DARK = mat(C("1c3a2e"), "needle")
PINE_NEEDLE = mat(C("2b5440"), "needle")
PINE_NEEDLE_LIGHT = mat(C("3d7552"), "needle")
PINE_NEEDLE_SUN = mat(C("619a68"), "needle")

PALM_FROND_DARK = mat(C("3a6b3a"), "leaf_fine", emissive=0.08)
PALM_FROND = mat(C("579348"), "leaf_fine", emissive=0.08)
PALM_FROND_LIGHT = mat(C("74b05a"), "leaf_fine", emissive=0.08)
PALM_FROND_SUN = mat(C("a0d37c"), "leaf_fine", emissive=0.08)
DEAD_FROND = mat(C("8f6f3f"), "reed")
DEAD_FROND_DARK = mat(C("6f5230"), "reed")

BUSH_LEAF_DARK = mat(C("2c5230"), "leaf_fine")
BUSH_LEAF = mat(C("3e763d"), "leaf_fine")
BUSH_LEAF_LIGHT = mat(C("5c9c4c"), "leaf_fine")
BUSH_LEAF_SUN = mat(C("8ec36c"), "leaf_fine")
BUSH_BERRY = mat(C("b34a58"), "flat")
BUSH_BERRY_LIGHT = mat(C("d8737c"), "flat")

GRASS_DARK = mat(C("6f7f33"), "reed")
GRASS = mat(C("94a544"), "reed")
GRASS_LIGHT = mat(C("bcc75e"), "reed")
GRASS_SUN = mat(C("deda84"), "reed")
STRAW = mat(C("c9b56f"), "reed")
STRAW_LIGHT = mat(C("e2d493"), "reed")

HEATHER_LEAF_DARK = mat(C("2b3d29"), "leaf_fine")
HEATHER_LEAF = mat(C("405634"), "leaf_fine")
HEATHER_LEAF_LIGHT = mat(C("566f42"), "leaf_fine")
HEATHER_BLOOM_DARK = mat(C("783770"), "bloom")
HEATHER_BLOOM = mat(C("a64f91"), "bloom")
HEATHER_BLOOM_LIGHT = mat(C("c96eae"), "bloom")
HEATHER_BLOOM_SUN = mat(C("e79bc8"), "bloom")

CATTAIL_LEAF_DARK = mat(C("365c33"), "reed")
CATTAIL_LEAF = mat(C("4f7c40"), "reed")
CATTAIL_LEAF_LIGHT = mat(C("6f9f55"), "reed")
CATTAIL_LEAF_SUN = mat(C("93bd6d"), "reed")
CATTAIL_HEAD_DARK = mat(C("5a3a1d"), "reed")
CATTAIL_HEAD = mat(C("7d5228"), "reed")
CATTAIL_HEAD_LIGHT = mat(C("a06d36"), "reed")

FLOWER_PINK = mat(C("d95f8c"), "bloom")
FLOWER_PINK_LIGHT = mat(C("f095b5"), "bloom")
CACTUS_SPINE = mat(C("e8e2b8"), "flat")
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
              dark=None) -> None:
        """The root flare: a widened collar and toes reaching into the turf."""
        gid = self.m.group() if group is None else group
        dark = material if dark is None else dark
        self.limb((x, y, z - 2.0), (x, y, z + radius * 1.15),
                  radius * 1.4, radius * 0.9, material, segments=9,
                  group=gid)
        for i in range(count):
            yaw = math.tau * i / count + rng.uniform(-0.4, 0.4)
            reach = radius * rng.uniform(1.25, 1.9)
            tip = (x + math.cos(yaw) * reach,
                   y + math.sin(yaw) * reach * 0.8, z - 1.8)
            self.limb((x, y, z + radius * 0.7), tip,
                      radius * 0.55, radius * 0.12,
                      dark if i % 2 else material, segments=5, group=gid)

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
                      spine_mat=None) -> None:
        """A cactus column: a shaded core with raised, sun-caught ribs."""
        gid = self.m.group() if group is None else group
        self.cylinder(x, y, z0, z1, radius * 0.88, mid, segments=12,
                      cap=False, group=gid)
        for i in range(ribs):
            yaw = math.tau * i / ribs
            dx, dy = math.cos(yaw), math.sin(yaw)
            band = tone_for((dark, mid, light, light), dx, dy, 0.0,
                            rng or _NullRng(), jitter=0.0)
            rx, ry = x + dx * radius * 0.78, y + dy * radius * 0.78
            self.limb((rx, ry, z0), (rx, ry, z1), radius * 0.26,
                      radius * 0.21, band, segments=4, group=gid,
                      cap=False)
        self.blob(x, y, z1, radius, radius * 0.98, radius * 0.8,
                  light, ao_base=0.86, segments=9, rings=4, group=gid,
                  wobble=0.05)
        if spines and rng is not None:
            # Pale spines stand along the rib crests in short rows - the
            # detail that makes a cactus read as a cactus at 1 px.
            spine_mat = light if spine_mat is None else spine_mat
            for rib in range(ribs):
                yaw = math.tau * rib / ribs
                for k in range(spines):
                    z = z0 + (z1 - z0) * (0.12 + 0.76 * k / max(1, spines - 1))
                    z += rng.uniform(-0.8, 0.8)
                    self.blob(x + math.cos(yaw) * radius * 0.94,
                              y + math.sin(yaw) * radius * 0.94, z,
                              0.8, 0.8, 0.55, spine_mat, ao_base=0.97,
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
           shell=0.9, tip_size=1.35, bias=0.0, spread=1.0) -> None:
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
        rad = cluster * rng.uniform(0.70, 1.12)
        if abs(dz) < 0.35:
            rad *= 1.08
        tone = tone_for(tones, dx, dy, dz, rng,
                        bias=bias - (0.12 if f < 0.55 else 0.0))
        builder.blob(ox, oy, oz, rad * rng.uniform(0.9, 1.12),
                     rad * rng.uniform(0.82, 1.02),
                     rad * rng.uniform(0.72, 0.94), tone,
                     ao_base=ao, segments=8, rings=5, group=gid,
                     wobble=0.12, phase=a * 1.7)
        if dz > 0.32:
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
                           (-0.42, -0.10, 0.36, 0.80)):
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
    lean = rng.uniform(-2.2, 2.2)
    builder.roots(32, 16, 0.0, 5.4, BARK, rng, count=4,
                  group=trunk, dark=BARK_DARK)
    fork = (32 + lean * 0.5, 16, rng.uniform(21.0, 25.0))
    builder.taper_path([(32, 16, 0.5), (32 + lean * 0.25, 16, fork[2] * 0.55),
                        fork], 6.2, 4.5, BARK, group=trunk, segments=9,
                       ao0=0.78, ao1=0.94)
    # Four heavy boughs, two reaching wide and two lifting into the crown.
    boughs = ((-0.95, 0.55, 17.0, 13.0), (0.98, 0.45, 18.0, 12.0),
              (-0.35, -0.9, 14.0, 16.0), (0.55, -0.75, 15.0, 15.0))
    for bx, by, reach, lift in boughs:
        end = (fork[0] + bx * reach, fork[1] + by * reach * 0.7,
               fork[2] + lift)
        builder.limb(fork, end, 3.4, 1.5, BARK, segments=6, group=trunk)
        builder.gnarl(end, math.atan2(by, bx), rng.uniform(0.7, 1.0),
                      rng.uniform(8.0, 12.0), 1.5, BARK_LIGHT, 1, rng,
                      group=trunk, light=BARK_WARM)
    # One old oak is three cloud-lobes: a high dome and two lower shoulders.
    # Each variant stands a little differently, so the four drawings are
    # independently sized as well as independently shaped.
    lift = (0.0, 1.5, 0.7, 2.2)[getattr(builder, "variant", 0) % 4]
    crown = builder.group()
    shrub_canopy(builder, (31.0 + lean, 16.0, 53.0 + lift), (46.0, 21.0, 13.5),
                 (OAK_LEAF_DARK, OAK_LEAF, OAK_LEAF_LIGHT, OAK_LEAF_SUN),
                 rng, group=crown, count=48, cluster=5.8, tips=24,
                 ao=0.70)
    shoulder_a = builder.group()
    shrub_canopy(builder, (9.0, 14.0, 43.5 + lift), (18.0, 10.0, 10.0),
                 (OAK_LEAF_DARK, OAK_LEAF, OAK_LEAF_LIGHT, OAK_LEAF_SUN),
                 rng, group=shoulder_a, count=18, cluster=4.7, tips=11,
                 ao=0.68, underside=2)
    shoulder_b = builder.group()
    shrub_canopy(builder, (53.0, 17.0, 45.0 + lift), (19.0, 10.5, 10.5),
                 (OAK_LEAF_DARK, OAK_LEAF, OAK_LEAF_LIGHT, OAK_LEAF_SUN),
                 rng, group=shoulder_b, count=19, cluster=4.7, tips=12,
                 ao=0.68, underside=2)


def draw_maple(builder: TreeBuilder, rng) -> None:
    """A maple: a slim upright trunk under a rounded crown of ember lobes."""
    trunk = builder.group()
    lean = rng.uniform(-1.5, 1.5)
    builder.roots(32, 16, 0.0, 4.3, BARK_DARK, rng, count=3,
                  group=trunk, dark=BARK_DARK)
    fork = (32 + lean, 16, rng.uniform(25.0, 29.0))
    builder.taper_path([(32, 16, 0.5), (32 + lean * 0.4, 16, 13.0), fork],
                       4.5, 3.1, BARK_DARK, group=trunk, segments=8,
                       ao0=0.78, ao1=0.92)
    for i in range(4):
        yaw = math.tau * i / 4 + rng.uniform(-0.45, 0.45)
        end = (fork[0] + math.cos(yaw) * rng.uniform(7.0, 10.5),
               fork[1] + math.sin(yaw) * rng.uniform(5.5, 8.0),
               fork[2] + rng.uniform(6.0, 11.0))
        builder.limb(fork, end, 2.2, 1.1, BARK_DARK, segments=5,
                     group=trunk)
        builder.gnarl(end, yaw, rng.uniform(0.8, 1.05),
                      rng.uniform(5.0, 7.5), 1.0, BARK_DARK, 1, rng,
                      group=trunk, light=BARK_LIGHT)
    crown = builder.group()
    shrub_canopy(builder, (32 + lean, 16, 50.0), (36.0, 16.5, 18.5),
                 (MAPLE_LEAF_DARK, MAPLE_LEAF, MAPLE_LEAF_LIGHT,
                  MAPLE_LEAF_SUN), rng, group=crown, count=52, cluster=4.5,
                 tips=26, ao=0.70)
    # Two lower side lobes tucked under the main crown give the maple its
    # broad, rounded-in-shoulders look without breaking into separate balls.
    for side in (-1.0, 1.0):
        lobe = builder.group()
        shrub_canopy(builder, (32 + lean + side * 17.0, 16 + side * 2.0,
                               43.5), (14.0, 8.0, 9.5),
                     (MAPLE_LEAF_DARK, MAPLE_LEAF, MAPLE_LEAF_LIGHT,
                      MAPLE_LEAF_SUN), rng, group=lobe, count=14,
                     cluster=4.0, tips=8, ao=0.68, underside=2)


def draw_birch(builder: TreeBuilder, rng) -> None:
    """A birch: a clump of white paper trunks under an airy, broken crown."""
    stems = 3
    crown_groups = []
    for stem in range(stems):
        trunk = builder.group()
        base_x = 32 + (stem - 1) * 6.0 + rng.uniform(-2.0, 2.0)
        base_y = 16 - (stem - 1) * 4.0 + rng.uniform(-1.6, 1.6)
        lean = (stem - 1) * rng.uniform(3.0, 6.5) + rng.uniform(-1.5, 1.5)
        height = rng.uniform(37.0, 45.0)
        builder.roots(base_x, base_y, 0.0, 2.3, BIRCH_BARK, rng, count=3,
                      group=trunk, dark=BIRCH_BARK_SHADE)
        top = (base_x + lean, base_y + rng.uniform(-1.5, 1.5), height)
        points = [(base_x, base_y, 0.5),
                  (base_x + lean * 0.25, base_y + lean * 0.05,
                   height * 0.36),
                  (base_x + lean * 0.62, base_y + lean * 0.1,
                   height * 0.72),
                  top]
        builder.taper_path(points, 2.5, 0.75, BIRCH_BARK, group=trunk,
                           segments=7, ao0=0.8, ao1=0.95)
        # The birch pattern paints the dark lenticel bars; a couple of small
        # branch scars add depth without fighting those markings.
        for _ in range(2):
            z = rng.uniform(height * 0.25, height * 0.7)
            a = rng.uniform(0, math.tau)
            rr = 2.0 * (1.0 - 0.55 * z / height)
            builder.blob(base_x + lean * (z / height) + math.cos(a) * rr,
                         base_y + math.sin(a) * rr, z, 0.8, 0.7, 0.5,
                         BIRCH_BARK_SHADE, ao_base=0.95, segments=5,
                         rings=3, group=trunk)
        # Thin, upward branches reaching into the crown.
        for k in range(3):
            yaw = math.tau * k / 3 + rng.uniform(-0.5, 0.5)
            start_z = height * rng.uniform(0.55, 0.82)
            start = (base_x + lean * (start_z / height),
                     base_y + rng.uniform(-0.6, 0.6), start_z)
            end = (start[0] + math.cos(yaw) * rng.uniform(7.0, 11.0),
                   start[1] + math.sin(yaw) * rng.uniform(5.0, 8.0),
                   start_z + rng.uniform(12.0, 19.0))
            builder.limb(start, end, 1.0, 0.3, BIRCH_BARK_SHADE,
                         segments=4, group=trunk)
            # One thinner fork per branch, so the crown is held by twigs.
            fork_yaw = yaw + rng.choice((-0.6, 0.6))
            builder.limb(end, (end[0] + math.cos(fork_yaw) * rng.uniform(4.0, 7.0),
                               end[1] + math.sin(fork_yaw) * rng.uniform(3.0, 5.0),
                               end[2] + rng.uniform(3.0, 6.0)),
                         0.45, 0.16, BIRCH_BARK_SHADE, segments=3,
                         group=trunk, cap=False)
        # The crown is three loose clouds, with sky between their edges: that
        # airiness is what makes a birch a birch.
        crown = builder.group()
        crown_groups.append(crown)
        shrub_canopy(builder, (top[0], top[1], height + 15.0),
                     (17.0, 9.5, 12.0),
                     (BIRCH_LEAF_DARK, BIRCH_LEAF, BIRCH_LEAF_LIGHT,
                      BIRCH_LEAF_SUN), rng, group=crown, count=20,
                     cluster=3.9, tips=12, ao=0.72, underside=2)
        side = rng.choice((-1.0, 1.0))
        lobe = builder.group()
        crown_groups.append(lobe)
        shrub_canopy(builder, (top[0] + side * rng.uniform(8.0, 13.0),
                               top[1] + rng.uniform(-3.0, 3.0),
                               height + rng.uniform(8.0, 14.0)),
                     (10.0, 7.0, 8.5),
                     (BIRCH_LEAF_DARK, BIRCH_LEAF, BIRCH_LEAF_LIGHT,
                      BIRCH_LEAF_SUN), rng, group=lobe, count=11,
                     cluster=3.4, tips=7, ao=0.72, underside=1)


def draw_pine(builder: TreeBuilder, rng) -> None:
    """A conifer: a straight bole under scalloped tiers of drooping boughs."""
    trunk = builder.group()
    builder.roots(32, 16, 0.0, 4.2, BARK_DARK, rng, count=3,
                  group=trunk, dark=BARK_DARK)
    builder.taper_path([(32, 16, 0.5), (32, 16, 24.0), (32, 16, 60.0)],
                       4.6, 0.9, BARK_DARK, group=trunk, segments=8,
                       ao0=0.76, ao1=0.95)
    tones = (PINE_NEEDLE_DARK, PINE_NEEDLE, PINE_NEEDLE_LIGHT,
             PINE_NEEDLE_SUN)
    tiers = 4
    base_z = 12.0
    for tier in range(tiers):
        t = tier / (tiers - 1.0)
        radius = 21.0 * (1.0 - 0.58 * t) * rng.uniform(0.96, 1.04)
        z0 = base_z + tier * 11.0
        layer = builder.group()
        boughs = 6
        for k in range(boughs):
            yaw = math.tau * k / boughs + rng.uniform(-0.18, 0.18) \
                + tier * 0.30
            dx, dy = math.cos(yaw), math.sin(yaw)
            tone = tone_for(tones, dx, dy, 0.2 if tier > 1 else 0.0,
                            rng, jitter=0.04)
            lit = tone_for(tones, dx, dy, 0.8, rng, jitter=0.03)
            # A bough is a run of overlapping, flattened leaf pads stepping
            # outward and drooping at the tip, so each tier ends in a
            # continuous scalloped edge rather than a string of beads.
            for step in range(3):
                q = (step + 1) / 3.0
                dist = radius * (0.22 + 0.78 * q)
                pad_w = radius * (0.48 - 0.17 * q)
                pad_r = radius * (0.32 - 0.09 * q)
                builder.blob(32 + dx * dist, 16 + dy * dist,
                             z0 - 2.8 * q * q + rng.uniform(-0.3, 0.3),
                             pad_w, pad_r, radius * 0.15,
                             tone, ao_base=0.70, segments=7, rings=4,
                             group=layer, yaw=yaw, tilt=-0.42,
                             wobble=0.12, phase=yaw + step)
                builder.blob(32 + dx * dist, 16 + dy * dist,
                             z0 + 1.1 - 2.8 * q * q,
                             pad_w * 0.62, pad_r * 0.52,
                             radius * 0.10, PINE_NEEDLE_LIGHT,
                             ao_base=0.80,
                             segments=6, rings=3, group=layer,
                             yaw=yaw, tilt=-0.28, wobble=0.14,
                             phase=yaw * 2.0 + step)
            # A dark needle pad under the bough gives it depth.
            builder.blob(32 + dx * radius * 0.62,
                         16 + dy * radius * 0.62, z0 - 3.6,
                         radius * 0.32, radius * 0.26, radius * 0.10,
                         PINE_NEEDLE_DARK, ao_base=0.68, segments=6,
                         rings=3, group=layer, yaw=yaw, tilt=-0.36,
                         wobble=0.16, phase=yaw * 3.0)
            # Needle tips hanging off the bough's rim.
            for _ in range(2):
                d = radius * rng.uniform(0.92, 1.05)
                builder.blob(32 + dx * d + rng.uniform(-0.8, 0.8),
                             16 + dy * d + rng.uniform(-0.8, 0.8),
                             z0 - rng.uniform(2.2, 3.8),
                             radius * 0.13, radius * 0.12,
                             radius * 0.09, tone, ao_base=0.84,
                             segments=5, rings=3, group=layer,
                             wobble=0.28, phase=yaw * 3.0)
        # A broad central pad closes the middle of each tier.
        builder.blob(32, 16, z0 + radius * 0.06, radius * 0.60,
                     radius * 0.54, radius * 0.24,
                     tone_for(tones, 0.0, -0.2, 0.8, rng, jitter=0.02),
                     ao_base=0.78, segments=8, rings=4, group=layer,
                     wobble=0.1, phase=tier)
    # The leader: one tapered spire, its edge broken by small needle tufts.
    top = builder.group()
    builder.cone(32, 16, 46.5, 69.5, 6.2, PINE_NEEDLE_LIGHT,
                 segments=9, cap=False, group=top)
    for i in range(7):
        t = i / 6.0
        z = 48.0 + 19.0 * t
        a = math.tau * i * 0.37 + 0.4
        reach = (5.6 * (1.0 - t) + 0.8) * 0.8
        builder.blob(32 + math.cos(a) * reach,
                     16 + math.sin(a) * reach * 0.85, z,
                     1.9 * (1.0 - 0.5 * t) + 0.5,
                     1.7 * (1.0 - 0.5 * t) + 0.5,
                     2.1 * (1.0 - 0.5 * t) + 0.4,
                     PINE_NEEDLE_SUN if i % 2 else PINE_NEEDLE_LIGHT,
                     ao_base=0.85, segments=6, rings=3, group=top,
                     wobble=0.18, phase=i * 1.4)
    for i in range(3):
        yaw = rng.uniform(0, math.tau)
        builder.limb((32, 16, 2.0),
                     (32 + math.cos(yaw) * 6.0,
                      16 + math.sin(yaw) * 6.0, -0.8),
                     2.2, 1.0, BARK_DARK, segments=5, group=trunk)


def draw_palm(builder: TreeBuilder, rng) -> None:
    """A coconut palm: a ringed leaning trunk under a radial feathered crown."""
    trunk = builder.group()
    lean = rng.uniform(-5.0, 5.0)
    height = rng.uniform(43.0, 48.0)
    builder.roots(32, 16, 0.0, 3.8, PALM_BARK_DARK, rng, count=3,
                  group=trunk, dark=PALM_BARK_DARK)
    points = [(32, 16, -0.5),
              (32 + lean * 0.10, 16, height * 0.28),
              (32 + lean * 0.38, 16, height * 0.56),
              (32 + lean * 0.78, 16, height * 0.82),
              (32 + lean, 16, height)]
    for i in range(len(points) - 1):
        t0 = i / (len(points) - 1)
        t1 = (i + 1) / (len(points) - 1)
        builder.limb(points[i], points[i + 1], 4.3 * (1.0 - 0.55 * t0),
                     4.3 * (1.0 - 0.55 * t1), PALM_BARK,
                     segments=8, group=trunk)
        joint = points[i + 1]
        # The raised leaf-scar ring that runs round a palm's trunk: a thin
        # darker band, not a bamboo joint.
        builder.limb((joint[0], joint[1], joint[2] - 0.55),
                     (joint[0], joint[1], joint[2] + 0.55),
                     4.3 * (1.0 - 0.55 * t1) * 1.06,
                     4.3 * (1.0 - 0.55 * t1) * 1.06,
                     PALM_BARK_DARK, segments=8, group=trunk)
    top = points[-1]
    # The crown is three ranks of fronds: steep young feathers above, a broad
    # middle umbrella, and older feathers arching down.  Each rank is spaced
    # so sky shows between the fronds - a palm is a wheel, not a bush.
    tones = (PALM_FROND_DARK, PALM_FROND, PALM_FROND_LIGHT,
             PALM_FROND_SUN)
    ranks = (
        (3, 17.0, 20.0, 16.0, 20.0, 4.0, 6.0, 5, 4.2, 2.6),
        (5, 20.0, 24.0, 11.0, 15.0, 8.0, 11.0, 6, 4.8, 1.7),
        (4, 18.0, 22.0, 6.0, 9.0, 12.0, 16.0, 5, 4.4, 1.0),
    )
    yaw0 = rng.uniform(0, math.tau)
    for rank, (count, len0, len1, lift0, lift1, droop0, droop1,
               leaflets, width, tone_index) in enumerate(ranks):
        for i in range(count):
            yaw = yaw0 + math.tau * i / count + rank * 0.55 \
                + rng.uniform(-0.16, 0.16)
            tone = tones[min(3, int(tone_index + rng.uniform(0, 0.9)))]
            _palm_frond(builder, top[0], top[1], top[2] + 1.0, yaw,
                        rng.uniform(len0, len1), rng.uniform(lift0, lift1),
                        rng.uniform(droop0, droop1), tone, rng,
                        leaflets=leaflets, width=rng.uniform(width, width + 0.6),
                        tones=tones, bias=0.25 - rank * 0.08)
    # A couple of spear feathers fill the very centre of the wheel.
    for i in range(2):
        yaw = yaw0 + math.tau * i / 2 + rng.uniform(-0.3, 0.3)
        _palm_frond(builder, top[0], top[1], top[2] + 2.0, yaw,
                    rng.uniform(11.0, 14.0), rng.uniform(12.0, 15.0),
                    rng.uniform(2.0, 3.5), PALM_FROND_SUN, rng,
                    leaflets=4, width=3.8, tones=tones, bias=0.4)
    # One spent frond hangs brown and close to the trunk.
    _palm_frond(builder, top[0], top[1], top[2] - 1.2,
                yaw0 + math.pi * 0.55, 10.0, 1.0, 9.0,
                DEAD_FROND, rng, leaflets=3, width=2.0,
                tones=(DEAD_FROND_DARK, DEAD_FROND, DEAD_FROND,
                       DEAD_FROND))
    # Coconuts nestle where the fronds spring.
    for i in range(4):
        a = math.tau * i / 4 + rng.uniform(-0.3, 0.3)
        builder.blob(top[0] + math.cos(a) * 3.0,
                     top[1] + math.sin(a) * 2.4, top[2] - 3.0,
                     2.1, 2.1, 2.2, COCONUT if i % 2 else COCONUT_LIGHT,
                     ao_base=0.82, segments=6, rings=4, group=trunk,
                     wobble=0.1, phase=a)
    builder.blob(top[0], top[1], top[2] + 0.6, 3.4, 3.2, 2.4,
                 PALM_FROND_DARK, ao_base=0.72, segments=7, rings=4,
                 group=trunk, wobble=0.1)


def _palm_frond(builder: TreeBuilder, x, y, z, yaw, length, lift, droop,
                tone, rng, leaflets=9, width=3.6, tones=None,
                bias=0.0) -> None:
    """One feather: an arching rib combed with paired leaflet vanes.

    A palm leaflet is a small vertical fin, not a flat ribbon on the ground:
    the vane stands in the plane of its direction and the sky, so it catches
    the isometric light as a visible blade and the crown reads as feathers.
    """
    gid = builder.group()
    dx, dy = math.cos(yaw), math.sin(yaw)
    px, py = -dy, dx
    tones = tones or (tone, tone, tone, tone)

    def spine(t):
        return (x + dx * length * t, y + dy * length * t,
                z + lift * math.sin(min(1.0, t * 1.2) * math.pi * 0.72)
                - droop * t * t)

    previous = spine(0.0)
    for i in range(4):
        t = (i + 1) / 4.0
        point = spine(t)
        builder.limb(previous, point, 0.62 * (1.0 - i * 0.16),
                     0.62 * (1.0 - (i + 1) * 0.16),
                     tone, segments=4, group=gid, cap=False,
                     ao0=0.9, ao1=1.0)
        previous = point
    for i in range(leaflets):
        t = 0.14 + 0.80 * i / max(1, leaflets - 1)
        bx, by, bz = spine(t)
        reach = (6.8 - 2.2 * t) * rng.uniform(0.9, 1.05)
        for side in (-1.0, 1.0):
            wyaw = math.atan2(dy * 0.5 + side * py, dx * 0.5 + side * px)
            leaf_tone = tone_for(tones, math.cos(wyaw), math.sin(wyaw),
                                 0.25, rng, jitter=0.08,
                                 bias=bias + 0.18)
            _palm_leaflet(builder, bx, by, bz - 0.4, wyaw, reach,
                          width * (1.0 - 0.20 * t), leaf_tone, gid,
                          rise=rng.uniform(0.4, 1.4),
                          droop=rng.uniform(0.8, 2.0))
    terminal = spine(1.0)
    tip_yaw = math.atan2(dy, dx)
    _palm_leaflet(builder, terminal[0], terminal[1], terminal[2], tip_yaw,
                  length * 0.20, width * 0.85, tone, gid, rise=0.3,
                  droop=1.0)


def _palm_leaflet(builder: TreeBuilder, x, y, z, yaw, length, depth, tone,
                  group, rise=0.5, droop=1.2) -> None:
    """A pointed leaf vane standing in the vertical plane of its direction."""
    dx, dy = math.cos(yaw), math.sin(yaw)
    belly_x, belly_y = x + dx * length * 0.45, y + dy * length * 0.45
    top = (belly_x, belly_y, z + rise + depth * 0.55)
    bottom = (belly_x, belly_y, z + rise - depth * 0.45)
    tip = (x + dx * length, y + dy * length, z + rise - droop)
    builder.m.quad((x, y, z), top, tip, bottom, tone,
                   uvs=((0.0, 0.0), (depth, length * 0.45),
                        (depth * 0.2, length), (0.0, length * 0.45)),
                   ao=(0.9, 1.0, 1.0, 0.82), group=group)


def draw_dead_tree(builder: TreeBuilder, rng) -> None:
    """A dead tree: a forked skeleton, twisted limbs and fine bare twigs."""
    trunk = builder.group()
    lean = rng.uniform(-2.5, 2.5)
    builder.roots(32, 16, 0.0, 5.4, DEAD_BARK_DARK, rng, count=4,
                  group=trunk, dark=DEAD_BARK_DARK)
    fork = (32 + lean, 16, rng.uniform(13.0, 16.0))
    builder.taper_path([(32, 16, 0.5), (32 + lean * 0.4, 16, fork[2] * 0.5),
                        fork], 6.4, 4.4,
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
                    builder.limb(tip, (tip[0] + math.cos(twig_yaw)
                                       * rng.uniform(4.0, 7.0),
                                       tip[1] + math.sin(twig_yaw)
                                       * rng.uniform(3.0, 5.5),
                                       tip[2] + rng.uniform(1.0, 5.0)),
                                 0.9, 0.24, DEAD_BARK_LIGHT if rng.random()
                                 < 0.4 else DEAD_BARK, segments=4,
                                 group=trunk, cap=False)
    # A low limb reaches out sideways, dead before it ever carried a crown.
    low_yaw = split_yaw + math.pi * 0.5 + rng.uniform(-0.4, 0.4)
    low_end = (fork[0] + math.cos(low_yaw) * rng.uniform(13.0, 17.0),
               fork[1] + math.sin(low_yaw) * rng.uniform(10.0, 13.0),
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
    # Knots and old wounds on the trunk, dark as a hollow.
    for _ in range(2):
        z = rng.uniform(4.0, fork[2] - 2.0)
        a = rng.uniform(0, math.tau)
        builder.blob(32 + math.cos(a) * 4.4, 16 + math.sin(a) * 3.6, z,
                     1.7, 1.5, 2.1, DEAD_BARK_DARK, ao_base=0.88,
                     segments=6, rings=4, group=trunk, wobble=0.16)


def draw_cactus(builder: TreeBuilder, rng) -> None:
    """A saguaro: a ribbed column, raised arms, and a crown of pink bloom."""
    trunk = builder.group()
    builder.roots(32, 16, 0.0, 5.4, CACTUS_SKIN_DARK, rng, count=3,
                  group=trunk, dark=CACTUS_SKIN_DARK)
    column_top = rng.uniform(43.0, 47.0)
    builder.ribbed_column(32, 16, -1.0, column_top, 7.0,
                          CACTUS_SKIN_DARK, CACTUS_SKIN,
                          CACTUS_SKIN_LIGHT, ribs=9, group=trunk,
                          rng=rng, spines=6, spine_mat=CACTUS_SPINE)
    arm_count = rng.randint(2, 3)
    arm_yaws = (-0.62, 2.42, 1.15)
    for arm_index in range(arm_count):
        height = rng.uniform(16.0, 30.0)
        yaw = arm_yaws[arm_index] + rng.uniform(-0.18, 0.18)
        reach = rng.uniform(11.0, 14.5)
        elbow = (32 + math.cos(yaw) * reach,
                 16 + math.sin(yaw) * reach * 0.8, height)
        up = rng.uniform(12.0, 17.0)
        tip = (elbow[0] + math.cos(yaw) * 1.4,
               elbow[1] + math.sin(yaw) * 1.4, height + up)
        arm = builder.group()
        builder.limb((32, 16, height), elbow, 4.3, 3.9,
                     CACTUS_SKIN, segments=8, group=arm, cap=False)
        builder.limb(elbow, tip, 3.9, 3.4, CACTUS_SKIN, segments=8,
                     group=arm, cap=False)
        builder.ribbed_column(tip[0], tip[1], tip[2] - 2.5,
                              tip[2] + 2.0, 3.8, CACTUS_SKIN_DARK,
                              CACTUS_SKIN, CACTUS_SKIN_LIGHT, ribs=7,
                              group=arm, rng=rng, spines=4,
                              spine_mat=CACTUS_SPINE)
        # A little bloom at the arm's tip, as saguaros wear after rain.
        if rng.random() < 0.8:
            for k in range(3):
                a = math.tau * k / 3 + rng.uniform(-0.2, 0.2)
                builder.blob(tip[0] + math.cos(a) * 1.8,
                             tip[1] + math.sin(a) * 1.6,
                             tip[2] + 2.6, 1.5, 1.5, 1.2,
                             FLOWER_PINK if k % 2 else FLOWER_PINK_LIGHT,
                             ao_base=0.92, segments=5, rings=3, group=arm)
    # The crown flower: a small rose of pink petals on the column's apex.
    for i in range(6):
        a = math.tau * i / 6 + rng.uniform(-0.12, 0.12)
        builder.blob(32 + math.cos(a) * 2.8, 16 + math.sin(a) * 2.6,
                     column_top + 1.8, 2.4, 2.3, 1.8,
                     FLOWER_PINK_LIGHT if i % 2 else FLOWER_PINK,
                     ao_base=0.92, segments=5, rings=3, group=trunk)
    builder.blob(32, 16, column_top + 3.0, 2.2, 2.1, 1.8,
                 FLOWER_PINK, ao_base=0.94, segments=5, rings=3,
                 group=trunk)
    # Desert gravel at the foot, tying the cactus to the ground.
    for _ in range(3):
        a = rng.uniform(0, math.tau)
        builder.pebble(32 + math.cos(a) * rng.uniform(7.0, 10.0),
                       16 + math.sin(a) * rng.uniform(4.5, 7.5), 0.0,
                       rng.uniform(1.8, 2.8), STONE_PEBBLE)


def draw_bush(builder: TreeBuilder, rng) -> None:
    """A garden shrub: a scalloped mound of leaves, wide and low."""
    twig = builder.group()
    builder.roots(32, 16, 0.0, 2.2, BARK_DARK, rng, count=3, group=twig,
                  dark=BARK_DARK)
    for i in range(4):
        yaw = rng.uniform(0, math.tau)
        reach = rng.uniform(2.0, 6.0)
        builder.limb((32, 16, 0.0),
                     (32 + math.cos(yaw) * reach,
                      16 + math.sin(yaw) * reach, rng.uniform(4.0, 8.5)),
                     1.6, 0.7, BARK_DARK, segments=4, group=twig)
    crown = builder.group()
    shrub_canopy(builder, (32, 16, 13.0), (18.0, 14.0, 11.0),
                 (BUSH_LEAF_DARK, BUSH_LEAF, BUSH_LEAF_LIGHT,
                  BUSH_LEAF_SUN), rng, group=crown, count=30, cluster=4.3,
                 tips=20, ao=0.70, underside=2)
    # A few low leaf sprays trail onto the turf, so the mound is rooted.
    for _ in range(5):
        a = rng.uniform(0, math.tau)
        builder.leaf_tuft(32 + math.cos(a) * rng.uniform(11.0, 15.0),
                          16 + math.sin(a) * rng.uniform(8.0, 11.0),
                          rng.uniform(3.0, 6.5), BUSH_LEAF, rng,
                          size=2.2, spread=1.1, group=crown, count=2)
    # One variant in three carries a handful of berries.
    if rng.random() < 0.45:
        for _ in range(7):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(5.0, 12.0)
            builder.blob(32 + math.cos(a) * d,
                         16 + math.sin(a) * d * 0.8,
                         rng.uniform(12.0, 19.0), 1.1, 1.1, 1.1,
                         BUSH_BERRY_LIGHT if rng.random() < 0.4
                         else BUSH_BERRY, ao_base=0.94, segments=5,
                         rings=3, group=crown)


def draw_fescue(builder: TreeBuilder, rng) -> None:
    """A fescue tussock: a low skirt and a tall fountain of arching blades."""
    clump = builder.group()
    tones = (GRASS_DARK, GRASS, GRASS_LIGHT, GRASS_SUN)

    def blade(x, y, yaw, length, width, rise, droop, tone, phase):
        builder.blade(x, y, rng.uniform(-0.6, 1.0), yaw, length, width,
                      tone, rise=rise, droop=droop, width_end=0.14,
                      segments=3, group=clump, phase=phase, cross=True)

    # The low skirt: wide blades that fall away from the tuft's crown.
    for i in range(16):
        yaw = math.tau * i / 16 + rng.uniform(-0.16, 0.16)
        reach = rng.uniform(1.8, 4.6)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(tones, dx, dy, -0.1, rng, jitter=0.16)
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(14.0, 21.0), rng.uniform(2.4, 3.2),
              rng.uniform(13.0, 19.0), rng.uniform(7.0, 13.0), tone,
              rng.uniform(0, math.tau))

    # The heart of the tuft: short upright blades that close the gap between
    # the spreading skirt and keep the tussock from reading as loose wires.
    for _ in range(12):
        yaw = rng.uniform(0, math.tau)
        reach = rng.uniform(0.2, 2.0)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(tones, dx, dy, 0.1, rng, jitter=0.14)
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(6.0, 11.0), rng.uniform(2.6, 3.4),
              rng.uniform(4.0, 12.0), rng.uniform(2.0, 5.0), tone,
              rng.uniform(0, math.tau))

    # The fountain: tall arcs rising between the skirt blades.
    for i in range(14):
        yaw = math.tau * i / 14 * 1.7 + 0.5 + rng.uniform(-0.2, 0.2)
        reach = rng.uniform(0.6, 2.6)
        dx, dy = math.cos(yaw), math.sin(yaw)
        tone = tone_for(tones, dx, dy, 0.35, rng, jitter=0.16)
        if rng.random() < 0.18:
            tone = STRAW_LIGHT if rng.random() < 0.5 else STRAW
        blade(32 + dx * reach, 16 + dy * reach * 0.72, yaw,
              rng.uniform(11.0, 17.0), rng.uniform(2.2, 3.0),
              rng.uniform(25.0, 33.0), rng.uniform(13.0, 20.0), tone,
              rng.uniform(0, math.tau))

    # A few tall flag blades lift the crown of the tussock.
    for _ in range(5):
        yaw = rng.uniform(0, math.tau)
        blade(32 + math.cos(yaw) * rng.uniform(0.4, 1.6),
              16 + math.sin(yaw) * rng.uniform(0.4, 1.2), yaw,
              rng.uniform(10.0, 15.0), rng.uniform(2.0, 2.8),
              rng.uniform(34.0, 41.0), rng.uniform(20.0, 28.0),
              rng.choice((GRASS_LIGHT, GRASS_SUN)),
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
    """A heather cushion: fine dark foliage smothered in purple bloom."""
    cushion = builder.group()
    shrub_canopy(builder, (32, 16, 7.5), (15.0, 12.0, 7.0),
                 (HEATHER_LEAF_DARK, HEATHER_LEAF, HEATHER_LEAF_LIGHT,
                  HEATHER_LEAF_LIGHT), rng, group=cushion, count=24,
                 cluster=3.4, tips=12, ao=0.68, underside=2, bias=-0.2)
    tones = (HEATHER_BLOOM_DARK, HEATHER_BLOOM, HEATHER_BLOOM_LIGHT,
             HEATHER_BLOOM_SUN)
    # Bloom spikes: short stems carrying little clusters of bell flowers.
    sprays = 40
    for i in range(sprays):
        yaw = math.tau * i / sprays * 3.3 + rng.uniform(-0.25, 0.25)
        reach = rng.uniform(0.8, 11.0)
        x = 32 + math.cos(yaw) * reach
        y = 16 + math.sin(yaw) * reach * 0.78
        base_z = rng.uniform(6.0, 10.5)
        height = rng.uniform(3.0, 9.0)
        builder.limb((x, y, base_z), (x + math.cos(yaw) * 0.8,
                                      y + math.sin(yaw) * 0.8,
                                      base_z + height),
                     0.34, 0.24, HEATHER_LEAF_DARK, segments=3,
                     group=cushion, cap=False)
        tone = tone_for(tones, math.cos(yaw), math.sin(yaw), 0.4, rng,
                        jitter=0.2)
        for k in range(rng.randint(2, 3)):
            t = 0.42 + 0.58 * k / 2.0
            builder.blob(x + math.cos(yaw) * (0.8 * t + rng.uniform(-0.5, 0.5)),
                         y + math.sin(yaw) * (0.8 * t + rng.uniform(-0.5, 0.5)),
                         base_z + height * t + rng.uniform(-0.3, 0.4),
                         rng.uniform(1.1, 1.9), rng.uniform(1.1, 1.8),
                         rng.uniform(0.9, 1.5), tone if k < 2 else
                         HEATHER_BLOOM_SUN, ao_base=0.92, segments=5,
                         rings=3, group=cushion, wobble=0.2,
                         phase=yaw * 2.0 + k)
    # A few taller sprigs lift the silhouette out of a flat dome.
    for _ in range(6):
        yaw = rng.uniform(0, math.tau)
        x = 32 + math.cos(yaw) * rng.uniform(2.0, 9.0)
        y = 16 + math.sin(yaw) * rng.uniform(1.5, 7.0)
        builder.blob(x, y, rng.uniform(15.0, 19.0), 1.5, 1.4, 1.9,
                     HEATHER_BLOOM_LIGHT, ao_base=0.94, segments=5,
                     rings=3, group=cushion, wobble=0.2)


def draw_cattails(builder: TreeBuilder, rng) -> None:
    """A cattail clump: slender ribbon leaves framing chocolate-cigar heads."""
    clump = builder.group()
    leaf_tones = (CATTAIL_LEAF_DARK, CATTAIL_LEAF, CATTAIL_LEAF_LIGHT,
                  CATTAIL_LEAF_SUN)

    # Back leaves first: tall ribbons that make the clump's frame.
    for i in range(7):
        yaw = math.tau * i / 7 + rng.uniform(-0.2, 0.2)
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
    for i in range(5):
        yaw = math.tau * i / 5 + 0.4 + rng.uniform(-0.3, 0.3)
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
    for i in range(5):
        yaw = math.tau * i / 5 + rng.uniform(-0.45, 0.45) + 0.4
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
        builder.cylinder(x + lean_x, y + lean_y, top_z - head, top_z, 1.15,
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
