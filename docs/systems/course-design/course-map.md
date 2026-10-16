# Course Map

> One isometric view of the whole course in four modes: buy the land around it, reorder its holes, read where golfers are happy and unhappy, and post the crew. Opens with **Shift+M**, or **Manage → Maps → Course Map**.

**Source:** `scripts/ui/course_map_screen.gd` (composition, modes, strip, keys), `scripts/ui/components/course_map_view.gd` (the drawn map, its picking and its legend), `scripts/ui/components/course_map_style.gd` (frames, type and money), `scripts/ui/components/course_map_land_panel.gd`, `scripts/ui/components/course_map_routing_panel.gd`, `scripts/ui/components/course_map_aura_panel.gd`, `scripts/ui/components/course_map_staff_panel.gd`, `scripts/main/main.gd` (`_open_course_map()`, `Shift+M`), `scripts/ui/terrain_toolbar.gd` (the Course Map button)
**Tests:** `tests/unit/ui_and_controls/test_course_map_layout.gd`, `tests/unit/ui_and_controls/test_course_map_terrain.gd`, `tests/integration/ui_and_controls/test_course_map_screen.gd`

---

## Plain English

The Course Map is the course seen all at once, flat, from above: one diamond of
terrain filling the screen with the holes, the parcels and the crew drawn on it.
It is the place to do the four jobs that are about the *whole* course rather than
one tile of it.

It is dressed as a menu rather than as a tool: the same clubhouse artwork the
title screen sits on (`MenuBackdrop`, `assets/ui/background.jpeg`), the same
notched pixel frames and Pixelify Sans type as the Main Menu and the World Map.
The day freezes while it is up (`GameManager.is_paused`) and the gameplay HUD
steps aside, so nothing on the course moves under your hands; **Back** (or
Escape) hands the day back exactly where it was.

Open it from **Manage → Maps → Course Map**, or with **Shift+M** anywhere in the
game. **M** on its own is still Marketing.

### The four modes

| Key | Mode | The map shows | The panel does |
| --- | --- | --- | --- |
| `1` | **Land** | Every parcel: yours (gold outline), for sale (amber, with its price and tier on it), and out of reach | The parcels you own, the parcel picked with its tier and cost, **Buy**, and the whole for-sale list |
| `2` | **Routing** | The route: a line from each green to the next tee, coloured by walk length, with a tee square, a green ring and a number badge per hole | The holes in play order with move-up, move-down, flip, par and open/shut buttons, **Play the round the other way round**, and the route report |
| `3` | **Aura** | The mood of the course, cell by cell: green where golfers were happy, amber where it is mixed, red where they were not | The happiest spots, the trouble spots and a per-hole breakdown of what golfers said |
| `4` | **Staff** | A ring for every employee's working area, coloured by job, plus the ground your own golfer works | The crew with **Move** and **Fire**, and the hire list you pick a job from |

Everything the map draws is live: the terrain comes from the terrain grid, the
parcels from `LandManager`, the holes from `GameManager.current_course.holes`,
the mood from `CourseAura` and the crew from `StaffManager`. Buying a parcel,
moving a hole or hiring a gardener updates the map in place.

The ground itself is a **colour key of the course, tile for tile**, drawn from
the same palette the minimap uses and the course surface is painted with (see
`CourseSurface.map_color`), so water, sand, turf, trees and flowers are all
recognisable at a glance and stay put when the theme changes. Three things keep
it that way:

- **The legend names the ground.** Under the mode's own colours the map keys the
  terrain types this course is actually made of (up to `TERRAIN_KEY_LIMIT`, and
  only those covering at least `TERRAIN_KEY_MIN_SHARE` of it), biggest patch of
  ground first, each chip in the colour that tile is painted with. A colour key
  that does not say what the colours are called is a decoration.
- **The tile grid appears as the tiles grow.** Once a tile is
  `TILE_GRID_MIN_PX` across on screen the grid is drawn, reaching full strength
  by `TILE_GRID_FULL_PX`, so the ground reads as tiles rather than as a
  painting. It keys off the size a tile is *drawn* at, not the zoom factor: a
  phone-sized map at 3x has smaller tiles than a desktop one at 1x.
- **Every mode is drawn *over* the ground, never instead of it.** The washes are
  only ever deep enough to make a mode's own marks read. Land mode lays nothing
  over the course at all, and a parcel's state is carried by its outline, its
  price label and the panel rather than by a colour field — a 20 x 20 tile
  parcel covered by an even wash reads as one flat rectangle and takes the whole
  tile mosaic with it.

### The strip

A single line under the map says what the mode is about, what is picked, or what
the map is waiting for. It carries the mode's own buttons:

| Button | Appears when | What it does |
| --- | --- | --- |
| **Buy for $X** / **Not now** | A purchasable parcel is picked | Buys the parcel (the terrain features are generated and the day's balance changes) or puts the offer away |
| **Buy** | In the for-sale list | The same buy, from the list rather than the map |
| **Cancel** | An action is armed and waiting for a tap | Puts the armed action away (Escape does too) |
| **Clear** | Something is picked | Drops the pick |

While an action is armed the strip says where to tap, and the map greys the
course and draws a ghost on the ground the tap would hand over, so a hire is
never placed blind.

---

## Algorithm

### 1. The diamond

The map is the game's own terrain grid drawn through `GridProjection`: the tile
grid is projected to a diamond, the diamond is scaled to fit the control with
`PAD` of margin, and everything else in the mode is drawn in that same space.
There is no camera and no scene tree behind it.

- One texture of the terrain is generated per terrain revision (`TEXTURE_SIDE`
  px, or `COMPACT_TEXTURE_SIDE` on the small shapes), coloured from each
  terrain type's palette colour — the same one the minimap and the course
  surface draw with — and stretched onto the diamond. Terrain edits (from the
  map's own modes or from the course behind it) dirty it.
- Each mode lays its own wash over the course, no deeper than it takes to make
  the mode's marks read (`SCRIM_LAND`, `SCRIM_OVERLAY`, `SCRIM_AURA`), and the
  Land mode dims land that is out of reach rather than blacking it out, so the
  tile colours still carry the ground.
- Once a tile is drawn at least `TILE_GRID_MIN_PX` across, the tile grid goes
  over the texture, so the ground can be counted tile by tile rather than only
  read as a picture.
- Hole markers, parcels, aura cells and staff rings are drawn over that texture
  with `draw_line`, `draw_polygon` and `draw_string`, so they stay crisp at any
  zoom and can carry live numbers (par, price, hole number).
- Zoom runs from `MIN_ZOOM` (the whole course framed) to `MAX_ZOOM`, one
  `ZOOM_STEP` per notch. Panning is clamped so a corner of the course always
  stays inside the control.

### 2. Picking

| Mode | A press picks |
| --- | --- |
| Land | The parcel the tile belongs to |
| Routing | The hole whose tee, green or route line is within `PICK_RADIUS` of the pointer |
| Aura | The aura cell the tile belongs to, if golfers have commented there |
| Staff | The employee whose area the tile stands in |

A press that moved the pointer more than `CLICK_SLOP` is a drag, not a pick, so
panning never selects anything. Hovering writes a one-line description under the
map — the parcel's tier and cost, the hole's length and par, the mood of a cell,
or the employee's name, wage and area.

### 3. Routing edits

The Routing panel is the Course Map's front end for
[Hole Routing](hole-routing.md). A move renumbers the round and tells the game
through `EventBus.holes_reordered`; a flip swaps a hole's tee and green on the
grid and re-cuts the cup; a par change writes `par_override` (or clears it back
to `-1` when the new par is the automatic one). All of it goes through
`HoleManager`, so the stroke index, the hole visualizers and the golfers part-way
round are kept in step.

### 4. Choosing a shape

`CourseMapScreen.layout_mode_for()` turns the viewport into one of five shapes.
The breakpoints are the same ones the World Map and the toolbar use, so the game
changes shape at one size everywhere.

| Shape | When | Composition |
| --- | --- | --- |
| Desktop | ≥ 1180 × 680 and wider than tall | Mode tabs across the top, map on the left, dossier panel down the right side, strip under the map |
| Tablet landscape | ≥ 680 × 620 | Modes on a rail down the left, panel beside the map, a **Hide**/**Show** toggle that hands the map the full width |
| Tablet portrait | ≥ 680 × 620 and taller than wide | Tabs across the top, map above, panel stacked underneath |
| Phone landscape | Wide and short (under 620 tall) | Compact rail, the panel slides in over the map as a sheet with a scrim to tap away, strip stays under the map |
| Phone portrait | Everything else | Tabs, map, strip, and the panel as a bottom sheet that peeks at `SHEET_PEEK_HEIGHT` and lifts to `SHEET_LIFT_RATIO` of the screen |

Every shape is built from the same parts, and the map and the four mode panels
survive a relayout: resizing the window (or turning a tablet) throws away the
frames around them and rebuilds those, so the zoom, the pan, the pick and
everything the panels were saying are all still there afterwards. Only the
composition is ever freed; the map and the panels are carried from one shape to
the next (a panel that is not the current mode's is parked on the screen, so
nothing is left floating outside the screen's own tree).

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Desktop breakpoint | `course_map_screen.gd` `DESKTOP_MIN_WIDTH`/`DESKTOP_MIN_HEIGHT` | `1180` × `680` | Below this a window gets the tablet shape |
| Tablet breakpoint | `course_map_screen.gd` `TABLET_MIN_WIDTH`/`TABLET_MIN_HEIGHT` | `680` × `620` | Below this the shape is a phone's |
| Panel width | `course_map_screen.gd` `PANEL_WIDTH_DESKTOP`/`PANEL_WIDTH_TABLET` | `348` / `286` px | How much of the width the dossier takes |
| Sheet peek | `course_map_screen.gd` `SHEET_PEEK_HEIGHT` | `76` px | How much of the folded panel shows on a portrait phone |
| Sheet lift | `course_map_screen.gd` `SHEET_LIFT_RATIO` | `0.56` | Share of the screen the open sheet takes |
| Terrain texture | `course_map_view.gd` `TEXTURE_SIDE`/`COMPACT_TEXTURE_SIDE` | `512` / `320` px | Sharpness of the terrain against the cost of rebuilding it |
| Tile colours | `course_surface.gd` `PALETTE_KEYS`, `map_color()` | one key per terrain type | What each tile looks like, on the course, the minimap and this map at once |
| Mode wash | `course_map_view.gd` `SCRIM_LAND`/`SCRIM_OVERLAY`/`SCRIM_AURA` | `0.0` / `0.03` / `0.20` | How far a mode's own colours push the course back |
| Parcel washes | `course_map_view.gd` `LAND_OWNED_FILL`/`LAND_BUY_FILL`/`LAND_LOCKED_FILL` | 5% / 12% / 5% | How loudly a parcel's state colours its ground |
| Tile grid | `course_map_view.gd` `TILE_GRID_MIN_PX`/`TILE_GRID_FULL_PX`/`TILE_GRID_COLOR` | `5` / `13` px / 22% ink | How big a tile has to be drawn before the grid shows, and how loud it is |
| Terrain key | `course_map_view.gd` `TERRAIN_KEY_LIMIT`/`TERRAIN_KEY_MIN_SHARE` | `5` types / 0.5% of the course | How many kinds of ground the legend names, and how much of the course one has to be to earn a chip |
| Zoom | `course_map_view.gd` `MIN_ZOOM`/`MAX_ZOOM`/`ZOOM_STEP` | `1.0` / `3.2` / `1.25` | How far in the map goes, and how fast |
| Pick radius | `course_map_view.gd` `PICK_RADIUS` | `20` px | How near a hole marker a tap has to land |
| Drag slop | `course_map_view.gd` `CLICK_SLOP` | `6` px | How far a pointer may wander and still count as a tap |

---

## Related

- [Hole Routing](hole-routing.md) covers the order of play, the walks between holes and the route report.
- [Course Aura](../golfers/course-aura.md) covers the mood map the Aura mode draws.
- [Premium Land](../economy-and-land/premium-land.md) covers parcel tiers, costs and what buying one generates.
- [Staff and Weeds](../economy-and-land/staff-and-weeds.md) covers the crew, their wages and their areas.
- [Routing Overlay](routing-overlay.md) covers the same walk lengths drawn on the course itself.
- [UI & Controls](../../ui-and-controls.md) lists the keys and gestures for every screen.
