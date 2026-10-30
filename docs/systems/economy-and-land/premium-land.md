# Premium Land & Prebuilt Courses

> Expanding the course means buying land parcels on a 6×6 map. Premium and Elite parcels cost more and come with terrain already built. Prebuilt packages lay out playable holes on land you already own.

**Source:** `scripts/managers/land_manager.gd` (`BASE_PARCEL_COST`, `COST_ESCALATION`, `TIER_COST_MULTIPLIER`, `ELITE_REPUTATION_REQUIREMENT`, tier layout, purchase rules), `scripts/terrain/premium_feature_generator.gd` (feature generation), `scripts/systems/prebuilt_course_generator.gd` (`PACKAGE_COSTS`, `PACKAGE_NAMES`, package layouts), `scripts/ui/components/course_map_land_panel.gd` (the Course Map's Land mode), `scripts/terrain/overlays/land_boundary_overlay.gd` (the property lines and the unowned tint)

**Tests:** `tests/unit/course_design/test_land_boundary_overlay.gd`, `tests/unit/economy_and_land/test_land_manager.gd`, `tests/unit/course_design/test_camera_redraw_cadence.gd`

---

## Plain English

You expand by buying parcels that touch land you already own. Parcels come in three tiers:

- **Standard:** blank grass at base price.
- **Premium:** pre-built terrain features, such as a pond, trees, elevation or rough. It costs 2.5× the base.
- **Elite:** more dramatic features and denser vegetation. It costs 5× the base, and you need **50 reputation** to buy one.

The four centre parcels, where you start, are always Standard. Each theme decides where the Premium and Elite parcels sit, and the layout is the same every time for that theme. The City theme has no Elite parcels.

You can also buy **prebuilt course packages**. These lay out playable holes on land you already own. They range from a 3-hole Starter to a full 18-hole Championship. Money you earned in earlier games carries over.

---

## Algorithm

### 1. Parcel cost

```
base_cost   = 5,000 × 1.3 ^ (number of parcels bought so far)
parcel_cost = base_cost × tier multiplier

tier multiplier:  Standard 1.0×   Premium 2.5×   Elite 5.0×
```

The escalation counts every parcel you have bought, whatever its tier.

### 2. Tier layout

The tier of each parcel is fixed by its theme. Typically there are 4 to 6 Premium parcels, mostly at the edges and corners, and 1 or 2 Elite parcels at high-value spots. The City theme has none.

### 3. Feature generation

When you buy a Premium or Elite parcel, terrain is generated inside its 20 × 20 tile area. Each theme picks which features to use. Elite gets more of each feature.

| Feature | Premium | Elite |
| --- | --- | --- |
| Pond radius | 3 to 5 tiles | 4 to 7 tiles |
| Trees | 4 to 8 | 8 to 16 |
| Elevation range | ±2 | ±4 |
| Rough patches | 1 to 2 | 2 to 4 |

Generation is seeded from the parcel's position. The same parcel always generates the same features. Each parcel is generated only once, even if it is sold and bought again.

### 4. Prebuilt packages

Packages are bought before a new game. Each lays out finished holes with fairways, greens, bunkers and water on your owned land. You can change anything afterward.

| Package | Holes | Par | Cost |
| --- | --- | --- | --- |
| Starter | 3 | 12 | $25,000 |
| Executive 9 | 9 (all par 3) | 27 | $75,000 |
| Standard 9 | 9 (mixed) | 36 | $100,000 |
| Championship 18 | 18 (mixed) | 72 | $200,000 |

The Championship needs at least 8 parcels. The old main-menu package picker has been replaced by the World Map and Start New Game flow. See [World Map](world-map.md).

### 5. Drawing the boundary

`LandBoundaryOverlay` shows where the plot ends: one gold property line per edge between owned and unowned land (cached, rebuilt on a purchase), and a subtle dark tint over the land the company does not own.

The tint is drawn only for the camera's visible tile window (`TerrainGrid.get_visible_tile_range()`), walked a parcel row at a time — ownership is per parcel, so a row asks the land manager once per parcel it crosses instead of once per tile — and emitted as **one triangle batch** rather than one `draw_colored_polygon()` per tile. A camera-driven repaint therefore touches the tiles on screen, not all 16,384 of the map, and records one renderer call for them. Each tile's projected diamond is shelved and reused until the ground is sculpted (`vertex_elevation_changed`, or `invalidate_ground()` after a bulk load) or the course is turned (`EventBus.view_rotated`).

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Base parcel cost | `land_manager.gd` `BASE_PARCEL_COST` | $5,000 | Price of the first expansion parcel |
| Cost escalation | `land_manager.gd` `COST_ESCALATION` | `1.3` | Growth per parcel bought |
| Tier multipliers | `land_manager.gd` `TIER_COST_MULTIPLIER` | 1.0 / 2.5 / 5.0 | Price of each tier |
| Elite reputation gate | `land_manager.gd` `ELITE_REPUTATION_REQUIREMENT` | 50 | Reputation needed for Elite |
| Package prices | `prebuilt_course_generator.gd` `PACKAGE_COSTS` | $25K / $75K / $100K / $200K | Cost of each package |
| Pond size | `premium_feature_generator.gd` | 3–5 / 4–7 tiles | Water feature size |
| Tree count | `premium_feature_generator.gd` | 4–8 / 8–16 | Vegetation density |
| Elevation range | `premium_feature_generator.gd` | ±2 / ±4 | Terrain drama |
| Rough patches | `premium_feature_generator.gd` | 1–2 / 2–4 | Rough count |

---

## Related

- [Course Map](../course-design/course-map.md) is where a parcel is bought from the map itself (Land mode).
- [Economy](economy.md) covers how land spending fits into your budget.
- [World Map](world-map.md) covers where the parcels are.
- [Course Themes](../course-design/course-themes.md) covers the theme that sets the tier layout.
