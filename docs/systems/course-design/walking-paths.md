# Walking Paths

> A walking path is a slim trail golfers can see and walk on. It is laid as a trodden dirt ribbon, and the whole network turns into a paved stone promenade once it reaches the clubhouse. Golfers walk quicker on it than on the ground it crosses, so planned routes step onto it whenever that saves them time.

**Source:** `scripts/terrain/walking_path_overlay.gd` (art, the connection rule and `speed_modifier_at()`), `scripts/terrain/terrain_grid.gd` (`walk_speed_modifier_at()`, `walk_field()`, `WalkField`), `scripts/entities/golfer.gd` (`_process_walking()`, `_find_path_to()`, `_find_quickest_route()`), `scripts/main/main.gd` (`_paint_walking_path_stamp()` and the bulldozer), `scripts/ui/placement_preview.gd`, `scripts/ui/components/terrain_tile_button.gd`
**Tests:** `tests/unit/test_walking_paths.gd`, `tests/unit/test_golfer_walking_routes.gd`, `tests/unit/test_terrain_toolbar.gd`, `tests/unit/test_path_furniture.gd`; `tests/harness/walking_path_harness.tscn`

---

## Plain English

The **Path** leads the Improvements tab's honeycomb. It is a painting tool, not a building: click or drag and each tile costs **$8**, the same as a cart path tile, and it adds no upkeep. A tile a building or a decoration already occupies cannot take one.

- **Dirt:** a freshly laid trail is a trodden ribbon over the ground it crosses — packed earth at the middle, trodden grass at the verges, a paler strip down the centre that boots have polished, and dry patches, pebbles and grass blades scattered along it. Each tile carries a pad, and pads on edge-adjacent tiles join into one continuous walk, so a trail reads as a trail rather than a row of tiles.
- **Paved:** the moment the connected trail network touches a clubhouse tile, **every** trail in that network is paved — light flagstones with joints across the walk, a kerb of dressed darker stone either side, gravel bedded into the grass, and a few slabs catching the light. Take the link away — bulldoze a tile of it, paint over the ground, or move the clubhouse — and the trail is dirt again.
- **Walking quicker:** a golfer on a dirt trail walks **1.25×** as fast as the same ground without it, and **1.5×** on paving. The ground's own rate still counts, so a trail through brush is quicker than ploughing through the brush but slower than a trail over rough.
- **Preferring the walk:** a planned walk steps onto the trail when that gets the golfer there no more than **a moment slower** than walking straight there, and never crosses the course to reach a distant trail. Water and out of bounds are still walked around.
- Trails are also carried across **cart paths** (`TerrainTypes.Type.PATH`) and vice versa: painting the course terrain joins the network, so a trail can be paved by connecting to a cart path that already reaches the clubhouse.
- The bulldozer removes a trail for **$5** a tile, leaving rough ground. Its tooltip says so, and undo and redo put the trail back.

## Algorithm

### 1. What the trail can be laid on

`TerrainTypes.can_host_walking_path()` allows the flag on `WALKING_PATH_TERRAINS`: rough and deep rough, waste bunkers, brush, rocks and boulders, streams, wild flowers, and every woodland tile. Fairway, green, the playable bunkers, water, out of bounds and cart paths themselves do not take one. The placement is refused with a message and no charge; painting the ground with a course tile afterwards drops the flag, as course terrain always replaces what is there.

### 2. Dirt or paved

`WalkingPathOverlay.rebuild()` collects the flagged tiles, then asks `upgraded_component_tiles()` which of them are paved. It is a static function so the rule is unit-testable without a scene:

```
flood the trail network 4-connected, treating a tile as a node when
    it carries the walking-path flag, or its terrain is Type.PATH
a component is paved when any of its tiles is orthogonally adjacent
    to a clubhouse footprint tile
```

The rebuild listens to `walking_paths_changed`, `elevation_changed`, a `terrain_tile_changed` on a cart path (both old and new type), `load_completed`, and a clubhouse being placed, removed or moved. Sculpting elevation only reprojects the trail; it does not re-decide the paving.

### 3. Drawing

`tile_draw_commands(pos, upgraded, detail)` returns the drawing for one tile as data, so the same geometry can be unit-tested and reused by the toolbar button's art. The `_draw()` loop culls off-screen tiles and feeds the commands to Godot; `detail` is off on the Web build.

| | Dirt | Paved |
| --- | --- | --- |
| Verge | `DIRT_VERGE` band, half-width `DIRT_VERGE_W` | `PAVED_VERGE` band, half-width `PAVED_VERGE_W` |
| Kerb | — | `PAVED_DARK` band, half-width `PAVED_OUTER_W` |
| Body | `DIRT_COLOR` band, half-width `DIRT_HALF_W` | `PAVED_COLOR` band, half-width `PAVED_HALF_W` |
| Detail | pale centre band, grain and blades | jittered joints across the walk, sheen on about 60% of slabs, grain and blades |
| Where arms meet | `_pad_shape` pad, octagon cut across the corners, aligned to `_walk_dir()` | kerb ring plus flagstone pad, the same way |
| A trail end | `_taper` head pointing away from its one neighbour | kerb and flagstone heads pointing away |
| On its own | verge and body circles plus a pale core | gravel, kerb and flagstone circles |

Widths and radii are authored in tile units along the tile's isometric axes, so a trail is the same width on steep and shallow edges before projection; one tile edge is about 36 px on screen. `DIRT_END_REACH` and `PAVED_END_REACH` run a dead end past the tile centre so the walk dies away into the grass instead of being cut off at the tile line.

### 4. The walk rate

Two functions answer "how quick is this tile for a walker?":

```
TerrainTypes.get_speed_modifier(type)          # cart path 1.5x, deep rough 0.85x, brush 0.75x
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
| Build cost and upkeep | `terrain_types.gd` `PROPERTIES` (Type.PATH) | `$8`, no upkeep | Price of a trail tile, and of painting a cart path |
| Bulldozer fee | `main.gd` `BULLDOZER_COSTS` | `$5` per path tile | Cost of removing a trail |
| Dirt walk rate | `walking_path_overlay.gd` `DIRT_SPEED_MODIFIER` | `1.25` | Speed multiplier on an unpaved trail |
| Paved walk rate | `walking_path_overlay.gd` `PAVED_SPEED_MODIFIER` | `1.5` | Speed multiplier once the trail reaches the clubhouse |
| Trail width | `walking_path_overlay.gd` `DIRT_HALF_W`, `DIRT_VERGE_W` | `0.155`, `0.23` tile units | Width of the ribbon and its trodden verge |
| Pavement width | `walking_path_overlay.gd` `PAVED_HALF_W`, `PAVED_OUTER_W`, `PAVED_VERGE_W` | `0.23`, `0.28`, `0.31` | Width of the flagstones, kerb and gravel |
| Colours | `walking_path_overlay.gd` `DIRT_*`, `PAVED_*`, `GRASS_BLADES` | see the constants | Palette of both surfaces and their weather |
| Shortest planned walk | `golfer.gd` `MIN_ROUTE_DISTANCE` | `5.0` tiles | Under this the golfer just walks straight there |
| Trail preference | `golfer.gd` `TRAIL_PREFERENCE_TIME` | `1.0` tile-times | How much slower than the straight walk a trail route may be |
| Search box | `golfer.gd` `ROUTE_SLACK_FRACTION`, `ROUTE_MIN_SLACK`, `ROUTE_MAX_SLACK`, `ROUTE_MAX_BOX` | `0.35`, `1`, `5`, `1200` tiles | How far a route may wander from the straight line |
| Search budget | `golfer.gd` `ROUTE_NODE_BUDGET` | `2500` tiles | Caps the work one walk can cost |
| Walk speed | `golfer.gd` `walk_speed` | `100` px/s | Base pace, before any surface multiplier |

## Related

- [Improvement Catalog](garden-catalog.md) lists the tile in the Improvements honeycomb.
- [Path Furniture](path-furniture.md) covers the benches and ball washers placed beside a walk.
- [Clubhouse](clubhouse.md) is what a trail has to reach to be paved.
- [Terrain Types](terrain-types.md) has the walking rates of the terrain under the trail, including the cart path.
- [Golfer Needs](../golfers/golfer-needs.md) covers pace satisfaction while walking.
- [Group Turn Order](../golf-play/group-turn-order.md) covers walkers stepping clear of a partner's shot.
