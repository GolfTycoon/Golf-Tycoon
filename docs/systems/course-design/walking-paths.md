# Walking Paths

> A walking path is a slim trail golfers can see and walk on. It is laid over the ground rather than instead of it — a trodden dirt ribbon that leaves the turf, the lie and the upkeep exactly as they were — and the whole network turns into a paved stone promenade once it reaches the clubhouse. It joins whatever it comes up against: another trail tile, or the wall of a building. Golfers walk quicker on it than on the ground it crosses, so planned routes step onto it whenever that saves them time. It is also what a generated course arrives with.

**Source:** `scripts/terrain/walking_path_overlay.gd` (art, the connection rule and `speed_modifier_at()`), `scripts/terrain/terrain_types.gd` (`WALKING_PATH_TERRAINS`, `can_host_walking_path()`, `WALKING_PATH_TOOL`, `WALKING_PATH_COST`), `scripts/terrain/terrain_grid.gd` (`set_walking_path()`, `can_place_walking_path()`, `walk_speed_modifier_at()`, `walk_field()`, `WalkField`, and `GROUND_DETAIL_ORDER` with `_order_ground_detail()` for where the trail paints), `scripts/entities/golfer.gd` (`_process_walking()`, `_find_path_to()`, `_find_quickest_route()`), `scripts/main/main.gd` (`_paint_walking_path_stamp()` and the bulldozer), `scripts/ui/placement_preview.gd`, `scripts/ui/components/terrain_tile_button.gd`
**Tests:** `tests/unit/test_walking_paths.gd`, `tests/unit/test_golfer_walking_routes.gd`, `tests/unit/test_terrain_toolbar.gd`, `tests/unit/test_path_furniture.gd`, `tests/unit/course_design/test_terrain_draw_order.gd`; `tests/harness/walking_path_harness.tscn`

---

## Plain English

The **Path** leads the Improvements tab's honeycomb. It is a painting tool, not a building: click or drag and each tile costs **$8**, and it adds no upkeep. A tile a building or a decoration already occupies cannot take one, and neither can ground the trail cannot be trodden on — the mown playing line above all.

- **Dirt:** a freshly laid trail is a slim trodden ribbon over the ground it crosses — packed earth at the middle, trodden grass at the verges, a paler crown wandering down it where the boots polish the ground, dry patches and pebbles trodden in, and grass blades leaning over the verges. Each tile carries a pad, and pads on edge-adjacent tiles join into one continuous walk, so a trail reads as a trail rather than a row of tiles.
- **Paved:** the moment the connected trail network touches a clubhouse tile, **every** trail in that network is paved — light flagstones laid slab by slab with the joints crossing the whole walk, a kerb of dressed darker stone either side, gravel spilled over the grass, and every other slab a shade off its neighbours. Take the link away — bulldoze a tile of it, paint over the ground, or move the clubhouse — and the trail is dirt again.
- **Up to the buildings:** a walk runs into whatever stands beside it. A trail tile against a building lays its arm right up to the shared edge and broadens there — swept earth at a dirt trail's door, a stone threshold where paving meets the wall — so the walk comes up to the clubhouse, the shop and the barns instead of stopping short of them. A building is where a walk ends, never a way through: it joins nothing, and only the clubhouse paves.
- **Walking quicker:** a golfer on a dirt trail walks **1.25×** as fast as the same ground without it, and **1.5×** on paving. The ground's own rate still counts, so a trail through brush is quicker than ploughing through the brush but slower than a trail over rough.
- **Preferring the walk:** a planned walk steps onto the trail when that gets the golfer there no more than **a moment slower** than walking straight there, and never crosses the course to reach a distant trail. Water and out of bounds are still walked around.
- **Nothing but the walk changes.** A trail is a flag on a tile, not a terrain: the ball lies on the ground underneath, rolls as it did, and the tile keeps its own build cost and upkeep. Painting the ground with a course tile that cannot host a trail — fairway, say — takes the trail with it.
- **A generated course arrives with its trails already laid:** out of the clubhouse door, beside every fairway, from each green to the next tee and home again. They are laid by the same rule as a brush stroke, so a network that reaches the clubhouse is paved, and a trail the player paints onto it joins the same network and paves with it. See [Generated Walking Paths](generated-walking-paths.md), including where a course's walks stop short and stay dirt.
- **Under the golfers, and under the trees:** the trail is ground art — it paints in the terrain's own band, under the entities (see [Draw Order](../../architecture.md)) — so a golfer walking the trail is drawn over it, sprite, shadow and all, and a read of the walk never hides the players on it. A wood the walk crosses is the one thing painted over it: the trail ranks below the tree sprites in the ground band, so a trunk and its crown stand on the ribbon rather than being cut in half by it.
- The bulldozer removes a trail for **$5** a tile, leaving the ground it crossed untouched. Its tooltip says so, and undo and redo put the trail back.

## Algorithm

### 1. What the trail can be laid on

`TerrainTypes.can_host_walking_path()` allows the flag on `WALKING_PATH_TERRAINS`: rough and deep rough, waste bunkers, brush, rocks and boulders, streams, wild flowers, and every woodland tile. Fairway and firm fairway, green, tee box, the playable bunkers, water, out of bounds, natural grass, heavy rough and empty ground do not take one. The placement is refused with a message and no charge; painting the ground with a course tile afterwards drops the flag, as course terrain always replaces what is there (`TerrainGrid.set_tile()` erases it and emits `walking_paths_changed`).

One list serves the whole game: the player's brush stroke, `TerrainGrid.can_place_walking_path()`, and the paths a generated course is laid out with all read `can_host_walking_path()`. There is no generation-only allowance, so no trail anywhere sits on ground the player could not have trodden themselves.

### 2. Dirt or paved

`WalkingPathOverlay.rebuild()` collects the flagged tiles, then asks `upgraded_component_tiles()` which of them are paved. It is a static function so the rule is unit-testable without a scene:

```
flood the trail network 4-connected over the tiles that carry the walking-path flag
a component is paved when any of its tiles is orthogonally adjacent
    to a clubhouse footprint tile
```

The rebuild listens to `walking_paths_changed`, `elevation_changed`, `load_completed`, and a clubhouse being placed, removed or moved. Sculpting elevation only reprojects the trail; it does not re-decide the paving.

The same rebuild collects every tile a building stands on (`_occupied_tiles()`), because the drawing joins onto walls too. Those tiles are **not** walkable and never take a trail: a building is where a walk ends, so it never carries the network through itself, and two trails up against the same shop stay two networks. Only the clubhouse paves, and it paves through the flag, not through the walls.

A network that never touches the clubhouse stays dirt, and that is a normal outcome: the ground between two holes may be all fairway, so a generated course can arrive with its walks in several pieces (see [Generated Walking Paths](generated-walking-paths.md)).

### 3. Drawing

`tile_draw_commands(pos, upgraded, detail)` returns the drawing for one tile as data, so the same geometry can be unit-tested and reused by the toolbar button's art. The `_draw()` loop culls off-screen tiles and feeds the commands to Godot; `detail` is off on the Web build.

| | Dirt | Paved |
| --- | --- | --- |
| Verge | `DIRT_VERGE` band, half-width `DIRT_VERGE_W` | `PAVED_VERGE` band, half-width `PAVED_VERGE_W` |
| Kerb | — | `PAVED_DARK` band, half-width `PAVED_OUTER_W` |
| Body | `DIRT_COLOR` band, half-width `DIRT_HALF_W` | `PAVED_COLOR` band, half-width `PAVED_HALF_W` |
| Detail | a crown that wanders (`_wavy_band`), pebbles on the tread, blades on the verges | slabs laid between jittered joints that cross the whole walk, every other slab in `PAVED_LIGHT`, gravel on the verges, blades |
| Where arms meet | `_pad_shape` pad, octagon cut across the corners, aligned to `_walk_dir()` | kerb ring plus flagstone pad, the same way |
| Against a wall | `DIRT_APRON` threshold, flaring to `DIRT_APRON_W` | kerb and flagstone thresholds, flaring to `PAVED_APRON_W` |
| A trail end | `_taper` head pointing away from its one neighbour | kerb and flagstone heads pointing away |
| On its own | verge and body circles plus a pale core | gravel, kerb and flagstone circles |

Widths and radii are authored in tile units along the tile's isometric axes, so a trail is the same width on steep and shallow edges before projection; one tile edge is about 36 px on screen. Both walks are slimmer than the tile they cross — under the `0.155` half-width a dirt trail used to be — and paving is only a shade broader than the dirt it replaces. `DIRT_END_REACH` and `PAVED_END_REACH` run a dead end past the tile centre so the walk dies away into the grass instead of being cut off at the tile line; against a wall it is the far end that dies away, because the walk itself runs right up to the building.

An arm is a dictionary — `dir`, `edge`, `axis` and whether it ends at a wall — so the same band, pad and taper geometry lays a walk to another trail tile and to a building. `APRON_REACH` is how far back from the wall a threshold starts; `_flare()` is the band that broadens from the walking width to the width at the door. Every decoration of the walk — the wandering crown, the pebbles, the blades, the slab rhythm — is seeded from `_deterministic_rng()` on the tile and the arm, so a trail looks the same every time it is drawn and no two tiles look stamped out alike.

The trail is painted in the ground band (`z_index` 1), under the entities and — because `TerrainGrid.GROUND_DETAIL_ORDER` ranks it there — under `TreeOverlay`, which paints the standing trees last among the ground art. A walk laid through a wood is therefore drawn first and the sprites over it, so no ribbon crosses a trunk. Nothing is taken off the trail for it: a woodland tile still paints its ribbon in full, and the tree only covers the stretch its own art stands on.

### 4. The walk rate

Two functions answer "how quick is this tile for a walker?":

```
TerrainTypes.get_speed_modifier(type)          # deep rough 0.85x, brush 0.75x
WalkingPathOverlay.speed_modifier_at(pos)      # 1.0 off the trail, 1.25 dirt, 1.5 paved
TerrainGrid.walk_speed_modifier_at(pos)        # the two multiplied
```

`Golfer._process_walking()` reads it once per frame and multiplies `walk_speed` by it, so a golfer at 100 px/s covers 10 units in a tenth of a second on rough and 12.5 on a dirt trail — and the step is clamped to the distance left to the waypoint, so an accelerated frame cannot overshoot.

### 5. Route planning

`Golfer._find_path_to()` walks straight there when the two points are under 2.5 tiles apart, or under `MIN_ROUTE_DISTANCE` (5 tiles) with a clear straight line. Anything longer is offered to `_find_quickest_route()`, which returns a trail route, or nothing when walking straight there is the quickest way:

- `TerrainGrid.walk_field(bounds)` reads the box once into a flat rate array (`WalkField.rate`, 0.0 for a tile no walker enters) plus `best`, the quickest rate in the box. `best <= 1.0` means there is nothing quicker to walk on, so the walk is straight there.
- The search box is the two points grown by `slack` tiles: `ROUTE_SLACK_FRACTION` (35%) of the straight-line distance, between `ROUTE_MIN_SLACK` and `ROUTE_MAX_SLACK`, shrunk further until it holds at most `ROUTE_MAX_BOX` tiles. A golfer never crosses the course to reach a distant trail.
- Each step costs its walking time, `step / rate`, over the flat arrays with a binary heap. Diagonal steps cost √2 and may not cut a blocked corner.
- `TRAIL_PREFERENCE_TIME` (1.0) is how much longer than the straight walk a trail route may be before it is abandoned; if the straight line is blocked instead, any clear route is taken. `ROUTE_NODE_BUDGET` (2500) bounds the search.
- The route is snapped to the exact destination and reduced by `_corner_waypoints()` to tile-centre corners. With no route worth walking, `_find_path_around_obstacles()` still routes around water and out of bounds.

## Tuning Levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Build cost and upkeep | `terrain_types.gd` `WALKING_PATH_COST` | `$8`, no upkeep | Price of a trail tile |
| Bulldozer fee | `main.gd` `BULLDOZER_COSTS` | `$5` per path tile | Cost of removing a trail |
| Dirt walk rate | `walking_path_overlay.gd` `DIRT_SPEED_MODIFIER` | `1.25` | Speed multiplier on an unpaved trail |
| Paved walk rate | `walking_path_overlay.gd` `PAVED_SPEED_MODIFIER` | `1.5` | Speed multiplier once the trail reaches the clubhouse |
| Trail width | `walking_path_overlay.gd` `DIRT_HALF_W`, `DIRT_VERGE_W` | `0.125`, `0.185` tile units | Width of the ribbon and its trodden verge |
| Pavement width | `walking_path_overlay.gd` `PAVED_HALF_W`, `PAVED_OUTER_W`, `PAVED_VERGE_W` | `0.135`, `0.17`, `0.21` | Width of the flagstones, kerb and gravel |
| Threshold at a wall | `walking_path_overlay.gd` `APRON_REACH`, `DIRT_APRON_W`, `PAVED_APRON_W` | `0.17`, `0.165`, `0.175` | How far back a threshold starts, and how wide the walk is at a door |
| Crown and grain | `walking_path_overlay.gd` `DIRT_CENTRE_W`, `GRASS_BLADES` | `0.055`, see the constants | Width of the polished crown, and the blades over the verges |
| Colours | `walking_path_overlay.gd` `DIRT_*`, `PAVED_*`, `GRASS_BLADES` | see the constants | Palette of both surfaces and their weather |
| Shortest planned walk | `golfer.gd` `MIN_ROUTE_DISTANCE` | `5.0` tiles | Under this the golfer just walks straight there |
| Trail preference | `golfer.gd` `TRAIL_PREFERENCE_TIME` | `1.0` tile-times | How much slower than the straight walk a trail route may be |
| Search box | `golfer.gd` `ROUTE_SLACK_FRACTION`, `ROUTE_MIN_SLACK`, `ROUTE_MAX_SLACK`, `ROUTE_MAX_BOX` | `0.35`, `1`, `5`, `1200` tiles | How far a route may wander from the straight line |
| Search budget | `golfer.gd` `ROUTE_NODE_BUDGET` | `2500` tiles | Caps the work one walk can cost |
| Walk speed | `golfer.gd` `walk_speed` | `100` px/s | Base pace, before any surface multiplier |

## Related

- [Improvement Catalog](garden-catalog.md) lists the tile in the Improvements honeycomb.
- [Path Furniture](path-furniture.md) covers the benches and ball washers placed beside a walk.
- [Generated Walking Paths](generated-walking-paths.md) covers the network a generated course is laid out with.
- [Clubhouse](clubhouse.md) is what a trail has to reach to be paved.
- [Terrain Types](terrain-types.md) has the walking rates of the ground under the trail, and the retired id 9.
- [Golfer Needs and Statuses](../golfers/golfer-needs.md) covers pace satisfaction while walking.
- [Group Turn Order](../golf-play/group-turn-order.md) covers walkers stepping clear of a partner's shot.
- [Architecture](../../architecture.md) lists the draw bands the trail and the golfers paint in.
