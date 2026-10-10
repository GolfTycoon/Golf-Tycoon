# Tee Aim Arrow

> Each tee tile carries a painted arrow that points at the hole. On a dogleg the arrow curves to follow the bend, so a golfer can see the direction of play from the tee.

**Source:** `scripts/course/tee_aim_route.gd` (`aim_route()`, fairway spine and dogleg detection), `scripts/terrain/tee_aim_overlay.gd` (`rebuild()`, `marker_layout()`, arrow fitting), `scripts/terrain/terrain_grid.gd` (`tile_polygon()`), `scripts/tools/hole_layout.gd` (`unused_cups()`)
**Tests:** `tests/unit/test_tee_aim_route.gd`, `tests/unit/test_tee_aim_overlay.gd`, `tests/integration/tee_aim_arrows.gd`

---

## Plain English

Each tee tile shows a small arrow in its grass, with a red ball on each side of the shaft. Those two red balls mark where a golfer stands. The arrow says where the hole plays.

- **Straight hole:** one straight arrow pointing down the tee-to-cup line.
- **Dogleg:** a curved arrow. The tail leaves the tee along the drive line. The bend follows the turn of the hole. The tip points down the approach line toward the green.
- **Waiting tee box:** a tee you have painted but not yet opened already aims at the waiting cup. It shows the same arrow the hole gets once you press **Open Hole**.
- **Nothing to aim at:** a tee on a course with no waiting cup and no hole of its own stays bare. Automatic forward and middle tees each aim at the cup of their own hole.

The arrow is a fixed-size sign, not a miniature map, so every tee looks the same. Its direction comes from the flat map. Elevation lifts the tile the arrow sits on, but it does not bend the arrow. The arrow is then scaled to fit inside the tile's grass.

---

## Algorithm

### 1. Which tee aims where

`TeeAimOverlay.rebuild()` indexes each hole's cup by tee tile. It includes `hole.tee_position` and every entry of `hole.tee_positions` (back, forward and middle). It then walks `TerrainGrid.get_tee_box_tiles()`. Any tee not claimed by a hole aims at the single waiting cup from `HoleLayout.unused_cups()`. Opening a hole consumes that cup marker, so the two cases never overlap.

`TerrainGrid` runs this rebuild, deferred and coalesced, whenever a tile, a waiting cup or a hole changes. The overlay also redraws when the view rotates or the camera moves.

### 2. Finding a dogleg

A dogleg is read from the fairway, not from the shot planner. A bend in the fairway is what makes a dogleg. Reading the fairway costs one bounded grid scan, instead of the roughly 0.2 s that a ShotAI pass takes.

```
axis   = cup − tee,  dir = axis / |axis|
band(p) = clamp(floor(((p + 0.5 − tee) · dir) / |axis| × SPINE_BANDS), 0, SPINE_BANDS − 1)
spine[i] = mean position of the fairway tiles in band i      (firm fairway counts; empty bands are skipped)
corner   = the spine point furthest from the line, within the middle 20% to 80% of the hole
dogleg   = corner offset ≥ DOGLEG_MIN_TILES  → bent route [tee, corner, cup]
         otherwise                             → straight route [tee, cup]
```

A wide straight fairway keeps its centre on the line, so it is not mistaken for a dogleg. A fairway that flares out near the tee or green is ignored because it falls outside the middle band. Par 3s and new holes have no fairway, so they always aim straight. The search covers the tee-to-cup line plus `SPINE_SEARCH_MARGIN` tiles to each side, clipped to the grid.

### 3. Drawing the arrow

The route has two legs: `in_dir` (tee to corner, the drive line) and `out_dir` (corner to cup, the approach line).

```
turn      = in_dir.angle_to(out_dir)           # below TURN_MIN_RADIANS → straight arrow
chord_dir = normalize(in_dir + out_dir)
radius    = ARROW_LENGTH / (2 × sin(|turn| / 2))
shaft     = circular arc of length ARROW_LENGTH, turning by exactly the hole's bend
head      = triangle at the shaft tip, aligned with the last leg
balls     = two red markers, BALL_ANCHOR_FRACTION along the shaft, offset ± BALL_OFFSET
```

A circular arc keeps the arrow the same length as a straight one. A 90° dogleg therefore reads as a quarter-turn, and a 45° dogleg as a gentler curve. The tip always points down the approach line.

### 4. Fitting the tile

The marker is centred on the tile, by the box of what is actually painted (head included), and scaled to fit the tile's grass.

- The grass outline is the tile's **projected** shape from `TerrainGrid.tile_polygon()`. In the isometric view this is a 2:1 diamond, which bends with the corner elevations of sculpted ground. In the top-down view it is a square.
- Each edge becomes an inward limit. Each painted part reaches toward an edge by its own width, and the scale is the largest value that keeps every part inside its limit, never above 1.
- The red markers are usually the limiting part on a diagonal arrow. The isometric diamond leaves less room sideways, so a diagonal arrow ends up slightly smaller than an axis-aligned one.

Two tile shapes cannot be fitted honestly, and both stop at `MIN_FIT_SCALE` instead of shrinking to an unreadable speck:

- **Folded tile.** A cliff steeper than the tile is wide can fold its outline over itself. This is detected when the corners stop turning the same way.
- **Sliver tile.** A tile leaning sharply can leave less room at its centre than the arrowhead needs.

In these cases the marker may overlap a neighbouring tile by a pixel or two. That is acceptable, because a clear arrow still shows the direction of play and a speck does not.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| `SPINE_BANDS` | `tee_aim_route.gd` | `8` | How finely the fairway is sampled along the hole |
| `DOGLEG_MIN_TILES` | `tee_aim_route.gd` | `2.5` tiles (about 55 yards) | How far the fairway must leave the line before a dogleg is shown |
| `SPINE_SEARCH_MARGIN` | `tee_aim_route.gd` | `6` tiles | How far either side of the line is searched for fairway |
| `CORNER_BAND_START` / `CORNER_BAND_END` | `tee_aim_route.gd` | `0.2` / `0.8` | Middle part of the hole where the bend must sit |
| `ARROW_LENGTH` | `tee_aim_overlay.gd` | `32` px | Arrow length before fitting to the tile |
| `TURN_MIN_RADIANS` | `tee_aim_overlay.gd` | `0.05` rad | Below this turn the arrow is straight |
| `SHAFT_WIDTH` / `EDGE_WIDTH` | `tee_aim_overlay.gd` | `3.6` / `5.2` px | Paint width, and the dark rim that keeps it readable on dark turf |
| `HEAD_LENGTH` / `HEAD_HALF` | `tee_aim_overlay.gd` | `8.6` / `5.0` px | Arrowhead size |
| `BALL_RADIUS` / `BALL_OFFSET` | `tee_aim_overlay.gd` | `2.5` / `6.8` px | Size of the red tee markers, and how far apart they sit |
| `BALL_ANCHOR_FRACTION` | `tee_aim_overlay.gd` | `0.5` | Where along the shaft the markers sit |
| `SAFE_INSET` | `tee_aim_overlay.gd` | `2.6` px | Gap kept between the paint and the tile edge |
| `MIN_FIT_SCALE` | `tee_aim_overlay.gd` | `0.45` | Smallest size the marker is ever drawn at |
| `PAINT_COLOR` / `BALL_COLOR` | `tee_aim_overlay.gd` | Off-white / red | Colours of the arrow and the tee markers |
| `Z_INDEX` | `tee_aim_overlay.gd` | `6` | Draw order: terrain, then this overlay, then golfers and the ball |

---

## Related

- [Hole Creation](hole-creation.md) explains when a waiting tee aims at a waiting cup.
- [Multiple Tee Boxes](multiple-tee-boxes.md) covers the forward and middle tees, which each get an arrow.
- [Course Surface](course-surface.md) covers the grass the arrow is painted on.
