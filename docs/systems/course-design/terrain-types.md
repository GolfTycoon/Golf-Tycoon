# Terrain Types

> Every tile of the course is one terrain type. The type sets its build cost and upkeep, how a ball lies on it, how far it runs after landing, whether it is a hazard, and how the course surface draws it.

**Source:** `scripts/terrain/terrain_types.gd` (`enum Type`, `PROPERTIES`, family helpers `is_water()`, `is_bunker()`, `is_tree()`, …), `scripts/systems/golf_rules.gd` (`get_lie_modifier()`, `get_terrain_distance_modifier()`, `get_roll_multiplier()`, `catches_rolling_ball()`), `scripts/systems/shot_ai.gd` (`TERRAIN_SCORES`), `scripts/ui/terrain_toolbar.gd` (tiles and hotkeys), `scripts/terrain/course_surface.gd` and `shaders/course_surface.gdshader` (drawing), `data/terrain_types.json` (mirror for tools)
**Tests:** `tests/unit/test_new_terrain_types.gd`

---

## Plain English

**Course Terrain tab.** The tab shows course surfaces, hazards, Flower Bed, the stony grounds and the theme's woodland tiles in one scrolling honeycomb of two rows:

| Row | Tiles (left to right) |
| --- | --- |
| Top | Tee Box, Green, Bunker, Rough, Pot Bunker, Stream, Water, Out of Bounds |
| Bottom | Fairway, Firm Fairway, Deep Rough, Waste Bunker, Brush, Rocks, Small Boulders, Large Boulders |

The woodland tiles follow, and their number depends on the theme. **Open Hole** is a small cell nestled between the Tee Box and Green tiles. Its ring is gold when a tee and a cup are waiting to be paired, and grey when they are not. The Bulldozer is not a course tool. It lives on the Improvements and Buildings tabs, and it removes paths, decorations and buildings, never course terrain. The Path is an improvement, shown on the Improvements tab (see [Improvement Catalog](garden-catalog.md)).

**Natural grass.** Natural Grass is only the blank canvas a fresh grid starts from. Terrain generation turns it into Rough, the zero-upkeep base turf of generated courses. Heavy Rough, the woodland tiles and Empty are placed by generation. The stony grounds and tree species are ordinary painted tiles, so generation can scatter them like any other zero-upkeep terrain. A tree is simply a tile, not a separate object.

### The newer tiles

- **Firm Fairway.** Fast, firm turf. It has a full fairway lie for full swings, a slightly tighter lie for wedges, and a ball that lands on it runs **1.6×** as far as on a fairway.
- **Pot Bunker.** A small, deep pit with a stacked-turf face. It is harsher than any bunker. Only a wedge gets out, and the ball barely advances. Balls rolling into it stop.
- **Stream.** Running water. It takes the same penalty and point-of-entry drop as Water, but it is narrow, and golfers can walk across it. It can cut through a hole. Paint it in lines, because the channel only joins edge-adjacent stream tiles and widens where it meets a pond.
- **Deep Rough.** Knee-high unmown grass. It is harsher than Heavy Rough, and it stops a rolling ball dead. It costs $1 to paint and has no upkeep.
- **Waste Bunker.** Natural sandy scrubland. It is **not** a hazard, so you can ground your club in it. It plays like sandy rough and has no upkeep.
- **Rocks, Small Boulders and Large Boulders.** Stony ground, the worst lie on the course. Each one plays exactly like the others. They differ only in the stones drawn on them: gravel for Rocks, pebbles with the odd large stone for Small Boulders, and big standing boulders for Large Boulders.
- **Brush.** Dense scrub (gorse, heather, sagebrush). It has a poor lie, cuts the distance, and swallows rolling balls. Golfers wade through it slowly.
- **Woodland, one tile per species.** Oak, Pine, Maple, Birch, Cactus, Fescue, Cattails, Shrub, Palm, Dead Tree and Heather, plus the generic Trees tile. Every one plays exactly like Trees: same cost, no upkeep, same lie, same blocked shot, same roll and same AI score. Only the canopy drawn on the tile and the ground painted under it change (see [Course Surface](course-surface.md)). Each theme offers the species that suit it. A desert offers cacti, and a links offers fescue, but none of them plays differently.

---

## Algorithm

### 1. Ids and save compatibility

Saves store terrain as raw integers. New types are therefore only ever appended to the end of the enum:

| Id | Type | Id | Type |
| --- | --- | --- | --- |
| 0 | Empty | 17 | Deep Rough |
| 1 | Grass | 18 | Waste Bunker |
| 2 | Fairway | 19 | Brush |
| 3 | Rough | 20 | Small Boulders |
| 4 | Heavy Rough | 21 | Large Boulders |
| 5 | Green | 22 to 32 | Oak, Pine, Maple, Birch, Cactus, Fescue, Cattails, Shrub, Palm, Dead Tree, Heather |
| 6 | Tee Box | 11 | Trees (generic) |
| 7 | Bunker | 12 | Flower Bed |
| 8 | Water | 13 | Rocks |
| 9 | Path | 14 | Firm Fairway |
| 10 | Out of Bounds | 15 | Pot Bunker |
| | | 16 | Stream |

The three stony grounds share one palette key, so they share one base colour. The eleven species share the `trees` key. Each theme needs a palette colour for every id, from `CourseTheme.get_terrain_colors()`.

`data/terrain_types.json` mirrors the ids, names, `playable`, `placement_cost` and `blocks_shots`. The game does not read it at runtime. It is there for tools and modders. `test_json_mirror_lists_every_type` fails if an id is missing or its name or cost drifts from `PROPERTIES`.

### 2. Families

Gameplay code asks about families rather than single types, so each variant behaves like its parent:

| Helper | Includes | Used for |
| --- | --- | --- |
| `is_water()` | Water, Stream | Penalty area, drop at entry |
| `is_out_of_play()` | Water, Stream, Out of Bounds, Empty | Lost-ball rules |
| `is_bunker()` | Bunker, Pot Bunker | Hazards where the ball plugs |
| `is_sand()` | Bunker, Pot Bunker, Waste Bunker | Sand spray and sandy lies |
| `is_fairway()` | Fairway, Firm Fairway | Shot shapes, AI bonuses, carries |
| `is_rough()` | Rough, Heavy Rough, Deep Rough | Rough lies |
| `is_rocks()` | Rocks, Small Boulders, Large Boulders | Stony lies |
| `is_tree()` | Trees and all eleven species | Blocked shots |

Walking is the exception. Golfers path around water, out of bounds and off-property land, but they can cross streams.

### 3. Costs

| Terrain | Build cost | Upkeep per day | Hazard | Penalty | Walk speed |
| --- | --- | --- | --- | --- | --- |
| Fairway | $5 | $1 | No | — | 1.0× |
| Firm Fairway | $6 | $1 | No | — | 1.0× |
| Rough | $2 | $0 | No | — | 1.0× |
| Heavy Rough | $0 | $0 | No | — | 1.0× |
| Deep Rough | $1 | $0 | No | — | 0.85× |
| Green | $20 | $2 | No | — | 1.0× |
| Tee Box | $12 | $1 | No | — | 1.0× |
| Flower Bed (Wild Flowers) | $15 | $0 | No | — | 1.0× |
| Path (Cart Path) | $8 | $0 | No | — | 1.5× |
| Bunker | $10 | $1 | Yes | — | 1.0× |
| Pot Bunker | $18 | $2 | Yes | — | 1.0× |
| Waste Bunker | $6 | $0 | No | — | 1.0× |
| Water | $20 | $0 | Yes | 1 stroke and drop at entry | — |
| Stream | $15 | $0 | Yes | 1 stroke and drop at entry | — |
| Brush | $3 | $0 | No | — | 0.75× |
| Rocks, Small Boulders, Large Boulders | $8 | $0 | No | — | 1.0× |
| Trees and all species | $10 | $0 | No | — | 1.0× |
| Out of Bounds | $0 | $0 | Yes | 1 stroke and distance | — |

Upkeep is summed over player-placed tiles. See [Economy](../economy-and-land/economy.md).

### 4. Shot rules

| Terrain | Lie (wedge / other) | Distance kept | Roll-out | Stops rolling ball | AI score | Recovery clubs |
| --- | --- | --- | --- | --- | --- | --- |
| Fairway | 1.0 | 1.0 | 1.0× | No | +150 | — |
| Firm Fairway | 0.92 / 1.0 | 1.0 | 1.6× | No | +145 | — |
| Tee Box | 1.0 (driver 1.05) | 1.0 | 1.0× | No | +130 | — |
| Green | 1.0 | 1.0 | 1.3× | No | +180 | — |
| Rough | 0.75 | 0.85 | 0.3× | No | +10 | — |
| Heavy Rough | 0.5 | 0.7 | 0.12× | No | −20 | Wedge, iron |
| Deep Rough | 0.4 | 0.6 | 0.06× | Yes | −45 | Wedge, iron |
| Waste Bunker | 0.8 / 0.7 | 0.85 | 0.3× | No | −10 | — |
| Brush | 0.3 | 0.5 | 0.05× | Yes | −85 | Wedge |
| Bunker | 0.6 / 0.4 (deep: 0.45 / 0.25) | 0.75 (deep: 0.60) | None | Yes | −50 | Wedge, iron |
| Pot Bunker | 0.35 / 0.15 | 0.45 | None | Yes | −90 | Wedge |
| Rocks and boulders | 0.25 | 0.5 | 0.15× | No | −100 | Wedge |
| Trees and all species | 0.3 | 0.6 | 0.2× | No | −80 | Wedge, iron |
| Stream, Water, Out of Bounds | Penalty | Penalty | None | Yes | −1000 | — |

The AI plays a recovery shot when its lie quality falls below 0.4. That covers deep rough, pot bunkers, brush, trees and stony ground. See [Shot Accuracy](../golf-play/shot-accuracy.md), [Ball Physics](../golf-play/ball-physics.md) and [Shot AI: Target Finding](../golf-play/shot-ai-target-finding.md).

### 5. Painting

- Painting a course tile replaces whatever is there, including trees, sand, greens and walking paths. `TerrainGrid.set_tile()` swaps the ground, and drops any cup, tee or walking-path state the new ground cannot keep. Painting costs only the new tile's placement cost. There is no clearing fee. Cart-path terrain counts as a node of the walking network, so painting or removing one re-paves the trails that touch it.
- Buildings and decorations are not course terrain. A course tile will not paint over them. The Bulldozer removes them.
- Stream strokes are 4-connected (`TerrainBrush.centers_4_connected()`), so the channel never breaks at a diagonal step.
- A species tile draws its own canopy on its own ground, wherever it is placed.
- Older saves that stored trees as entities are converted on load. `EntityLayer.deserialize` paints the matching species tile for each one, so a loaded course becomes ordinary painted woodland.

### 6. Rendering

Each type has its own look in `shaders/course_surface.gdshader`. See [Course Surface](course-surface.md). Pot Bunker, Stream, Waste Bunker, the stony grounds, Brush and the woodland tiles are inset terrain. They are drawn over the turf around them, so their patches have natural outlines.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Build cost and upkeep | `terrain_types.gd` `PROPERTIES` | See the cost table | Economy of each tile |
| Lie and distance modifiers | `golf_rules.gd` `get_lie_modifier()`, `get_terrain_distance_modifier()` | See the shot table | Accuracy and distance from each lie |
| Roll-out multipliers | `golf_rules.gd` `get_roll_multiplier()` | See the shot table | How far a ball runs after landing |
| Rolling-ball catchers | `golf_rules.gd` `catches_rolling_ball()` | Water, stream, OB, bunkers, deep rough, brush | Where a rolling ball stops |
| AI terrain scores | `shot_ai.gd` `TERRAIN_SCORES` | See the shot table | Where AI golfers aim |
| Walk speed | `terrain_types.gd` `speed_modifier` | Deep rough 0.85×, brush 0.75×, cart path 1.5× | Pace through long grass, scrub and paths |
| Walk speed with a trail | `terrain_grid.gd` `walk_speed_modifier_at()` | The tile's own rate × 1.25 dirt or 1.5 paved | A laid trail quickens the walk over any hostable ground — see [Walking Paths](walking-paths.md) |
| Hotkeys | `terrain_toolbar.gd` | `9`, `0`, Shift+2/5/6/7/8/9/0 | Keyboard access to the tiles (Shift+9 Small Boulders, Shift+0 Large Boulders) |
| Woodland grounds | `terrain_types.gd` `TREE_GROUND_LOOKS` | Litter, needles, sand, silt, peat, straw | What each species grows in |
| Species per theme | `course_theme.gd` `get_tree_types()` | 4 to 6 per theme | Which tree tiles the tab shows |

---

## Related

- [Course Surface](course-surface.md) draws each terrain type.
- [Walking Paths](walking-paths.md) covers the trail laid on this ground, and the pace it buys.
- [Bunker Depth](bunker-depth.md) covers the two bunker depths.
- [Shot Accuracy](../golf-play/shot-accuracy.md) uses the lie and distance values.
- [Ball Physics](../golf-play/ball-physics.md) uses the roll-out values.
- [Economy](../economy-and-land/economy.md) uses the build and upkeep costs.
