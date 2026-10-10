# Path Furniture Placement

> Benches, signs, bins, ball washers and bird baths are drawn on the ground plane and turned to face the walk they sit beside. Their placement never changes pathfinding or terrain.

**Source:** `scripts/entities/path_furniture.gd` (`layout()`, `draw_item()`, `SMALL_FIXTURES`, `EDGE_ORDER`), `scripts/entities/decoration.gd`, `scripts/terrain/terrain_grid.gd` (`surface_refreshed`), `scripts/terrain/walking_path_overlay.gd`
**Tests:** `tests/unit/test_path_furniture.gd`

---

## Plain English

Path furniture used to sit at a fixed diagonal angle, and sometimes on a patch of grass under its feet. Now it follows the walk:

- **Benches, signs, bins, ball washers and bird baths** are small fixtures. A fixture on a path tile sits just inside its exposed edge, facing back into the tile.
- **Benches on grass** beside a walk face the walk.
- Furniture is drawn on the same ground layout as the placement ghost, so what you see while placing is what gets built.

The tile you placed the item on is still the anchor for selection, removal and saving. Furniture never moves into a neighbouring tile. It does not change pathfinding, costs or terrain.

Existing decorations realign after path painting, undo and redo, or any bulk refresh.

---

## Algorithm

### 1. Choosing the edge

`PathFurniture.layout()` checks the four cardinal neighbours of the tile. For a path tile, it picks the first exposed edge in this order:

```
north → west → east → south
```

An edge counts as exposed only if the neighbour is land. Water, bunkers, invalid positions and other paths are excluded. The visual is offset toward that edge, and it faces inward. Its footprint stays within the tile.

For furniture off the path, it faces the first adjacent path tile and is not offset.

Plaza and intersection tiles, which are surrounded on every side, keep the tile centre. Large decorations such as fountains and gazebos keep their placement centre.

### 2. Drawing

- **Edge offset:** `23` px for an edge on the horizontal axis, `10` px for an edge on the vertical axis. This keeps the middle of a walk open.
- **Benches** project their length and depth onto the grid, with height drawn upward. A horizontal walk gets a horizontal bench. A vertical walk gets a bench that recedes at half scale. The legs and contact marks share the same foot coordinates. The backrest stays visible when seen edge-on.
- **Foot anchor:** decorations use the visible bottom of their artwork as the foot, which corrects for transparent padding. Fountain and bird-bath animation uses the same correction.
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
| Small fixtures | `path_furniture.gd` `SMALL_FIXTURES` | Bench, signage, waste bin, ball washer, bird bath | Items that get edge placement |

---

## Related

- [Garden Catalog](garden-catalog.md) lists the decorations.
- [Builder Tools](builder-and-review.md) covers the path tile.
- [Course Wildlife](course-wildlife.md) covers the bird baths and fountains that use this placement.
