#!/usr/bin/env python3
"""3D models for every facility on the course.

Each building is authored in world-pixel space on its own tiles: ``x`` across
the footprint (a tile is 64 wide), ``y`` down it (a tile is 32 deep) and ``z``
up.  The shared ``Builder`` supplies real 3D solids - boxes, pitched roofs,
cylinders, cones, domes, tubes and lathed props - so a facility is a small
architectural model rather than a stack of flat faces.

The renderer projects the model through the game's 2:1 isometric axes and bakes
one pixel sprite for each view rotation.  That is why the same model can have a
porch, a deep window reveal, a tiled hip roof and a cast shadow and still land
exactly on its tiles in every direction.

One model pixel is one world pixel.  A storey is about 46 px, a door 26 px tall
and a window 18 px.
"""

from __future__ import annotations

import math

import numpy as np

from render import (
    ASPHALT, ASPHALT_LIGHT, BLUE, BLUE_MAT, BUNKER_MAT, C, CREAM, CREAM_DARK,
    CREAM_MAT, GLASS, GLASS_DARK, GLASS_DARK_MAT, GLASS_LIGHT, GLASS_MAT, GOLD,
    GOLD_DARK, GOLD_DARK_MAT, GOLD_MAT, GRAVEL, GRASS, GRASS_LIGHT, GRASS_LIGHT_MAT, GRASS_MAT,
    GREEN_MAT, HAY, HAY_MAT, HEDGE, HEDGE_DARK, HEDGE_LIGHT, INK, INK_MAT, KERB,
    LAMP, LAMP_MAT, LEAF, LEAF_DARK, LEAF_LIGHT, MAROON, MAROON_DARK, Model,
    FACING_COUNT, NEON_CYAN, NEON_PINK, PAVE, PAVE_DARK, PINK, PINK_MAT, PLASTER, PLASTER_PALE,
    PLASTER_WARM, PLANK_WHITE, RED, RED_MAT, ROOF_BROWN, ROOF_BROWN_DARK,
    ROOF_BROWN_MAT, ROOF_GREEN, ROOF_GREEN_DARK, ROOF_GREEN_MAT, ROOF_RED,
    ROOF_RED_DARK, ROOF_RED_MAT, ROOF_SLATE, ROOF_SLATE_DARK, ROOF_SLATE_MAT,
    ROPE, SAND_MAT, SHADOW_MAT, SHADOW_SOFT, SLATE, SLATE_DARK, SLATE_DARK_MAT,
    SLATE_MAT, SMOKE, STEAM, STONE, STONE_DARK, STONE_DARK_MAT, STONE_LIGHT,
    STONE_MAT, STONE_WALL, STONE_WALL_DARK, TARMAC, THATCH, TIMBER, TIMBER_DARK,
    TIMBER_LIGHT, WATER_DEEP_MAT, WATER_LIGHT, WATER_MAT, WHITE, WHITE_MAT, WOOD,
    WOOD_DARK, WOOD_DARK_MAT, WOOD_LIGHT, WOOD_LIGHT_MAT, WOOD_MAT, YELLOW, YELLOW_MAT,
    mat, net_texture, text_texture, window_texture, door_texture, clock_texture,
    display_texture, menu_texture, marquee_texture,
)


# ---------------------------------------------------------------------------
# builder
# ---------------------------------------------------------------------------

def _tex_material(texture, unlit: bool = True) -> "mat":
    return mat(C("ffffff"), texture=texture, unlit=unlit)


class Builder:
    """Architectural primitives in world-pixel space, with the course palette."""

    def __init__(self, model: Model):
        self.m = model
        self.width = model.width
        self.depth = model.depth
        self.facing = 0

    # -- basic solids -----------------------------------------------------
    def box(self, x0, y0, x1, y1, z0, z1, material, top=None, side=None,
            skip=(), bottom=False, ao_base=0.76, ao_top=1.0) -> None:
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        top_mat = top if top is not None else material
        side_mat = side if side is not None else material
        side_ao = (ao_base, ao_base, ao_top, ao_top)
        if "x+" not in skip:
            self.m.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1),
                        side_mat, ao=side_ao)
        if "x-" not in skip:
            self.m.quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1),
                        side_mat, ao=side_ao)
        if "y+" not in skip:
            self.m.quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1),
                        side_mat, ao=side_ao)
        if "y-" not in skip:
            self.m.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
                        side_mat, ao=side_ao)
        if "z+" not in skip:
            self.m.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
                        top_mat, ao=(1.0, 1.0, 1.0, 1.0))
        if bottom:
            self.m.quad((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0),
                        material, ao=(0.45, 0.45, 0.45, 0.45))

    def slab(self, x0, y0, x1, y1, z0, z1, material, kerb=None, inset=3.0,
             top=None) -> None:
        """A paved terrace: a kerb slab with an inset top surface."""
        if kerb is not None:
            self.box(x0, y0, x1, y1, z0, z1, kerb, top=kerb)
        self.box(x0 + inset, y0 + inset, x1 - inset, y1 - inset, z1, z1 + 1.2,
                 top if top is not None else material, top=top if top is not None else material,
                 skip=("z-",), ao_base=1.0)

    def pool(self, x0, y0, x1, y1, z_base, z_rim, rim=5.0,
             coping=None, water=None) -> None:
        """A sunken pool: coping border, tiled inner walls and a water plane."""
        coping = coping if coping is not None else WHITE_MAT
        water = water if water is not None else WATER_MAT
        inner = mat(C("8fd0e0"), "flagstone")
        self.box(x0 - rim, y0 - rim, x1 + rim, y0, z_base, z_rim, coping,
                 top=coping)
        self.box(x0 - rim, y1, x1 + rim, y1 + rim, z_base, z_rim, coping,
                 top=coping)
        self.box(x0 - rim, y0, x0, y1, z_base, z_rim, coping, top=coping)
        self.box(x1, y0, x1 + rim, y1, z_base, z_rim, coping, top=coping)
        self.box(x0, y0, x1, y1, z_base, z_rim - 1.8, inner, top=inner)
        self.m.quad((x0 + 1, y0 + 1, z_rim - 1.2),
                    (x1 - 1, y0 + 1, z_rim - 1.2),
                    (x1 - 1, y1 - 1, z_rim - 1.2),
                    (x0 + 1, y1 - 1, z_rim - 1.2), water,
                    uvs=((x0, y0), (x1, y0), (x1, y1), (x0, y1)),
                    bias=0.03)

    def ground(self, x0, y0, x1, y1, material, z=0.8, thickness=2.0,
               kerb=None, inset=0.0) -> None:
        if kerb is not None:
            self.box(x0, y0, x1, y1, z - thickness, z, kerb, top=kerb)
        self.box(x0 + inset, y0 + inset, x1 - inset, y1 - inset, z, z + 0.8,
                 material, top=material, skip=(), ao_base=1.0)

    # -- pitched roofs ----------------------------------------------------
    @staticmethod
    def _slope_uv(x, y, z, eave_y, z_eave, along_x=True):
        dist = math.hypot(y - eave_y, z - z_eave)
        return (x if along_x else y, dist)

    def roof_gable(self, x0, y0, x1, y1, z_eave, z_ridge, axis, material,
                   overhang=5.0, gable_material=None, ridge=True,
                   fascia=True) -> None:
        gable_material = material if gable_material is None else gable_material
        self._eave_trim(x0 - overhang, y0 - overhang, x1 + overhang,
                        y1 + overhang, z_eave)
        ox = overhang
        oy = overhang
        ox0, ox1, oy0, oy1 = x0 - ox, x1 + ox, y0 - oy, y1 + oy
        if axis == "x":
            ym = (y0 + y1) * 0.5
            # back slope (-y +z)
            self.m.quad(
                (ox0, oy0, z_eave), (ox1, oy0, z_eave),
                (ox1, ym, z_ridge), (ox0, ym, z_ridge), material,
                uvs=((ox0, 0.0), (ox1, 0.0),
                     (ox1, math.hypot(ym - oy0, z_ridge - z_eave)),
                     (ox0, math.hypot(ym - oy0, z_ridge - z_eave))),
                ao=(0.86, 0.86, 1.0, 1.0))
            # front slope (+y +z)
            self.m.quad(
                (ox0, ym, z_ridge), (ox1, ym, z_ridge),
                (ox1, oy1, z_eave), (ox0, oy1, z_eave), material,
                uvs=((ox0, math.hypot(ym - oy1, z_ridge - z_eave)),
                     (ox1, math.hypot(ym - oy1, z_ridge - z_eave)),
                     (ox1, 0.0), (ox0, 0.0)),
                ao=(1.0, 1.0, 0.9, 0.9))
            if gable_material is not None:
                self.m.tri((x0, oy1, z_eave), (x0, oy0, z_eave),
                           (x0, ym, z_ridge), gable_material)
                self.m.tri((x1, oy0, z_eave), (x1, oy1, z_eave),
                           (x1, ym, z_ridge), gable_material)
            if ridge:
                self.box(ox0 - 1, ym - 2.0, ox1 + 1, ym + 2.0,
                         z_ridge - 1.0, z_ridge + 1.6,
                         material, top=material)
            if fascia:
                for yy in (oy0, oy1):
                    self.box(ox0, yy - 1.4, ox1, yy + 1.4,
                             z_eave - 3.0, z_eave, WOOD_DARK_MAT)
        else:
            xm = (x0 + x1) * 0.5
            # left slope (-x +z)
            self.m.quad(
                (ox1, oy0, z_eave), (ox1, oy1, z_eave),
                (xm, oy1, z_ridge), (xm, oy0, z_ridge), material,
                uvs=((0.0, oy0), (0.0, oy1),
                     (math.hypot(xm - ox1, z_ridge - z_eave), oy1),
                     (math.hypot(xm - ox1, z_ridge - z_eave), oy0)),
                ao=(0.86, 0.86, 1.0, 1.0))
            # right slope (+x +z)
            self.m.quad(
                (xm, oy0, z_ridge), (xm, oy1, z_ridge),
                (ox0, oy1, z_eave), (ox0, oy0, z_eave), material,
                uvs=((math.hypot(xm - ox0, z_ridge - z_eave), oy0),
                     (math.hypot(xm - ox0, z_ridge - z_eave), oy1),
                     (0.0, oy1), (0.0, oy0)),
                ao=(1.0, 1.0, 0.9, 0.9))
            if gable_material is not None:
                self.m.tri((ox1, y0, z_eave), (ox0, y0, z_eave),
                           (xm, y0, z_ridge), gable_material)
                self.m.tri((ox0, y1, z_eave), (ox1, y1, z_eave),
                           (xm, y1, z_ridge), gable_material)
            if ridge:
                self.box(xm - 2.0, oy0 - 1, xm + 2.0, oy1 + 1,
                         z_ridge - 1.0, z_ridge + 1.6,
                         material, top=material)
            if fascia:
                for xx in (ox0, ox1):
                    self.box(xx - 1.4, oy0, xx + 1.4, oy1,
                             z_eave - 3.0, z_eave, WOOD_DARK_MAT)

    def roof_hip(self, x0, y0, x1, y1, z_eave, z_ridge, material,
                 overhang=5.0, ridge=True, fascia=True) -> None:
        self._eave_trim(x0 - overhang, y0 - overhang, x1 + overhang,
                        y1 + overhang, z_eave)
        ox, oy = overhang, overhang
        ox0, ox1, oy0, oy1 = x0 - ox, x1 + ox, y0 - oy, y1 + oy
        ym = (y0 + y1) * 0.5
        d = min((x1 - x0) * 0.42, (y1 - y0) * 0.55)
        rx0, rx1 = x0 + d, x1 - d
        # back trapezoid
        self.m.quad((ox0, oy0, z_eave), (ox1, oy0, z_eave),
                    (rx1, ym, z_ridge), (rx0, ym, z_ridge), material,
                    uvs=((ox0, 0.0), (ox1, 0.0),
                         (rx1, math.hypot(ym - oy0, z_ridge - z_eave)),
                         (rx0, math.hypot(ym - oy0, z_ridge - z_eave))),
                    ao=(0.86, 0.86, 1.0, 1.0))
        # front trapezoid
        self.m.quad((ox1, oy1, z_eave), (ox0, oy1, z_eave),
                    (rx0, ym, z_ridge), (rx1, ym, z_ridge), material,
                    uvs=((ox1, 0.0), (ox0, 0.0),
                         (rx0, math.hypot(ym - oy1, z_ridge - z_eave)),
                         (rx1, math.hypot(ym - oy1, z_ridge - z_eave))),
                    ao=(0.9, 0.9, 1.0, 1.0))
        # left hip
        self.m.tri((ox0, oy1, z_eave), (ox0, oy0, z_eave),
                   (rx0, ym, z_ridge), material,
                   uvs=((oy1, 0.0), (oy0, 0.0),
                        (ym, math.hypot(rx0 - ox0, z_ridge - z_eave))),
                   ao=(0.9, 0.86, 1.0))
        # right hip
        self.m.tri((ox1, oy0, z_eave), (ox1, oy1, z_eave),
                   (rx1, ym, z_ridge), material,
                   uvs=((oy0, 0.0), (oy1, 0.0),
                        (ym, math.hypot(rx1 - ox1, z_ridge - z_eave))),
                   ao=(0.86, 0.9, 1.0))
        if ridge and rx1 - rx0 > 1:
            self.box(rx0, ym - 2.0, rx1, ym + 2.0,
                     z_ridge - 1.0, z_ridge + 1.6, material, top=material)
        if fascia:
            for yy in (oy0, oy1):
                self.box(ox0, yy - 1.3, ox1, yy + 1.3,
                         z_eave - 3.0, z_eave, WOOD_DARK_MAT)

    def roof_pyramid(self, x0, y0, x1, y1, z_eave, z_ridge, material,
                     overhang=4.0) -> None:
        self._eave_trim(x0 - overhang, y0 - overhang, x1 + overhang,
                        y1 + overhang, z_eave)
        ox, oy = overhang, overhang
        ox0, ox1, oy0, oy1 = x0 - ox, x1 + ox, y0 - oy, y1 + oy
        xm, ym = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        apex = (xm, ym, z_ridge)
        corners = [(ox0, oy0), (ox1, oy0), (ox1, oy1), (ox0, oy1)]
        for i in range(4):
            a = corners[i]
            b = corners[(i + 1) % 4]
            # Rows of tiles run parallel to the eave, so each face gets its
            # own basis instead of the renderer's dominant-axis auto-UV.
            ex, ey = b[0] - a[0], b[1] - a[1]
            el = max(math.hypot(ex, ey), 1e-6)
            ex, ey = ex / el, ey / el
            mid_x, mid_y = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            pts = [a, b, (apex[0], apex[1])]
            heights = [z_eave, z_eave, z_ridge]
            uvs = []
            for (px, py), pz in zip(pts, heights):
                uu = (px - mid_x) * ex + (py - mid_y) * ey
                horizontal = math.hypot(px - mid_x, py - mid_y)
                vv = math.hypot(horizontal, pz - z_eave)
                uvs.append((uu, vv))
            self.m.tri((a[0], a[1], z_eave), (b[0], b[1], z_eave),
                       (apex[0], apex[1], z_ridge), material,
                       uvs=tuple(uvs), ao=(0.88, 0.88, 1.0))
        # Ridge finial.
        self.box(xm - 1.5, ym - 1.5, xm + 1.5, ym + 1.5,
                 z_ridge - 1.0, z_ridge + 4.0, GOLD_MAT)

    def roof_shed(self, x0, y0, x1, y1, z_high, z_low, axis, material,
                  high_side="y0", overhang=3.0, fascia=True) -> None:
        self._eave_trim(x0 - overhang, y0 - overhang, x1 + overhang,
                        y1 + overhang, min(z_high, z_low))
        ox, oy = overhang, overhang
        ox0, ox1, oy0, oy1 = x0 - ox, x1 + ox, y0 - oy, y1 + oy
        if axis == "y":
            if high_side == "y0":
                p = [(ox0, oy0, z_high), (ox1, oy0, z_high),
                     (ox1, oy1, z_low), (ox0, oy1, z_low)]
                eave_y, ze = oy0, z_high
            else:
                p = [(ox1, oy1, z_high), (ox0, oy1, z_high),
                     (ox0, oy0, z_low), (ox1, oy0, z_low)]
                eave_y, ze = oy1, z_high
            uvs = tuple((q[0], math.hypot(q[1] - eave_y, q[2] - ze)) for q in p)
            self.m.quad(*p, material, uvs=uvs, ao=(0.9, 0.9, 1.0, 1.0))
            if fascia:
                self.box(ox0, oy0 - 1.2, ox1, oy0 + 1.2, z_high - 3.0, z_high,
                         WOOD_DARK_MAT)
                self.box(ox0, oy1 - 1.2, ox1, oy1 + 1.2, z_low - 3.0, z_low,
                         WOOD_DARK_MAT)
        else:
            if high_side == "x0":
                p = [(ox0, oy0, z_high), (ox0, oy1, z_high),
                     (ox1, oy1, z_low), (ox1, oy0, z_low)]
                eave_x, ze = ox0, z_high
            else:
                p = [(ox1, oy1, z_high), (ox1, oy0, z_high),
                     (ox0, oy0, z_low), (ox0, oy1, z_low)]
                eave_x, ze = ox1, z_high
            uvs = tuple((q[1], math.hypot(q[0] - eave_x, q[2] - ze)) for q in p)
            self.m.quad(*p, material, uvs=uvs, ao=(0.9, 0.9, 1.0, 1.0))
            if fascia:
                self.box(ox0 - 1.2, oy0, ox0 + 1.2, oy1, z_high - 3.0, z_high,
                         WOOD_DARK_MAT)
                self.box(ox1 - 1.2, oy0, ox1 + 1.2, oy1, z_low - 3.0, z_low,
                         WOOD_DARK_MAT)

    def roof_cone(self, cx, cy, z_eave, z_apex, radius, material,
                  segments=12, overhang=3.0) -> None:
        r = radius + overhang
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0), z_eave)
            p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1), z_eave)
            self.m.tri(p0, p1, (cx, cy, z_apex), material,
                       uvs=((a0 * r, 0.0), (a1 * r, 0.0),
                            ((a0 + a1) * 0.5 * r, z_apex - z_eave)),
                       ao=(0.9, 0.9, 1.0))
        # A little gold finial.
        self.m.tri((cx - 1, cy, z_apex), (cx, cy + 1, z_apex),
                   (cx, cy, z_apex + 5), GOLD_MAT)

    # -- curved solids ----------------------------------------------------
    def cylinder(self, cx, cy, z0, z1, radius, material, segments=12,
                 cap=True, cap_material=None, ao_base=0.8,
                 group: int | None = None) -> None:
        cap_material = material if cap_material is None else cap_material
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            p0 = (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0)
            p1 = (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0)
            p2 = (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z1)
            p3 = (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z1)
            self.m.quad(p0, p1, p2, p3, material,
                        uvs=((a0 * radius, z0), (a1 * radius, z0),
                             (a1 * radius, z1), (a0 * radius, z1)),
                        ao=(ao_base, ao_base, 1.0, 1.0), group=group)
        if cap:
            for i in range(segments):
                a0 = 2 * math.pi * i / segments
                a1 = 2 * math.pi * (i + 1) / segments
                self.m.tri((cx, cy, z1),
                           (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z1),
                           (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z1),
                           cap_material, ao=(1.0, 1.0, 1.0), group=group)
                self.m.tri((cx, cy, z0),
                           (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0),
                           (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0),
                           material, ao=(0.5, 0.5, 0.5), group=group)

    def cylinder_between(self, p0, p1, radius, material, segments=10,
                         cap=True) -> None:
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
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            o0 = u * (radius * math.cos(a0)) + v * (radius * math.sin(a0))
            o1 = u * (radius * math.cos(a1)) + v * (radius * math.sin(a1))
            self.m.quad(tuple(a + o0), tuple(a + o1), tuple(b + o1), tuple(b + o0),
                        material,
                        uvs=((a0 * radius, 0.0), (a1 * radius, 0.0),
                             (a1 * radius, length), (a0 * radius, length)),
                        ao=(0.86, 0.86, 1.0, 1.0))
        if cap:
            for i in range(segments):
                a0 = 2 * math.pi * i / segments
                a1 = 2 * math.pi * (i + 1) / segments
                o0 = u * (radius * math.cos(a0)) + v * (radius * math.sin(a0))
                o1 = u * (radius * math.cos(a1)) + v * (radius * math.sin(a1))
                self.m.tri(tuple(b), tuple(b + o0), tuple(b + o1), material,
                           ao=(1.0, 1.0, 1.0))
                self.m.tri(tuple(a), tuple(a + o1), tuple(a + o0), material,
                           ao=(0.5, 0.5, 0.5))

    def ellipsoid(self, cx, cy, cz, rx, ry, rz, material, segments=10,
                  rings=6, ao_base=0.78) -> None:
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
                    self.m.tri(p00, p11, p01, material, ao=(ao0, ao1, ao1))
                elif j == rings - 1:
                    self.m.tri(p00, p10, p01, material, ao=(ao0, ao0, ao1))
                else:
                    self.m.quad(p00, p10, p11, p01, material,
                                uvs=((a0 * rx, t0 * rz), (a1 * rx, t0 * rz),
                                     (a1 * rx, t1 * rz), (a0 * rx, t1 * rz)),
                                ao=(ao0, ao0, ao1, ao1))

    def cone(self, cx, cy, z0, z1, radius, material, segments=10,
             cap=True, group: int | None = None) -> None:
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            p0 = (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0)
            p1 = (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0)
            self.m.tri(p0, p1, (cx, cy, z1), material,
                       uvs=((a0 * radius, 0.0), (a1 * radius, 0.0),
                            ((a0 + a1) * 0.5 * radius, z1 - z0)),
                       ao=(0.9, 0.9, 1.0), group=group)
        if cap:
            for i in range(segments):
                a0 = 2 * math.pi * i / segments
                a1 = 2 * math.pi * (i + 1) / segments
                self.m.tri((cx, cy, z0),
                           (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0),
                           (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0),
                           material, ao=(0.5, 0.5, 0.5), group=group)

    # -- trim -------------------------------------------------------------
    def _eave_trim(self, x0, y0, x1, y1, z) -> None:
        """Soffit ceiling, fascia and gutter under a roof's eave."""
        self.box(x0, y0, x1, y1, z - 2.6, z - 1.0, TIMBER_DARK, top=WOOD_DARK_MAT,
                 bottom=False)
        for yy in (y0, y1):
            self.cylinder_between((x0, yy, z - 1.8), (x1, yy, z - 1.8),
                                  1.15, SLATE_DARK_MAT, segments=5, cap=False)
        for xx in (x0, x1):
            self.cylinder_between((xx, y0, z - 1.8), (xx, y1, z - 1.8),
                                  1.15, SLATE_DARK_MAT, segments=5, cap=False)

    def dormer(self, x0, x1, y_front, y_back, z_base, height, roof,
               wall=PLASTER_PALE, window_frame=WOOD_DARK):
        """A gabled dormer whose little roof runs out of the main slope."""
        self.box(x0, y_back, x1, y_front, z_base, z_base + height, wall)
        self.roof_gable(x0, y_back, x1, y_front, z_base + height,
                        z_base + height + 11.0, "y", roof, overhang=2.0,
                        gable_material=wall, ridge=False, fascia=False)
        a0 = (x0 + x1) * 0.5 - 6.0
        self.window("front", (x0, y_back, x1, y_front), a0, a0 + 12.0,
                    z_base + 2.0, z_base + height - 3.0, frame=window_frame)

    def window_box(self, side, wall, a0, a1, z, colour=PINK_MAT):
        x0, y0, x1, y1 = wall
        if side in ("front", "back"):
            yy = y1 if side == "front" else y0
            off = 1 if side == "front" else -1
            self.box(min(a0, a1) - 1, yy + off * 0.2, max(a0, a1) + 1,
                     yy + off * 5.0, z - 5.0, z, TIMBER)
        else:
            xx = x1 if side == "right" else x0
            off = 1 if side == "right" else -1
            self.box(xx + off * 0.2, min(a0, a1) - 1, xx + off * 5.0,
                     max(a0, a1) + 1, z - 5.0, z, TIMBER)
        for frac in (0.2, 0.5, 0.8):
            ax = a0 + (a1 - a0) * frac
            if side in ("front", "back"):
                cx = ax
                cy = (y1 if side == "front" else y0) + (3.0 if side == "front" else -3.0)
            else:
                cx = (x1 if side == "right" else x0) + (3.0 if side == "right" else -3.0)
                cy = ax
            self.ellipsoid(cx, cy, z + 2.5, 2.6, 2.4, 2.4, colour,
                           segments=5, rings=3)

    def porch(self, side, wall, a0, a1, z_floor, roof, depth=13.0, height=40.0):
        x0, y0, x1, y1 = wall
        if side not in ("front", "back"):
            return
        yy = y1 if side == "front" else y0
        off = 1 if side == "front" else -1
        y_out = yy + off * depth
        # Posts.
        for ax in (min(a0, a1) + 2, max(a0, a1) - 2):
            self.cylinder(ax, y_out - off * 1.5, z_floor, height, 2.0,
                          STONE_MAT, segments=7)
            self.box(ax - 3, y_out - off * 4.5 - 1.5, ax + 3,
                     y_out - off * 4.5 + 1.5, height - 2, height + 2, STONE_MAT)
        # Canopy.
        self.roof_shed(min(a0, a1), min(yy, y_out), max(a0, a1), max(yy, y_out),
                       height + 8.0, height + 3.0, "y", roof,
                       high_side="y0" if off > 0 else "y1", overhang=2.0,
                       fascia=True)

    # -- wall openings ----------------------------------------------------
    def wall_point(self, side, wall, a, off, z):
        x0, y0, x1, y1 = wall
        if side == "front":
            return (a, y1 + off, z)
        if side == "back":
            return (a, y0 - off, z)
        if side == "right":
            return (x1 + off, a, z)
        return (x0 - off, a, z)

    def _screen_left_to_right(self, side, wall, a0, a1, z):
        """Choose the along-wall direction that reads left-to-right on screen."""
        p0 = self.wall_point(side, wall, a0, 6.0, z)
        p1 = self.wall_point(side, wall, a1, 6.0, z)
        from render import project
        s0 = project(*p0, self.facing)[0]
        s1 = project(*p1, self.facing)[0]
        return (a0, a1) if s0 <= s1 else (a1, a0)

    def side_visible(self, side, wall, z) -> bool:
        """Whether a wall's outer face points towards this view rotation."""
        from render import project
        x0, y0, x1, y1 = wall
        a = (x0 + x1) * 0.5 if side in ("front", "back") else (y0 + y1) * 0.5
        inner = self.wall_point(side, wall, a, 0.0, z)
        outer = self.wall_point(side, wall, a, 10.0, z)
        ru0 = project(*inner, self.facing)
        ru1 = project(*outer, self.facing)
        # Moving out of the wall towards the viewer moves down the screen at
        # this projection; depth is the better test: project both points and
        # compare their isometric depth.
        from render import rotate_uv, TILE_W, TILE_H
        def depth(p):
            u, v = p[0] / TILE_W, p[1] / TILE_H
            rr = rotate_uv(u, v, self.facing)
            return rr[0] + rr[1] + p[2] / TILE_H
        return depth(outer) >= depth(inner)

    def wall_decal(self, side, wall, a0, a1, z0, z1, material,
                   off=1.0, bias=0.02, name=None):
        if not self.side_visible(side, wall, (z0 + z1) * 0.5):
            return
        a0, a1 = self._screen_left_to_right(side, wall, a0, a1, (z0 + z1) * 0.5)
        p0 = self.wall_point(side, wall, a0, off, z1)
        p1 = self.wall_point(side, wall, a1, off, z1)
        p2 = self.wall_point(side, wall, a1, off, z0)
        p3 = self.wall_point(side, wall, a0, off, z0)
        width = max(1.0, abs(a1 - a0))
        height = max(1.0, abs(z1 - z0))
        self.m.decal(p0, p1, p2, p3, material, (width, height), bias=bias)

    def window(self, side, wall, a0, a1, z0, z1, frame=None,
               lit=False, shutters=False, sill=True):
        width = max(6, int(round(abs(a1 - a0))))
        height = max(8, int(round(abs(z1 - z0))))
        texture, _ = window_texture(width, height, frame=frame, lit=lit)
        self.wall_decal(side, wall, a0, a1, z0, z1, _tex_material(texture),
                        off=0.8, bias=0.015)
        x0, y0, x1, y1 = wall
        if sill:
            if side in ("front", "back"):
                sx0, sx1 = min(a0, a1) - 2, max(a0, a1) + 2
                yy = y1 if side == "front" else y0
                off_sign = 1 if side == "front" else -1
                self.box(sx0, yy + off_sign * 0.4, sx1, yy + off_sign * 3.2,
                         z0 - 2.2, z0, STONE_MAT)
            else:
                sy0, sy1 = min(a0, a1) - 2, max(a0, a1) + 2
                xx = x1 if side == "right" else x0
                off_sign = 1 if side == "right" else -1
                self.box(xx + off_sign * 0.4, sy0, xx + off_sign * 3.2, sy1,
                         z0 - 2.2, z0, STONE_MAT)
        if shutters:
            span = max(a1, a0) - min(a1, a0)
            for sign in (-1, 1):
                sa = (min(a0, a1) - span * 0.28) if sign < 0 else (max(a0, a1) + span * 0.02)
                sb = sa + span * 0.26
                if side in ("front", "back"):
                    yy = y1 if side == "front" else y0
                    off_sign = 1 if side == "front" else -1
                    self.box(sa, yy + off_sign * 0.2, sb, yy + off_sign * 1.8,
                             z0, z1, TIMBER_LIGHT)
                else:
                    xx = x1 if side == "right" else x0
                    off_sign = 1 if side == "right" else -1
                    self.box(xx + off_sign * 0.2, sa, xx + off_sign * 1.8, sb,
                             z0, z1, TIMBER_LIGHT)

    def door(self, side, wall, a0, a1, z0, z1, colour=None, frame=None,
             steps=True, awning=False):
        width = max(8, int(round(abs(a1 - a0))))
        height = max(10, int(round(abs(z1 - z0))))
        texture, _ = door_texture(width, height, colour=colour, frame=frame)
        self.wall_decal(side, wall, a0, a1, z0, z1, _tex_material(texture),
                        off=0.9, bias=0.015)
        x0, y0, x1, y1 = wall
        # Stone stoop.
        if steps:
            if side in ("front", "back"):
                yy = y1 if side == "front" else y0
                off_sign = 1 if side == "front" else -1
                self.box(min(a0, a1) - 3, yy, max(a0, a1) + 3, yy + off_sign * 7,
                         0.0, 3.0, STONE_MAT, top=PAVE)
            else:
                xx = x1 if side == "right" else x0
                off_sign = 1 if side == "right" else -1
                self.box(xx, min(a0, a1) - 3, xx + off_sign * 7, max(a0, a1) + 3,
                         0.0, 3.0, STONE_MAT, top=PAVE)
        # Lintel.
        if side in ("front", "back"):
            yy = y1 if side == "front" else y0
            off_sign = 1 if side == "front" else -1
            self.box(min(a0, a1) - 2, yy, max(a0, a1) + 2, yy + off_sign * 2.4,
                     z1, z1 + 2.0, STONE_MAT)
        else:
            xx = x1 if side == "right" else x0
            off_sign = 1 if side == "right" else -1
            self.box(xx, min(a0, a1) - 2, xx + off_sign * 2.4, max(a0, a1) + 2,
                     z1, z1 + 2.0, STONE_MAT)

    def sign(self, side, wall, a_center, z, text, fg=CREAM, bg=ROOF_GREEN,
             scale=1, padding=2, off=2.2, border=None):
        texture, (tw, th) = text_texture(text, fg, bg, scale, padding, border)
        half = tw * 0.5
        z0 = z
        z1 = z + th
        material = _tex_material(texture)
        # Board behind the text, proud of the wall.
        x0, y0, x1, y1 = wall
        if side in ("front", "back"):
            yy = y1 if side == "front" else y0
            off_sign = 1 if side == "front" else -1
            self.box(a_center - half - 1, yy + off_sign * 0.2,
                     a_center + half + 1, yy + off_sign * off,
                     z0 - 1, z1 + 1, bg)
        else:
            xx = x1 if side == "right" else x0
            off_sign = 1 if side == "right" else -1
            self.box(xx + off_sign * 0.2, a_center - half - 1,
                     xx + off_sign * off, a_center + half + 1,
                     z0 - 1, z1 + 1, bg)
        self.wall_decal(side, wall, a_center - half, a_center + half,
                        z0, z1, material, off=off + 0.5, bias=0.02)
        return tw, th

    def awning(self, side, wall, a0, a1, z_top, colour_a=ROOF_RED,
               colour_b=CREAM, depth=24.0, drop=10.0, valance=4.0,
               posts=True, label=None, label_fg=CREAM, label_bg=ROOF_GREEN):
        stripe = mat(colour_a, "stripe", colour_b)
        x0, y0, x1, y1 = wall
        if side in ("front", "back"):
            yy = y1 if side == "front" else y0
            off = 1 if side == "front" else -1
            p0 = (min(a0, a1), yy, z_top)
            p1 = (max(a0, a1), yy, z_top)
            p2 = (max(a0, a1), yy + off * depth, z_top - drop)
            p3 = (min(a0, a1), yy + off * depth, z_top - drop)
            self.m.quad(p0, p1, p2, p3, stripe,
                        uvs=((p0[0], 0.0), (p1[0], 0.0),
                             (p2[0], depth), (p3[0], depth)),
                        ao=(0.94, 0.94, 1.0, 1.0), bias=0.05)
            # Valance skirt.
            q0 = (min(a0, a1), yy + off * depth, z_top - drop)
            q1 = (max(a0, a1), yy + off * depth, z_top - drop)
            q2 = (max(a0, a1), yy + off * depth, z_top - drop - valance)
            q3 = (min(a0, a1), yy + off * depth, z_top - drop - valance)
            self.m.quad(q0, q1, q2, q3, stripe,
                        uvs=((q0[0], 0.0), (q1[0], 0.0),
                             (q2[0], valance), (q3[0], valance)),
                        ao=(1.0, 1.0, 0.96, 0.96))
            if label:
                texture, (tw, th) = text_texture(label, label_fg, label_bg)
                cx = (min(a0, a1) + max(a0, a1)) * 0.5
                z1 = z_top - drop - valance - 1.0
                z0 = z1 - th
                y_out = yy + off * depth
                # Hanging board, proud of the awning's outer edge.
                self.box(cx - tw * 0.5 - 2, min(y_out, y_out + off * 2.0),
                         cx + tw * 0.5 + 2, max(y_out, y_out + off * 2.0),
                         z0 - 2.0, z1 + 2.0, label_bg)
                self.wall_decal("front" if off > 0 else "back",
                                (x0, y_out, x1, y_out),
                                cx - tw * 0.5, cx + tw * 0.5, z0, z1,
                                _tex_material(texture), off=2.4, bias=0.03)
            if posts:
                for ax in (min(a0, a1) + 3, max(a0, a1) - 3):
                    self.cylinder(ax, yy + off * (depth - 3), 0.0,
                                  z_top - drop - valance, 1.6, WOOD_LIGHT_MAT,
                                  segments=6)
        else:
            xx = x1 if side == "right" else x0
            off = 1 if side == "right" else -1
            p0 = (xx, min(a0, a1), z_top)
            p1 = (xx, max(a0, a1), z_top)
            p2 = (xx + off * depth, max(a0, a1), z_top - drop)
            p3 = (xx + off * depth, min(a0, a1), z_top - drop)
            self.m.quad(p0, p1, p2, p3, stripe,
                        uvs=((p0[1], 0.0), (p1[1], 0.0),
                             (p2[1], depth), (p3[1], depth)),
                        ao=(0.94, 0.94, 1.0, 1.0), bias=0.05)
            q0 = (xx + off * depth, min(a0, a1), z_top - drop)
            q1 = (xx + off * depth, max(a0, a1), z_top - drop)
            q2 = (xx + off * depth, max(a0, a1), z_top - drop - valance)
            q3 = (xx + off * depth, min(a0, a1), z_top - drop - valance)
            self.m.quad(q0, q1, q2, q3, stripe,
                        uvs=((q0[1], 0.0), (q1[1], 0.0),
                             (q2[1], valance), (q3[1], valance)),
                        ao=(1.0, 1.0, 0.96, 0.96))
            if posts:
                for ay in (min(a0, a1) + 3, max(a0, a1) - 3):
                    self.cylinder(xx + off * (depth - 3), ay, 0.0,
                                  z_top - drop - valance, 1.6, WOOD_LIGHT_MAT,
                                  segments=6)

    def bench(self, x, y, along="x", z=0.0):
        if along == "x":
            self.box(x, y, x + 28, y + 10, z + 5, z + 8, WOOD_LIGHT_MAT, top=WOOD_MAT)
            self.box(x, y, x + 3, y + 10, z, z + 5, WOOD_DARK_MAT)
            self.box(x + 25, y, x + 28, y + 10, z, z + 5, WOOD_DARK_MAT)
            self.box(x, y, x + 28, y + 2, z + 13, z + 20, WOOD_LIGHT_MAT)
            self.box(x, y, x + 2, y + 2, z + 8, z + 13, WOOD_DARK_MAT)
            self.box(x + 26, y, x + 28, y + 2, z + 8, z + 13, WOOD_DARK_MAT)
        else:
            self.box(x, y, x + 10, y + 28, z + 5, z + 8, WOOD_LIGHT_MAT, top=WOOD_MAT)
            self.box(x, y, x + 10, y + 3, z, z + 5, WOOD_DARK_MAT)
            self.box(x, y + 25, x + 10, y + 28, z, z + 5, WOOD_DARK_MAT)
            self.box(x, y, x + 2, y + 28, z + 13, z + 20, WOOD_LIGHT_MAT)
            self.box(x, y, x + 2, y + 2, z + 8, z + 13, WOOD_DARK_MAT)
            self.box(x, y + 26, x + 2, y + 28, z + 8, z + 13, WOOD_DARK_MAT)

    def string_lights(self, x0, y0, x1, y1, z, count=7, sag=4.0):
        steps = max(2, count)
        for i in range(steps):
            t0 = i / steps
            t1 = (i + 1) / steps
            p0 = (x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0,
                  z - sag * math.sin(math.pi * t0))
            p1 = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1,
                  z - sag * math.sin(math.pi * t1))
            self.cylinder_between(p0, p1, 0.45, SLATE_DARK_MAT, segments=4,
                                  cap=False)
        for i in range(1, steps):
            t = i / steps
            cx = x0 + (x1 - x0) * t
            cy = y0 + (y1 - y0) * t
            cz = z - sag * math.sin(math.pi * t) - 2.0
            self.ellipsoid(cx, cy, cz, 1.8, 1.8, 2.2, LAMP_MAT,
                           segments=5, rings=3)

    # -- scenery ----------------------------------------------------------
    def planter(self, cx, cy, z=0.0, size=9.0):
        self.box(cx - size, cy - size, cx + size, cy + size, z, z + 8.0,
                 STONE_MAT, top=STONE_DARK_MAT)
        self.box(cx - size + 2, cy - size + 2, cx + size - 2, cy + size - 2,
                 z + 8.0, z + 9.0, C("6b4a33"))
        self.bush(cx, cy, z + 8.0, 0.7)

    def bush(self, cx, cy, z=0.0, scale=1.0, material=HEDGE) -> None:
        r = 13.0 * scale
        self.ellipsoid(cx, cy, z + r * 0.9, r, r * 0.92, r * 0.8,
                       material, segments=8, rings=5, ao_base=0.7)
        self.ellipsoid(cx + r * 0.55, cy + r * 0.15, z + r * 0.7,
                       r * 0.7, r * 0.65, r * 0.62, HEDGE_LIGHT,
                       segments=7, rings=4, ao_base=0.72)

    def flower_bed(self, x0, y0, x1, y1, z=0.0, colour=PINK_MAT):
        self.box(x0, y0, x1, y1, z, z + 3.0, WOOD_MAT, top=C("6b4a33"))
        rng = np.random.default_rng(int(x0 * 13 + y0 * 7 + x1 * 3))
        for _ in range(7):
            cx = float(rng.uniform(x0 + 2, max(x0 + 3, x1 - 2)))
            cy = float(rng.uniform(y0 + 2, max(y0 + 3, y1 - 2)))
            self.ellipsoid(cx, cy, z + 5.0, 2.4, 2.2, 2.0, colour,
                           segments=5, rings=3)

    def palm(self, cx, cy, z=0.0, height=52.0, scale=1.0):
        lean = 5.0 * scale
        z0 = z
        points = [(cx, cy, z0), (cx + lean * 0.25, cy, z0 + height * 0.35),
                  (cx + lean * 0.7, cy, z0 + height * 0.72),
                  (cx + lean, cy, z0 + height)]
        for i in range(3):
            self.cylinder_between(points[i], points[i + 1], 2.6 * scale,
                                  TIMBER, segments=7, cap=False)
        top = points[-1]
        self.ellipsoid(top[0], top[1], top[2] + 2, 5.5 * scale, 5.0 * scale,
                       4.0 * scale, HEDGE_DARK, segments=7, rings=4)
        for k in range(7):
            angle = 2 * math.pi * k / 7 + 0.3
            dx = math.cos(angle)
            dy = math.sin(angle)
            length = 25.0 * scale
            droop = 9.0 * scale
            tip = (top[0] + dx * length, top[1] + dy * length,
                   top[2] - droop)
            left = (top[0] - dy * 4.5 * scale, top[1] + dx * 4.5 * scale,
                    top[2] + 2)
            right = (top[0] + dy * 4.5 * scale, top[1] - dx * 4.5 * scale,
                     top[2] + 2)
            mat_leaf = HEDGE_LIGHT if k % 2 == 0 else HEDGE
            self.m.tri(left, tip, right, mat_leaf,
                       uvs=((0.0, 0.0), (length, 4.0), (0.0, 8.0)),
                       ao=(1.0, 0.86, 1.0))
        for k in range(3):
            angle = 2 * math.pi * k / 3
            self.ellipsoid(top[0] + math.cos(angle) * 4, top[1] + math.sin(angle) * 4,
                           top[2] - 2, 2.4, 2.4, 2.4, C("6b4a33"),
                           segments=5, rings=3)

    def flag(self, cx, cy, z0=0.0, height=44.0, colour=RED, width=26.0,
             logo=None):
        self.cylinder(cx, cy, z0, z0 + height, 1.3, WHITE_MAT, segments=6)
        self.cylinder(cx, cy, z0 + height, z0 + height + 3, 2.0, GOLD_MAT,
                      segments=6)
        wave = 3.0
        p0 = (cx + 1.2, cy, z0 + height - 2)
        p1 = (cx + 1.2 + width, cy, z0 + height - 2 - wave)
        p2 = (cx + 1.2 + width, cy, z0 + height - 14 - wave)
        p3 = (cx + 1.2, cy, z0 + height - 14)
        mat_flag = mat(colour, "flat")
        self.m.quad(p0, p1, p2, p3, mat_flag,
                    uvs=((0, 0), (width, 0), (width, 12), (0, 12)),
                    ao=(1.0, 1.0, 1.0, 1.0))
        # Back face so the flag reads from either side of the course.
        self.m.quad(p3, p2, p1, p0, mat_flag,
                    uvs=((0, 12), (width, 12), (width, 0), (0, 0)),
                    ao=(1.0, 1.0, 1.0, 1.0))

    def ball(self, cx, cy, z=0.0, r=2.2):
        self.ellipsoid(cx, cy, z + r, r, r, r, WHITE_MAT, segments=6, rings=4)

    def lounger(self, x, y, along="x", colour=PINK_MAT):
        if along == "x":
            # Legs, a slatted seat and a tilted backrest: reads as a sun bed
            # rather than a stack of coloured boxes.
            for dx in (4, 21):
                for dy in (1, 7):
                    self.box(x + dx, y + dy, x + dx + 2, y + dy + 2, 0.0, 2.4,
                             WOOD_DARK_MAT)
            self.box(x + 1, y, x + 27, y + 10, 2.4, 4.0, WHITE_MAT, top=colour)
            for dx in range(5, 26, 4):
                self.box(x + dx, y + 1, x + dx + 2, y + 9, 4.0, 4.4,
                         WHITE_MAT, skip=("x+", "x-", "y+", "y-"))
            q = ((x + 2, y, 12.0), (x + 2, y + 10, 12.0),
                 (x + 7, y + 10, 4.2), (x + 7, y, 4.2))
            self.m.quad(*q, WHITE_MAT,
                        uvs=((0, 0), (10, 0), (10, 8), (0, 8)))
            q2 = ((x + 2.4, y + 1, 11.4), (x + 2.4, y + 9, 11.4),
                  (x + 6.2, y + 9, 4.8), (x + 6.2, y + 1, 4.8))
            self.m.quad(*q2, colour,
                        uvs=((0, 0), (8, 0), (8, 6.6), (0, 6.6)))
            self.box(x + 7, y + 2, x + 12, y + 8, 4.0, 5.6, WHITE_MAT)
            self.cylinder_between((x + 19, y + 2, 5.0), (x + 19, y + 8, 5.0),
                                  1.4, WHITE_MAT, segments=5)
        else:
            for dy in (4, 21):
                for dx in (1, 7):
                    self.box(x + dx, y + dy, x + dx + 2, y + dy + 2, 0.0, 2.4,
                             WOOD_DARK_MAT)
            self.box(x, y + 1, x + 10, y + 27, 2.4, 4.0, WHITE_MAT, top=colour)
            q = ((x, y + 2, 12.0), (x + 10, y + 2, 12.0),
                 (x + 10, y + 7, 4.2), (x, y + 7, 4.2))
            self.m.quad(*q, WHITE_MAT,
                        uvs=((0, 0), (10, 0), (10, 8), (0, 8)))
            q2 = ((x + 1, y + 2.4, 11.4), (x + 9, y + 2.4, 11.4),
                  (x + 9, y + 6.2, 4.8), (x + 1, y + 6.2, 4.8))
            self.m.quad(*q2, colour,
                        uvs=((0, 0), (8, 0), (8, 6.6), (0, 6.6)))
            self.box(x + 2, y + 7, x + 8, y + 12, 4.0, 5.6, WHITE_MAT)

    def umbrella(self, cx, cy, z=0.0, radius=17.0, colour_a=ROOF_RED,
                 colour_b=CREAM):
        self.cylinder(cx, cy, z, z + 34, 1.2, WOOD_LIGHT_MAT, segments=5)
        segments = 8
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            p0 = (cx, cy, z + 42)
            p1 = (cx + radius * math.cos(a0), cy + radius * math.sin(a0), z + 31)
            p2 = (cx + radius * math.cos(a1), cy + radius * math.sin(a1), z + 31)
            self.m.tri(p0, p1, p2, mat(colour_a if i % 2 == 0 else colour_b),
                       ao=(1.0, 0.9, 0.9))

    def fence(self, x0, y0, x1, y1, z0=0.0, height=14.0, spacing=16.0,
              material=WOOD_LIGHT_MAT, axis="x"):
        if axis == "x":
            count = max(2, int(round(abs(x1 - x0) / spacing)) + 1)
            for i in range(count):
                x = x0 + (x1 - x0) * i / (count - 1)
                self.box(x - 1, y0 - 1, x + 1, y0 + 1, z0, z0 + height, material)
            for h in (height * 0.45, height * 0.85):
                self.box(x0, y0 - 0.8, x1, y0 + 0.8, z0 + h - 1.2, z0 + h, material)
        else:
            count = max(2, int(round(abs(y1 - y0) / spacing)) + 1)
            for i in range(count):
                y = y0 + (y1 - y0) * i / (count - 1)
                self.box(x0 - 1, y - 1, x0 + 1, y + 1, z0, z0 + height, material)
            for h in (height * 0.45, height * 0.85):
                self.box(x0 - 0.8, y0, x0 + 0.8, y1, z0 + h - 1.2, z0 + h, material)

    def lamp_post(self, cx, cy, z=0.0, height=34.0):
        self.cylinder(cx, cy, z, z + height, 1.4, SLATE_DARK_MAT, segments=6)
        self.ellipsoid(cx, cy, z + height + 3, 3.2, 3.2, 3.2, LAMP_MAT,
                       segments=6, rings=4)
        self.box(cx - 3.6, cy - 3.6, cx + 3.6, cy + 3.6,
                 z + height - 1, z + height + 0.5, SLATE_DARK_MAT)

    def crate(self, x, y, z=0.0, size=10.0):
        self.box(x, y, x + size, y + size, z, z + size, TIMBER_LIGHT,
                 top=WOOD_LIGHT_MAT)

    def barrel(self, cx, cy, z=0.0, r=6.0, height=14.0):
        self.cylinder(cx, cy, z, z + height, r, TIMBER,
                      segments=10, cap_material=WOOD_LIGHT_MAT)
        for h in (3.0, height - 3.0):
            self.cylinder(cx, cy, z + h, z + h + 1.2, r + 0.8, SLATE_DARK_MAT,
                          segments=10, cap=False)

    def shadow_rect(self, x0, y0, x1, y1, z=0.8, material=SHADOW_MAT):
        self.m.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z),
                    material, ao=(1.0, 1.0, 1.0, 1.0), bias=0.02)

    def contact_shadow(self, x0, y0, x1, y1, z=0.8, spread=5.0):
        self.shadow_rect(x0 - spread, y0 - spread, x1 + spread, y1 + spread,
                         z, SHADOW_SOFT)
        self.shadow_rect(x0, y0, x1, y1, z + 0.1, SHADOW_MAT)

    # -- vehicles ---------------------------------------------------------
    def golf_cart(self, x, y, z=0.0, colour=CREAM_MAT, roof=ROOF_GREEN_MAT):
        # Chassis, body tub and a contrasting side flash.
        self.box(x + 2, y + 2, x + 34, y + 18, z + 4, z + 6, INK_MAT)
        self.box(x, y, x + 34, y + 18, z + 6, z + 14, colour)
        self.box(x + 1, y - 0.8, x + 33, y + 0.8, z + 8, z + 11, roof, top=roof)
        self.box(x + 1, y + 17.2, x + 33, y + 18.8, z + 8, z + 11, roof, top=roof)
        # Bench seat with a backrest, dash and steering wheel.
        self.box(x + 6, y + 3, x + 22, y + 15, z + 13, z + 16, TIMBER_LIGHT)
        self.box(x + 6, y + 13, x + 22, y + 16, z + 16, z + 25, INK_MAT)
        self.box(x + 26, y + 2, x + 33, y + 16, z + 14, z + 19, colour)
        self.box(x + 28, y + 6, x + 31, y + 12, z + 19, z + 20, INK_MAT)
        self.cylinder_between((x + 28, y + 9, z + 19), (x + 30, y + 9, z + 25),
                              1.0, SLATE_DARK_MAT, segments=5)
        self.cylinder_between((x + 29, y + 7, z + 25), (x + 31, y + 11, z + 25),
                              2.2, INK_MAT, segments=6)
        # Wheels with pale hubs.
        for dx in (8, 27):
            for wy in (y - 0.5, y + 18.5):
                self.cylinder_between((x + dx, wy - 1.6, z + 5.5),
                                      (x + dx, wy + 1.6, z + 5.5),
                                      4.6, INK_MAT, segments=8)
                self.cylinder_between((x + dx, wy - 1.8, z + 5.5),
                                      (x + dx, wy + 1.8, z + 5.5),
                                      2.1, STONE_LIGHT, segments=6)
        # Canopy posts and a slightly oversized roof.
        for dx, dy in ((4, 2), (30, 2), (4, 16), (30, 16)):
            self.box(x + dx - 1, y + dy - 1, x + dx + 1, y + dy + 1,
                     z + 15, z + 31, WHITE_MAT)
        self.box(x + 1, y - 2, x + 35, y + 20, z + 31, z + 33, roof)
        self.box(x + 2, y - 1, x + 34, y + 19, z + 30.4, z + 31, WHITE_MAT)
        # Headlights and a bumper.
        self.box(x + 33, y + 3, x + 34.4, y + 6, z + 10, z + 12, LAMP_MAT)
        self.box(x + 33, y + 12, x + 34.4, y + 15, z + 10, z + 12, LAMP_MAT)
        self.box(x + 33, y + 1, x + 35, y + 17, z + 5, z + 7, SLATE_MAT)

    def plane(self, cx, cy, z=0.0):
        """A light aircraft: a raised hull, low tapered wings and a small prop."""
        white = WHITE_MAT
        trim = RED_MAT
        # Fuselage with a tapered nose and tail cone.
        self.box(cx - 40, cy - 9, cx + 24, cy + 9, z + 5, z + 17, white)
        self.box(cx + 24, cy - 7, cx + 36, cy + 7, z + 6.5, z + 15.5, white)
        self.box(cx + 36, cy - 5, cx + 43, cy + 5, z + 8, z + 14, white)
        self.box(cx - 46, cy - 6, cx - 40, cy + 6, z + 9, z + 15, white)
        # Cheat-line, belly and cabin windows.
        for side in (-1, 1):
            self.box(cx - 38, cy + side * 9 - 0.6, cx + 24,
                     cy + side * 9 + 0.6, z + 11, z + 13.5, trim)
            for wx in (-30, -22, -14):
                self.box(cx + wx, cy + side * 9 - 0.8, cx + wx + 5,
                         cy + side * 9 + 0.8, z + 13.5, z + 16.2,
                         GLASS_DARK_MAT)
        self.box(cx - 34, cy - 8.6, cx + 22, cy + 8.6, z + 5, z + 6.4, BLUE_MAT)
        # Cockpit canopy.
        self.box(cx + 2, cy - 6.5, cx + 20, cy + 6.5, z + 17, z + 20.5,
                 GLASS_DARK_MAT)
        self.box(cx + 4, cy - 5.5, cx + 18, cy + 5.5, z + 20.5, z + 21.5,
                 GLASS_MAT)
        for wx in (7, 12, 17):
            self.box(cx + wx, cy - 6.8, cx + wx + 1.2, cy + 6.8,
                     z + 17.5, z + 20.5, WHITE_MAT)
        # Wings: low, thin and tapered, so the hull stays readable from above.
        for side in (-1, 1):
            self.box(cx - 9, cy + side * 7, cx + 9, cy + side * 30,
                     z + 8.5, z + 11.5, white, top=C("efede2"))
            self.box(cx - 13, cy + side * 30, cx + 3, cy + side * 40,
                     z + 9, z + 11, white, top=C("efede2"))
            self.box(cx - 13, cy + side * 40 - 1, cx - 10,
                     cy + side * 40 + 1, z + 10, z + 12,
                     RED_MAT if side < 0 else C("5fd47a"))
            self.cylinder_between((cx - 4, cy + side * 24, z + 8.5),
                                  (cx - 2, cy + side * 8, z + 6),
                                  0.8, SLATE_DARK_MAT, segments=4)
        # Tailplane, fin and rudder.
        self.box(cx - 44, cy - 22, cx - 28, cy + 22, z + 11.5, z + 13.5,
                 white, top=C("efede2"))
        self.box(cx - 46, cy - 2, cx - 38, cy + 2, z + 13, z + 29, white)
        self.box(cx - 47, cy - 1.6, cx - 44, cy + 1.6, z + 14, z + 28, trim)
        self.box(cx - 44, cy - 2.4, cx - 37, cy + 2.4, z + 27, z + 29, BLUE_MAT)
        # Spinner and a compact two-blade propeller.
        self.cylinder_between((cx + 43, cy, z + 11), (cx + 49, cy, z + 11),
                              2.2, SLATE_DARK_MAT, segments=6)
        self.box(cx + 48, cy - 13, cx + 50, cy + 13, z + 10.6, z + 11.4,
                 SLATE_DARK_MAT)
        self.box(cx + 48, cy - 1, cx + 50, cy + 1, z + 2, z + 20,
                 SLATE_DARK_MAT)
        # Landing gear.
        for wy in (cy - 14, cy + 14):
            self.cylinder_between((cx + 4, wy, z + 8.5), (cx + 4, wy, z + 4),
                                  0.9, SLATE_DARK_MAT, segments=5)
            self.cylinder_between((cx + 2, wy - 1.4, z + 4),
                                  (cx + 6, wy + 1.4, z + 4),
                                  2.2, INK_MAT, segments=6)

    # -- ferris wheel -----------------------------------------------------
    def ferris_wheel(self, cx, cy, z, radius, facing):
        from render import rotate_uv
        # The wheel plane is turned to face this pre-rendered camera.  A
        # world-pixel direction whose projected y is zero keeps the wheel
        # round from every rotation instead of collapsing to a sliver.
        base_x, base_y = -2.0, 1.0
        length = math.hypot(base_x * 64.0, base_y * 32.0)
        dx = base_x * 64.0 / length
        dy = base_y * 32.0 / length
        # Undo the view rotation to get the direction in model space.
        u, v = dx / 64.0, dy / 32.0
        u, v = rotate_uv(u, v, (-facing) % FACING_COUNT)
        dx, dy = u * 64.0, v * 32.0
        d = np.array([dx, dy, 0.0], dtype=float)
        d /= np.linalg.norm(d)
        up = np.array([0.0, 0.0, 1.0])
        normal = np.cross(d, up)
        centre = np.array([cx, cy, z], dtype=float)
        segments = 28
        ring_points = []
        for i in range(segments):
            angle = 2 * math.pi * i / segments
            p = centre + d * (radius * math.cos(angle)) + up * (radius * math.sin(angle))
            ring_points.append(tuple(p))
        for i in range(segments):
            a = ring_points[i]
            b = ring_points[(i + 1) % segments]
            self.cylinder_between(a, b, 2.2, SLATE_MAT, segments=5, cap=False)
        # Spokes.
        hub = centre
        for i in range(0, segments, 2):
            p = ring_points[i]
            self.cylinder_between(tuple(hub), p, 1.0, SLATE_DARK_MAT,
                                  segments=4, cap=False)
        self.ellipsoid(cx, cy, z, 5.0, 5.0, 5.0, GOLD_MAT, segments=8, rings=5)
        # Gondolas.
        colours = [RED_MAT, BLUE_MAT, YELLOW_MAT, PINK_MAT]
        for i in range(0, segments, 2):
            angle = 2 * math.pi * i / segments
            p = ring_points[i]
            gx, gy, gz = float(p[0]), float(p[1]), float(p[2])
            self.cylinder_between((gx, gy, gz), (gx, gy, gz - 5), 1.0,
                                  SLATE_DARK_MAT, segments=4, cap=False)
            self.box(gx - 5, gy - 5, gx + 5, gy + 5, gz - 13, gz - 5,
                     colours[(i // 2) % 4], top=ROOF_RED_MAT)
        # A-frame supports, splayed in the facing plane.
        for sign in (-1, 1):
            foot = centre + d * (radius * 0.95 * sign)
            foot[2] = z * 0.0 + 2.0
            self.cylinder_between(tuple(foot), (cx, cy, z), 2.6,
                                  SLATE_MAT, segments=6, cap=False)
        self.cylinder_between((cx - abs(d[0]) * radius * 0.55,
                               cy - abs(d[1]) * radius * 0.55, 4),
                              (cx + abs(d[0]) * radius * 0.55,
                               cy + abs(d[1]) * radius * 0.55, 4),
                              2.0, SLATE_DARK_MAT, segments=5, cap=False)


# ---------------------------------------------------------------------------
# facilities
# ---------------------------------------------------------------------------

def _wall_shadows(b: Builder, x0, y0, x1, y1, z, spread=5.0):
    """Soft contact shadows on the terrace around a wall rectangle."""
    b.shadow_rect(x0 - spread, y0 - spread, x0, y1 + spread, z, SHADOW_SOFT)
    b.shadow_rect(x0, y1, x1 + spread, y1 + spread, z, SHADOW_MAT)
    b.shadow_rect(x1, y0 - spread, x1 + spread, y1, z, SHADOW_MAT)


def clubhouse(b: Builder, tier: int) -> None:
    roof = {1: ROOF_RED_MAT, 2: ROOF_BROWN_MAT, 3: ROOF_SLATE_MAT}[tier]
    roof_dark = {1: ROOF_RED_DARK, 2: ROOF_BROWN_DARK, 3: ROOF_SLATE_DARK}[tier]
    b.slab(8, 6, 248, 122, -2.0, 1.5, PAVE, kerb=KERB, inset=4, top=PAVE)
    # A path to the front edge, flanked by planters.
    b.box(112, 104, 148, 123, 1.5, 2.6, PAVE_DARK, top=PAVE)
    # Contact shading under the eaves and along the walls.
    _wall_shadows(b, 36, 20, 220, 100, 3.0, 6.0)

    if tier == 1:
        x0, y0, x1, y1 = 36, 20, 220, 100
        wall_h = 60.0
        b.box(x0, y0, x1, y1, 2.0, 9.0, STONE_WALL_DARK, top=STONE_MAT)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 8.0, wall_h, PLASTER)
        b.roof_hip(x0, y0, x1, y1, wall_h, wall_h + 21.0, roof,
                   overhang=7.0, fascia=True)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, wall_h - 4, wall_h, CREAM_MAT)
        # Chimney with a stone cap and a curl of smoke.
        b.box(170, 38, 188, 56, wall_h + 9, wall_h + 36, STONE_WALL_DARK)
        b.box(168, 36, 190, 58, wall_h + 36, wall_h + 40, STONE_DARK_MAT)
        b.ellipsoid(180, 46, wall_h + 44, 5, 5, 4, SMOKE, segments=6, rings=4)
        b.ellipsoid(186, 42, wall_h + 53, 7, 6, 5, SMOKE, segments=6, rings=4)
        # Door, fanlight and club plaque.
        b.door("front", (x0, y0, x1, y1), 118, 138, 3, 31)
        b.window("front", (x0, y0, x1, y1), 115, 141, 32, 39, frame=WOOD_DARK)
        b.sign("front", (x0, y0, x1, y1), 128, 44, "CLUB", fg=CREAM,
               bg=ROOF_GREEN, border=GOLD, scale=2)
        # Bay of windows either side of the entrance.
        for ax in (58, 76, 180, 198):
            b.window("front", (x0, y0, x1, y1), ax, ax + 16, 30, 48,
                     shutters=True)
        for ay in (36, 62):
            b.window("right", (x0, y0, x1, y1), ay, ay + 16, 30, 48)
            b.window("left", (x0, y0, x1, y1), ay, ay + 16, 30, 48)
        b.window("back", (x0, y0, x1, y1), 100, 116, 32, 48)
        b.window("back", (x0, y0, x1, y1), 150, 166, 32, 48)
        # A gabled dormer looking out over the entrance.
        b.dormer(106, 142, 86, 64, 64.0, 15.0, roof)
        # Stone entrance surround, window boxes and a lamp.
        b.box(105, 100, 111, 105, 3.0, 42.0, STONE_MAT)
        b.box(145, 100, 151, 105, 3.0, 42.0, STONE_MAT)
        b.box(103, 100, 153, 105, 42.0, 46.0, STONE_MAT)
        b.box(107, 100, 149, 105, 46.0, 48.0, STONE_DARK_MAT)
        b.window_box("front", (x0, y0, x1, y1), 58, 74, 30)
        b.window_box("front", (x0, y0, x1, y1), 180, 196, 30)
        b.lamp_post(160, 114, 2.6, 26.0)
        # Flag, planters and a couple of stray balls.
        b.flag(232, 108, 2.0, 72.0, ROOF_GREEN, width=28)
        b.planter(24, 110, 2.0, 11)
        b.planter(238, 30, 2.0, 10)
        b.ball(96, 112, 2.2)
        b.lounger(64, 106, "x")

    elif tier == 2:
        x0, y0, x1, y1 = 32, 16, 220, 96
        wall_h = 72.0
        b.box(x0, y0, x1, y1, 2.0, 9.0, STONE_WALL_DARK, top=STONE_MAT)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 8.0, wall_h, PLASTER)
        b.roof_hip(x0, y0, x1, y1, wall_h, wall_h + 22.0, roof,
                   overhang=7.0, fascia=True)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, wall_h - 4, wall_h, CREAM_MAT)
        # Pro-shop wing with a shed roof and a long striped awning.
        wx0, wy0, wx1, wy1 = 32, 96, 100, 118
        b.box(wx0, wy0, wx1, wy1, 2.0, 8.0, STONE_WALL_DARK, top=STONE_MAT)
        b.box(wx0 + 1, wy0 + 1, wx1 - 1, wy1 - 1, 7.0, 44.0, PLASTER_PALE)
        b.roof_shed(wx0, wy0, wx1, wy1, 48.0, 42.0, "y", roof,
                    high_side="y0", overhang=4.0, fascia=True)
        b.awning("front", (wx0, wy0, wx1, wy1), 38, 94, 37.0,
                 ROOF_GREEN, CREAM, depth=17.0, drop=7.0, valance=3.0,
                 posts=True)
        b.window("front", (wx0, wy0, wx1, wy1), 44, 66, 16, 30)
        b.sign("front", (wx0, wy0, wx1, wy1), 76, 16, "SHOP", fg=CREAM,
               bg=ROOF_GREEN, scale=1)
        # Entrance.
        b.door("front", (x0, y0, x1, y1), 118, 138, 3, 33)
        b.window("front", (x0, y0, x1, y1), 114, 142, 34, 42, frame=WOOD_DARK)
        b.sign("front", (x0, y0, x1, y1), 128, 47, "CLUB", fg=CREAM,
               bg=ROOF_GREEN, border=GOLD, scale=2)
        for ax in (56, 74, 178, 196):
            b.window("front", (x0, y0, x1, y1), ax, ax + 16, 34, 54,
                     shutters=True)
        for ax in (112, 144):
            b.window("front", (x0, y0, x1, y1), ax, ax + 16, 58, 70)
        for ay in (30, 56):
            b.window("right", (x0, y0, x1, y1), ay, ay + 16, 34, 54)
            b.window("left", (x0, y0, x1, y1), ay, ay + 16, 34, 54)
        b.window("back", (x0, y0, x1, y1), 96, 112, 36, 54)
        b.window("back", (x0, y0, x1, y1), 150, 166, 36, 54)
        # Two dormers over the entrance range.
        b.dormer(80, 114, 92, 66, 76.0, 15.0, roof)
        b.dormer(150, 184, 92, 66, 76.0, 15.0, roof)
        b.window_box("front", (x0, y0, x1, y1), 56, 72, 34)
        b.window_box("front", (x0, y0, x1, y1), 178, 194, 34)
        b.lamp_post(106, 112, 2.6, 28.0)
        b.lamp_post(150, 112, 2.6, 28.0)
        b.box(176, 34, 194, 52, wall_h + 10, wall_h + 42, STONE_WALL_DARK)
        b.box(174, 32, 196, 54, wall_h + 42, wall_h + 46, STONE_DARK_MAT)
        b.ellipsoid(185, 42, wall_h + 50, 5, 5, 4, SMOKE, segments=6, rings=4)
        b.flag(230, 108, 2.0, 82.0, ROOF_BROWN, width=30)
        b.planter(22, 110, 2.0, 11)
        b.planter(236, 24, 2.0, 10)
        b.planter(242, 108, 2.0, 9)
        b.flower_bed(12, 24, 26, 46, 1.5, PINK_MAT)
        b.ball(56, 112, 2.2)
        b.lounger(74, 106, "x")

    else:
        x0, y0, x1, y1 = 32, 14, 222, 88
        wall_h = 104.0
        b.box(x0, y0, x1, y1, 2.0, 10.0, STONE_WALL_DARK, top=STONE_MAT)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 9.0, wall_h, PLASTER)
        b.roof_hip(x0, y0, x1, y1, wall_h, wall_h + 20.0, roof,
                   overhang=7.0, fascia=True)
        b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, wall_h - 4, wall_h, CREAM_MAT)
        # Ground-floor front range with the long signboard awning.
        fx0, fy0, fx1, fy1 = 32, 88, 204, 116
        b.box(fx0, fy0, fx1, fy1, 2.0, 9.0, STONE_WALL_DARK, top=STONE_MAT)
        b.box(fx0 + 1, fy0 + 1, fx1 - 1, fy1 - 1, 8.0, 54.0, PLASTER)
        b.roof_shed(fx0, fy0, fx1, fy1, 58.0, 52.0, "y", roof,
                    high_side="y0", overhang=4.0, fascia=True)
        b.awning("front", (fx0, fy0, fx1, fy1), 80, 198, 48.0,
                 ROOF_GREEN, CREAM, depth=18.0, drop=7.0, valance=3.0,
                 posts=True, label="CLUBHOUSE")
        b.door("front", (fx0, fy0, fx1, fy1), 104, 128, 3, 30)
        b.window("front", (fx0, fy0, fx1, fy1), 142, 166, 16, 34)
        b.window("front", (fx0, fy0, fx1, fy1), 176, 198, 16, 34)
        # Upper windows across the hall.
        for ax in (36, 66, 96, 126, 156, 186):
            b.window("front", (x0, y0, x1, y1), ax, ax + 14, 62, 80)
            b.window("front", (x0, y0, x1, y1), ax, ax + 14, 84, 98)
        for ay in (28, 52):
            for zz in (30, 58, 84):
                b.window("right", (x0, y0, x1, y1), ay, ay + 14, zz, zz + 16)
                b.window("left", (x0, y0, x1, y1), ay, ay + 14, zz, zz + 16)
        b.window("back", (x0, y0, x1, y1), 84, 98, 62, 80)
        b.window("back", (x0, y0, x1, y1), 156, 170, 62, 80)
        # A central clock tower rising through the roof, so it reads against
        # the sky from every view rotation instead of hiding behind the ridge.
        tx0, ty0, tx1, ty1 = 100, 34, 156, 82
        b.box(tx0, ty0, tx1, ty1, 2.0, 12.0, STONE_DARK_MAT, top=STONE_MAT)
        b.box(tx0 + 1, ty0 + 1, tx1 - 1, ty1 - 1, 11.0, 150.0, PLASTER_WARM)
        b.box(tx0 - 1, ty0 - 1, tx1 + 1, ty1 + 1, 124.0, 128.0, STONE_MAT)
        b.box(tx0 - 2, ty0 - 2, tx1 + 2, ty1 + 2, 150.0, 154.0, STONE_MAT)
        b.roof_pyramid(tx0, ty0, tx1, ty1, 154.0, 164.0, roof, overhang=3.0)
        b.flag((tx0 + tx1) * 0.5, (ty0 + ty1) * 0.5, 164.0, 11.0,
               ROOF_SLATE, width=16)
        for side in ("right", "left"):
            wall = (tx0, ty0, tx1, ty1)
            a = (ty0 + ty1) * 0.5
            texture, (tw, th) = clock_texture(13)
            b.wall_decal(side, wall, a - 6.5, a + 6.5, 132, 145,
                         _tex_material(texture), off=1.2, bias=0.02)
        # Chimneys and dormers.
        b.box(170, 26, 190, 46, wall_h + 4, wall_h + 34, STONE_WALL_DARK)
        b.box(168, 24, 192, 48, wall_h + 34, wall_h + 38, STONE_DARK_MAT)
        b.ellipsoid(180, 36, wall_h + 42, 5, 5, 4, SMOKE, segments=6, rings=4)
        b.dormer(58, 90, 76, 50, 110.0, 15.0, roof)
        b.dormer(166, 198, 76, 50, 110.0, 15.0, roof)
        b.window_box("front", (x0, y0, x1, y1), 36, 50, 62)
        b.window_box("front", (x0, y0, x1, y1), 186, 200, 62)
        b.lamp_post(88, 114, 2.6, 30.0)
        b.lamp_post(160, 114, 2.6, 30.0)
        b.flag(232, 108, 2.0, 88.0, ROOF_SLATE, width=32)
        b.planter(20, 110, 2.0, 11)
        b.planter(238, 22, 2.0, 10)
        b.planter(242, 106, 2.0, 9)
        b.flower_bed(10, 22, 24, 44, 1.5, PINK_MAT)
        b.ball(60, 112, 2.2)
        b.lounger(80, 106, "x")
        b.lounger(108, 106, "x")


BUILDINGS = {
    "clubhouse": {"tiles": (4, 4), "tiers": 3, "draw": clubhouse},
}


# ---------------------------------------------------------------------------

def putting_green(b: Builder, tier: int) -> None:
    b.ground(0, 0, 192, 96, GRASS_MAT, z=0.0, thickness=2.0)
    b.box(12, 12, 180, 84, 0.8, 1.8, C("6aa957"), top=C("6aa957"))
    b.box(20, 20, 172, 76, 1.8, 3.0, mat(C("84ce6e"), "grass"), top=mat(C("84ce6e"), "grass"))
    # Mowing stripes.
    for i in range(5):
        x0 = 28 + i * 28
        shade = GREEN_MAT if i % 2 == 0 else mat(C("9bdd80"), "grass")
        b.box(x0, 26, x0 + 14, 70, 3.0, 3.4, shade, top=shade, skip=("x+", "x-", "y+", "y-"))
    # Bunker: a shallow sand patch with a darker lip, flat-shaded so the
    # radial facets do not read as a starburst.
    b.ellipsoid(44, 72, 2.0, 19, 11, 0.5,
                mat(C("c9bb92"), unlit=True), segments=18, rings=3)
    b.ellipsoid(44, 72, 2.3, 17, 9.5, 0.6,
                mat(C("eadcb0"), unlit=True), segments=18, rings=3)
    # Cup and flag.
    b.box(104, 38, 109, 43, 3.4, 3.6, INK_MAT)
    b.flag(106, 40, 3.4, 42.0, RED, width=24)
    for cx, cy in ((78, 34), (62, 58), (134, 30), (120, 64), (146, 58)):
        b.ball(cx, cy, 3.4)
    # Bench, club rack and a tee marker.
    b.bench(24, 18, "x", 1.0)
    b.box(148, 20, 170, 24, 0.8, 12.0, TIMBER)
    for i in range(4):
        b.cylinder(152 + i * 5, 22, 12.0, 34.0, 1.2, WOOD_LIGHT_MAT, segments=5)
    b.cylinder(168, 34, 0.8, 22.0, 3.2, WOOD_MAT, segments=8)
    b.box(20, 84, 36, 90, 0.8, 2.2, STONE_MAT)


def snack_bar(b: Builder, tier: int) -> None:
    b.slab(4, 4, 124, 60, -2.0, 1.2, PAVE, kerb=KERB, inset=4, top=PAVE)
    b.box(9, 10, 34, 24, 1.2, 2.2, C("8b6b4a"), top=PAVE_DARK)
    # Kiosk.
    x0, y0, x1, y1 = 16, 14, 112, 48
    b.box(x0, y0, x1, y1, 1.2, 8.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 7.0, 38.0, PLASTER_PALE)
    b.roof_gable(x0, y0, x1, y1, 38.0, 54.0, "x", ROOF_RED_MAT,
                 overhang=5.0, gable_material=PLASTER_PALE)
    b.window("front", (x0, y0, x1, y1), 30, 58, 18, 31,
             frame=WOOD_DARK, lit=True)
    b.box(28, y1, 60, y1 + 8, 14.0, 17.0, CREAM_MAT, top=CREAM_DARK)
    b.awning("front", (x0, y0, x1, y1), 24, 68, 35.0, ROOF_RED, CREAM,
             depth=16.0, drop=6.0, valance=3.0, posts=True, label="SNACKS")
    b.door("front", (x0, y0, x1, y1), 84, 100, 1.2, 27)
    b.window("right", (x0, y0, x1, y1), 16, 32, 18, 32)
    # Menu board on a post.
    texture, (tw, th) = menu_texture(22, 16)
    b.box(114, 40, 117, 43, 1.2, 24.0, TIMBER)
    b.m.decal((113, 40, 12), (135, 40, 12), (135, 40, 12 - th),
              (113, 40, 12 - th), _tex_material(texture), (tw, th), bias=0.03)
    b.box(112, 40.5, 136, 41.5, 10, 28, WOOD_DARK_MAT)
    # Picnic table, bin and string lights.
    b.box(28, 54, 62, 58, 13.0, 15.0, WOOD_LIGHT_MAT, top=WOOD_MAT)
    b.box(28, 64, 62, 68, 13.0, 15.0, WOOD_LIGHT_MAT, top=WOOD_MAT)
    b.box(28, 58, 62, 64, 15.0, 16.0, WOOD_MAT, skip=("z-",))
    for dx in (30, 52):
        b.box(dx, 56, dx + 3, 66, 1.2, 13.0, WOOD_DARK_MAT)
    b.cylinder(118, 44, 1.2, 11.0, 3.4, SLATE_DARK_MAT, segments=8)
    b.cylinder(118, 44, 11.0, 12.4, 3.8, SLATE_MAT, segments=8)
    # Gable vent and a small attic window break up the blank end wall.
    vent, _ = window_texture(8, 8, frame=WOOD_DARK, mullions=False)
    b.wall_decal("right", (x0, y0, x1, y1), 25, 33, 41, 49,
                 _tex_material(vent), off=0.8, bias=0.02)
    b.window("right", (x0, y0, x1, y1), 24, 36, 28, 37, frame=WOOD_DARK)
    b.planter(12, 50, 1.2, 8)
    b.lamp_post(104, 56, 1.2, 30.0)
    b.string_lights(20, 6, 116, 6, 46.0, 6, 4.0)
    b.ball(74, 58, 1.2)


def pub(b: Builder, tier: int) -> None:
    b.slab(4, 4, 188, 60, -2.0, 1.3, PAVE_DARK, kerb=STONE_DARK_MAT, inset=4,
           top=GRAVEL)
    x0, y0, x1, y1 = 14, 8, 172, 50
    b.box(x0, y0, x1, y1, 1.3, 8.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 7.0, 44.0, STONE_WALL)
    b.roof_gable(x0, y0, x1, y1, 44.0, 72.0, "x", ROOF_BROWN_MAT,
                 overhang=6.0, gable_material=STONE_WALL)
    # Mock-Tudor framing on the front.
    for ax in (18, 44, 72, 100, 128, 158):
        b.box(ax, y1, ax + 3, y1 + 1.6, 8.0, 44.0, TIMBER_DARK)
    for zz in (8, 26, 43):
        b.box(x0, y1, x1, y1 + 1.6, zz, zz + 3.0, TIMBER_DARK)
    b.box(x0, y1, x1, y1 + 1.6, 8, 44, TIMBER_DARK, skip=("y+", "z+", "z-", "x+", "x-"))
    # Door and windows.
    b.door("front", (x0, y0, x1, y1), 78, 96, 1.3, 30, colour=WOOD,
           frame=STONE_MAT)
    b.box(74, y1, 100, y1 + 3, 30, 34, STONE_MAT)
    b.window("front", (x0, y0, x1, y1), 30, 50, 24, 40, lit=True,
             shutters=True)
    b.window("front", (x0, y0, x1, y1), 112, 132, 24, 40, lit=True,
             shutters=True)
    b.window("right", (x0, y0, x1, y1), 18, 36, 24, 40, shutters=True)
    b.window("left", (x0, y0, x1, y1), 18, 36, 24, 40, shutters=True)
    b.window("back", (x0, y0, x1, y1), 56, 76, 24, 40)
    b.window("front", (x0, y0, x1, y1), 56, 72, 52, 64, frame=WOOD_DARK)
    b.window("front", (x0, y0, x1, y1), 108, 124, 52, 64, frame=WOOD_DARK)
    # Chimney, smoke and a hanging bracket sign.
    b.box(38, 24, 54, 40, 48, 84, mat(C("9a5b45"), "brick"))
    b.box(36, 22, 56, 42, 84, 88, STONE_DARK_MAT)
    b.box(37, 23, 55, 41, 88, 89, STONE_DARK_MAT)
    b.ellipsoid(46, 32, 89, 4.6, 4.6, 3.6, SMOKE, segments=6, rings=4)
    b.ellipsoid(51, 28, 95, 5.0, 4.2, 3.6, SMOKE, segments=6, rings=4)
    b.box(136, y1, 140, y1 + 14, 36, 38, TIMBER_DARK)
    b.box(126, y1 + 10, 140, y1 + 14, 20, 38, TIMBER_DARK)
    texture, (tw, th) = text_texture("PUB", CREAM, ROOF_GREEN, 1, 3, GOLD)
    b.box(126, y1 + 10, 126 + tw, y1 + 13, 20 - th, 20, ROOF_GREEN)
    b.m.decal((126, y1 + 13.5, 20), (126 + tw, y1 + 13.5, 20),
              (126 + tw, y1 + 13.5, 20 - th), (126, y1 + 13.5, 20 - th),
              _tex_material(texture), (tw, th), bias=0.03)
    # Lantern by the door, barrels, bench and planters.
    b.cylinder(104, y1 + 4, 26, 30, 2.4, LAMP_MAT, segments=6)
    b.box(103, y1 + 3, 105, y1 + 4, 30, 34, TIMBER_DARK)
    b.barrel(158, y1 + 8, 1.3, 7.0, 16.0)
    b.barrel(170, y1 + 10, 1.3, 6.0, 14.0)
    b.bench(20, 54, "x", 1.3)
    b.planter(12, 54, 1.3, 8)
    b.planter(178, 50, 1.3, 8)
    b.flag(182, 12, 1.3, 60.0, ROOF_GREEN, width=24)
    b.ground(6, 52, 40, 60, PAVE, 1.3, 0.8)


def pro_shop(b: Builder, tier: int) -> None:
    b.slab(4, 4, 124, 60, -2.0, 1.2, PAVE, kerb=KERB, inset=4, top=PAVE)
    x0, y0, x1, y1 = 12, 10, 112, 50
    b.box(x0, y0, x1, y1, 1.2, 7.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 6.0, 46.0, PLASTER_PALE)
    b.roof_gable(x0, y0, x1, y1, 46.0, 64.0, "x", ROOF_GREEN_MAT,
                 overhang=5.0, gable_material=PLASTER_PALE)
    texture, (tw, th) = display_texture(22, 14)
    b.wall_decal("front", (x0, y0, x1, y1), 24, 24 + tw, 20, 20 + th,
                 _tex_material(texture), off=1.0, bias=0.02)
    b.awning("front", (x0, y0, x1, y1), 16, 52, 42.0, ROOF_GREEN, CREAM,
             depth=17.0, drop=6.0, valance=3.0, posts=True)
    b.door("front", (x0, y0, x1, y1), 70, 88, 1.2, 28)
    b.sign("front", (x0, y0, x1, y1), 80, 30, "PRO", fg=CREAM, bg=ROOF_GREEN,
           scale=1)
    b.window("right", (x0, y0, x1, y1), 14, 32, 22, 38)
    b.window("left", (x0, y0, x1, y1), 14, 32, 22, 38)
    b.window("back", (x0, y0, x1, y1), 44, 62, 22, 38)
    # Bag stand and a row of clubs.
    b.box(18, 52, 50, 55, 1.2, 3.0, WOOD_DARK_MAT)
    for i in range(3):
        cx = 22 + i * 11
        b.cylinder(cx, 53.5, 3.0, 24.0, 4.0, [RED_MAT, BLUE_MAT, YELLOW_MAT][i],
                   segments=8)
        b.cylinder(cx, 53.5, 24.0, 27.0, 2.6, INK_MAT, segments=6)
        b.cylinder(cx + 2, 53.5, 20.0, 34.0, 0.9, SLATE_MAT, segments=5)
    b.box(92, 52, 116, 56, 1.2, 13.0, TIMBER, top=WOOD_LIGHT_MAT)
    for i in range(4):
        b.cylinder(96 + i * 5, 54, 13.0, 36.0, 1.1, WOOD_LIGHT_MAT, segments=5)
    b.planter(110, 8, 1.2, 8)
    b.lamp_post(58, 56, 1.2, 30.0)
    b.ball(64, 56, 1.2)


def driving_range(b: Builder, tier: int) -> None:
    b.ground(2, 2, 382, 94, GRASS_MAT, z=0.0, thickness=2.0)
    b.box(8, 8, 376, 50, 0.8, 2.0, mat(C("8cc268"), "grass"),
          top=mat(C("8cc268"), "grass"))
    b.box(8, 52, 376, 92, 0.8, 1.8, mat(C("9bcf74"), "grass"),
          top=mat(C("9bcf74"), "grass"))
    x0, y0, x1, y1 = 16, 10, 368, 54
    b.box(x0, y0, x1, y1, 1.8, 6.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 5.0, 34.0, PLASTER_PALE,
          skip=("y+",))
    # A dark rear wall makes the six bays read as depth, not a flat facade.
    b.box(x0 + 3, y0 + 2, x1 - 3, y0 + 4, 5.0, 33.0, C("3b342c"))
    for i in range(6):
        ax = x0 + 8 + i * 50
        b.box(ax, y0 + 4, ax + 44, y0 + 6, 8.0, 26.0, C("4a4238"))
    b.roof_shed(x0, y0, x1, y1, 42.0, 34.0, "y", ROOF_GREEN_MAT,
                high_side="y0", overhang=5.0, fascia=True)
    for vx in (96, 264):
        b.box(vx, 16, vx + 18, 26, 40.0, 45.0, SLATE_DARK_MAT)
        b.box(vx + 2, 18, vx + 16, 24, 45.0, 46.0, SLATE_MAT)
    # Six open bays with padded dividers.
    for i in range(7):
        ax = x0 + 8 + i * 50
        b.box(ax, y1 - 6, ax + 4, y1 + 2, 2.0, 31.0, CREAM_MAT)
        b.box(ax - 1, y1 - 7, ax + 5, y1 + 3, 28.0, 31.0, CREAM_DARK,
              skip=("z+",))
    b.box(x0 + 6, y1 + 1, x1 - 6, y1 + 5, 2.0, 7.0, CREAM_DARK, top=CREAM_MAT)
    b.box(x0 + 6, y1 + 1, x1 - 6, y1 + 5, 7.0, 9.0, TIMBER_DARK)
    b.sign("front", (x0, y0, x1, y1), 56, 24, "RANGE", fg=CREAM,
           bg=ROOF_GREEN, scale=1)
    # Mats, baskets and balls.
    for i in range(6):
        mx = x0 + 14 + i * 50
        b.box(mx, 62, mx + 38, 86, 1.8, 2.4, mat(C("6fae57"), "grass"),
              top=mat(C("6fae57"), "grass"))
        b.box(mx + 12, 58, mx + 26, 62, 2.4, 3.0, STONE_DARK_MAT)
        b.cylinder(mx + 19, 60, 3.0, 10.0, 3.4, WOOD_LIGHT_MAT, segments=7)
        b.ball(mx + 8, 66, 2.4)
        b.ball(mx + 28, 74, 2.4)
    b.flag(338, 70, 2.0, 34.0, YELLOW, width=20)
    b.flag(250, 74, 2.0, 30.0, RED, width=18)
    b.flag(150, 78, 2.0, 26.0, BLUE, width=16)
    b.planter(350, 58, 2.0, 8)
    b.bench(330, 12, "x", 1.0)


def cart_garage(b: Builder, tier: int) -> None:
    # A three-bay cart port: a stone floor, a solid back wall and a deep open
    # front so the carts themselves are the subject of the sprite.
    b.slab(2, 2, 190, 62, -2.0, 1.2, GRAVEL, kerb=STONE_DARK_MAT, inset=4,
           top=GRAVEL)
    x0, y0, x1, y1 = 12, 10, 180, 54
    b.box(x0, y0, x1, y1, 1.2, 2.4, STONE_DARK_MAT, top=PAVE)
    # Back and side walls, open across the front.
    b.box(x0, y0, x1, y0 + 2, 2.4, 38.0, PLASTER_PALE, top=CREAM_MAT)
    b.box(x0, y0, x0 + 2, y1, 2.4, 38.0, PLASTER_PALE, top=CREAM_MAT)
    b.box(x1 - 2, y0, x1, y1, 2.4, 38.0, PLASTER_PALE, top=CREAM_MAT)
    # Posts, header beam and a three-bay shed roof.
    for px in (x0 + 2, 86, 90, x1 - 2):
        b.box(px - 2, y1 - 3, px + 2, y1 + 1, 2.4, 38.0, TIMBER_DARK)
    b.box(x0, y1 - 2, x1, y1 + 2, 38.0, 41.0, TIMBER_DARK)
    b.roof_shed(x0, y0, x1, y1, 50.0, 44.0, "y", ROOF_GREEN_MAT,
                high_side="y0", overhang=5.0, fascia=True)
    b.roof_shed(x0 + 9, y0 + 3, x1 - 9, y1 - 4, 49.5, 44.5, "y",
                mat(ROOF_GREEN_DARK, "slate"), high_side="y0", overhang=2.0,
                fascia=False)
    # Two carts on the pad, plus a divider, wheel stops and hanging lamps.
    for bx in (24, 100):
        b.golf_cart(bx, 30, 1.2)
        b.box(bx + 2, y1 - 8, bx + 46, y1 - 4, 1.2, 4.0, SLATE_DARK_MAT)
        b.box(bx + 14, y1 - 4, bx + 34, y1 - 2, 4.0, 4.6, CREAM_DARK)
    b.box(86, y0 + 2, 90, y1 - 2, 2.4, 38.0, TIMBER_DARK)
    for lx in (60, 136):
        b.box(lx, y0 + 8, lx + 2, y0 + 12, 36.0, 38.0, TIMBER_DARK)
        b.box(lx - 2, y0 + 9, lx + 4, y0 + 11, 34.0, 36.0, LAMP_MAT)
    b.sign("front", (x0, y0, x1, y1), 96, 25, "CARTS", fg=CREAM,
           bg=ROOF_GREEN, scale=1, off=3.0)
    b.golf_cart(132, 44, 1.2, colour=C("e8dfc9"))
    # Rooftop vent, a fuel pump and tidy planting.
    b.box(146, 20, 160, 34, 46, 51, SLATE_DARK_MAT)
    b.cylinder(153, 27, 51, 53, 6.0, SLATE_MAT, segments=8)
    b.cylinder(172, 14, 2.4, 24.0, 2.8, RED_MAT, segments=7)
    b.box(168, 12, 176, 16, 24, 27, SLATE_DARK_MAT)
    b.planter(10, 56, 1.2, 8)
    b.planter(176, 10, 1.2, 7)


def tennis_court(b: Builder, tier: int) -> None:
    # A 4x2 footprint: a doubles court with a proper run-back on all sides.
    b.ground(0, 0, 256, 64, GRASS_MAT, z=0.0, thickness=2.0)
    b.box(6, 4, 250, 60, 0.8, 2.0, C("b96950"), top=C("b96950"))
    b.box(12, 8, 244, 56, 2.0, 3.0, BLUE_MAT, top=BLUE_MAT)
    line = 2.0
    for x0, y0, x1, y1 in ((18, 12, 238, 12 + line), (18, 52 - line, 238, 52),
                           (18, 12, 18 + line, 52), (238 - line, 12, 238, 52),
                           (128, 12, 128 + line, 52), (70, 12, 70 + line, 52),
                           (186, 12, 186 + line, 52),
                           (18, 32 - line * 0.5, 238, 32 + line * 0.5)):
        b.box(x0, y0, x1, y1, 3.0, 3.3, WHITE_MAT, top=WHITE_MAT,
              skip=("x+", "x-", "y+", "y-"))
    # Net across the middle with posts and a real open mesh.
    net, (nw, nh) = net_texture(70, 16)
    z0, z1 = 3.0, 18.0
    b.m.decal((128, 10, z1), (128, 54, z1), (128, 54, z0), (128, 10, z0),
              Material_net(net), (70, 16), bias=0.02)
    b.cylinder(128, 9, 2.0, 22.0, 2.0, WOOD_DARK_MAT, segments=6)
    b.cylinder(128, 55, 2.0, 22.0, 2.0, WOOD_DARK_MAT, segments=6)
    b.box(126, 9, 130, 55, 20, 22, WHITE_MAT)
    # Corner posts, fence rails, bench and balls.
    for x, y in ((8, 5), (248, 5), (8, 59), (248, 59)):
        b.cylinder(x, y, 0.8, 16.0, 1.6, CREAM_DARK, segments=6)
    for y in (5, 59):
        for z in (7.0, 12.0):
            b.box(8, y - 0.8, 248, y + 0.8, z, z + 1.0, CREAM_DARK)
    b.bench(10, 20, "y", 0.8)
    b.ball(160, 42, 3.0)
    b.ball(176, 36, 3.0)
    b.planter(242, 52, 0.8, 7)


def Material_net(texture):
    from render import C, Material
    return Material(color=C("ffffff"), texture=texture, alpha=0.92, unlit=True)


def stable(b: Builder, tier: int) -> None:
    b.ground(2, 2, 190, 94, GRASS_MAT, z=0.0, thickness=2.0)
    b.box(10, 10, 156, 62, 0.8, 2.0, GRAVEL, top=GRAVEL)
    x0, y0, x1, y1 = 14, 8, 148, 56
    b.box(x0, y0, x1, y1, 2.0, 8.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 7.0, 48.0, TIMBER)
    b.roof_gable(x0, y0, x1, y1, 45.0, 77.0, "x", ROOF_BROWN_MAT,
                 overhang=6.0, gable_material=TIMBER)
    # Big split door and hayloft hatch.
    b.door("front", (x0, y0, x1, y1), 60, 88, 2.0, 32, colour=WOOD,
           frame=WHITE_MAT)
    b.box(74, y1, 76, y1 + 1.2, 2.0, 32.0, WHITE_MAT)
    b.box(84, y1, 108, y1 + 1.2, 32.0, 40.0, TIMBER_DARK)
    b.window("front", (x0, y0, x1, y1), 88, 100, 34, 44, frame=WHITE_MAT)
    b.window("front", (x0, y0, x1, y1), 28, 46, 24, 40)
    b.window("right", (x0, y0, x1, y1), 18, 34, 24, 40)
    b.window("left", (x0, y0, x1, y1), 18, 34, 24, 40)
    # Weathervane.
    b.cylinder(80, 28, 80, 90, 1.2, SLATE_DARK_MAT, segments=5)
    b.box(70, 27, 90, 29, 87, 89, SLATE_MAT)
    b.m.tri((78, 28, 92), (82, 28, 92), (80, 28, 97), RED_MAT)
    # Paddock fence, hay bales, trough and a horse.
    for x in range(160, 191, 10):
        b.box(x, 16, x + 2, 18, 0.8, 18.0, TIMBER_LIGHT)
    for z in (7.0, 13.0):
        b.box(158, 16, 190, 18, z, z + 1.4, TIMBER_LIGHT)
    b.box(158, 56, 190, 58, 0.8, 18.0, TIMBER_LIGHT, skip=("x+", "x-"))
    for i in range(3):
        b.box(158 + i * 13, 64 + (i % 2) * 8, 170 + i * 13, 76 + (i % 2) * 8,
              0.8, 10.0, HAY_MAT, top=HAY_MAT)
    b.box(166, 86, 186, 92, 0.8, 6.0, TIMBER)
    b.box(167, 87, 185, 91, 3.0, 3.6, WATER_DEEP_MAT)
    # A chestnut horse in the paddock: body, arched neck, head, ears,
    # mane, tail and hooves.
    hx, hy = 176, 34
    coat = C("8a5836")
    mane = C("4c2f1e")
    b.ellipsoid(hx, hy, 20, 14, 6.2, 7.4, coat, segments=10, rings=6)
    b.ellipsoid(hx - 12, hy, 21, 4.0, 5.4, 6.2, coat, segments=8, rings=5)
    b.cylinder_between((hx + 10, hy, 23), (hx + 16, hy, 30), 3.6, coat,
                       segments=7)
    b.ellipsoid(hx + 18, hy, 31, 4.8, 3.4, 3.8, coat, segments=8, rings=5)
    b.ellipsoid(hx + 22, hy, 29.5, 3.0, 2.4, 2.6, C("9a6640"),
                segments=7, rings=4)
    b.box(hx + 16, hy - 2, hx + 18, hy + 2, 33, 36, coat)
    b.box(hx + 16, hy - 2.2, hx + 17.4, hy - 1.0, 36, 38.6, coat)
    b.box(hx + 16, hy + 1.0, hx + 17.4, hy + 2.2, 36, 38.6, coat)
    b.box(hx + 12, hy - 1.2, hx + 17, hy + 1.2, 31, 35.6, mane)
    b.box(hx + 10, hy - 2.0, hx + 12, hy + 2.0, 28, 32, mane)
    b.box(hx + 23, hy - 1.6, hx + 24.4, hy + 1.6, 28, 30.4, INK_MAT)
    b.cylinder_between((hx - 15, hy, 24), (hx - 19, hy, 8), 1.8, mane,
                       segments=6)
    for dx in (-8, 0, 8, 12):
        b.cylinder_between((hx + dx, hy - 3, 15), (hx + dx, hy - 3, 1.2),
                           1.7, coat, segments=5)
        b.box(hx + dx - 1.2, hy - 4.2, hx + dx + 1.2, hy - 1.8, 0.8, 2.0,
              mane)
    # Saddle blanket and a stirrup.
    b.box(hx - 5, hy - 7.4, hx + 5, hy + 7.4, 26, 27.4, RED_MAT)
    b.box(hx - 2, hy - 8.2, hx + 2, hy - 7.4, 24, 27, GOLD_MAT)
    b.planter(8, 88, 0.8, 7)


def spa(b: Builder, tier: int) -> None:
    b.slab(2, 2, 190, 94, -2.0, 1.4, PAVE, kerb=STONE_DARK_MAT, inset=4,
           top=PAVE)
    # Treatment hut.
    x0, y0, x1, y1 = 10, 10, 78, 56
    b.box(x0, y0, x1, y1, 1.4, 7.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 6.0, 40.0, PLASTER_WARM)
    b.roof_hip(x0, y0, x1, y1, 40.0, 54.0, THATCH, overhang=6.0)
    b.door("front", (x0, y0, x1, y1), 28, 46, 1.4, 29, colour=WOOD)
    b.window("front", (x0, y0, x1, y1), 52, 66, 18, 32)
    b.window("right", (x0, y0, x1, y1), 14, 30, 18, 32)
    b.sign("front", (x0, y0, x1, y1), 36, 29, "SPA", fg=CREAM, bg=ROOF_GREEN,
           scale=1)
    # Bathing pool.
    px0, py0, px1, py1 = 92, 20, 180, 82
    b.pool(px0, py0, px1, py1, 1.4, 6.0, rim=5.0, coping=mat(STONE_LIGHT))
    # A couple of hard ripples instead of opaque steam blobs.
    for i in range(3):
        b.box(px0 + 22 + i * 26, py0 + 34 + (i % 2) * 14,
              px0 + 34 + i * 26, py0 + 35.4 + (i % 2) * 14, 4.9, 5.0,
              WHITE_MAT, skip=("x+", "x-", "y+", "y-"))
    b.lounger(94, 88, "x")
    b.lounger(126, 88, "x")
    b.lounger(158, 88, "x")
    b.umbrella(104, 92, 1.4, 16.0, PINK_MAT, CREAM)
    b.umbrella(168, 92, 1.4, 16.0, ROOF_GREEN, CREAM)
    b.palm(180, 12, 1.4, 58.0, 0.9)
    b.palm(86, 86, 1.4, 48.0, 0.75)
    b.box(84, 86, 92, 92, 1.4, 3.4, STONE_MAT, top=STONE_LIGHT)
    b.box(174, 84, 182, 91, 1.4, 3.0, STONE_MAT, top=STONE_LIGHT)
    b.lamp_post(84, 84, 1.4, 28.0)


def swim_club(b: Builder, tier: int) -> None:
    b.slab(2, 2, 254, 94, -2.0, 1.3, PAVE, kerb=STONE_DARK_MAT, inset=4,
           top=PAVE)
    x0, y0, x1, y1 = 10, 10, 88, 58
    b.box(x0, y0, x1, y1, 1.3, 7.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 6.0, 36.0, PLASTER_PALE)
    b.roof_gable(x0, y0, x1, y1, 36.0, 54.0, "x", mat(C("d18aa4"), "shingle"),
                 overhang=5.0, gable_material=PLASTER_PALE)
    b.door("front", (x0, y0, x1, y1), 28, 44, 1.3, 28, colour=WHITE,
           frame=PINK)
    b.door("front", (x0, y0, x1, y1), 56, 72, 1.3, 28, colour=BLUE,
           frame=PINK)
    # A hanging sign on the pool-side wall, below the eave so the roof
    # overhang cannot swallow it.
    b.sign("right", (x0, y0, x1, y1), 34, 26, "SWIM", fg=CREAM, bg=BLUE,
           scale=1, off=6.0)
    # Pool with lane lines.
    px0, py0, px1, py1 = 102, 12, 246, 86
    b.pool(px0, py0, px1, py1, 1.3, 5.0, rim=5.0)
    for i in range(1, 5):
        ly = py0 + 4 + i * 14
        b.box(px0 + 4, ly, px1 - 4, ly + 1.5, 4.5, 4.7, WHITE_MAT,
              top=WHITE_MAT, skip=("x+", "x-", "y+", "y-"))
    # Diving board and ladder.
    b.box(128, 4, 140, 12, 4.0, 6.0, WHITE_MAT, top=WHITE_MAT)
    b.box(132, 2, 150, 10, 6.0, 8.0, CREAM_MAT, top=CREAM_DARK)
    for x in (226, 238):
        b.cylinder(x, 8, 4.0, 20.0, 1.4, SLATE_MAT, segments=5)
    b.box(224, 8, 240, 10, 18, 21, SLATE_MAT)
    # Loungers, umbrellas and towels.
    for i in range(3):
        b.lounger(110 + i * 28, 88, "x", PINK_MAT if i % 2 else YELLOW_MAT)
    b.umbrella(104, 92, 1.3, 16.0, BLUE_MAT, CREAM)
    b.umbrella(198, 92, 1.3, 16.0, PINK_MAT, CREAM)
    b.planter(96, 88, 1.3, 7)
    b.planter(252, 10, 1.3, 7)
    b.ball(96, 46, 2.4)


def resort_hotel(b: Builder, tier: int) -> None:
    b.slab(4, 4, 252, 124, -2.0, 1.5, PAVE, kerb=KERB, inset=5, top=PAVE)
    x0, y0, x1, y1 = 20, 10, 236, 88
    b.box(x0, y0, x1, y1, 1.5, 8.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 7.0, 89.0, PLASTER_PALE)
    b.roof_hip(x0, y0, x1, y1, 89.0, 105.0, ROOF_SLATE_MAT,
               overhang=7.0, fascia=True)
    # Storeys: windows and front balconies.
    for floor in range(4):
        z0 = 18 + floor * 18
        for col in range(8):
            ax = 32 + col * 25
            b.window("front", (x0, y0, x1, y1), ax, ax + 14, z0, z0 + 15,
                     frame=WOOD_DARK)
        if floor > 0:
            b.box(26, y1, 230, y1 + 8, z0 - 5, z0 - 2, STONE_MAT)
            for ax in range(30, 230, 12):
                b.box(ax, y1 + 6, ax + 2, y1 + 8, z0 - 2, z0 + 6,
                      WHITE_MAT)
            b.box(26, y1 + 6, 230, y1 + 8, z0 + 5, z0 + 7, STONE_MAT)
    for floor in range(4):
        z0 = 18 + floor * 18
        for ay in (24, 48, 72):
            b.window("right", (x0, y0, x1, y1), ay, ay + 14, z0, z0 + 15)
            b.window("left", (x0, y0, x1, y1), ay, ay + 14, z0, z0 + 15)
        for ax in (60, 120, 180):
            b.window("back", (x0, y0, x1, y1), ax, ax + 14, z0, z0 + 15)
    # Entrance canopy, red carpet and sign.
    b.box(70, y1, 186, y1 + 30, 24, 28, WHITE_MAT, top=CREAM_MAT)
    for ax in (74, 182):
        b.cylinder(ax, y1 + 24, 1.5, 24.0, 2.0, STONE_MAT, segments=6)
    b.box(96, y1, 160, y1 + 44, 1.5, 2.6, MAROON, top=MAROON)
    b.sign("front", (70, y1, 186, y1 + 30), 128, 30, "HOTEL", fg=GOLD,
           bg=SLATE_DARK, border=GOLD, scale=2)
    b.box(114, y1, 142, y1 + 6, 1.5, 22.0, WOOD_DARK_MAT)
    b.door("front", (x0, y0, x1, y1), 112, 144, 2.0, 24, colour=WOOD)
    # Rooftop sign and flag.
    b.box(96, 44, 160, 48, 105, 115, MAROON)
    texture, (tw, th) = text_texture("GRAND", GOLD, MAROON, 2, 3, GOLD)
    sign_mat = _tex_material(texture)
    # A double-sided rooftop sign, readable from the front and the back.
    sx0 = 96 + (64 - tw) * 0.5
    b.m.decal((sx0, 48.6, 113), (sx0 + tw, 48.6, 113),
              (sx0 + tw, 48.6, 113 - th), (sx0, 48.6, 113 - th),
              sign_mat, (tw, th), bias=0.03)
    b.m.decal((sx0 + tw, 43.4, 113), (sx0, 43.4, 113),
              (sx0, 43.4, 113 - th), (sx0 + tw, 43.4, 113 - th),
              sign_mat, (tw, th), bias=0.03)
    b.flag(238, 104, 1.5, 78.0, ROOF_SLATE, width=30)
    b.palm(12, 104, 1.5, 68.0, 1.0)
    b.palm(244, 104, 1.5, 68.0, 1.0)
    b.planter(16, 20, 1.5, 9)
    b.planter(240, 20, 1.5, 9)
    b.lounger(34, 110, "x")
    b.lounger(58, 110, "x")
    b.lounger(198, 110, "x")
    b.umbrella(46, 114, 1.5, 16.0, ROOF_SLATE, CREAM)
    b.umbrella(210, 114, 1.5, 16.0, ROOF_SLATE, CREAM)


def airstrip(b: Builder, tier: int) -> None:
    b.ground(0, 0, 320, 96, ASPHALT, z=0.0, thickness=2.0)
    b.box(6, 6, 314, 90, 0.8, 1.6, ASPHALT_LIGHT, top=ASPHALT_LIGHT)
    for i in range(10):
        x0 = 12 + i * 30
        b.box(x0, 47, x0 + 16, 49, 1.7, 1.9, WHITE_MAT, top=WHITE_MAT,
              skip=("x+", "x-", "y+", "y-"))
    # Hangar with a wide open front and a bright interior.
    x0, y0, x1, y1 = 10, 10, 144, 58
    b.box(x0, y0, x1, y1, 1.6, 7.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0, y0, x1, y0 + 2, 7.0, 38.0, PLASTER_PALE, top=CREAM_MAT)
    b.box(x0, y0, x0 + 2, y1, 7.0, 38.0, PLASTER_PALE, top=CREAM_MAT)
    b.box(x1 - 2, y0, x1, y1, 7.0, 38.0, PLASTER_PALE, top=CREAM_MAT)
    b.box(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 7.0, 7.6, PAVE_DARK, top=PAVE_DARK)
    b.box(x0 + 2, y0 + 2, x1 - 2, y0 + 4, 7.6, 30.0, C("4a4f55"))
    b.roof_shed(x0, y0, x1, y1, 46.0, 38.0, "y", ROOF_GREEN_MAT,
                high_side="y0", overhang=5.0, fascia=True)
    # Door frame: jambs, a header and open sliding doors.
    for px in (x0 + 2, x1 - 6):
        b.box(px, y1 - 3, px + 4, y1 + 1, 7.0, 36.0, CREAM_MAT)
    b.box(x0 + 2, y1 - 3, x1 - 2, y1 + 1, 36.0, 39.0, CREAM_DARK)
    b.box(x0 + 6, y1 - 2, x0 + 26, y1 - 1, 8.0, 34.0, C("c9c2ad"))
    b.box(x1 - 26, y1 - 2, x1 - 6, y1 - 1, 8.0, 34.0, C("c9c2ad"))
    for gx in range(x0 + 8, x0 + 26, 5):
        b.box(gx, y1 - 1.2, gx + 1.4, y1 - 0.6, 9.0, 34.0, SLATE_DARK_MAT)
    for gx in range(x1 - 24, x1 - 6, 5):
        b.box(gx, y1 - 1.2, gx + 1.4, y1 - 0.6, 9.0, 34.0, SLATE_DARK_MAT)
    b.sign("front", (x0, y0, x1, y1), 77, 28, "HANGAR", fg=CREAM,
           bg=ROOF_GREEN, scale=1, off=2.4)
    # A fuel bowser parked inside the open bay.
    b.box(x0 + 16, y0 + 12, x0 + 40, y0 + 26, 7.6, 13.0, RED_MAT,
          top=CREAM_MAT)
    b.box(x0 + 18, y0 + 14, x0 + 38, y0 + 24, 13.0, 16.0, SLATE_DARK_MAT)
    for wx in (x0 + 19, x0 + 35):
        b.cylinder_between((wx, y0 + 12, 9.6), (wx, y0 + 12, 7.0),
                           2.0, INK_MAT, segments=6)
    # Parked light plane.
    b.plane(226, 48, 1.6)
    # Windsock and fuel drums.
    b.cylinder(292, 26, 1.6, 38.0, 1.4, WHITE_MAT, segments=5)
    for i in range(3):
        colour = [RED_MAT, WHITE_MAT, RED_MAT][i]
        b.m.quad((292, 26, 37 - i * 4), (292 + 14, 26, 36 - i * 4),
                 (292 + 14, 26, 31 - i * 4), (292, 26, 32 - i * 4),
                 colour, uvs=((0, 0), (14, 0), (14, 4), (0, 4)),
                 ao=(1.0, 1.0, 1.0, 1.0))
    for i in range(2):
        b.cylinder(152 + i * 18, 76, 1.6, 14.0, 5.0, RED_MAT, segments=8)
    b.flag(304, 8, 1.6, 24.0, YELLOW, width=16)
    b.planter(140, 16, 1.6, 7)


def castle(b: Builder, tier: int) -> None:
    b.slab(2, 2, 318, 126, -2.0, 1.5, GRAVEL, kerb=STONE_DARK_MAT, inset=4,
           top=GRAVEL)
    stone = STONE_WALL
    dark = STONE_WALL_DARK
    keep = (80, 24, 240, 88)
    b.box(*keep, 1.5, 12.0, dark, top=STONE_DARK_MAT)
    b.box(keep[0] + 1, keep[1] + 1, keep[2] - 1, keep[3] - 1, 11.0, 66.0, stone)
    b.box(keep[0] + 4, keep[1] + 4, keep[2] - 4, keep[3] - 4, 66.0, 68.0,
          STONE_DARK_MAT)
    # Crenellations around the keep.
    for x in range(keep[0] + 4, keep[2] - 6, 14):
        b.box(x, keep[1] + 2, x + 8, keep[1] + 9, 66, 76, stone)
        b.box(x, keep[3] - 9, x + 8, keep[3] - 2, 66, 76, stone)
    for y in range(keep[1] + 16, keep[3] - 10, 14):
        b.box(keep[0] + 2, y, keep[0] + 9, y + 8, 66, 76, stone)
        b.box(keep[2] - 9, y, keep[2] - 2, y + 8, 66, 76, stone)
    # Gatehouse: two piers, a lintel and a genuinely open arch with a
    # raised portcullis, instead of a dark rectangle painted on a solid box.
    gx0, gy0, gx1, gy1 = 136, 80, 184, 106
    gz = 54.0
    b.box(gx0, gy0, gx0 + 10, gy1, 1.5, gz, stone)
    b.box(gx1 - 10, gy0, gx1, gy1, 1.5, gz, stone)
    b.box(gx0 + 10, gy0, gx1 - 10, gy1, 34.0, gz, stone)
    b.box(gx0, gy0, gx1, gy1, gz, gz + 3.0, STONE_DARK_MAT)
    # Interior: a dark rear wall and floor, visible through the arch.
    b.box(gx0 + 10, gy0, gx1 - 10, gy0 + 2, 1.5, 34.0, C("241f1c"))
    b.box(gx0 + 10, gy0 + 2, gx1 - 10, gy1 - 2, 1.5, 2.4, STONE_DARK_MAT,
          top=C("3a332c"))
    # Arch trim and portcullis bars.
    b.box(gx0 + 8, gy1 - 3, gx1 - 8, gy1 + 1, 32.0, 36.0, STONE_MAT)
    b.box(gx0 + 8, gy1 - 3, gx0 + 12, gy1 + 1, 2.0, 32.0, STONE_MAT)
    b.box(gx1 - 12, gy1 - 3, gx1 - 8, gy1 + 1, 2.0, 32.0, STONE_MAT)
    for i in range(6):
        b.box(gx0 + 14 + i * 6, gy1 - 2, gx0 + 16 + i * 6, gy1 - 1,
              4.0, 30.0, SLATE_DARK_MAT)
    for i in range(5):
        b.box(gx0 + 12, gy1 - 2, gx1 - 12, gy1 - 1, 6 + i * 5, 7 + i * 5,
              SLATE_DARK_MAT)
    # Crenellations across the gatehouse roof.
    for x in range(gx0 + 2, gx1 - 6, 12):
        b.box(x, gy0 + 2, x + 7, gy0 + 10, gz + 3, gz + 10, stone)
        b.box(x, gy1 - 10, x + 7, gy1 - 2, gz + 3, gz + 10, stone)
    # Drawbridge planks and chains.
    for i in range(9):
        b.box(gx0 + 12, gy1 + 1 + i * 2.2, gx1 - 12, gy1 + 3 + i * 2.2,
              1.5, 2.6, TIMBER_DARK)
    for cx in (gx0 + 14, gx1 - 14):
        b.cylinder_between((cx, gy1 + 1, 30.0), (cx, gy1 + 14, 3.4), 0.6,
                           SLATE_DARK_MAT, segments=4)
    # Corner towers.
    towers = ((80, 24), (240, 24), (80, 88), (240, 88))
    for i, (cx, cy) in enumerate(towers):
        tx0, ty0, tx1, ty1 = cx - 24, cy - 24, cx + 24, cy + 24
        top = 96 if i == 1 else 90
        b.box(tx0, ty0, tx1, ty1, 1.5, top, stone)
        b.box(tx0 - 3, ty0 - 3, tx1 + 3, ty1 + 3, top, top + 4, STONE_DARK_MAT)
        for dx in (-18, -6, 6, 18):
            for dy in (-18, 18):
                b.box(cx + dx - 4, cy + dy - 4, cx + dx + 4, cy + dy + 4,
                      top + 4, top + 12, stone)
        for dy in (-6, 6):
            for dx in (-18, 18):
                b.box(cx + dx - 4, cy + dy - 4, cx + dx + 4, cy + dy + 4,
                      top + 4, top + 12, stone)
        b.window("front", (tx0, ty0, tx1, ty1), cx - 3, cx + 3,
                 top - 20, top - 10, frame=STONE_DARK_MAT)
        b.window("right", (tx0, ty0, tx1, ty1), cy - 3, cy + 3,
                 top - 20, top - 10, frame=STONE_DARK_MAT)
    b.flag(80, 24, 102.0, 28.0, RED, width=22)
    b.flag(240, 88, 102.0, 28.0, BLUE, width=20)
    b.flag(136, 24, 104.0, 24.0, ROOF_SLATE, width=16)
    # Torches, banners and crates in the courtyard.
    for x in (122, 198):
        b.cylinder(x, 104, 1.5, 22.0, 1.3, TIMBER_DARK, segments=5)
        b.ellipsoid(x, 104, 25, 3.2, 3.0, 4.0, LAMP_MAT, segments=6, rings=4)
    for x in (96, 224):
        b.box(x - 1, 90, x + 1, 92, 30, 62, MAROON)
        b.m.tri((x - 10, 91, 60), (x + 10, 91, 60), (x, 91, 52), GOLD_MAT)
    b.crate(28, 100, 1.5, 12)
    b.crate(42, 104, 1.5, 12)
    b.barrel(60, 108, 1.5, 6.5, 16.0)


def casino(b: Builder, tier: int) -> None:
    b.slab(2, 2, 254, 94, -2.0, 1.4, PAVE, kerb=GOLD_DARK_MAT, inset=4,
           top=PAVE)
    x0, y0, x1, y1 = 12, 8, 244, 68
    b.box(x0, y0, x1, y1, 1.4, 8.0, STONE_DARK_MAT, top=STONE_MAT)
    b.box(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 7.0, 56.0, PLASTER_WARM)
    b.box(x0 - 3, y0 - 3, x1 + 3, y1 + 3, 56.0, 62.0, MAROON)
    b.box(x0 + 4, y0 + 4, x1 - 4, y1 - 4, 62.0, 64.0, MAROON_DARK)
    # Marquee of chasing lights.
    texture, (tw, th) = marquee_texture(72, 8)
    b.wall_decal("front", (x0, y0, x1, y1), 40, 40 + tw, 46, 46 + th,
                 _tex_material(texture), off=3.0, bias=0.02)
    b.sign("front", (x0, y0, x1, y1), 128, 31, "CASINO", fg=GOLD,
           bg=MAROON, border=GOLD, scale=2)
    b.door("front", (x0, y0, x1, y1), 112, 144, 2.0, 28, colour=MAROON,
           frame=GOLD)
    b.box(68, y1, 188, y1 + 2, 50, 53, GOLD_MAT)
    for x in (70, 186):
        b.cylinder(x, y1 + 6, 1.4, 50.0, 3.4, GOLD_MAT, segments=8)
        b.box(x - 4, y1 + 2, x + 4, y1 + 10, 50, 53, GOLD_DARK_MAT)
    # Lit windows and palms.
    for i in range(5):
        b.window("front", (x0, y0, x1, y1), 22 + i * 46, 38 + i * 46,
                 18, 40, frame=GOLD, lit=True)
    for i in range(2):
        b.window("right", (x0, y0, x1, y1), 18 + i * 22, 34 + i * 22,
                 20, 40, frame=GOLD, lit=True)
        b.window("left", (x0, y0, x1, y1), 18 + i * 22, 34 + i * 22,
                 20, 40, frame=GOLD, lit=True)
    # Rooftop neon sign.
    b.box(84, 30, 172, 34, 64, 82, MAROON_DARK)
    texture, (tw, th) = text_texture("CASINO", GOLD, MAROON_DARK, 2, 3, GOLD)
    sign_mat = _tex_material(texture)
    rx = 84 + (88 - tw) * 0.5
    b.m.decal((rx, 34.6, 79), (rx + tw, 34.6, 79),
              (rx + tw, 34.6, 79 - th), (rx, 34.6, 79 - th),
              sign_mat, (tw, th), bias=0.03)
    b.m.decal((rx + tw, 29.4, 79), (rx, 29.4, 79),
              (rx, 29.4, 79 - th), (rx + tw, 29.4, 79 - th),
              sign_mat, (tw, th), bias=0.03)
    b.palm(20, 74, 1.4, 62.0, 0.85)
    b.palm(236, 74, 1.4, 62.0, 0.85)
    b.planter(14, 86, 1.4, 8)
    b.planter(242, 86, 1.4, 8)
    # Fountain.
    b.cylinder(128, 84, 1.4, 6.0, 14.0, STONE_MAT, segments=12,
               cap_material=STONE_LIGHT)
    b.cylinder(128, 84, 6.0, 6.8, 11.0, WATER_MAT, segments=12, cap=False)
    b.cylinder(128, 84, 6.8, 20.0, 3.0, STONE_MAT, segments=8)
    b.ellipsoid(128, 84, 22, 5, 5, 3, WATER_MAT, segments=6, rings=3)
    b.box(96, y1, 160, y1 + 30, 1.4, 2.2, MAROON, top=MAROON)
    b.box(120, y1, 136, y1 + 34, 2.2, 2.8, GOLD_MAT, top=GOLD_MAT)


def theme_park(b: Builder, tier: int) -> None:
    b.ground(2, 2, 318, 126, GRASS_MAT, z=0.0, thickness=2.0)
    b.box(10, 42, 310, 122, 0.8, 1.8, PAVE, top=PAVE)
    # Striped ticket tent.
    x0, y0, x1, y1 = 224, 18, 300, 74
    b.box(x0, y0, x1, y1, 1.8, 30.0, CREAM_MAT)
    b.roof_pyramid(x0, y0, x1, y1, 30.0, 58.0, mat(ROOF_RED, "stripe", CREAM),
                   overhang=4.0)
    b.door("front", (x0, y0, x1, y1), 238, 258, 1.8, 26, colour=WOOD,
           frame=CREAM)
    b.window("front", (x0, y0, x1, y1), 266, 288, 12, 26)
    b.sign("front", (x0, y0, x1, y1), 252, 18, "TICKETS", fg=CREAM,
           bg=ROOF_GREEN, scale=1)
    b.flag(262, 12, 58.0, 22.0, YELLOW, width=18)
    # Ferris wheel and its boarding platform.
    b.ferris_wheel(150, 70, 86.0, 40.0, b.facing)
    b.box(112, 58, 188, 84, 1.8, 5.0, TIMBER_LIGHT, top=WOOD_MAT)
    b.box(112, 84, 188, 86, 5.0, 8.0, WOOD_DARK_MAT)
    # Midway stalls and lights.
    for i, x in enumerate((24, 62, 100)):
        bx0 = x
        bx1 = x + 32
        b.box(bx0, 92, bx1, 118, 1.8, 20.0, CREAM_MAT)
        b.roof_gable(bx0, 92, bx1, 118, 20.0, 30.0, "x",
                     mat(ROOF_RED if i % 2 == 0 else BLUE, "stripe", CREAM),
                     overhang=3.0, gable_material=CREAM_MAT)
        b.window("front", (bx0, 92, bx1, 118), bx0 + 8, bx1 - 8, 6, 16,
                 frame=WOOD_DARK, lit=True)
    b.string_lights(16, 90, 216, 90, 34.0, 12, 5.0)
    b.string_lights(216, 90, 216, 118, 34.0, 4, 4.0)
    b.lamp_post(206, 108, 1.8, 34.0)
    b.lamp_post(92, 108, 1.8, 34.0)
    b.bench(206, 62, "y", 1.8)
    b.planter(12, 110, 1.8, 8)
    b.planter(300, 110, 1.8, 8)
    b.planter(216, 44, 1.8, 7)
    b.ball(60, 80, 1.8)
    b.ball(74, 76, 1.8)


BUILDINGS = {
    "clubhouse": {"tiles": (4, 4), "tiers": 3, "draw": clubhouse},
    "putting_green": {"tiles": (3, 3), "tiers": 1, "draw": putting_green},
    "snack_bar": {"tiles": (2, 2), "tiers": 1, "draw": snack_bar},
    "pub": {"tiles": (3, 2), "tiers": 1, "draw": pub},
    "pro_shop": {"tiles": (2, 2), "tiers": 1, "draw": pro_shop},
    "driving_range": {"tiles": (6, 3), "tiers": 1, "draw": driving_range},
    "cart_garage": {"tiles": (3, 2), "tiers": 1, "draw": cart_garage},
    "tennis_court": {"tiles": (4, 2), "tiers": 1, "draw": tennis_court},
    "stable": {"tiles": (3, 3), "tiers": 1, "draw": stable},
    "spa": {"tiles": (3, 3), "tiers": 1, "draw": spa},
    "swim_club": {"tiles": (4, 3), "tiers": 1, "draw": swim_club},
    "resort_hotel": {"tiles": (4, 4), "tiers": 1, "draw": resort_hotel},
    "airstrip": {"tiles": (5, 3), "tiers": 1, "draw": airstrip},
    "castle": {"tiles": (5, 4), "tiers": 1, "draw": castle},
    "casino": {"tiles": (4, 3), "tiers": 1, "draw": casino},
    "theme_park": {"tiles": (5, 4), "tiers": 1, "draw": theme_park},
}
