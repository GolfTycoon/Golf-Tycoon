# Course Themes

> Ten course environments, each with its own terrain palette, vegetation, wind strength, shot distance, maintenance cost and green-fee baseline.

**Source:** `scripts/systems/course_theme.gd` (`enum Type`, `get_gameplay_modifiers()`, `get_terrain_colors()`, `get_accent_color()`, `get_description()`, `from_string()`), `scripts/ui/start_new_game_screen.gd`, `scripts/ui/main_menu.gd`, `scripts/autoload/game_manager.gd` (`new_game()`, `current_theme`), `scripts/autoload/save_manager.gd`

---

## Plain English

A theme sets the look and some of the rules for a course. The ten themes are:

| Theme | Character |
| --- | --- |
| **Parkland** | Classic lush grass and deciduous trees. Balanced gameplay. |
| **Desert** | Sandy tan ground, oasis-green fairways, cacti and rock outcrops. Dry air adds a little distance. |
| **Links** | Coastal Scottish style with golden fescue, pot bunkers and a much stronger wind. |
| **Mountain** | Alpine greens and pine forests. Thinner air adds 5% to shot distance. |
| **City** | Flat, urban, with chain-link out-of-bounds. Cheaper maintenance. |
| **Resort** | Tropical colours, turquoise water, white sand bunkers. Premium green fees. |
| **Heathland** | Inland sandy soil with heather, gorse and scattered pines. Pot bunkers. |
| **Woodland** | Dense tree-lined corridors and tight fairways. Rewards accuracy. |
| **Tropical** | Palms, volcanic island, ocean carries and trade winds. |
| **Marshland** | Coastal wetlands, marsh grass and water everywhere. |

**Choosing a theme.** You pick a theme with the location you buy on the World Map. The Start New Game screen collects the company name, difficulty, starting money, generated holes and the Weather, Wind and Seasons features. The first course on the World Map inherits the location's theme. The main menu links straight to the World Map, and to the setup screen for a new game.

**What a theme changes.** Terrain colours and vegetation, wind strength, shot distance, maintenance cost and the green-fee baseline. The fee baseline is a starting point, and you still set the actual fee.

---

## Algorithm

### 1. Theme data

`CourseTheme` is a static class. Each theme has:

- `get_terrain_colors()`: the palette for every terrain type.
- `get_gameplay_modifiers()`: wind, distance, maintenance and fee values.
- `get_accent_color()` and `get_description()`: display helpers.

### 2. Gameplay modifiers

| Theme | Wind strength | Distance | Maintenance cost | Fee baseline |
| --- | --- | --- | --- | --- |
| Parkland | 1.0 | 1.00 | 1.00 | $10 |
| Desert | 0.8 | 1.02 | 0.70 | $10 |
| Links | 1.8 | 0.98 | 0.85 | $14 |
| Mountain | 1.2 | 1.05 | 1.15 | $12 |
| City | 0.7 | 1.00 | 0.60 | $10 |
| Resort | 1.0 | 1.00 | 1.40 | $18 |
| Heathland | 1.2 | 1.01 | 0.75 | $12 |
| Woodland | 0.6 | 0.98 | 0.90 | $12 |
| Tropical | 1.4 | 1.02 | 1.20 | $16 |
| Marshland | 1.3 | 1.00 | 1.10 | $14 |

- **Wind strength** multiplies the base wind. Links at 1.8 is almost twice Parkland. Woodland at 0.6 blocks most of the wind.
- **Distance** multiplies shot distance.
- **Maintenance cost** multiplies the daily maintenance cost.
- **Fee baseline** is the starting green fee.

### 3. Applying a theme

1. `GameManager.new_game()` sets `current_theme` and updates the terrain palette.
2. `EventBus.theme_changed` is emitted.
3. `CourseSurface` and any theme-aware UI refresh from the signal.

### 4. Saving

The theme is saved as a string and restored with `CourseTheme.from_string()`. On load, the theme colours are re-applied and `theme_changed` is emitted again.

---

## Tuning Levers

| Lever | Location | Effect |
| --- | --- | --- |
| Wind strength | `course_theme.gd` `wind_base_strength` | How windy a theme is |
| Distance modifier | `course_theme.gd` `distance_modifier` | Shot distance change for the theme |
| Maintenance multiplier | `course_theme.gd` `maintenance_cost_multiplier` | Daily upkeep for landscaping |
| Fee baseline | `course_theme.gd` `green_fee_baseline` | Starting green fee |
| Terrain palette | `course_theme.gd` `get_terrain_colors()` | Colours for each terrain type |

---

## Related

- [Terrain Types](terrain-types.md) lists the terrain each theme paints.
- [Course Surface](course-surface.md) draws the theme palette.
- [Seasonal Calendar](../environment-and-time/seasonal-calendar.md) adds the seasonal modifiers for each theme.
- [World Map](../economy-and-land/world-map.md) assigns a theme to each location.
