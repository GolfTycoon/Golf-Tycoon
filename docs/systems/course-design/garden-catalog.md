# Improvement & Facility Catalog

> The catalog of improvements (5) and buildings (16) that the player can place, what each one does, and how placement is validated.

**Source:** `data/decorations.json` (5 entries, root key `decorations`), `data/buildings.json` (16 entries, root key `buildings`), `scripts/entities/decoration.gd` (sprite anchoring and procedural fallback), `scripts/entities/path_furniture.gd` (bench and ball washer artwork), `scripts/entities/building.gd`, `scripts/entities/course_architecture.gd`, `scripts/ui/components/decoration_tile_art.gd`, `scripts/ui/components/terrain_tile_button.gd`, `scripts/terrain/walking_path_overlay.gd`

---

## Plain English

The catalog is data-driven. Each item is a JSON entry, so adding a new item needs no new code path and older saves need no migration.

- **Improvements** are the path-side and ornamental items on the Improvements tab: the **Path**, the **Ball Washer**, the **Park Bench**, the **Fountain**, the **Golfer Statue** and the **Sundial**. Benches and ball washers are drawn with `PathFurniture`; the fountain, statue and sundial use their pixel-art sprites, with a simple procedural drawing as a fallback.
- **Facilities** are the buildings on the Buildings tab: the **putting green, snack bar, pub, pro shop, driving range, cart garage, tennis court, stable, spa, swim club, resort hotel, airstrip, castle, casino** and **theme park**. Each has a construction cost, a daily operating cost, and an effect. A facility that serves golfers earns revenue only when a golfer uses it during a normal interaction check. Which facilities a course is offered depends on its location theme; see [Buildings](../../data-reference.md#buildings).

The **Improvements** tab shows the improvements as a honeycomb of isometric tiles. Pressing a tile starts placement straight away. The hover tooltip shows the price, upkeep and unlock status. The walking path is listed on this honeycomb too, as its first tile. It previews as a dirt ribbon over rough turf, so it reads like a continuous trail.

Placement is validated the same way for the preview and the click. Every footprint tile must be owned, on compatible ground, and clear of other buildings and improvements. Woodland counts as ground rather than as an obstacle. Ghosts tint red when a placement is invalid. Failure messages say what is in the way. Buildings may sit on paths.

Placing, bulldozing, undoing, aesthetics scoring and saving all use the same entity machinery as the rest of the course. A save from before an improvement left the catalog simply drops it when it loads (see [Save & Load](../../save-and-load.md)).

---

## Algorithm

### 1. Catalog load

`data/decorations.json` and `data/buildings.json` are read at startup. Each building entry defines its size, build cost and operating cost. A facility also defines `needs_service`, which maps it to the existing golfer needs rules.

### 2. Placement validation

A single function checks the footprint. The preview and the placement click both call it, so they cannot disagree.

```
for each tile in footprint:
    must be owned land
    must be compatible ground (fairway, rough, flower bed, path, woodland, etc.)
    must not hold another building or improvement
result: valid, or the first obstruction as a message
```

### 3. Placement and undo

A placed item is recorded through `UndoManager.record_entity_placement()`, which stores the item's type, position, subtype and cost, so undo can reverse the placement.

### 4. Golfer service

A golfer uses a facility when the needs check selects it. Revenue is paid only in that interaction. A tired golfer may also rest on a park bench, which uses the `bench` need.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Improvement catalog | `data/decorations.json` | 5 entries | Improvements the player can place |
| Building catalog | `data/buildings.json` | 16 entries | Buildings and facilities |
| Facility cost and operating cost | `data/buildings.json` per entry | Per entry | Cost to build and daily operating cost |
| Facility golfer service | `data/buildings.json` `needs_service` | Per entry | Which golfer need the facility restores |
| Bench and ball washer artwork | `scripts/entities/path_furniture.gd` | Code | Look of the two drawn improvements |
| Path tile preview | `scripts/terrain/walking_path_overlay.gd` | Code | Colours and widths of the dirt ribbon |

---

## Related

- [Clubhouse](clubhouse.md) covers the one required building that is never sold.
- [Path Furniture](path-furniture.md) covers benches, ball washers and other path-side items.
- [Isometric Buildings](isometric-buildings.md) covers how buildings are drawn.
- [Golfer Needs](../golfers/golfer-needs.md) covers how facilities restore needs.
