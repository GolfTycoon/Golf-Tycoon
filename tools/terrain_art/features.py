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
* **Eight drawings, one feature.**  The eight view variants are independent
  seeded drawings (see ``feature_seed()``), not rotations: neighbouring tiles
  wear different outcrops at once, exactly as a wood wears different trees.
  The extra Rocks drawings are what lets a tile scatter more, smaller stones
  without two neighbouring stamps looking like the same pebble.

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

#: How many independent view variants a feature can wear, matching
#: ``TerrainFeatureOverlay.FACINGS``.  More than four gives the scattered
#: Rocks tiles enough different drawings that a dense field never repeats.
VARIANT_COUNT = 8

#: Every size in a Rocks drawing is multiplied by this.  The outcrops stay
#: smaller than Brush bushes or a Boulder, and `layout.json` draws them at 0.95,
#: but they are baked large enough that a crack, a moss fleck and a quartz
#: glint each get a whole pixel.  At one pixel per world pixel, sub-pixel
#: geometry simply disappears.
ROCKS_SIZE = 0.95

#: Extra draw-time scale for the Rocks art, written to ``layout.json`` by the
#: generator.  A feature can be drawn smaller without changing the baked PNGs;
#: ``TerrainFeatureOverlay.art_scale()`` applies it to the course and the
#: toolbar alike.
FEATURE_DRAW_SCALE = {"rocks": 0.95}


def feature_draw_scale(feature: str) -> float:
    """The per-feature draw scale the layout sidecar records (1.0 by default)."""
    return float(FEATURE_DRAW_SCALE.get(feature, 1.0))


def feature_seed(feature: str, variant: int) -> int:
    """A stable per-drawing seed: the same outcrop every time the tool runs."""
    return 0x5709 + variant * 104729 + sum(ord(c) for c in feature) * 53


# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------

# Slate: cool blue-grey stone with pale quartz, matching the tile's dark slate
# border.  Four tones, darkest in the lee, palest on the sunlit crown.  The
# extra crevice, warm and moss tones let one drawing read as a *particular*
# stone - shaded, sun-bleached or weathered - rather than a grey blob.
SLATE_CREVICE = mat(C("313a45"), "gravel")
SLATE_DARK = mat(C("4a525e"), "gravel")
SLATE = mat(C("6b7482"), "gravel")
SLATE_LIGHT = mat(C("959fab"), "gravel", emissive=0.06)
SLATE_SUN = mat(C("b6c0ca"), "gravel", emissive=0.10)
SLATE_WARM = mat(C("c9c6bb"), "gravel", emissive=0.10)
SLATE_MOSS = mat(C("6c7663"), "gravel")
MOSS_DARK = mat(C("46533a"), "gravel")
MOSS_SUN = mat(C("8d9a5e"), "gravel")
QUARTZ = mat(C("d9dde3"), "gravel", emissive=0.10)
QUARTZ_DIM = mat(C("aeb5bd"), "gravel")
QUARTZ_VEIN = mat(C("e8ebee"), "gravel", emissive=0.22)

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
# gorse-ochre blossoms on the sunward tips.  Seed pods, thorn tips and fallen
# petals give a bush a season and a life cycle, not just a green silhouette.
GORSE_DARK = mat(C("293818"), "leaf_fine")
GORSE = mat(C("3d5524"), "leaf_fine")
GORSE_LIGHT = mat(C("577430"), "leaf_fine")
GORSE_SUN = mat(C("829e4a"), "leaf_fine")
GORSE_GOLD = mat(C("a5ab52"), "leaf_fine")
GORSE_DEEP = mat(C("1f2c14"), "leaf_fine")
BLOSSOM = mat(C("dec033"), "bloom")
BLOSSOM_LIGHT = mat(C("f3df6d"), "bloom")
BLOSSOM_DEEP = mat(C("b07d1e"), "bloom")
BLOSSOM_PALE = mat(C("f7edb0"), "bloom", emissive=0.06)
SEED_POD = mat(C("5b4a2d"), "gravel")
SCRUB_TWIG = mat(C("4a3924"), "bark")
SCRUB_TWIG_DARK = mat(C("32261a"), "bark")
THORN = mat(C("6a5738"), "flat")
THORN_TIP = mat(C("b8a877"), "flat")

SLATE_TONES = (SLATE_DARK, SLATE, SLATE_LIGHT, SLATE_SUN)
SLATE_COOL_TONES = (SLATE_CREVICE, SLATE_DARK, SLATE, SLATE_LIGHT)
SLATE_WARM_TONES = (SLATE_DARK, SLATE, SLATE_LIGHT, SLATE_WARM)
SLATE_MOSS_TONES = (SLATE_DARK, SLATE, SLATE_MOSS, SLATE_LIGHT)
#: One palette per pair of variants: a rocky field reads as a stretch of
#: geology, not eight copies of one grey stone.
ROCK_PALETTES = (SLATE_TONES, SLATE_COOL_TONES, SLATE_WARM_TONES,
                 SLATE_MOSS_TONES)

GRANITE_TONES = (GRANITE_DARK, GRANITE, GRANITE_LIGHT, GRANITE_SUN)
GRANITE_COOL_TONES = (GRANITE_DARK, GRANITE_COOL, GRANITE_LIGHT, GRANITE_SUN)
GORSE_TONES = (GORSE_DARK, GORSE, GORSE_LIGHT, GORSE_SUN)
GORSE_SUN_TONES = (GORSE_DARK, GORSE_LIGHT, GORSE_SUN, GORSE_GOLD)
GORSE_SHADE_TONES = (GORSE_DARK, GORSE, GORSE_LIGHT, GORSE_SUN)
#: Bush palettes shift from deep shade to sun-bleached gold with the seed.
BRUSH_PALETTES = (GORSE_TONES, GORSE_SUN_TONES, GORSE_TONES,
                  GORSE_SHADE_TONES, GORSE_SUN_TONES, GORSE_TONES,
                  GORSE_SUN_TONES, GORSE_TONES)

#: Eight deliberately different silhouettes, one per drawing.  The seed still
#: shapes each one, but the *composition* is art-directed: a field of small
#: stones should read as a field, not eight rotations of the same slab.
ROCK_FORMS = ("slab", "shard", "cairn", "ledge", "split", "wedge",
              "pebbles", "outcrop")
#: The same idea for gorse: cushion, flowering, windswept, twin crowns, spiky,
#: sprawling, a young sprig and an old gnarled bush.
BRUSH_FORMS = ("cushion", "flowering", "windswept", "twin", "spiky",
               "sprawling", "young", "old")


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


def rock_cap_seam(builder: TreeBuilder, cx: float, cy: float, z: float,
                  rx: float, angle: float, material) -> None:
    """A hairline fissure across a slab's sunlit cap.

    One dark quad, a fraction of a pixel wide and sitting just above the cap,
    is enough at this scale to say *cracked stone* rather than *grey pillow*.
    ``bias`` keeps it in front of the cap it lies on.
    """
    dx, dy = math.cos(angle), math.sin(angle)
    px, py = -dy, dx
    length = rx * 0.86
    w = 0.80 * ROCKS_SIZE
    corners = [
        (cx - dx * length - px * w, cy - dy * length - py * w, z),
        (cx - dx * length + px * w, cy - dy * length + py * w, z),
        (cx + dx * length + px * w, cy + dy * length + py * w, z),
        (cx + dx * length - px * w, cy + dy * length - py * w, z),
    ]
    builder.m.quad(corners[0], corners[1], corners[2], corners[3],
                   material, bias=0.03)


def rock_grounding(builder: TreeBuilder, rng, cx: float, cy: float,
                   rx: float, ry: float, tones) -> None:
    """Dark scree at the foot: the stone sits *in* the rough, not on it."""
    for _ in range(rng.randint(2, 4)):
        a = rng.uniform(0.0, math.tau)
        reach = rng.uniform(0.35, 0.75)
        r = rng.uniform(1.1, 1.9) * ROCKS_SIZE
        builder.pebble(cx + math.cos(a) * rx * reach,
                       cy + math.sin(a) * ry * reach, -0.25, r,
                       tones[0] if rng.random() < 0.55 else SLATE_CREVICE)


def rock_details(builder: TreeBuilder, rng, cx: float, cy: float, z: float,
                 rx: float, ry: float, tones) -> None:
    """Moss in the lee, quartz on the crown, loose chips on the turf."""
    # Lichen gathers on the shaded flank (the sun sits at +x / -y / +z).
    # Everything sits inside the stone's own footprint: a fleck outside the
    # silhouette reads as a rendering artefact, not as detail.
    for _ in range(rng.randint(2, 3)):
        a = rng.uniform(2.0, 4.3)
        r = rng.uniform(1.0, 1.7) * ROCKS_SIZE
        builder.blob(cx + math.cos(a) * rx * rng.uniform(0.40, 0.72),
                     cy + math.sin(a) * ry * rng.uniform(0.40, 0.72),
                     z - rng.uniform(0.1, 0.6) * ROCKS_SIZE,
                     r, r * rng.uniform(0.7, 1.0), r * 0.45,
                     rng.choice((MOSS_DARK, SLATE_MOSS, MOSS_SUN)),
                     ao_base=0.88, segments=5, rings=3,
                     wobble=0.25, phase=rng.uniform(0.0, math.tau))
    # Quartz catches the sun on the crown: a few bright flecks, never a
    # uniform sprinkle.
    for _ in range(rng.randint(2, 3)):
        a = rng.uniform(-0.9, 0.7)
        r = rng.uniform(1.0, 1.6) * ROCKS_SIZE
        builder.blob(cx + math.cos(a) * rx * rng.uniform(0.45, 0.80),
                     cy + math.sin(a) * ry * rng.uniform(0.45, 0.80),
                     z + rng.uniform(0.08, 0.45) * ROCKS_SIZE,
                     r, r * 0.8, r * 0.5,
                     rng.choice((QUARTZ_VEIN, QUARTZ, QUARTZ_DIM)),
                     ao_base=0.96, segments=5, rings=3,
                     wobble=0.2, phase=rng.uniform(0.0, math.tau))
    # Grit that has shaken loose around the outcrop.
    for _ in range(rng.randint(1, 3)):
        a = rng.uniform(0.0, math.tau)
        reach = rng.uniform(0.55, 0.95)
        speckle_stone(builder,
                      cx + math.cos(a) * rx * reach,
                      cy + math.sin(a) * ry * reach,
                      0.0, rng.uniform(0.9, 1.5) * ROCKS_SIZE,
                      rng.choice((tones[0], tones[1], QUARTZ_DIM)), rng)


def draw_rocks(builder: TreeBuilder, rng) -> None:
    """One small slate outcrop, drawn as one of eight art-directed forms.

    A tile stands five to eight of these drawings, so each is a single stone
    rather than a field.  ``ROCK_FORMS`` gives every drawing a *deliberate*
    silhouette - a cracked flagstone, a leaning shard, a cairn, a stepped
    ledge, a split block, a wedge, a nest of rounded pebbles or a radiating
    outcrop - while ``ROCK_PALETTES`` gives each pair a different geology.
    The seed still decides the lean, the chips and where the quartz sits.
    Every measurement is scaled by ``ROCKS_SIZE``: small stones, rich detail.
    """
    variant = int(getattr(builder, "variant", 0))
    form = ROCK_FORMS[variant % len(ROCK_FORMS)]
    tones = ROCK_PALETTES[variant % len(ROCK_PALETTES)]
    s = ROCKS_SIZE
    angle = rng.uniform(0.0, math.tau)
    cx = BASE_X + math.cos(angle) * rng.uniform(0.0, 2.2) * s
    cy = BASE_Y + math.sin(angle) * rng.uniform(0.0, 1.3) * s
    rx = rng.uniform(7.4, 9.8) * s
    ry = rx * rng.uniform(0.62, 0.80)
    h = rng.uniform(3.6, 5.2) * s
    detail_z = h * 0.8
    # How wide the form really is.  A narrow shard must not wear moss at the
    # radius of a broad slab, or the lichen floats in mid-air beside it.
    foot = 1.0
    cap = tones[3]
    buried = 1.3 * s

    def block(x: float, y: float, z: float, brx: float, bry: float,
              bh: float, sides: int = 6, taper: float = 0.72,
              lean=(0.0, 0.0), cap_tone=None) -> None:
        rock_solid(builder, x, y, z, brx, bry, bh, tones, rng,
                   sides=sides, taper=taper,
                   wobble=rng.uniform(0.17, 0.28), lean=lean,
                   cap_tone=cap_tone or cap, buried=buried)

    if form == "slab":
        # A broad broken flagstone: one clean fissure and a stepped ledge.
        block(cx, cy, 0.0, rx, ry, h * 0.72, sides=7, taper=0.92)
        rock_cap_seam(builder, cx - rx * 0.06, cy, h * 0.72 + 0.05,
                      rx * 0.86, angle + 0.5, SLATE_CREVICE)
        detail_z = h * 0.72
        foot = 1.0
        ledge_a = angle + math.pi
        block(cx + math.cos(ledge_a) * rx * 0.78,
              cy + math.sin(ledge_a) * ry * 0.78, 0.0,
              rx * 0.42, ry * 0.50, h * 0.34, sides=5, taper=0.78)

    elif form == "shard":
        # A tall leaning flake of broken slate, with two foot stones.
        block(cx, cy, 0.0, rx * 0.44, ry * 0.48, h * 1.75,
              sides=4, taper=0.42,
              lean=(rng.uniform(-0.34, 0.34), rng.uniform(-0.22, 0.22)),
              cap_tone=rng.choice((tones[3], SLATE_WARM)))
        detail_z = h * 1.45
        foot = 0.55
        block(cx - rx * 0.62, cy + ry * 0.32, 0.0,
              rx * 0.40, ry * 0.46, h * 0.40, sides=5, taper=0.70)
        block(cx + rx * 0.66, cy - ry * 0.24, 0.0,
              rx * 0.30, ry * 0.36, h * 0.30, sides=5, taper=0.66)

    elif form == "cairn":
        # Three stones stacked, each smaller and a little off-centre.
        z = 0.0
        for i, (f, hf) in enumerate(((1.0, 0.62), (0.72, 0.58), (0.48, 0.52))):
            block(cx + rng.uniform(-0.7, 0.7) * s,
                  cy + rng.uniform(-0.5, 0.5) * s, z,
                  rx * f, ry * f, h * hf, sides=5,
                  taper=rng.uniform(0.70, 0.90))
            z += h * hf * 0.84
        detail_z = h * 1.4
        foot = 0.80

    elif form == "ledge":
        # A low shelf carrying a smaller block: two distinct horizons.
        block(cx, cy, 0.0, rx, ry, h * 0.42, sides=6, taper=0.96)
        rock_cap_seam(builder, cx, cy, h * 0.42 + 0.04,
                      rx * 0.7, angle - 0.6, tones[0])
        block(cx + rx * 0.34, cy - ry * 0.26, h * 0.40,
              rx * 0.55, ry * 0.60, h * 0.78, sides=5, taper=0.76,
              lean=(0.10, -0.06))
        detail_z = h * 1.1
        foot = 0.95

    elif form == "split":
        # Two halves of one cracked block, with a dark crevice between.
        px, py = -math.sin(angle), math.cos(angle)
        for side in (-1.0, 1.0):
            block(cx + px * rx * 0.30 * side,
                  cy + py * ry * 0.30 * side, 0.0,
                  rx * 0.54, ry * 0.70, h * 0.86, sides=5, taper=0.82,
                  lean=(px * 0.09 * side, py * 0.07 * side))
        rock_cap_seam(builder, cx, cy, h * 0.88, rx * 0.5,
                      angle + math.pi * 0.5, SLATE_CREVICE)

    elif form == "wedge":
        # One steep triangular face leaning into the light.
        foot = 0.85
        block(cx, cy, 0.0, rx * 0.92, ry * 0.80, h * 1.25,
              sides=5, taper=0.44, lean=(0.26, -0.13))
        block(cx - rx * 0.70, cy + ry * 0.36, 0.0,
              rx * 0.44, ry * 0.50, h * 0.42, sides=4, taper=0.60)

    elif form == "pebbles":
        # No slab at all: a nest of rounded stones, water-worn and low.
        foot = 0.85
        detail_z = h * 0.55
        rock_dome(builder, cx, cy, 0.0, 3.1 * s, 2.5 * s, 2.7 * s,
                  tones, rng, segments=7, rings=4, wobble=0.18,
                  buried=0.8 * s, cap_tone=tones[3], profile=2.2)
        count = rng.randint(4, 6)
        for i in range(count):
            a = math.tau * i / count + rng.uniform(-0.4, 0.4)
            reach = rng.uniform(0.45, 1.0)
            r = rng.uniform(1.4, 2.4) * s
            rock_dome(builder,
                      cx + math.cos(a) * rx * reach,
                      cy + math.sin(a) * ry * reach, 0.0,
                      r, r * rng.uniform(0.65, 0.90),
                      r * rng.uniform(0.70, 1.10), tones, rng,
                      segments=6, rings=3, wobble=0.20,
                      buried=0.6 * s, cap_tone=tones[3],
                      profile=rng.uniform(1.8, 2.6))

    else:  # "outcrop": a central block with shards radiating out of it.
        foot = 1.0
        block(cx, cy, 0.0, rx * 0.80, ry * 0.80, h * 0.90,
              sides=6, taper=0.80)
        for i in range(3):
            a = angle + i * 2.1 + rng.uniform(-0.4, 0.4)
            reach = rng.uniform(0.72, 1.02)
            block(cx + math.cos(a) * rx * reach,
                  cy + math.sin(a) * ry * reach, 0.0,
                  rx * 0.30, ry * 0.36, h * rng.uniform(0.36, 0.72),
                  sides=4, taper=0.55,
                  lean=(math.cos(a) * 0.20, math.sin(a) * 0.15))

    rock_grounding(builder, rng, cx, cy, rx * foot, ry * foot, tones)
    rock_details(builder, rng, cx, cy, detail_z, rx * foot, ry * foot, tones)


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

#: Per-form silhouette, flowering and thorn budgets.  These are art direction,
#: not noise: a "flowering" bush is a yellow dome, a "spiky" one a dark crown
#: of thorns, a "young" one a small bright sprig.  The seed only decides the
#: lean and where each cluster lands.
BRUSH_SHAPES = {
    "cushion":   dict(lobes=3, height=0.80, width=1.15, lean=0.00,
                      sprays=2, thorns=2, pods=1, petals=2, sprigs=5, stems=3),
    "flowering": dict(lobes=2, height=1.00, width=1.00, lean=0.10,
                      sprays=5, thorns=2, pods=0, petals=3, sprigs=4, stems=3),
    "windswept": dict(lobes=2, height=0.92, width=1.05, lean=0.42,
                      sprays=2, thorns=5, pods=1, petals=1, sprigs=4, stems=3),
    "twin":      dict(lobes=2, height=0.96, width=0.82, lean=0.00,
                      sprays=3, thorns=3, pods=1, petals=2, sprigs=4, stems=4),
    "spiky":     dict(lobes=1, height=1.25, width=0.72, lean=0.12,
                      sprays=1, thorns=7, pods=2, petals=0, sprigs=3, stems=2),
    "sprawling": dict(lobes=3, height=0.70, width=1.30, lean=0.00,
                      sprays=3, thorns=2, pods=1, petals=4, sprigs=7, stems=3),
    "young":     dict(lobes=1, height=0.86, width=0.70, lean=0.00,
                      sprays=2, thorns=2, pods=0, petals=1, sprigs=4, stems=2),
    "old":       dict(lobes=2, height=1.05, width=1.10, lean=0.20,
                      sprays=1, thorns=4, pods=3, petals=1, sprigs=5, stems=4),
}


def _gorse_spray(builder: TreeBuilder, rng, cx: float, cy: float, cz: float,
                 group: int, dense: bool = False) -> None:
    """One yellow raceme: a short stalk with blossom baubles along it.

    Gorse flowers grow in sprays, not as an even dusting of yellow pixels.
    The stalk leans toward the sun and the last bud is the palest, so a spray
    reads as a flowering tip even at one pixel per world pixel.
    """
    a = rng.uniform(-1.0, 0.8)
    bx = cx + math.cos(a) * rng.uniform(2.2, 4.8)
    by = cy + math.sin(a) * rng.uniform(-3.4, 2.0)
    bz = cz + rng.uniform(0.6, 2.0)
    tip = (bx + rng.uniform(0.8, 2.0), by - rng.uniform(0.2, 1.0),
           bz + rng.uniform(0.8, 1.8))
    builder.limb((bx, by, bz), tip, 0.24, 0.10, SCRUB_TWIG_DARK,
                 segments=3, group=group, cap=False)
    count = rng.randint(4, 6) if dense else rng.randint(3, 4)
    for i in range(count):
        t = i / max(1, count - 1)
        r = rng.uniform(0.95, 1.40) * (1.0 - 0.22 * t)
        if i == count - 1 and rng.random() < 0.75:
            material = BLOSSOM_PALE
        else:
            material = rng.choice((BLOSSOM_LIGHT, BLOSSOM_LIGHT,
                                     BLOSSOM, BLOSSOM_PALE))
        builder.blob(bx + (tip[0] - bx) * t + rng.uniform(-0.5, 0.5),
                     by + (tip[1] - by) * t + rng.uniform(-0.5, 0.5),
                     bz + (tip[2] - bz) * t + rng.uniform(-0.4, 0.5),
                     r, r * 0.92, r * 0.88, material,
                     ao_base=0.94, segments=5, rings=3, group=group)


def _gorse_clump(builder: TreeBuilder, rng, centre, radii, tones,
                 group: int, lobes: int = 2, count: int = 20,
                 tips: int = 8, twin: bool = False) -> None:
    """A crown of overlapping leaf masses, so the rim is never one ellipse."""
    cx, cy, cz = centre
    rx, ry, rz = radii
    if twin:
        # Two separate small crowns with their own gap of sky between them.
        for side in (-1.0, 1.0):
            canopy(builder,
                   (cx + side * rx * 0.62, cy + side * ry * 0.12,
                    cz + rng.uniform(-0.2, 0.3)),
                   (rx * 0.62, ry * 0.68, rz * rng.uniform(0.85, 1.05)),
                   tones, rng, group=group,
                   count=max(12, count // 2), cluster=1.5,
                   tips=max(5, tips // 2), underside=1, ao=0.86,
                   shell=0.92, tip_size=1.25, spread=1.0,
                   fillers=2, shoulders=False)
        return
    for i in range(lobes):
        f = 1.0 if i == 0 else rng.uniform(0.58, 0.82)
        ox = rng.uniform(-0.38, 0.38) * rx if i else rng.uniform(-0.1, 0.1) * rx
        oy = rng.uniform(-0.30, 0.30) * ry if i else 0.0
        oz = rng.uniform(-0.18, 0.28) * rz if i else 0.0
        canopy(builder, (cx + ox, cy + oy, cz + oz),
               (rx * f, ry * f, rz * rng.uniform(0.82, 1.10)),
               tones, rng, group=group,
               count=max(11, count // lobes), cluster=1.6,
               tips=max(5, tips // lobes), underside=1, ao=0.86,
               shell=0.92, tip_size=1.25, spread=1.0,
               fillers=2, shoulders=False)


def _gorse_bush(builder: TreeBuilder, rng, cx: float, cy: float,
                scale: float, form: str, tones, stem_group: int,
                crown_group: int) -> None:
    """One gorse bush of a given form: wood, lobes, flowers, thorns, pods."""
    shape = BRUSH_SHAPES[form]
    lean = shape["lean"]
    rx = rng.uniform(7.4, 9.0) * scale * shape["width"]
    ry = rx * rng.uniform(0.68, 0.84)
    rz = rng.uniform(2.6, 3.4) * scale * shape["height"]
    cz = rng.uniform(4.8, 6.2) * scale * shape["height"]

    # Woody stems with forks: old bushes show more wood, young ones hide it.
    stems = shape["stems"]
    for i in range(stems):
        yaw = math.tau * i / stems + rng.uniform(-0.5, 0.5)
        base = (cx + math.cos(yaw) * rng.uniform(0.4, 1.8),
                cy + math.sin(yaw) * rng.uniform(0.3, 1.4), 0.0)
        top = (cx + math.cos(yaw) * rng.uniform(1.4, 3.6) * scale
               + lean * 2.2 * scale,
               cy + math.sin(yaw) * rng.uniform(1.2, 3.0) * scale,
               cz - rz * rng.uniform(0.25, 0.55))
        wood = SCRUB_TWIG_DARK if form == "old" else SCRUB_TWIG
        builder.limb(base, top, 0.72 if form == "old" else 0.56, 0.26,
                     wood, segments=4, group=stem_group)
        for side in (-0.7, 0.8):
            if rng.random() > 0.55:
                continue
            fork_yaw = yaw + side + rng.uniform(-0.3, 0.3)
            fork_reach = rng.uniform(1.8, 3.6) * scale
            tip = (top[0] + math.cos(fork_yaw) * fork_reach,
                   top[1] + math.sin(fork_yaw) * fork_reach * 0.7,
                   top[2] + rng.uniform(0.5, 1.5) * scale)
            builder.limb(top, tip, 0.40, 0.14, SCRUB_TWIG_DARK,
                         segments=3, group=stem_group, cap=False)

    _gorse_clump(builder, rng, (cx + lean * 1.4 * scale, cy, cz),
                 (rx, ry, rz), tones, crown_group,
                 lobes=shape["lobes"], count=22, tips=10,
                 twin=(form == "twin"))

    # Lit rim: the sun is at +x / -y / +z, so the bright leaves ride the
    # upper right shoulder.  Clusters, not a painted outline.
    for _ in range(rng.randint(5, 8)):
        a = rng.uniform(-1.15, 0.55)
        r = rng.uniform(1.0, 1.7)
        builder.blob(cx + lean * 1.4 * scale + math.cos(a) * rx * rng.uniform(0.45, 0.86),
                     cy + math.sin(a) * ry * rng.uniform(0.45, 0.86),
                     cz + rz * rng.uniform(0.35, 0.85),
                     r, r * 0.9, r * 0.8,
                     rng.choice((GORSE_SUN, GORSE_GOLD, tones[3])),
                     ao_base=0.98, segments=5, rings=3,
                     group=crown_group)

    # Flower sprays on the sunward shell, clustered rather than scattered.
    for i in range(shape["sprays"]):
        a = -1.25 + i * (2.1 / max(1, shape["sprays"] - 1)) \
            + rng.uniform(-0.22, 0.22)
        _gorse_spray(builder, rng,
                     cx + math.cos(a) * rx * rng.uniform(0.35, 0.65),
                     cy + math.sin(a) * ry * rng.uniform(0.35, 0.65),
                     cz + rz * rng.uniform(0.15, 0.85),
                     crown_group, dense=(form == "flowering"))

    # Seed pods in the lee: a bush has a season, not just a colour.
    for _ in range(shape["pods"]):
        a = rng.uniform(2.0, 4.2)
        r = rng.uniform(1.0, 1.5)
        builder.blob(cx + math.cos(a) * rx * rng.uniform(0.35, 0.70),
                     cy + math.sin(a) * ry * rng.uniform(0.35, 0.8),
                     cz + rz * rng.uniform(0.05, 0.35),
                     r, r * 0.8, r * 0.95, SEED_POD,
                     ao_base=0.86, segments=5, rings=3,
                     group=crown_group)

    # Thorn branches breaking the silhouette, tipped with a pale point.
    for _ in range(shape["thorns"]):
        thorn_angle = rng.uniform(0.0, math.tau)
        thorn_reach = rng.uniform(6.0, 10.5) * scale * shape["width"]
        start_z = cz * rng.uniform(0.45, 0.85)
        end = (cx + math.cos(thorn_angle) * thorn_reach,
               cy + math.sin(thorn_angle) * thorn_reach * 0.72,
               start_z + rng.uniform(0.6, 2.2) * scale)
        builder.limb((cx, cy, start_z), end, 0.32, 0.09,
                     SCRUB_TWIG_DARK, segments=3, group=stem_group, cap=False)
        builder.blob(end[0], end[1], end[2], 0.42, 0.42, 0.42,
                     THORN_TIP if rng.random() < 0.6 else THORN,
                     ao_base=0.96, segments=4, rings=3, group=stem_group)

    # Low sprigs and a dark leaf skirt keep the bush rooted in the rough.
    for _ in range(shape["sprigs"]):
        sprig_angle = rng.uniform(0.0, math.tau)
        reach = rng.uniform(4.5, 8.5) * scale * shape["width"]
        sprig_z = rng.uniform(0.4, 1.6)
        material = GORSE_SUN if rng.random() < 0.35 else GORSE
        builder.leaf_tuft(cx + math.cos(sprig_angle) * reach,
                          cy + math.sin(sprig_angle) * reach * 0.7,
                          sprig_z, material, rng,
                          size=1.15, spread=1.0, group=crown_group, count=3)
    for _ in range(3):
        a = rng.uniform(0.0, math.tau)
        builder.blob(cx + math.cos(a) * rx * 0.55,
                     cy + math.sin(a) * ry * 0.55, 0.15,
                     1.1, 0.9, 0.45, tones[0], ao_base=0.72,
                     segments=5, rings=3, group=crown_group)

    # A few fallen petals on the turf: the brightest, smallest grounding cue.
    for _ in range(max(1, shape["petals"] // 3)):
        a = rng.uniform(0.0, math.tau)
        reach = rng.uniform(5.0, 9.0) * scale * shape["width"]
        builder.blob(cx + math.cos(a) * reach,
                     cy + math.sin(a) * reach * 0.72, 0.12,
                     rng.uniform(0.6, 1.0), 0.7, 0.32,
                     BLOSSOM_LIGHT if rng.random() < 0.6 else BLOSSOM,
                     ao_base=0.96, segments=5, rings=3, group=crown_group)


def draw_brush(builder: TreeBuilder, rng) -> None:
    """One gorse bush, drawn as one of eight art-directed forms.

    The overlay plants five to eight of these drawings across every Brush tile,
    so the model is a single bush rather than a hedge.  ``BRUSH_FORMS`` gives
    each drawing its own character - low cushion, flowering dome, windswept
    lean, twin crowns, thorny spike, sprawler, young sprig or gnarled old
    wood - and ``BRUSH_PALETTES`` shifts the green from deep shade to
    sun-bleached gold.  Stems, blossom racemes, seed pods, thorn tips, low
    sprigs and fallen petals all stay at one pixel per world pixel, so the
    detail has to be deliberate rather than merely dense.
    """
    variant = int(getattr(builder, "variant", 0))
    form = BRUSH_FORMS[variant % len(BRUSH_FORMS)]
    tones = BRUSH_PALETTES[variant % len(BRUSH_PALETTES)]
    stem_group = builder.group()
    crown_group = builder.group()
    angle = rng.uniform(0.0, math.tau)
    cx = BASE_X + math.cos(angle) * rng.uniform(0.0, 2.5)
    cy = BASE_Y + math.sin(angle) * rng.uniform(0.0, 1.5)
    scale = rng.uniform(1.0, 1.16)
    _gorse_bush(builder, rng, cx, cy, scale, form, tones,
                stem_group, crown_group)


#: The features the game draws as a sprite over their tile, in toolbar order.
FEATURES = {
    "rocks": {"draw": draw_rocks, "label": "Rocks"},
    "boulder": {"draw": draw_boulder, "label": "Boulder"},
    "brush": {"draw": draw_brush, "label": "Brush"},
}
