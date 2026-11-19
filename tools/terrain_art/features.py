#!/usr/bin/env python3
"""3D models for the Course Terrain tiles that wear a sprite.

Three painted tiles are objects rather than patterns: **Brush** (tangled gorse
scrub), **Rocks** (a slate scree outcrop) and **Boulder** (standing granite).
Like a tree's canopy, each is a real 3D model baked by
``tools/terrain_art/generate.py`` through the buildings' isometric renderer and
drawn over the ground its tile already paints, so the tiles share the woodland's
art direction: chunky pixel silhouettes, one warm sun from the upper right,
quantised shading and ink outlines.

Art direction
-------------
* **One light, one grain.**  Every stone facet and every leaf cluster takes its
  tone from the shared sun, and the models are built at leaf- and pebble-scale
  so a scree stone is textured like a canopy is.
* **Silhouette first.**  A scrub clump reads as a thorny bush at one pixel per
  world pixel; a boulder reads as a rounded standing stone with a broad sunlit
  crown and a dark lee; a scree field reads as scattered angular slabs, not
  gravel noise.
* **Grounded.**  Stones are set into the turf, scrub springs from woody stems,
  and each drawing keeps a little bare ground so the tile's own border and
  ground still show at the edges.
* **Four drawings, one feature.**  The four view variants are independent seeded
  drawings (see ``feature_seed()``), not rotations: neighbouring tiles wear
  different outcrops at once, exactly as a wood wears different trees.

Model space
-----------
A feature stands on the centre of its 1x1 tile at ``(32, 16, 0)`` in the same
world-pixel space the trees use (64 px across the tile, 32 px deep, z up).  The
model is not clipped to the diamond: a boulder's crown and a scrub bush's rim
spill over their tile's edge the way a canopy does, and the sprite is anchored
to the tile centre rather than to a trunk foot.
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "tree_art"))
sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "tools", "building_art"))

from render import C, mat  # noqa: E402  (paths set up above)
from trees import TreeBuilder, canopy, tone_for  # noqa: E402

#: The tile's centre, where every feature stands.
BASE_X, BASE_Y = 32.0, 16.0

#: The four view variants a feature can wear, matching
#: ``TerrainFeatureOverlay.FACINGS``.
VARIANT_COUNT = 4


def feature_seed(feature: str, variant: int) -> int:
    """A stable per-drawing seed: the same outcrop every time the tool runs."""
    return 0x5709 + variant * 104729 + sum(ord(c) for c in feature) * 53


# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------

# Slate: cool blue-grey stone with pale quartz, matching the tile's dark slate
# border.  Four tones, darkest in the lee, palest on the sunlit crown.
SLATE_DARK = mat(C("4a525e"), "gravel")
SLATE = mat(C("6b7482"), "gravel")
SLATE_LIGHT = mat(C("959fab"), "gravel")
SLATE_SUN = mat(C("b6c0ca"), "gravel")
SLATE_MOSS = mat(C("6c7663"), "gravel")
QUARTZ = mat(C("d9dde3"), "gravel", emissive=0.10)
QUARTZ_DIM = mat(C("aeb5bd"), "gravel")

# Granite: warm-grey standing rock with lichen on the crown.
GRANITE_DARK = mat(C("494c4a"), "gravel")
GRANITE = mat(C("6d726e"), "gravel")
GRANITE_LIGHT = mat(C("92968e"), "gravel")
GRANITE_SUN = mat(C("b6b5a6"), "gravel")
GRANITE_COOL = mat(C("6c7276"), "gravel")
LICHEN = mat(C("7d8c4d"), "bloom")
LICHEN_LIGHT = mat(C("a2b167"), "bloom")
LICHEN_PALE = mat(C("c6cf98"), "bloom")

# Gorse and scrub: four-tone foliage like a tree crown, with the tile's own
# gorse-ochre blossoms on the sunward tips.
GORSE_DARK = mat(C("293818"), "leaf_fine")
GORSE = mat(C("3d5524"), "leaf_fine")
GORSE_LIGHT = mat(C("577430"), "leaf_fine")
GORSE_SUN = mat(C("829e4a"), "leaf_fine")
BLOSSOM = mat(C("dec033"), "bloom")
BLOSSOM_LIGHT = mat(C("f3df6d"), "bloom")
SCRUB_TWIG = mat(C("4a3924"), "bark")
SCRUB_TWIG_DARK = mat(C("32261a"), "bark")
THORN = mat(C("6a5738"), "flat")

SLATE_TONES = (SLATE_DARK, SLATE, SLATE_LIGHT, SLATE_SUN)
GRANITE_TONES = (GRANITE_DARK, GRANITE, GRANITE_LIGHT, GRANITE_SUN)
GRANITE_COOL_TONES = (GRANITE_DARK, GRANITE_COOL, GRANITE_LIGHT, GRANITE_SUN)
GORSE_TONES = (GORSE_DARK, GORSE, GORSE_LIGHT, GORSE_SUN)


# ---------------------------------------------------------------------------
# stone kit
# ---------------------------------------------------------------------------

def rock_solid(builder: TreeBuilder, cx: float, cy: float, z: float,
               rx: float, ry: float, height: float, tones,
               rng, sides: int = 6, taper: float = 0.62,
               twist: float = 0.35, wobble: float = 0.18,
               lean: tuple[float, float] = (0.0, 0.0),
               cap_tone=None, buried: float = 1.6) -> None:
    """One angular stone block: a flat-topped, faceted shard of rock.

    A solid is built as two irregular rings of corners - a foot buried in the
    turf and a narrower, twisted crown lifted above it - bridged by flat side
    planes and closed with a flat cap.  Unlike an ellipsoid this gives a boulder
    real geology: hard sunlit facets, a broad top plane that catches the light,
    and a footprint that is never a smooth circle.  ``lean`` tips the crown in
    world x/y so the block stands at an angle.

    Each face takes one of the four stone tones by the direction it faces the
    shared sun, the way a tree's leaf clusters do.  Geometry alone would leave
    every camera-facing plane in shadow, which turns a boulder into a hole; the
    toned faces keep a stone readable from every side.
    """
    shadow, mid, light, sun = tones
    cap_tone = light if cap_tone is None else cap_tone
    gid = builder.group()

    def ring(radius_scale: float, lift: float, rotation: float,
             drift_x: float, drift_y: float) -> list[tuple[float, float, float]]:
        points = []
        for i in range(sides):
            angle = math.tau * i / sides + rotation
            rough = 1.0 + wobble * math.sin(angle * 3.0 + rng.uniform(-0.2, 0.2)) \
                + rng.uniform(-wobble, wobble) * 0.35
            points.append((cx + math.cos(angle) * rx * radius_scale * rough + drift_x,
                           cy + math.sin(angle) * ry * radius_scale * rough + drift_y,
                           z + lift))
        return points

    foot = ring(1.0, -buried, rng.uniform(0.0, math.tau), 0.0, 0.0)
    crown = ring(taper, height,
                 rng.uniform(0.0, math.tau), lean[0] * height, lean[1] * height)
    for i in range(sides):
        j = (i + 1) % sides
        # Outward direction of this face, measured from the two corners, and
        # lifted a little so a stone's flanks favour the lit tones.
        angle = math.tau * (i + 0.5) / sides
        dx, dy = math.cos(angle), math.sin(angle)
        material = tone_for(tones, dx, dy, 0.30, rng, bias=0.08, jitter=0.05)
        builder.m.quad(foot[i], foot[j], crown[j], crown[i], material,
                       group=gid)
    # The flat crown: a fan of facets around the top's centre, in the lighter
    # tone so a stone is read from its sunlit top first.
    centre_z = z + height
    top_x = cx + lean[0] * height * 0.5
    top_y = cy + lean[1] * height * 0.5
    for i in range(sides):
        j = (i + 1) % sides
        builder.m.tri((top_x, top_y, centre_z), crown[i], crown[j],
                      cap_tone, group=gid)


def rock_dome(builder: TreeBuilder, cx: float, cy: float, z: float,
              rx: float, ry: float, height: float, tones, rng,
              segments: int = 9, rings: int = 5, wobble: float = 0.13,
              buried: float = 1.2, cap_tone=None,
              profile: float = 2.6, spread: float = 0.46,
              lean: tuple[float, float] = (0.0, 0.0)) -> None:
    """One rounded, faceted boulder: a lump of stone, not a built block.

    A :func:`rock_solid` is a shard - a foot ring, a twisted crown and a flat
    cap.  A boulder is the other kind of stone: widest where it meets the turf,
    shouldered through its middle and rounded to a broad sunlit top.  The mass
    is a lathe of rings whose radius falls by ``profile``/``spread``, so the
    silhouette swells out of the ground instead of standing on it.  Every facet
    takes its tone from the shared sun, ``wobble`` chips the rim so no two faces
    or two views are alike, and ``lean`` tips the whole mass the way a weathered
    boulder settles.
    """
    shadow, mid, light, sun = tones
    cap_tone = sun if cap_tone is None else cap_tone
    gid = builder.group()
    phase = rng.uniform(0.0, math.tau)

    def ring(t: float) -> list[tuple[float, float, float]]:
        radius = max(0.0, 1.0 - t ** profile) ** spread
        points = []
        for i in range(segments):
            angle = math.tau * i / segments + phase * 0.3
            rough = 1.0 + wobble * math.sin(angle * 3.0 + phase) \
                + rng.uniform(-wobble, wobble) * 0.34
            r = radius * rough
            points.append((cx + math.cos(angle) * rx * r + lean[0] * height * t,
                           cy + math.sin(angle) * ry * r + lean[1] * height * t,
                           z + (height + buried) * t - buried))
        return points

    steps = [j / rings for j in range(rings)]
    bands = [ring(t) for t in steps]
    apex = (cx + lean[0] * height + rng.uniform(-0.5, 0.5),
            cy + lean[1] * height + rng.uniform(-0.5, 0.5), z + height)

    def facet(i: int, lift: float):
        angle = math.tau * (i + 0.5) / segments
        return tone_for(tones, math.cos(angle), math.sin(angle), lift, rng,
                        bias=0.0, jitter=0.06)

    for j in range(rings - 1):
        lower, upper = bands[j], bands[j + 1]
        lift = 0.12 + 0.30 * steps[j]
        for i in range(segments):
            k = (i + 1) % segments
            builder.m.quad(lower[i], lower[k], upper[k], upper[i],
                           facet(i, lift), group=gid)

    top = bands[-1]
    for i in range(segments):
        k = (i + 1) % segments
        builder.m.tri(top[i], top[k], apex, cap_tone, group=gid)


def chip(builder: TreeBuilder, cx: float, cy: float, r: float,
         tones, rng) -> None:
    """A small angular chip or pebble among the stones."""
    rock_solid(builder, cx, cy, 0.0, r, r * rng.uniform(0.6, 0.9),
               r * rng.uniform(0.45, 0.9), tones, rng,
               sides=rng.choice((4, 5)), taper=rng.uniform(0.4, 0.7),
               wobble=0.24, cap_tone=tones[2], buried=r * 0.55)


def speckle_stone(builder: TreeBuilder, cx: float, cy: float, z: float,
                  r: float, material, rng) -> None:
    """A chipped pebble or quartz fleck at the foot of an outcrop."""
    builder.blob(cx, cy, z + r * 0.30, r, r * rng.uniform(0.62, 0.88),
                 r * rng.uniform(0.34, 0.58), material,
                 ao_base=0.74, segments=5, rings=3, wobble=0.26,
                 phase=rng.uniform(0.0, math.tau))


def lichen_patch(builder: TreeBuilder, cx: float, cy: float, z: float,
                 rx: float, ry: float, rng, count=(3, 5)) -> None:
    """A crust of lichen on a stone's crown or face."""
    for _ in range(rng.randint(*count)):
        angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(0.10, 0.82)
        px = cx + math.cos(angle) * rx * reach
        py = cy + math.sin(angle) * ry * reach * 0.72
        r = rng.uniform(1.0, 2.6)
        material = rng.choice((LICHEN, LICHEN, LICHEN_LIGHT, LICHEN_PALE))
        builder.blob(px, py, z, r, r * rng.uniform(0.7, 1.05),
                     r * rng.uniform(0.22, 0.40), material,
                     ao_base=0.94, segments=6, rings=3, wobble=0.22,
                     phase=rng.uniform(0.0, math.tau))


def lichen_face(builder: TreeBuilder, cx: float, cy: float, rx: float,
                ry: float, z0: float, z1: float, rng) -> None:
    """Cream lichen crusts on the sunlit face, standing proud of the stone."""
    for _ in range(rng.randint(3, 5)):
        angle = rng.uniform(-0.35, 1.25)
        reach = rng.uniform(0.88, 1.0)
        px = cx + math.cos(angle) * rx * reach
        py = cy + math.sin(angle) * ry * reach
        pz = rng.uniform(z0, z1)
        r = rng.uniform(1.1, 2.4)
        material = rng.choice((LICHEN, LICHEN_LIGHT, LICHEN_PALE))
        builder.blob(px, py, pz, r, r * rng.uniform(0.6, 0.9),
                     r * rng.uniform(0.5, 0.8), material,
                     ao_base=0.95, segments=6, rings=3, wobble=0.3,
                     phase=rng.uniform(0.0, math.tau))


# ---------------------------------------------------------------------------
# Rocks: a slate scree outcrop
# ---------------------------------------------------------------------------

def draw_rocks(builder: TreeBuilder, rng) -> None:
    """One low slate outcrop: a cracked slab, its ledge, chunks and grit.

    The overlay scatters two or three of these drawings across every Rocks
    tile, so the model is a single stone rather than a field.  The slab is
    low - knee-high to a golfer - with a broken ledge against one flank, a few
    angular chunks and quartz flecks around its foot, and one tilted flake of
    broken slate leaning out of it.
    """
    angle = rng.uniform(0.0, math.tau)
    cx = BASE_X + math.cos(angle) * rng.uniform(0.0, 4.0)
    cy = BASE_Y + math.sin(angle) * rng.uniform(0.0, 2.5)
    rx = rng.uniform(7.5, 10.2)
    ry = rx * rng.uniform(0.60, 0.78)
    height = rng.uniform(3.8, 5.6)
    rock_solid(builder, cx, cy, 0.0, rx, ry, height,
               SLATE_TONES, rng, sides=6,
               taper=rng.uniform(0.60, 0.80), wobble=0.23,
               lean=(rng.uniform(-0.14, 0.14), rng.uniform(-0.10, 0.10)),
               cap_tone=rng.choice((SLATE_LIGHT, SLATE_SUN)))

    # A lower shelf beside it: the outcrop has ledges, not one dome.
    ledge_angle = angle + math.pi + rng.uniform(-0.9, 0.9)
    ledge_reach = rng.uniform(6.0, 9.0)
    ledge_rx = rng.uniform(2.6, 4.2)
    rock_solid(builder,
               cx + math.cos(ledge_angle) * ledge_reach,
               cy + math.sin(ledge_angle) * ledge_reach * 0.60,
               0.0, ledge_rx, ledge_rx * rng.uniform(0.6, 0.85),
               rng.uniform(1.4, 2.4), SLATE_TONES, rng, sides=5,
               taper=rng.uniform(0.50, 0.75), wobble=0.28,
               lean=(rng.uniform(-0.16, 0.16), rng.uniform(-0.12, 0.12)),
               cap_tone=SLATE_LIGHT)

    # Angular chunks wedged around the slab: a stone, not a scoop of gravel.
    for _ in range(rng.randint(4, 6)):
        chunk_angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(7.0, 14.0)
        r = rng.uniform(1.5, 3.2)
        chip(builder, cx + math.cos(chunk_angle) * reach,
             cy + math.sin(chunk_angle) * reach * 0.60, r,
             SLATE_TONES, rng)

    # One tilted flake of broken slate leaning out of the field.
    flake_angle = angle + rng.uniform(-1.2, 1.2)
    flake_reach = rng.uniform(7.0, 11.0)
    flake_rx = rng.uniform(2.6, 4.0)
    rock_solid(builder,
               cx + math.cos(flake_angle) * flake_reach,
               cy + math.sin(flake_angle) * flake_reach * 0.60,
               rng.uniform(0.8, 1.8), flake_rx,
               rng.uniform(1.8, 3.0), rng.uniform(1.0, 1.8),
               SLATE_TONES, rng, sides=4, taper=0.5, wobble=0.2,
               lean=(rng.uniform(-0.25, 0.25), rng.uniform(-0.2, 0.2)),
               cap_tone=SLATE_SUN, buried=0.4)

    # Gravel and quartz grit that has shaken loose around the stone.
    for _ in range(rng.randint(4, 6)):
        grit_angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(5.0, 13.0)
        speckle_stone(builder,
                      cx + math.cos(grit_angle) * reach,
                      cy + math.sin(grit_angle) * reach * 0.62,
                      0.0, rng.uniform(0.6, 1.5),
                      rng.choice((QUARTZ, QUARTZ_DIM, SLATE_SUN)),
                      rng)


# ---------------------------------------------------------------------------
# Boulder: standing granite
# ---------------------------------------------------------------------------

def draw_boulder(builder: TreeBuilder, rng) -> None:
    """A colossal standing boulder, shouldered by its broken kin.

    The tile's ground paints the fissured granite bed; this model raises the
    boulder the tile is named for.  A low bedrock shelf carries one broad,
    rounded granite mass with a second lobe breaking out of its flank, so the
    boulder reads as a single weathered stone rather than a stack of slabs.  A
    companion shard leans against one side, wedged stones gather at the foot and
    lichen crusts the sunlit crown.
    """
    main_x = BASE_X + rng.uniform(-3.5, 3.5)
    main_y = BASE_Y + rng.uniform(-2.0, 2.0)

    # The shelf: a low bedrock lump the boulder grows out of, so the stone is
    # rooted in the tile rather than sitting on top of it.
    shelf_rx = rng.uniform(13.5, 16.5)
    rock_dome(builder, main_x + rng.uniform(-1.5, 1.5),
              main_y + rng.uniform(-1.0, 1.0), 0.0,
              shelf_rx, shelf_rx * rng.uniform(0.62, 0.76),
              rng.uniform(4.0, 5.8), GRANITE_COOL_TONES, rng,
              segments=9, rings=4, wobble=0.17, buried=1.0,
              cap_tone=GRANITE_LIGHT, profile=rng.uniform(2.0, 3.0),
              spread=0.40)

    # The boulder proper: widest at the turf, shouldered through the middle and
    # rounded to a broad, sunlit crown.
    rx = rng.uniform(12.5, 15.5)
    ry = rx * rng.uniform(0.80, 0.94)
    height = rng.uniform(17.0, 21.5)
    lean = (rng.uniform(-0.11, 0.11), rng.uniform(-0.07, 0.07))
    rock_dome(builder, main_x, main_y, 0.0, rx, ry, height, GRANITE_TONES,
              rng, segments=9, rings=5, wobble=0.11, buried=1.4,
              cap_tone=GRANITE_LIGHT, profile=rng.uniform(2.2, 3.2),
              spread=rng.uniform(0.42, 0.54), lean=lean)

    # A second lobe breaks out of one flank, lower and cooler, giving the
    # silhouette a shoulder instead of a symmetrical egg.
    side = -1.0 if rng.random() < 0.5 else 1.0
    lobe_rx = rng.uniform(7.0, 9.5)
    lobe_x = main_x + side * rng.uniform(rx * 0.55, rx * 0.78)
    lobe_y = main_y + rng.uniform(0.5, 3.0)
    rock_dome(builder, lobe_x, lobe_y, 0.0, lobe_rx,
              lobe_rx * rng.uniform(0.78, 0.95),
              rng.uniform(10.0, 13.5), GRANITE_COOL_TONES, rng,
              segments=8, rings=4, wobble=0.14, buried=1.2,
              cap_tone=GRANITE_LIGHT, profile=rng.uniform(2.0, 2.8),
              spread=rng.uniform(0.40, 0.52),
              lean=(side * rng.uniform(0.02, 0.12), rng.uniform(-0.06, 0.06)))

    # A companion shard leans against the other flank.
    shard_side = -side
    comp_x = main_x + shard_side * rng.uniform(12.0, 15.5)
    comp_y = main_y + rng.uniform(0.5, 4.0)
    comp_rx = rng.uniform(4.5, 6.5)
    rock_solid(builder, comp_x, comp_y, 0.0, comp_rx,
               comp_rx * rng.uniform(0.7, 0.95),
               comp_rx * rng.uniform(1.6, 2.3), GRANITE_COOL_TONES, rng,
               sides=5, taper=rng.uniform(0.35, 0.6), wobble=0.22,
               lean=(-shard_side * rng.uniform(0.12, 0.26),
                     rng.uniform(-0.06, 0.06)),
               cap_tone=GRANITE_LIGHT)

    # Wedged stones and chips around the foot.
    for _ in range(rng.randint(5, 8)):
        angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(11.0, 23.0)
        r = rng.uniform(1.8, 4.0)
        chip(builder, main_x + math.cos(angle) * reach,
             main_y + math.sin(angle) * reach * 0.65, r,
             GRANITE_TONES, rng)
    for _ in range(rng.randint(3, 5)):
        angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(12.0, 24.0)
        speckle_stone(builder,
                      main_x + math.cos(angle) * reach,
                      main_y + math.sin(angle) * reach * 0.65,
                      0.0, rng.uniform(0.6, 1.5),
                      rng.choice((QUARTZ_DIM, GRANITE_SUN, SLATE_MOSS)),
                      rng)

    # Weathering: lichen on the sunlit crown, cream crusts down the warm face
    # and moss gathering in the seam at the foot.
    lichen_patch(builder, main_x, main_y, height - 1.0,
                 rx * 0.50, ry * 0.46, rng, count=(4, 7))
    lichen_face(builder, main_x, main_y, rx * 0.90, ry * 0.90,
                height * 0.22, height * 0.72, rng)
    for _ in range(rng.randint(2, 4)):
        angle = rng.uniform(-0.4, 1.3)
        builder.blob(main_x + math.cos(angle) * rx * rng.uniform(0.85, 1.02),
                     main_y + math.sin(angle) * ry * rng.uniform(0.85, 1.02),
                     rng.uniform(0.6, 2.2), rng.uniform(1.2, 2.4),
                     1.6, 0.9, SLATE_MOSS, ao_base=0.88,
                     segments=6, rings=3, wobble=0.3,
                     phase=rng.uniform(0.0, math.tau))


# ---------------------------------------------------------------------------
# Brush: tangled gorse scrub
# ---------------------------------------------------------------------------

def _gorse_clump(builder: TreeBuilder, cx: float, cy: float, cz: float,
                 radii, rng, group=None, count=24, cluster=2.4,
                 tips=10) -> None:
    """One gorse bush: a dark heart under a cloud of leaf clusters."""
    gid = builder.m.group() if group is None else group
    canopy(builder, (cx, cy, cz), radii, GORSE_TONES, rng, group=gid,
           count=count, cluster=cluster, tips=tips, underside=2,
           ao=0.64, shell=0.9, tip_size=cluster * 0.55, spread=1.0,
           fillers=2, shoulders=False)
    # Gorse flowers cluster on the sunward shell: two or three sprays of
    # baubles, never a uniform sprinkle.
    rx, ry, rz = radii
    for _ in range(rng.randint(3, 5)):
        dx = rng.uniform(0.20, 0.88)
        dy = rng.uniform(-0.35, 0.55)
        dz = rng.uniform(0.15, 0.65)
        bx = cx + dx * rx
        by = cy + dy * ry
        bz = cz + dz * rz
        for _ in range(rng.randint(4, 8)):
            r = rng.uniform(0.6, 1.15)
            builder.blob(bx + rng.uniform(-1.6, 1.6),
                         by + rng.uniform(-1.2, 1.2),
                         bz + rng.uniform(-1.0, 1.4), r, r, r * 0.85,
                         BLOSSOM_LIGHT if rng.random() < 0.55 else BLOSSOM,
                         ao_base=0.94, segments=5, rings=3, group=gid)


def _gorse_bush(builder: TreeBuilder, rng, cx: float, cy: float, scale: float,
                stem_group: int, crown_group: int) -> None:
    """One low gorse bush: short woody stems under a flat crown of foliage."""
    stem_count = rng.randint(2, 3)
    for i in range(stem_count):
        yaw = math.tau * i / stem_count + rng.uniform(-0.5, 0.5)
        base = (cx + math.cos(yaw) * rng.uniform(0.4, 1.8),
                cy + math.sin(yaw) * rng.uniform(0.3, 1.4), 0.0)
        top = (cx + math.cos(yaw) * rng.uniform(1.5, 4.0) * scale,
               cy + math.sin(yaw) * rng.uniform(1.2, 3.0) * scale,
               rng.uniform(3.2, 5.0) * scale)
        builder.limb(base, top, 0.75, 0.30, SCRUB_TWIG,
                     segments=4, group=stem_group)
        # A short fork or two, so the wood still shows through the crown.
        for side in (-0.7, 0.8):
            if rng.random() > 0.65:
                continue
            fork_yaw = yaw + side + rng.uniform(-0.3, 0.3)
            fork_reach = rng.uniform(1.8, 3.6) * scale
            tip = (top[0] + math.cos(fork_yaw) * fork_reach,
                   top[1] + math.sin(fork_yaw) * fork_reach * 0.7,
                   top[2] + rng.uniform(0.5, 1.5) * scale)
            builder.limb(top, tip, 0.42, 0.16, SCRUB_TWIG_DARK,
                         segments=3, group=stem_group, cap=False)

    rx = rng.uniform(6.6, 8.8) * scale
    ry = rx * rng.uniform(0.68, 0.86)
    _gorse_clump(builder, cx, cy, rng.uniform(3.8, 5.2) * scale,
                 (rx, ry, rng.uniform(2.6, 3.6) * scale),
                 rng, group=crown_group, count=20, cluster=2.0, tips=8)


def draw_brush(builder: TreeBuilder, rng) -> None:
    """One low gorse bush: short woody stems under a flat crown of foliage.

    The overlay plants two or three of these drawings across every Brush tile,
    so the model is a single bush rather than a hedge.  Gorse in this course
    grows low - the bush stands about a rock's height - with thorn stems
    breaking its rim, bright blossom on the sunward shell and a few sprigs
    rooting it in the turf.
    """
    stem_group = builder.group()
    crown_group = builder.group()

    angle = rng.uniform(0.0, math.tau)
    cx = BASE_X + math.cos(angle) * rng.uniform(0.0, 2.5)
    cy = BASE_Y + math.sin(angle) * rng.uniform(0.0, 1.5)
    scale = rng.uniform(1.0, 1.18)
    _gorse_bush(builder, rng, cx, cy, scale, stem_group, crown_group)

    # Thorn branches breaking the silhouette: a bramble's warning.
    for _ in range(rng.randint(2, 4)):
        thorn_angle = rng.uniform(0.0, math.tau)
        thorn_reach = rng.uniform(6.0, 10.0) * scale
        start_z = rng.uniform(2.2, 4.2) * scale
        end = (cx + math.cos(thorn_angle) * thorn_reach,
               cy + math.sin(thorn_angle) * thorn_reach * 0.72,
               start_z + rng.uniform(0.5, 2.0) * scale)
        builder.limb((cx, cy, start_z), end, 0.34, 0.10,
                     SCRUB_TWIG_DARK, segments=3, group=stem_group, cap=False)
        for _ in range(rng.randint(1, 2)):
            builder.blob(end[0] + rng.uniform(-1.2, 1.2),
                         end[1] + rng.uniform(-0.9, 0.9),
                         end[2] + rng.uniform(-0.8, 0.8),
                         0.42, 0.42, 0.42, THORN,
                         ao_base=0.96, segments=4, rings=3,
                         group=stem_group)

    # Low sprigs trailing onto the turf, so the bush is rooted in its tile.
    for _ in range(rng.randint(4, 6)):
        sprig_angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(6.0, 11.0) * scale
        builder.leaf_tuft(cx + math.cos(sprig_angle) * reach,
                          cy + math.sin(sprig_angle) * reach * 0.7,
                          rng.uniform(0.6, 1.8), GORSE, rng,
                          size=1.4, spread=1.0, group=crown_group, count=3)


#: The features the game draws as a sprite over their tile, in toolbar order.
FEATURES = {
    "rocks": {"draw": draw_rocks, "label": "Rocks"},
    "boulder": {"draw": draw_boulder, "label": "Boulder"},
    "brush": {"draw": draw_brush, "label": "Brush"},
}
