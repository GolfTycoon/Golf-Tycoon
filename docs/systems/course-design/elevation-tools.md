# Elevation Selector Tools

> Three selector tools (Vertex, Flat Square and Gradual Square) reshape the ground one step at a time, and each has its own rules for which corners move.

**Source:** `scripts/tools/elevation_tool.gd` (`tile_offsets()`, `vertex_offsets()`, `brush_tiles()`, `brush_vertices()`, `middle_vertices()`, `distance_to_middle()`, `anchor_for_tool()`), `scripts/ui/terrain_toolbar.gd` (`BRUSH_SIZES`, hotkeys), `scripts/terrain/terrain_grid.gd` (`MIN_ELEVATION`, `MAX_ELEVATION`, `BASE_ELEVATION`, `set_vertex_elevation()`), `scripts/main/main.gd` (elevation input flow), `scripts/tools/undo_manager.gd` (`record_elevation_stroke()`)
**Tests:** `tests/unit/test_elevation_tools.gd`, `tests/unit/test_elevation_preview.gd`, `tests/harness/elevation_tools_harness.tscn`

---

## Plain English

Elevation is sculpted on the **Elevation** tab with three selector tools. They replace the older Rolling Hill, Hollow, Raise and Lower tools.

| Tool | Hotkey | What it does |
| --- | --- | --- |
| **Vertex Selector** | `V` | Raises or lowers a single corner (vertex) by one step. |
| **Flat Square Selector** | `+` | Levels uneven ground. Only the highest or lowest corners of the brush move, one step at a time. Once the brush is even, the whole square steps together as one flat slab. |
| **Gradual Square Selector** | `-` | Raises or lowers the centre, then moves nearby corners so no corner differs from the centre by more than one step per tile of distance. Repeated clicks build a gradual pyramid or basin. |

With a selector active:

- **Right-click raises** the ground, and **left-click lowers** it.
- Press to start a stroke, drag to paint, and release to end it.
- No corner outside the selection is touched. Corners under buildings, or on land you don't own, are skipped.
- **Esc** cancels the tool. Right-click no longer cancels.

The two square tools share one **Elevation Brush Size** and one **Brush Shape** control (square or round). They are kept separate from the Terrain Brush controls on the Course Terrain tab. Both square tools offer sizes from 1×1 to 9×9. Switching between them keeps the same size and shape.

### Brush sizes are counted in tiles

A brush of size S covers S×S tiles. Its corners are the (S+1)×(S+1) vertices that it edits. The hover preview tints exactly those tiles and marks exactly those vertices, so what you see under the cursor is what a click changes.

| Size | Square shape | Round shape |
| --- | --- | --- |
| 1×1 | 1 tile, 4 vertices | 1 tile, 4 vertices |
| 2×2 | 4 tiles, 9 vertices | 4 tiles, 9 vertices |
| 3×3 | 9 tiles, 16 vertices | 5 tiles, 12 vertices |
| 4×4 | 16 tiles, 25 vertices | 12 tiles, 21 vertices |
| 5×5 | 25 tiles, 36 vertices | 13 tiles, 24 vertices |
| S×S | S² tiles, (S+1)² vertices | Tiles whose centre is within S/2 of the middle |

---

## Algorithm

### 1. Brush geometry

`anchor_tile()` gives the tile under the cursor. A brush of size S covers tiles from `−(S/2)` to `S − 1 − (S/2)` on each axis. Odd sizes centre on the anchor tile. Even sizes centre on the vertex at the anchor's near corner.

With the round shape, a tile is kept when its centre is within `S/2` of the middle of the block. This is the same logic as the Course Terrain paint brush (`TerrainBrush.offsets()`), so an S×S stamp covers the same tiles in both tools.

```gdscript
static func tile_offsets(size: int, square_shape: bool) -> Array[Vector2i]:
	return TerrainBrush.offsets(size, not square_shape)
```

`vertex_offsets()` gathers the corners of those tiles without duplicates. Because the vertices come from the tiles, the preview and the click always agree.

- `middle_vertices()` returns `[anchor]` for even sizes, and the four corners of the anchor tile for odd sizes. The Gradual tool moves these first.
- `distance_to_middle()` is the Chebyshev distance from a vertex to the middle, measured in vertices.

### 2. Vertex Selector

```
new = clamp(old + (1 if raising else −1), MIN_ELEVATION, MAX_ELEVATION)
```

### 3. Flat Square Selector

Let `A` be the brush's editable vertices, with `lowest = min(A)` and `highest = max(A)`.

```
raising  (right-click): vertex == lowest  →  clamp(vertex + 1)
lowering (left-click):  vertex == highest →  clamp(vertex − 1)
every other vertex keeps its height
```

For example, raising a brush of heights `{0, 0, 2, 2}` gives `{1, 1, 2, 2}`. Lowering it gives `{0, 0, 1, 1}`. An already-even brush moves as one flat slab. If the extreme is already at the limit, nothing changes.

### 4. Gradual Square Selector

1. **Move the middle.** The middle vertex (or middle 2×2 block) is levelled to its highest or lowest value, then shifted by one step:
   ```
   level = max(middle)  (raising)   or   min(middle)  (lowering)
   target = clamp(level ± 1, MIN_ELEVATION, MAX_ELEVATION)
   ```
   If the middle does not change, the stroke does nothing.
2. **Keep the slope gradual.** Each other selected vertex `v` is clamped into a cone around the new target:
   ```
   new = clamp(old, target − d, target + d)     # d = distance_to_middle(v)
   ```
   A vertex one step away may differ from the middle by at most one level. A vertex two steps away may differ by at most two, and so on.

### 5. Recording and undo

Each tool records every changed vertex as `{position, old_elevation, new_elevation}`. The list goes to `UndoManager.record_elevation_stroke()`. Undo and redo replay the entries through `TerrainGrid.set_vertex_elevation()`.

### 6. Input flow

- A left press starts a lowering stroke, and a right press starts a raising stroke. The right press is handled before the Esc/cancel action.
- While a button is held, moving the cursor paints each new anchor it crosses. Releasing the button ends the stroke, and the tool stays selected.
- `anchor_for_tool()` snaps the Vertex Selector to the nearest vertex. The square tools use the tile the cursor is on. A drag therefore repaints once per tile the cursor enters.

### 7. Levels

Elevation levels are integers from `MIN_ELEVATION` (0) to `MAX_ELEVATION` (10), stored on the `(grid_width + 1) × (grid_height + 1)` vertex field. Flat, untouched ground sits at `BASE_ELEVATION` (5), so any course can be raised five levels or dug down five levels.

---

## Tuning Levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Elevation range | `terrain_grid.gd` `MIN_ELEVATION` / `MAX_ELEVATION` | `0` / `10` | Limits every tool clamps to |
| Base elevation | `terrain_grid.gd` `BASE_ELEVATION` | `5` | Flat level for untouched ground |
| Brush sizes | `elevation_tool.gd` `BRUSH_SIZES` | `1` to `9` | Available square and round sizes |
| Step size | Each paint function | `1` | Change per moved vertex |
| Round-clip radius | `TerrainBrush.offsets()` | `S/2` tiles | Which corners a round brush keeps |
| Gradual slope | Gradual cone clamp | `1` per vertex of distance | Maximum difference from the middle |
| Hotkeys | `terrain_toolbar.gd` input handling | `V` / `+` / `-` | Vertex / Flat Square / Gradual Square |

---

## Related

- [Course Architecture](course-character.md) covers how sculpted landforms are used by Quick Start.
- [Builder Tools](builder-and-review.md) covers the Course Terrain paint brush, which shares the same brush shapes.
- [Terrain Types](terrain-types.md) lists the tile types the elevation sits under.
