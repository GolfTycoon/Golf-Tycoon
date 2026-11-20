"""Hand-painted improvements: radial props that the voxel renderer fights.

The fountain and the sundial are read from above: a basin, a water surface and
a dial face.  Rendered as a 3D solid at one output pixel per world pixel the
rim occludes its own water and every engraved tick disappears into the facet
noise, so these two are painted directly in screen space, in the same palette
and with the same dark outlines as the rendered props.  Everything is drawn on
a supersampled canvas and reduced once, which gives the crisp pixel shapes of
the building and terrain art without hand-placing sixty thousand pixels.
"""

from __future__ import annotations

import math

from PIL import Image, ImageDraw

#: Supersampling factor for the painted canvas.
S = 4

# Shared course palette, tuned to sit beside the terrain and building sprites.
INK = (37, 41, 48)
STONE_DARK = (74, 81, 92)
STONE_MID = (112, 121, 133)
STONE_LIGHT = (154, 163, 174)
STONE_PALE = (196, 204, 212)
MOSS = (78, 111, 62)
MOSS_LIGHT = (108, 144, 80)
WATER_DEEP = (44, 124, 158)
WATER_MID = (70, 172, 202)
WATER_LIGHT = (120, 213, 235)
WATER_PALE = (186, 240, 250)
BRASS_DARK = (122, 92, 44)
BRASS = (176, 133, 55)
BRASS_LIGHT = (226, 186, 92)
CREAM = (239, 231, 206)
CREAM_DARK = (206, 195, 164)
FLOWER = (223, 198, 96)


def _c(colour, alpha=255):
    return (colour[0], colour[1], colour[2], alpha)


class Canvas:
    """A supersampled RGBA canvas addressed in final (1x) pixels."""

    def __init__(self, width: int, height: int, ground: int):
        self.width = width
        self.height = height
        self.ground = ground
        self.image = Image.new("RGBA", (width * S, height * S), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)

    # -- primitives -------------------------------------------------------
    def ellipse(self, box, fill=None, outline=None, width=1.0):
        self.draw.ellipse(tuple(v * S for v in box), fill=_c(fill) if fill else None,
                          outline=_c(outline) if outline else None,
                          width=max(1, int(round(width * S))))

    def poly(self, points, fill=None, outline=None, width=1.0):
        pts = [(x * S, y * S) for x, y in points]
        self.draw.polygon(pts, fill=_c(fill) if fill else None)
        if outline:
            self.draw.line(pts + [pts[0]], fill=_c(outline),
                           width=max(1, int(round(width * S))), joint="curve")

    def line(self, points, fill, width=1.0):
        pts = [(x * S, y * S) for x, y in points]
        self.draw.line(pts, fill=_c(fill), width=max(1, int(round(width * S))),
                       joint="curve")

    def arc(self, box, start, end, fill, width=1.0):
        self.draw.arc(tuple(v * S for v in box), start, end, fill=_c(fill),
                      width=max(1, int(round(width * S))))

    def dot(self, x, y, r, fill):
        self.ellipse((x - r, y - r, x + r, y + r), fill=fill)

    def gradient_ellipse(self, box, top, bottom):
        """Fill an ellipse with a vertical gradient, without banding lobes."""
        x0, y0, x1, y1 = (int(round(v * S)) for v in box)
        w = max(1, x1 - x0)
        h = max(1, y1 - y0)
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, w - 1, h - 1), fill=255)
        grad = Image.new("RGBA", (w, h))
        gd = ImageDraw.Draw(grad)
        for i in range(h):
            t = i / max(h - 1, 1)
            colour = tuple(int(round(top[k] + (bottom[k] - top[k]) * t))
                           for k in range(3))
            gd.line([(0, i), (w, i)], fill=colour + (255,))
        self.image.paste(grad, (x0, y0), mask)

    # -- output -----------------------------------------------------------
    def finish(self, width: int | None = None, height: int | None = None):
        """Reduce the supersampled canvas, optionally to a smaller target.

        Painting stays in the logical 1x coordinates; a prop that should sit
        smaller on its tile passes a smaller target here instead of respacing
        every ellipse.
        """
        size = (width if width is not None else self.width,
                height if height is not None else self.height)
        return self.image.resize(size, Image.LANCZOS)


def _ellipse_points(cx, cy, rx, ry, segments):
    return [(cx + rx * math.cos(math.tau * i / segments),
             cy + ry * math.sin(math.tau * i / segments))
            for i in range(segments)]


def _stone_blocks(c: Canvas, cx, cy, rx, ry, thickness, segments, inner=True):
    """A ring of stone blocks between two ellipses, with grout between them."""
    for i in range(segments):
        a0 = math.tau * i / segments
        a1 = math.tau * (i + 1) / segments
        gap = (a1 - a0) * 0.08
        a0 += gap
        a1 -= gap
        outer = [(cx + rx * math.cos(a), cy + ry * math.sin(a))
                 for a in (a0, a1)]
        inner_pts = [(cx + (rx - thickness) * math.cos(a),
                      cy + (ry - thickness) * math.sin(a)) for a in (a1, a0)]
        tone = (STONE_MID, STONE_LIGHT, STONE_PALE, STONE_LIGHT)[i % 4]
        c.poly(outer + inner_pts, fill=tone, outline=INK, width=0.55)


def _moss(c: Canvas, cx, ground, spread=22.0, rng=0.0):
    for i in range(7):
        a = rng + i * 2.399963
        x = cx + math.cos(a) * spread * (0.55 + 0.45 * ((i * 37) % 11) / 11.0)
        y = ground - abs(math.sin(a)) * 2.2
        r = 0.9 + ((i * 17) % 5) * 0.28
        c.dot(x, y, r + 0.5, MOSS)
        c.dot(x - 0.4, y - 0.5, r * 0.65, MOSS_LIGHT)
    for x in (-spread * 0.7, spread * 0.55):
        c.dot(cx + x, ground - 2.4, 1.0, FLOWER)


def paint_fountain() -> tuple[Image.Image, float, float]:
    """An octagonal stone fountain with three tiers and a bright plume."""
    w, h, ground = 64, 68, 60
    c = Canvas(w, h, ground)
    cx = 32.0

    # Contact shadow and the mossy footing.
    c.ellipse((cx - 26, ground - 4, cx + 26, ground + 5), fill=(30, 46, 34, 90))
    c.ellipse((cx - 24, ground - 6, cx + 24, ground + 2), fill=STONE_DARK,
              outline=INK, width=0.8)

    # The basin shell: a block wall whose lower half falls to the ground.
    c.ellipse((cx - 28, 36, cx + 28, 62), fill=STONE_MID, outline=INK,
              width=0.9)
    # Two courses of blocks around the outer wall, lit on the near face.
    for y in (50.5, 55.0):
        c.arc((cx - 27.4, y - 12.4, cx + 27.4, y + 12.4), 20, 160,
              INK, width=0.5)
    c.arc((cx - 27.6, 37, cx + 27.6, 63), 34, 150, STONE_LIGHT, width=1.0)
    c.arc((cx - 27.6, 38, cx + 27.6, 64), 44, 140, STONE_DARK, width=2.4)
    for i in range(17):
        a = math.pi * i / 16.0
        x0 = cx - 27.6 * math.cos(a)
        x1 = cx - 26.7 * math.cos(a)
        y0 = 47 + 9.6 * math.sin(a)
        y1 = 47 + 15.4 * math.sin(a)
        c.line([(x0, y0), (x1, y1)], INK, width=0.45)
    for i in range(15):
        a = math.pi * (i + 0.5) / 15.0
        x = cx - 26.6 * math.cos(a)
        y = 48 + 12.2 * math.sin(a)
        c.dot(x, y, 0.7, STONE_LIGHT if i % 2 else STONE_PALE)

    # The rim: a coping of pale blocks around a sunken blue basin.
    c.ellipse((cx - 27, 33, cx + 27, 53), fill=STONE_DARK, outline=INK,
              width=0.9)
    _stone_blocks(c, cx, 43, 26.5, 10.0, 5.2, 24)
    # A pale coping highlight along the far rim.
    c.arc((cx - 26.6, 32.4, cx + 26.6, 52.4), 196, 344, STONE_PALE, width=0.8)
    # The inner wall between the coping and the water line.
    c.ellipse((cx - 20.3, 36.4, cx + 20.3, 49.2), fill=(84, 108, 120),
              outline=INK, width=0.7)
    # The water surface: one vertical gradient, so the column and basin cannot
    # split a lighter inner ellipse into two odd bright lobes.
    c.gradient_ellipse((cx - 19.4, 37.2, cx + 19.4, 47.8),
                       (92, 196, 219), (34, 104, 136))
    c.ellipse((cx - 19.4, 37.2, cx + 19.4, 47.8), outline=(33, 90, 112),
              width=0.55)
    for i in range(3):
        c.ellipse((cx - 14.4 + i * 2.2, 39.6 + i * 1.0,
                   cx + 14.4 - i * 2.2, 45.0 - i * 0.8),
                  outline=(178, 238, 250), width=0.5)
    c.arc((cx - 13.0, 38.8, cx + 13.0, 44.6), 202, 296, (232, 252, 255),
          width=0.9)
    c.ellipse((cx - 10.0, 39.0, cx - 6.0, 40.2), fill=(200, 243, 252))
    c.ellipse((cx + 4.0, 43.6, cx + 8.4, 44.6), fill=(190, 240, 252))
    c.arc((cx - 19.0, 39.4, cx + 19.0, 47.4), 208, 332, (30, 84, 108),
          width=0.6)

    # The central piers: an octagonal shaft and two shallow bowls.
    c.ellipse((cx - 5.2, 45.0, cx + 5.2, 49.2), fill=STONE_DARK,
              outline=INK, width=0.6)
    c.poly([(cx - 4.2, 45.2), (cx + 4.2, 45.2), (cx + 3.4, 36.0),
            (cx - 3.4, 36.0)], fill=STONE_LIGHT, outline=INK, width=0.6)
    c.line([(cx - 1.4, 37.0), (cx - 2.4, 45.0)], STONE_DARK, width=0.5)
    c.line([(cx + 1.4, 37.0), (cx + 2.4, 45.0)], STONE_DARK, width=0.5)
    # Lower bowl.
    c.ellipse((cx - 11.0, 31.4, cx + 11.0, 38.2), fill=STONE_DARK,
              outline=INK, width=0.7)
    c.ellipse((cx - 10.0, 30.6, cx + 10.0, 36.0), fill=STONE_MID,
              outline=INK, width=0.7)
    c.ellipse((cx - 8.6, 31.2, cx + 8.6, 35.0), fill=WATER_DEEP)
    c.ellipse((cx - 7.4, 31.6, cx + 7.4, 34.2), fill=WATER_MID)
    c.ellipse((cx - 5.0, 31.9, cx + 5.0, 33.4), fill=WATER_LIGHT)
    # Upper bowl.
    c.ellipse((cx - 6.6, 25.4, cx + 6.6, 30.0), fill=STONE_LIGHT,
              outline=INK, width=0.6)
    c.ellipse((cx - 5.4, 25.8, cx + 5.4, 29.0), fill=WATER_DEEP)
    c.ellipse((cx - 3.8, 26.1, cx + 3.8, 28.2), fill=WATER_LIGHT)
    # A small carved finial on the upper bowl.
    c.dot(cx, 24.0, 1.7, STONE_PALE)
    c.dot(cx - 0.5, 23.5, 0.7, (236, 242, 246))

    # The plume: a narrow tapered column with a spray crown and falling sheets.
    c.poly([(cx - 2.6, 26.0), (cx + 2.6, 26.0), (cx + 1.3, 9.0),
            (cx - 1.3, 9.0)], fill=(160, 218, 237), outline=(222, 248, 254),
           width=0.45)
    c.poly([(cx - 1.1, 26.0), (cx + 1.1, 26.0), (cx + 0.5, 9.4),
            (cx - 0.5, 9.4)], fill=(228, 250, 255))
    c.poly([(cx - 2.0, 24.0), (cx - 1.2, 24.0), (cx - 0.6, 13.0),
            (cx - 1.3, 13.0)], fill=(250, 254, 255))
    c.ellipse((cx - 2.8, 6.4, cx + 2.8, 10.6), fill=(210, 243, 252),
              outline=(247, 254, 255), width=0.45)
    c.ellipse((cx - 1.6, 5.6, cx + 1.6, 8.2), fill=(250, 254, 255))
    for i in range(10):
        a = -math.pi * 0.94 + i * math.pi * 0.21
        x = cx + math.cos(a) * (3.2 + (i % 3) * 1.0)
        y = 9.4 + math.sin(a) * 2.2 + (i % 2) * 1.6
        c.dot(x, y, 0.65 + (i % 3) * 0.22, (228, 250, 255))
    for i in range(6):
        a = math.radians(-158 + i * 26)
        x0 = cx + math.cos(a) * 2.6
        x1 = cx + math.cos(a) * 9.6
        y0 = 27.0
        y1 = 32.0 + (i % 2) * 2.0
        c.arc((min(x0, x1) - 1.0, min(y0, y1) - 1.0,
               max(x0, x1) + 1.0, max(y0, y1) + 1.0), 250, 350,
              (222, 249, 255), width=0.65)
    # Splash on the lower bowl.
    for x in (-4.6, -1.6, 1.4, 4.4):
        c.dot(cx + x, 31.2, 0.75, (232, 250, 255))

    _moss(c, cx, ground, spread=25.0, rng=0.4)
    # Sit the whole basin smaller on the tile: 54x58 of the authored 64x68, so
    # the fountain leaves the path and its neighbours some air.
    target = (54, 58)
    return (c.finish(*target), cx * target[0] / w, float(ground) * target[1] / h)


def paint_sundial() -> tuple[Image.Image, float, float]:
    """A brass sundial on a short, sturdy stone plinth."""
    w, h, ground = 48, 50, 47
    c = Canvas(w, h, ground)
    cx = 24.0
    dial_y = 16.3

    # Shadow and a three-step plinth.
    c.ellipse((cx - 16, ground - 4, cx + 16, ground + 3), fill=(30, 46, 34, 95))
    c.ellipse((cx - 15, ground - 5, cx + 15, ground + 2), fill=STONE_DARK,
              outline=INK, width=0.8)
    c.ellipse((cx - 13, ground - 8, cx + 13, ground - 1), fill=STONE_MID,
              outline=INK, width=0.7)
    c.ellipse((cx - 10.4, ground - 11, cx + 10.4, ground - 3), fill=STONE_LIGHT,
              outline=INK, width=0.7)
    # A short block-built shaft: the dial sits low over the steps now.
    c.poly([(cx - 9.2, ground - 8.0), (cx + 9.2, ground - 8.0),
            (cx + 6.6, 26.0), (cx - 6.6, 26.0)], fill=STONE_MID,
           outline=INK, width=0.8)
    c.poly([(cx - 9.2, ground - 8.0), (cx - 1.0, ground - 8.0),
            (cx - 0.8, 26.0), (cx - 6.6, 26.0)], fill=STONE_LIGHT)
    for y in (33.0, 39.0):
        c.line([(cx - 7.0, y), (cx + 7.0, y)], INK, width=0.45)
    for x in (-3.4, 2.8):
        c.line([(cx + x, 27.0), (cx + x * 1.2, ground - 9.0)], INK,
               width=0.4)
    # A flared foot with a chamfered plinth.
    c.poly([(cx - 9.6, ground - 8.0), (cx + 9.6, ground - 8.0),
            (cx + 8.0, ground - 11.4), (cx - 8.0, ground - 11.4)],
           fill=STONE_LIGHT, outline=INK, width=0.6)
    c.line([(cx - 8.2, ground - 9.6), (cx + 8.2, ground - 9.6)], STONE_DARK,
           width=0.5)
    # A moulded cap, shorter and wider than the old pedestal's.
    c.ellipse((cx - 8.2, 21.6, cx + 8.2, 27.6), fill=STONE_DARK,
              outline=INK, width=0.7)
    c.ellipse((cx - 7.4, 21.0, cx + 7.4, 26.0), fill=STONE_LIGHT,
              outline=INK, width=0.6)
    c.ellipse((cx - 5.6, 20.6, cx + 5.6, 24.2), fill=STONE_PALE)
    # A turned brass stem under the dish.
    c.poly([(cx - 2.2, 21.0), (cx + 2.2, 21.0), (cx + 1.8, 17.0),
            (cx - 1.8, 17.0)], fill=BRASS_DARK, outline=INK, width=0.5)

    # The dial plate: a thick brass dish with a cream engraved face.
    c.ellipse((cx - 18.6, dial_y - 2.0, cx + 18.6, dial_y + 8.0),
              fill=BRASS_DARK, outline=INK, width=0.9)
    c.ellipse((cx - 18.0, dial_y - 5.4, cx + 18.0, dial_y + 6.0),
              fill=BRASS, outline=BRASS_LIGHT, width=0.7)
    c.ellipse((cx - 16.6, dial_y - 4.6, cx + 16.6, dial_y + 4.8),
              fill=CREAM, outline=CREAM_DARK, width=0.6)
    # Twelve hour marks.
    for i in range(12):
        a = math.tau * i / 12.0
        r0 = 15.0 if i % 3 == 0 else 14.2
        x0 = cx + math.cos(a) * r0
        y0 = dial_y + math.sin(a) * (r0 * 0.235)
        x1 = cx + math.cos(a) * 11.8
        y1 = dial_y + math.sin(a) * (11.8 * 0.235)
        c.line([(x0, y0), (x1, y1)], INK, width=0.55)
    # The gnomon's shadow, falling left across the face.
    c.poly([(cx - 0.6, dial_y + 3.2), (cx - 9.6, dial_y - 1.2),
            (cx - 8.8, dial_y - 2.0), (cx - 0.4, dial_y - 0.2)],
           fill=CREAM_DARK)
    c.ellipse((cx - 3.0, dial_y - 1.8, cx + 3.0, dial_y + 1.8), fill=BRASS,
              outline=BRASS_DARK, width=0.45)
    c.ellipse((cx - 1.6, dial_y - 1.2, cx + 1.6, dial_y + 0.8),
              fill=BRASS_LIGHT)
    # The gnomon: a broad gold blade, wide at the noon line and tapering to
    # the finial, with a lit left face.
    c.poly([(cx - 3.4, dial_y + 3.6), (cx + 3.2, dial_y + 3.6),
            (cx + 1.0, 6.0)], fill=BRASS_DARK, outline=INK, width=0.7)
    c.poly([(cx - 2.6, dial_y + 3.2), (cx + 1.4, dial_y + 3.2),
            (cx + 0.6, 7.0)], fill=BRASS_LIGHT)
    c.line([(cx - 0.4, dial_y + 2.6), (cx - 0.1, 7.8)],
           (250, 228, 160), width=0.5)
    c.line([(cx - 0.4, dial_y + 2.0), (cx - 0.5, 7.2)],
           (248, 224, 154), width=0.45)
    c.dot(cx + 0.1, 5.4, 1.6, BRASS)
    c.dot(cx - 0.3, 5.0, 0.8, BRASS_LIGHT)
    # Four little ball feet under the dish.
    for a in (0.35, 1.22, 2.09, 2.96):
        x = cx + math.cos(a) * 12.8
        y = dial_y + 5.4 + math.sin(a) * 2.4
        c.dot(x, y, 1.0, BRASS_DARK)

    _moss(c, cx, ground, spread=16.0, rng=1.1)
    return c.finish(), cx, float(ground)
