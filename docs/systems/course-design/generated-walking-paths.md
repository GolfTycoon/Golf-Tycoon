# Generated Walking Paths

> A generated course arrives with its walks already trodden: out of the clubhouse door to the first tee, along the mown edge of every hole, from each green to the next tee, and home again from the last green. What is laid is the Improvements tab's Path — dirt over the ground it crosses, stone once its network reaches the clubhouse — so it never replaces the turf, never takes a tee, a green, a bunker, water, a building or land the player does not own, and adds nothing to the maintenance bill. A trail sits only on ground the Path improvement accepts, and that ground is a rule rather than a preference: a hole sealed in by its own fairway and bunkers is met a few tiles out, or not at all, and a course can therefore arrive with its walks in more than one piece and with some of them still dirt.

**Source:** `scripts/terrain/course_path_generator.gd` (the whole network), `scripts/main/main.gd` (`_on_new_game_started()`, which lays it), `scripts/terrain/walking_path_overlay.gd` (how a trail is drawn, and which networks pave), `scripts/terrain/terrain_types.gd` (`WALKING_PATH_TERRAINS`, `can_host_walking_path()`)
**Tests:** `tests/unit/test_course_path_generator.gd`, `tests/integration/generated_course_hole_layout.gd`; `tests/harness/course_path_preview.gd`

---

## Plain English

Quick Start, the Start New Game layouts (3, 6, 9 or 18 holes) and every prebuilt package build their holes, place the clubhouse, and then the walks are laid over the lot. There is nothing to click: the course opens with its paths in place, and they are the same paths the player buys a tile at a time.

- **What you see:** the trodden ribbon of the Path improvement — a one-tile-wide trail of worn ground running *beside* each fairway rather than down it, coming up behind each tee and past each green. Where the trail's network reaches the clubhouse it is paved: stone rather than dirt, and walked at **1.5×** instead of **1.25×** (see [Walking Paths](walking-paths.md)).
- **Where it will not go:** the mown playing line — fairway, green, tee box — and bunkers, water, out of bounds, natural grass, heavy rough, and any tile a building or a decoration stands on. Land the player does not own is off limits, exactly as it is for a brush stroke. This is the player's own rule (`TerrainTypes.can_host_walking_path()`) applied to generation, so nothing a generator lays could not be painted by hand.
- **What it prefers:** rough and deep rough, then scrub, stone, wild flowers and a stream, then woodland. In practice it takes open rough: on every layout measured here the paths ran through **no** woodland tiles at all, because there was always cheaper ground to walk.
- **It stops short rather than crossing the play.** A tee or a green ringed by its own fairway is met at the nearest ground that can host a trail, up to `HUB_RINGS` rings out; where even that finds nothing, the hole keeps no walk at all. On the prebuilt Executive package one green of nine comes out that way.
- **The network can be in pieces, and unpaved.** Because the mown ground between two holes cannot be crossed, a walk that cannot be routed is simply not laid, and a trail that never touches the clubhouse stays dirt. This is the trade the design accepts: no hole is walked over, and some courses arrive with several separate networks. The measurements below say how often.
- **Golfers use it.** A trail is walked at **1.25×**, and at **1.5×** where it is paved, so planned routes step onto it whenever that saves time (see [Walking Paths](walking-paths.md)). The Pace rating does not move, because it measures the straight-line walk between holes (see [Routing Overlay](routing-overlay.md)).
- **It is free.** A trail is not a terrain tile: the ground underneath keeps its lie, its bounce, its upkeep and its difficulty, and the generator charges the player nothing for the tiles it lays.
- **It is laid once.** Bulldozing a trail, painting over the ground or building on it afterwards is the player's business, and behaves exactly as it does for a trail they laid themselves.

## Algorithm

### 1. When the network is laid

`main.gd::_on_new_game_started()` runs, in order:

```
reset the course → natural terrain → the layout (Quick Start / GeneratedCourse / PrebuiltCourseGenerator)
    → _ensure_course_clubhouse(preferred) → CoursePathGenerator.generate(...) → camera and rating
```

The call is guarded by `clubhouse != null and GameManager.get_open_hole_count() > 0`, wrapped in `_suppress_tile_undo` and a terrain batch, and followed by `refresh_all_overlays()`.

Two orderings matter:

- **After the clubhouse**, because the arrival walk is planned to the clubhouse door, and `_ensure_course_clubhouse()` may place it somewhere other than the layout's preferred tile. The layout's tile is still passed as `clubhouse_hint` for a course whose clubhouse could not be built.
- **After the holes**, because `HoleCreationTool.create_generated_hole()` computes difficulty and stroke index when a hole opens, and a trail is not a terrain tile at all. Ratings and difficulty are therefore exactly what they would be without the paths.

A layout may also author its own trails — Quick Start lays the arrival garden's walk itself — and the generator simply joins what it finds: a tile that already carries a trail is the cheapest ground there is.

### 2. The legs

```
clubhouse door → tee 1                        the arrival walk
tee N          → green N                      guided along the mown edge
green N        → tee N+1                      a link, no guide
green N        → clubhouse door               only when there is more than one hole
```

`generate()` sorts the holes into playing order by `hole_number`, skips holes that are not open, and returns how many tiles *this call* laid — nothing at all when the network is already on the ground, so it is safe to call twice.

Each leg is laid by `_lay_leg()`, which returns where the network has got to, and that is where the next leg starts. When a leg cannot be walked — no route at all, or one longer than `MAX_LINK_TILES` — the hole still gets its own walk: `end` moves to `_preferred()`, the best of the ground the hub search found, and the leg along the hole is laid from there. So a break in the network costs the link between two holes, never a hole's own walk.

### 3. What a leg may be laid on

Two lists agree, and both are the player's: `TerrainTypes.can_host_walking_path()` decides whether `TerrainGrid.can_place_walking_path()` will accept a tile at all, and `TERRAIN_COSTS` prices the ground a leg may cross. Ground missing from `TERRAIN_COSTS` is `BLOCKED_COST` (infinity) in `_step_cost()`. That is how every tee, green, bunker and hazard stays clear without a special case for each.

| Ground | Cost of a tile |
| --- | --- |
| A trail an earlier leg laid | `LAID_TRAIL_COST` = `0.25` |
| Rough, deep rough | `1.0` |
| Waste bunker, brush, flower bed, rocks, boulders, stream | `2.0` |
| Any woodland tile (`TerrainTypes.is_tree`) | `WOODLAND_COST` = `3.0` |
| Fairway, firm fairway, green, tee box, bunker, pot bunker, water, out of bounds, natural grass, heavy rough, empty | blocked |
| A building's or a decoration's tile | blocked |
| Land the player does not own | blocked |

### 4. The ends of a leg: the ground a walk comes in on

A leg is not planned to the tee or the cup but to the **ground beside it**, found by `_tee_ground()` and `_green_ground()` → `_hub_ground()`. Every layable tile within `HUB_RINGS` rings of the target is a goal at once, each priced for how far out it is and which side of the play it stands on:

```
price = (ring − 1) × RING_COST + (WRONG_SIDE_COST when the tile is on the same
        side as the hole's other end)
```

- A **tee's** targets are the back tee (`hole.tee_position` — the forward and middle tees of a multi-tee course lie along the corridor the path follows anyway), priced away from the green; a **green's** targets are the cup plus the ring of green around it (`_green_tiles()`), priced away from the tee. So a walk comes in behind the tee and past the green, never across the putting surface or in the line of play.
- Both prices are dear against a tile of ordinary walking: a leg that could come in two rings closer for a detour of three tiles takes the detour. The search then settles on the *cheapest arrival* rather than the first goal it reaches, so a walk comes as close to the play as the ground lets it.
- The **clubhouse end** is its door (`_clubhouse_door()`): the nearest layable tile orthogonally beside the footprint (`_clubhouse_arrival()`), else `CourseClubhouse.front_tile()`, else the nearest layable tile within `CLUBHOUSE_REACH`, or — when the course has no clubhouse yet — the tile below `clubhouse_hint`.

`_hub_ground()` returns nothing at all when a tee or a green has no hostable ground within `HUB_RINGS`, which is what a green sealed in by its own fairway and bunkers comes to: that hole keeps no walk rather than one that crosses the turf.

### 5. The guide

`_hole_guide()` merges the two `_corridor_guide()` polylines — one each side of the tee-to-green line — into the guide a hole's own leg follows. Each samples the line up to `GUIDE_MAX_POINTS` times; at every sample `_mown_edge()` scans `CORRIDOR_SCAN` tiles perpendicular for the **outermost** fairway tile, and the guide point is that edge pushed out by `PATH_CLEARANCE`. A sample with no mown ground at all — a corridor a hazard has taken — uses `FALLBACK_EDGE`.

The edge is read from the painted ground rather than from a layout table, so the guide follows the corridor's own bend and width, and a hole the *player* painted could be followed just as well. A link between two holes has no guide, so it is a plain terrain walk — which is what makes it follow the trails already laid rather than strike out across the property.

### 6. The walk

`_plan_route()` is a 4-directional A* over the leg's search box:

```
step cost = _step_cost(tile) + guide_weight × guide_field[cell]
estimate  = the goal field's distance to the nearest goal × the cheapest ground in the box
            (floored at LAID_TRAIL_COST, so it never over-estimates)
box       = the start and the goals grown by ROUTE_SLACK, clamped to the grid
budget    = NODE_BUDGET cells; the frontier is _Frontier, a binary heap over flat arrays
```

`_guide_field()` fills the distance from every cell of the box to the guide polyline once per leg, capped at `GUIDE_MAX_DISTANCE`: past a few tiles of the guide the ground has taken the walk somewhere else — round a pond, behind a green — and being further off there is no worse than being a little off. `_goal_field()` is a multi-source breadth-first walk from every goal over the same box, so the estimate works for a leg with many goals at once.

The search settles the **cheapest arrival**, not the first goal it reaches: `_arrival()` prices a goal tile by its own hub price, keeps expanding through goal tiles, and stops when the frontier can no longer beat the best arrival found. Without that, a leg takes the first ground it can touch and leaves the tee or the green a long way off.

Four directions only, never eight: `WalkingPathOverlay` floods the network 4-connected and draws a trail as one continuous band only where tiles share an edge, so a diagonal step would leave two tiles touching at a corner — a row of separate dots on screen, and a network split in two.

A leg that cannot be planned is skipped silently and the rest of the network is still laid; a capped leg longer than `MAX_LINK_TILES` is left unlaid for the same reason, because a walk that long would snake across the property rather than read as a path.

### 7. Painting

`_lay()` walks the planned route, re-checks `_is_layable()` on every tile — an earlier leg may have changed the ground — skips tiles that already carry a trail, and flags the rest with `TerrainGrid.set_walking_path_quiet(tile, true)`. Quiet, because the whole network is laid inside one terrain batch and the overlay rebuilds at the end. The ground is left exactly as the layout painted it, so the tiles are not player edits, carry no build cost and add nothing to `get_total_maintenance_cost()`.

A leg whose route is a single tile — the network has already got to a hub — still counts as arriving there, and a lone trail tile is drawn as a dot. That is what the one-tile networks in the measurements below are.

### 8. What it costs, and what it changes

Measured with `tests/harness/course_path_preview.gd` on a 128×128 course, seed 1234, one run each:

| Layout | Holes | Tiles laid | Time | Networks | Paved | Walked |
| --- | --- | --- | --- | --- | --- | --- |
| Quick Start | 9 | 176 (203 on the course) | 0.36 s | 5 | 38 | 9 tees, 9 greens |
| Generated (Start New Game) | 3 | 66 | 0.06 s | 1 | 66 | 3 tees, 3 greens |
| Generated (Start New Game) | 6 | 119 | 0.13 s | 1 | 119 | 6 tees, 6 greens |
| Generated (Start New Game) | 9 | 197 | 0.21 s | 2 | 35 | 9 tees, 9 greens |
| Generated (Start New Game) | 18 | 354 | 0.48 s | 3 | 32 | 18 tees, 18 greens |
| Prebuilt Starter | 3 | 76 | 0.07 s | 1 | 76 | 3 tees, 3 greens |
| Prebuilt Executive | 9 | 83 | 0.17 s | 1 | 83 | 9 tees, 8 greens |
| Prebuilt Standard 9 | 9 | 181 | 0.19 s | 2 | 17 | 9 tees, 9 greens |
| Prebuilt Championship 18 | 18 | 217 | 0.44 s | 7 | 0 | 18 tees, 18 greens |

`Playing surfaces a path was laid on: 0` on every one of those runs — of 202 to 1180 mown tiles and 114 to 386 greens, tees, sand and water, not one was walked on. All of the work happens inside the "Generating course..." loading screen.

How far a walk stands off the play, in Chebyshev rings from the tee or the cup to the nearest trail:

- **Quick Start:** tees 1 to 6 rings out (most 2 or 3), greens 2 to 4. Three of the nine holes have a paved tee or green.
- **Prebuilt Championship 18:** tees 1 to 8 (most 2), greens 2 to 8. Nothing is paved: the clubhouse door sits in a pocket of ground the fairways seal off, so no leg reaches it.
- **Generated 3, 6 and 18, Starter, Executive, Standard 9:** one network each on the small layouts, all of it paved.

This is the honest state of the design: **networks can be partial and unpaved.** A course whose clubhouse is walled in by its own mown ground arrives with dirt walks, and a hole whose ground is sealed off arrives with a walk that stops short of it — or, on the Executive package's ninth green, with none. The alternative, letting a generated path cross a fairway, was rejected: the point of laying the Path improvement rather than a terrain of its own is that the ground the player is sold a trail on is the ground a generated course is laid on.

Effects on the rest of the game:

- **Nothing changes** in [Difficulty Calculator](difficulty-calculator.md), the stroke index or the ratings: a trail is not a terrain tile, so there is nothing for them to weigh.
- **Condition, value and the maintenance bill** are untouched: the ground keeps its own upkeep, and the tiles laid cost the player nothing.
- **Play** is untouched: the ball lies on the ground under the trail, exactly as it did before the walk was trodden.

## Tuning Levers

All of these live in `scripts/terrain/course_path_generator.gd`.

| Setting | Constant | Current value | Effect |
| --- | --- | --- | --- |
| Ground a leg may take | `TERRAIN_COSTS` | see the table above | The priced allow-list; anything absent is blocked |
| Price of clearing trees | `WOODLAND_COST` | `3.0` | How readily a path cuts woodland |
| Price of joining an earlier leg | `LAID_TRAIL_COST` | `0.25` | How strongly legs merge into one network |
| Ground a path may not take | `BLOCKED_COST` | infinity | The mown line, sand, water, out of bounds |
| Distance from the fairway | `PATH_CLEARANCE` | `1.25` tiles | How far out from the mown edge the guide runs |
| Edge when a sample finds no turf | `FALLBACK_EDGE` | `2.0` tiles | The guide's distance where a hazard has taken the corridor |
| How wide the corridor is read | `CORRIDOR_SCAN` | `7` tiles | Must exceed the widest generated corridor plus its bend |
| Guide samples | `GUIDE_MAX_POINTS` | `48` | A leg is guided, not traced, so about one sample a tile is plenty |
| Pull toward the guide | `HOLE_GUIDE_WEIGHT` | `1.6` per tile | Above open ground's cost, below the cost of halving a corridor |
| Furthest the guide still pulls | `GUIDE_MAX_DISTANCE` | `4.0` tiles | Past this, being further off the guide costs no more |
| How far out a walk may come in | `HUB_RINGS` | `8` rings | Past this a hole keeps no walk at all |
| One ring further out | `RING_COST` | `4.0` | Preference for meeting a tee or green close up |
| Standing in the line of play | `WRONG_SIDE_COST` | `6.0` | Keeps walks behind tees and past greens |
| Clubhouse with no hostable door | `CLUBHOUSE_REACH` | `6` tiles | How far the network may arrive from the footprint |
| Longest walk between two holes | `MAX_LINK_TILES` | `80` tiles | Longer links are left unlaid |
| Search box | `ROUTE_SLACK` | `8` tiles | How far a leg may step round what is in its way |
| Search budget | `NODE_BUDGET` | `9000` cells | Caps the work one leg can cost |

## Related

- [Walking Paths](walking-paths.md) covers the trail itself: what it looks like, what it costs, how it paves and how a golfer walks it.
- [Terrain Types](terrain-types.md) has the ground a trail can be laid on, and the retired id 9.
- [Course Surface](course-surface.md) covers how the ground, including the trail, is drawn.
- [Clubhouse](clubhouse.md) is the door the network is planned to.
- [Hole Creation](hole-creation.md) covers what a generated hole is, and when its difficulty is settled.
- [Routing Overlay](routing-overlay.md) covers the Pace rating's straight-line walking distances.
- [Testing](../../development/testing.md) covers the preview harness that prints the measurements above.
