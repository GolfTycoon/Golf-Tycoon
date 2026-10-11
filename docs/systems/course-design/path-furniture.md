# Path Furniture Placement

> Benches and ball washers are drawn on the ground plane and turned to face the walk they sit beside. Their placement never changes pathfinding or terrain.

**Source:** `scripts/entities/path_furniture.gd` (`layout()`, `draw_item()`, `SMALL_FIXTURES`, `EDGE_ORDER`), `scripts/entities/decoration.gd`, `scripts/terrain/terrain_grid.gd` (`surface_refreshed`), `scripts/terrain/walking_path_overlay.gd`
**Tests:** `tests/unit/test_path_furniture.gd`

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
- **Benches** project their length and depth onto the grid, with height drawn upward. A horizontal walk gets a horizontal bench. A vertical walk gets a bench that recedes at half scale. The legs and contact marks share the same foot coordinates. The backrest stays visible when seen edge-on.
- **Foot anchor:** decorations use the visible bottom of their artwork as the foot, which corrects for transparent padding. The fountain's animated droplets use the same correction.
- **Built fixtures** stay upright. **Natural plantings** keep their deterministic variation. Ghosts use the same anchor and variation as placed sprites.

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
