# Bunker Depth (Shallow vs Deep)

> Each bunker tile is either shallow or deep. Deep bunkers cost more accuracy and distance and add more to the hole's difficulty. Pot bunkers are a separate, harsher tile type.

**Source:** `scripts/terrain/terrain_grid.gd` (`set_bunker_depth()`, `serialize_bunker_depth()`), `scripts/systems/golf_rules.gd` (`get_lie_modifier()`, `get_terrain_distance_modifier()`), `scripts/course/difficulty_calculator.gd`, `scripts/terrain/bunker_overlay.gd`, `scripts/systems/course_theme.gd` (`default_bunker_depth`), `scripts/main/main.gd` (Shift+click toggle)

---

## Plain English

A bunker is either **shallow** (the default) or **deep**. A deep bunker is harder to escape. Shots from it are less accurate and travel shorter distances. A deep bunker also adds more to the hole's difficulty.

**Changing depth.** Hold Shift and click a bunker tile to toggle it between shallow and deep. The depth is saved with the course.

**Theme defaults.** Newly painted bunkers take their depth from the course theme. **Links** and **Heathland** default to **deep**, because their pot bunkers are traditionally deep. All other themes default to shallow. Existing bunkers keep their depth when the theme changes.

**Pot bunkers are a different tile.** A pot bunker (`TerrainTypes.Type.POT_BUNKER`) is a small pit with a steep revetted face. It has no depth setting and is harsher than any bunker tile. Only a lofted wedge gets out cleanly, and the AI treats it as a wedge-only escape. Waste bunkers are sandy ground and are not hazards at all (see [Shot Accuracy](../golf-play/shot-accuracy.md)).

---

## Algorithm

### 1. Data model

```
_bunker_depth_grid: Dictionary   # Vector2i -> 0 (SHALLOW) or 1 (DEEP)
```

Depth is stored separately from the terrain grid. Setting a tile back to shallow erases its entry, so only deep tiles are kept and saved.

### 2. Lie modifier (accuracy)

`get_lie_modifier(terrain, club, depth)` multiplies the shot's accuracy.

| Lie | Wedge | Other clubs |
| --- | --- | --- |
| Shallow bunker | 0.60 (40% penalty) | 0.40 (60% penalty) |
| Deep bunker | 0.45 (55% penalty) | 0.25 (75% penalty) |
| Pot bunker | 0.35 | 0.15 |

### 3. Distance modifier

`get_terrain_distance_modifier()` multiplies the distance the shot carries.

| Lie | Modifier |
| --- | --- |
| Shallow bunker | 0.75 (25% loss) |
| Deep bunker | 0.60 (40% loss, the ball pops out shorter) |
| Pot bunker | 0.45 (55% loss, straight up over the face) |

### 4. Difficulty contribution

`difficulty_calculator.gd` adds to the hole's difficulty for each bunker tile in the corridor.

| Tile | Difficulty per tile |
| --- | --- |
| Shallow bunker | +0.15 |
| Deep bunker | +0.25 |
| Pot bunker | +0.30 |

### 5. Visual differences

`bunker_overlay.gd` draws a cluster of sand dots on each bunker tile. The dots are generated from a seed based on tile position, so they don't shimmer. Deep bunkers get more and larger dots, and a darker tint.

| Property | Shallow | Deep |
| --- | --- | --- |
| Dots per tile (desktop) | 6 to 12 | 10 to 18 |
| Dots per tile (web) | 5 to 8 | 5 to 8 |
| Dot radius | 0.8 to 1.5 px | 1.0 to 2.0 px |
| Dot colour (RGBA) | `(0.75, 0.68, 0.45, 0.35)` | `(0.60, 0.55, 0.35, 0.45)` |

The web build uses fewer dots (5 to 8) for both depths, to keep rendering light.

### 6. Painting and undo

When a bunker tile is painted, the theme default is applied in `main.gd`. Painting over an existing bunker does not change its depth. Each depth change is recorded in the undo stroke, so undo restores the previous depth.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Shallow lie modifier (wedge) | `golf_rules.gd` `get_lie_modifier()` | `0.60` | Wedge accuracy from a shallow bunker |
| Shallow lie modifier (other) | `golf_rules.gd` `get_lie_modifier()` | `0.40` | Non-wedge accuracy from a shallow bunker |
| Deep lie modifier (wedge) | `golf_rules.gd` `get_lie_modifier()` | `0.45` | Wedge accuracy from a deep bunker |
| Deep lie modifier (other) | `golf_rules.gd` `get_lie_modifier()` | `0.25` | Non-wedge accuracy from a deep bunker |
| Shallow distance modifier | `golf_rules.gd` `get_terrain_distance_modifier()` | `0.75` | Distance kept from a shallow bunker |
| Deep distance modifier | `golf_rules.gd` `get_terrain_distance_modifier()` | `0.60` | Distance kept from a deep bunker |
| Shallow difficulty per tile | `difficulty_calculator.gd` | `0.15` | Difficulty per shallow bunker tile |
| Deep difficulty per tile | `difficulty_calculator.gd` | `0.25` | Difficulty per deep bunker tile |
| Pot bunker difficulty per tile | `difficulty_calculator.gd` | `0.30` | Difficulty per pot bunker tile |
| Deep dot count (desktop) | `bunker_overlay.gd` | `10` to `18` | Visual density of deep bunkers |
| Theme default depth | `course_theme.gd` `default_bunker_depth` | Links and Heathland `1` (deep); others `0` | Depth given to new bunkers |

---

## Related

- [Terrain Types](terrain-types.md) lists every tile type.
- [Difficulty Calculator](difficulty-calculator.md) explains how the per-tile values combine.
- [Shot Accuracy](../golf-play/shot-accuracy.md) explains how lie modifiers affect a shot.
- [Shot AI: Target Finding](../golf-play/shot-ai-target-finding.md) explains how AI golfers handle bunkers.
