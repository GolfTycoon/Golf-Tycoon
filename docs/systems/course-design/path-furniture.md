# Path Furniture Placement

> Benches and ball washers are baked sprites turned to face the walk they sit beside. Their placement never changes pathfinding or terrain.

**Source:** `scripts/entities/path_furniture.gd` (`layout()`, `draw_item()`, `ground_reach()`, `SMALL_FIXTURES`, `EDGE_ORDER`), `scripts/entities/improvement_art.gd` (sprite, front and foot lookup), `scripts/entities/decoration.gd` (`refresh_terrain_occlusion()`, `art_reach()`), `scripts/terrain/terrain_grid.gd` (`surface_refreshed`), `scripts/terrain/walking_path_overlay.gd`, `assets/sprites/improvements/`
**Tests:** `tests/unit/test_path_furniture.gd`, `tests/unit/course_design/test_terrain_occlusion.gd`

---

## Plain English

Path furniture used to sit at a fixed diagonal angle, and sometimes on a patch of grass under its feet. Now it follows the walk:

- **Benches and ball washers** are small fixtures. A fixture on a tile the walk crosses sits just inside its exposed edge, facing back into the tile.
- **Benches on grass** beside a walk face the walk.
- Furniture is drawn on the same ground layout as the placement ghost, so what you see while placing is what gets built.

The tile you placed the item on is still the anchor for selection, removal and saving. Furniture never moves into a neighbouring tile. It does not change pathfinding, costs or terrain.

Existing fixtures realign after a trail is painted or bulldozed, after undo and redo, or on any bulk refresh.

---

## Algorithm

### 1. Choosing the edge

`PathFurniture.layout()` checks the four cardinal neighbours of the tile. For a tile carrying a trail, it picks the first exposed edge in this order:

```
north → west → east → south
```

An edge counts as exposed only if the neighbour is land. Water, bunkers, invalid positions and a neighbour carrying the same walk are excluded. The trail is a flag over the ground rather than a terrain of its own, so the neighbour beside it has to be ruled out by the flag and not by the ground under it. The visual is offset toward that edge, and it faces inward. Its footprint stays within the tile.

For furniture off the walk, it faces the first adjacent tile carrying a trail and is not offset.

Plaza and intersection tiles, which are surrounded on every side, keep the tile centre. Large improvements such as the fountain keep their placement centre.

### 2. Drawing

- **Edge offset:** `23` px for an edge on the horizontal axis, `10` px for an edge on the vertical axis. This keeps the middle of a walk open.
- **Benches and washers** are baked sprites, one drawing per front (`assets/sprites/improvements/park_bench_0..3.png`). `draw_item()` draws the drawing that matches `facing`; the old vector bench remains only as a fallback when the art is missing. See [Improvement Art](improvement-art.md).
- **Foot anchor:** the art is cropped to its pixels and anchored from the tile-centre foot recorded in `layout.json` (`ImprovementArt.foot_offset()`), never from transparent padding or a centered sprite.
- **Built fixtures** stay upright. **Natural plantings** keep their deterministic variation. Ghosts use the same texture, foot and variation as placed props.
- **Behind a hill:** a nearer hill hides furniture and every other decoration pixel by pixel. Each stands on its tile's centre and is measured from the lowest pixel of its art: `ground_reach()` is the drawing's own overhang below that foot, so the ground it stands on never cuts into it. Furniture casts no ground shadow, and ghosts are never clipped.

### 3. Refresh

Ordinary edits within one cardinal tile queue a single deferred visual rebuild. `TerrainGrid.surface_refreshed` also requests a rebuild after quiet generation or deserialization. There is no per-frame neighbour scan.

---

## Tuning Levers

| Setting | Location | Current value | Effect |
| --- | --- | --- | --- |
| Horizontal edge offset | `path_furniture.gd` `layout()` | `23` px | Distance from a horizontal edge |
| Vertical edge offset | `path_furniture.gd` `layout()` | `10` px | Distance from a vertical edge |
| Edge priority | `path_furniture.gd` `EDGE_ORDER` | North, west, east, south | Which edge wins when several are exposed |
| Small fixtures | `path_furniture.gd` `SMALL_FIXTURES` | Bench, ball washer | Items that get edge placement |

---

## Related

- [Improvement Catalog](garden-catalog.md) lists the improvements.
- [Builder Tools](builder-and-review.md) covers the path tile.
- [Course Wildlife](course-wildlife.md) covers the ducks and butterflies that live on the course.
