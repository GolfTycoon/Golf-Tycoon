# World Map & Locations

> The company grows by buying golf course **locations** around the world. Each location is a separate site, and the money, reputation and calendar carry over between them.

**Source:** `scripts/systems/world_locations.gd` (`LOCATIONS`, `SIZE_DATA`, `compute_price()`, `max_unlocked_for_size()`, `layout_order()`, `get_required_parcels()`), `scripts/autoload/world_map_state.gd` (`WorldMap` autoload: owned locations, unlocked land, `reset_world()`, `switch_to_location()`), `scripts/ui/world_map_screen.gd` (`BUY_LABEL`, `BUY_AND_PLAY_LABEL`, `_on_buy_pressed()`, `_on_buy_and_play_pressed()`), `scripts/ui/globe_map.gd` (`build_land_mask()`, `project_point()`, drag, zoom, fly-to, `_frame_seconds()`, `_take_hold()`, `LandStyle.PIXEL`), `shaders/globe_planet.gdshader` (`pixel_block`), `scripts/ui/components/pixel_button_style.gd`, `scripts/ui/components/pixel_icon.gd`, `scripts/systems/generated_course.gd` (`LAYOUT_9`, `LAYOUT_18_BACK`, `AMENITY_SPOTS`), `scripts/ui/start_new_game_screen.gd` (`MONEY_OPTIONS`, `HOLE_OPTIONS`), `scripts/autoload/save_manager.gd` (`SITE_STATE_KEYS`, `SNAPSHOT_COMPANY_KEYS`)
**Tests:** `tests/unit/test_world_map.gd`, `tests/unit/test_world_map_layout.gd`, `tests/unit/test_globe_map.gd`, `tests/unit/ui_and_controls/test_world_map_visual_style.gd`, `tests/unit/ui_and_controls/test_world_map_actions.gd`, `tests/integration/world_map_flow.gd`

---

## Plain English

The World Map is where you pick which course to build next. There are **27 destinations**, from Monterey and San Diego to Scotland, Spain, Jamaica, Dubai, Japan and Australia. Each has its own theme, size, position on the globe and price.

Every destination card has a **Buy & Play** button. One press pays the asking price and starts that course. The selected-site dossier also offers **Buy**, which purchases the land but leaves you on the map so you can keep browsing, beside **Buy & Play**. Sites you already own offer **Play** instead, which switches without charging. The course you leave keeps its progress.

Buying a location gives you a new **site**. A site has its own terrain, buildings, staff, holes and land. Your **company** keeps its money, reputation, calendar and milestones across every site.

Each location's land is partly cleared already. How much is cleared is rolled for each world. More cleared land costs more, so the same destination can be a bargain in one world and expensive in another. **Reset World** rolls the cleared land again for every location you do not own yet. It changes prices, but never makes a site unusable.

The globe in the middle of the screen is an atlas you can spin and zoom. Sprite pins mark each destination, the selected one ringed in gold brackets. Clicking a destination in the list selects it and flies the globe round to centre on it, just as clicking its pin does. A hand on the globe always wins: grabbing it stops the fly-to, so the globe follows the pointer instead of the animation. The whole screen wears the menu's pixel-art look: notched sprite frames, Pixelify Sans type, and the planet itself drawn in chunky cells (`LandStyle.PIXEL`, the shader's `pixel_block` mode) in the game's palette. The smooth-shaded planet remains the default for other callers.

**How you reach it.** The **World Map** button sits in the Club tab's **Maps** column beside **Land Parcels**; the same tab gathers **Review** and **Milestones**. Opening it there freezes the course — the day, the golfers and the daily costs all wait — so a site can be bought, browsed or switched without the club falling behind. **Back** (or Escape) hands the course back exactly as it was: the gameplay UI returns and the day resumes only if it was running before the map opened. Start New Game and Quick Start open the same screen before the company has a course.

---

## Algorithm

### 1. Location sizes

Every location has one of four sizes. Parcels are 20 × 20 tiles on the standard 6 × 6 land grid, so the parcel count is what really sets the size.

| Size | Parcels | Hole capacity | Base price |
| --- | --- | --- | --- |
| Small | 9 | 9 | $15,000 |
| Medium | 12 | 12 | $24,000 |
| Large | 16 | 16 | $36,000 |
| Championship | 20 | 18 | $52,000 |

### 2. Asking price

```
price = (size base price + unlocked_parcels × $2,200)
        × theme land multiplier
        × location prestige

rounded to the nearest $100
```

- **Theme land multiplier** comes from `CourseTheme`. Resort and City land is dearer, and Links and Marshland are cheaper.
- **Prestige** is a per-destination factor from 0.95 to 1.30. Famous destinations cost more.

`get_price_for_land(id, unlocked)` gives the price for any number of unlocked parcels, which is how the land purchase screen shows the cost of each extra parcel.

### 3. Land unlocked at the start

```
wanted          = random between min(4, total) and max_unlocked_for_size(size)
max_unlocked    = clamp(round(parcels × 0.75), 4, parcels)
```

So a Small site starts with 4 to 7 parcels unlocked, and a Championship site with 4 to 15. `layout_order()` turns the count into a compact block, since parcels are ordered by distance from the centre of the grid with a random tie-break. More land is always a tighter, usable cluster rather than scattered islands.

### 4. The first course always fits

The unlocked block always contains the parcels the biggest requested course needs.

- Up to 9 generated holes: the central 2 × 2 block, parcels `(2,2)` to `(3,3)`.
- 18 generated holes: the 3 × 3 block, parcels `(1,1)` to `(3,3)`. This contains every offset in the 18-hole layout.

`WorldLocations.get_required_parcels(holes)` returns this block. `layout_order()` guarantees it is included. Because `Reset World` only changes prices and unlocked parcels, the land a site lays down after purchase is always buildable.

### 5. The globe

The globe is drawn in two layers. Splitting the drawing keeps it smooth and cheap.

| Layer | What it draws | When it redraws |
| --- | --- | --- |
| Planet (`globe_planet.gdshader` on a `ColorRect`) | The whole sphere: ocean, land, polar ice, a sun with a day and night terminator, the graticule and the atmosphere halo | When the view moves (drag, flick, zoom, centre, resize) |
| Markers (`Control`) | One pin per destination, plus the selected and hovered labels | When the pins change (hover, selection, buying, list refresh) |

**Land mask.** The globe uses the Natural Earth 1:50m land dataset, bundled as `data/world_land_polygons.json` and simplified to a 0.04° tolerance for display. A scanline rasterises those rings once into a 2048 × 1024 equirectangular coverage mask (`build_land_mask()`), with soft coverage at the coast. The mask is cached as an `ImageTexture` and shared by every `GlobeMap`. Coastline edges are bucketed only into rows they cross, so the more detailed geometry stays fast to bake.

**Shading.** The shader inverts the orthographic projection to find the longitude and latitude under each pixel. This is the exact inverse of `GlobeMap.project_point()`, which places the pins, so the land and the pins always line up. The sphere depends only on four uniforms: view size, centre longitude, centre latitude and radius scale. Spinning the globe therefore costs four uniform writes and one draw call, with no per-frame CPU projection.

**Hand feel.** A drag tracks the pointer one-to-one. Letting go mid-drag keeps the spin, which decays at `SPIN_DECAY` per second up to `MAX_SPIN_DEG_PER_SEC`. Zooming eases toward its target. `look_at_location()` flies the shortest way round, so Japan from Hawaii crosses the Pacific rather than the whole of Asia. Taking hold of the globe cancels a fly-to still in flight (and any coasting flick), so a drag always wins over the animation instead of being written over by it. The globe only updates while an animation or a flick is running, so an idle globe costs nothing.

**Its own clock.** The globe animates on wall-clock time (`GlobeMap._frame_seconds()`), not the simulation's. That matters for the Club tab: it freezes the course behind the map, and a frozen simulation runs on `Engine.time_scale` 0 — every frame it hands out is worth no time at all, which would strand the fly-to mid-flight and let it write the same frozen centre back over every frame of a drag. Measuring real time keeps the drag, the flick, the zoom and the fly-to identical whether or not the course behind the map is running.

**Fallback.** `GlobeMap.LandStyle.DOTS` samples the same detailed land data into a lightweight dotted rendering, without a `ShaderMaterial`. The planet style is the default.

**Checking the look without a GPU.** `tests/harness/globe_preview.gd` renders the polygon mask, the baked mask and the dots fallback to PNG files. `tests/harness/planet_preview.gd` is a CPU port of the shader that renders the default view, the pole and the Pacific into `tmp_preview/`. It is a visual check only, not a replacement for compiling the shader.

### 6. Buy & Play

Each unowned location's directory card offers **Buy & Play** (`WorldMapScreen.BUY_AND_PLAY_LABEL`). The selected-site dossier offers **Buy** (`BUY_LABEL`) beside **Buy & Play**. Buy calls `WorldMap.buy_location()` and stays on the map (`_on_buy_pressed()`). Buy & Play then emits `play_location_requested` so the company starts that course (`main.gd` `_on_world_map_play_location()`). If the company cannot afford the site both buttons are disabled; `buy_location()` also refuses and never emits play. Owned sites hide Buy and offer **Play**; the course already being played shows **Playing**.

### 7. Generated first course

What a new site starts with depends on **Generated Holes** on the Start New Game screen. Quick Start uses 3 generated holes and buys a random affordable location (`WorldMap.pick_random_affordable_location()`), so it starts playing at once.

### The guided tutorial

The **Guided tutorial** switch on Start New Game is saved with the company (`WorldMap.tutorial_enabled`, the `tutorial` key of the world state). It is on by default until the tutorial has been completed (`WorldMap.default_tutorial_enabled()`, which reads `TutorialSystem.is_tutorial_completed()`). When a new game starts (`main.gd`, `_on_new_game_started()`), the tutorial runs only if all of these hold: the game was not a Quick Start or a prebuilt package, the course has no generated holes, and the switch is on. Starting the tutorial spends the choice (`tutorial_enabled` goes back to `false`), so every save made after that records it as used. Saves from before the switch existed keep the tutorial they would have had.

| Holes | Layout | Par |
| --- | --- | --- |
| 0 | None: a bare plot | — |
| 3 | First 3 holes of `LAYOUT_9` | 12 |
| 6 | First 6 holes of `LAYOUT_9` | 24 |
| 9 | `LAYOUT_9` | 36 |
| 18 | `LAYOUT_9` and `LAYOUT_18_BACK` | 72 |

The back nine is a counter-clockwise loop around the front nine. All its offsets stay within ±27 tiles of the anchor, so it fits the 3 × 3 block. `GeneratedCourse.get_anchor()` returns the tile the layout is built around: `(63, 63)` for up to 9 holes and `(53, 53)` for 18. The camera focuses on that tile when the site loads.

The generator then places the starter amenities (clubhouse, pro shop and a food stop — a Snack Bar, or a Pub on a links course) into the pocket beside the first fairway. Any spot that would overlap a play surface or a building is skipped, and a facility the site's theme does not allow is never placed.

### 8. Company and site state

| Company-wide | Per site |
| --- | --- |
| Money, unlimited flag | Terrain and elevation |
| Reputation, milestones, analytics | Entities, buildings and staff |
| Calendar (day and date) | Holes and land parcels |
| World map: owned locations, unlocked land, active location | Course statistics and records |

`SaveManager.build_location_snapshot()` removes the `SNAPSHOT_COMPANY_KEYS` and keeps only the `SITE_STATE_KEYS`. `switch_to_location()` puts the company state back afterwards, so switching sites never resets the business. Saves use `SAVE_VERSION` 5.

### 9. Reset World

`WorldMap.reset_world()` seeds a new random generator. It keeps every location you already own, since you paid for that land. It re-rolls the cleared land and price for all other locations, then emits `world_reset`. It never changes your money, the active site or its saved state.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Land value per parcel | `world_locations.gd` `LAND_VALUE_PER_PARCEL` | `$2,200` | Price added per cleared parcel |
| Minimum unlocked parcels | `world_locations.gd` `MIN_UNLOCKED_PARCELS` | `4` | Smallest starting block |
| Championship parcels | `world_locations.gd` `CHAMPIONSHIP_PARCELS` | `9` | Parcels reserved for an 18-hole layout |
| Size base prices | `world_locations.gd` `SIZE_DATA` | $15K to $52K | Base cost by size |
| Prestige | `world_locations.gd` `LOCATIONS` | 0.95 to 1.30 | Premium for each destination |
| Land multiplier | `course_theme.gd` `land_cost_multiplier` | Per theme | Theme price factor |
| Cleared-land ceiling | `world_locations.gd` `max_unlocked_for_size()` | 75% of parcels | Largest starting block |
| Land mask resolution | `globe_map.gd` `MASK_WIDTH`, `MASK_HEIGHT` | `2048` × `1024` | Coastline detail, baked once per run |
| Dot spacing (fallback) | `globe_map.gd` `LAND_STEP_DEG` | `3.0`° | Spacing of the land dots in the fallback |
| Zoom range | `globe_map.gd` `MIN_RADIUS_SCALE`, `MAX_RADIUS_SCALE` | `0.7` to `1.6` | How far the globe zooms |
| Flick spin | `globe_map.gd` `MAX_SPIN_DEG_PER_SEC`, `SPIN_DECAY` | `320`°/s, `0.02` | Speed cap and how quickly a flick settles |
| Fly-to and zoom easing | `globe_map.gd` `CENTER_DURATION`, `ZOOM_SETTLE_RATE` | `0.5` s, `14` | How quickly the globe moves to a destination (wall-clock seconds: the globe keeps its own clock, see above) |
| Starting money options | `start_new_game_screen.gd` `MONEY_OPTIONS` | $100K, $150K, $200K, Unlimited (`-1`) | Starting money choices |
| Generated hole options | `start_new_game_screen.gd` `HOLE_OPTIONS` | `0`, `3`, `6`, `9`, `18` | Pre-built hole choices |
| Layout anchors | `generated_course.gd` `SMALL_ANCHOR`, `CHAMPIONSHIP_ANCHOR` | `(63, 63)`, `(53, 53)` | Where a generated layout sits |
| Back-nine offsets | `generated_course.gd` `LAYOUT_18_BACK` | 9 offsets | Must stay within ±27 tiles of the anchor |
| Globe colours and lighting | `globe_planet.gdshader` uniforms | See the shader | Sun, terminator, relief, ice, graticule and halo |

---

## Related

- [Premium Land](premium-land.md) covers parcel tiers and prebuilt packages inside a site.
- [Economy](economy.md) covers the money the price is paid from.
- [Course Surface](../course-design/course-surface.md) covers the other shader-driven surface, and the theme palette.
- [Terrain Types](../course-design/terrain-types.md) covers what the generator paints.
