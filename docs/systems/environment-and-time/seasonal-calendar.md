# Seasonal Calendar & Theme Modifiers

> Seasons follow the calendar: spring is March to May, summer June to August, fall September to November, and winter December to February. Each course theme has its own spawn, maintenance, weather and prestige pattern across the year.

**Source:** `scripts/systems/season_system.gd` (`get_season_for_month()`, `get_season()`, `get_blended_*()`, `THEME_SPAWN_MODIFIERS`, `THEME_MAINTENANCE_MODIFIERS`, `THEME_TOURNAMENT_PRESTIGE`, `THEME_WEATHER_MODIFIERS`, `get_weather_weights()`, `get_fee_tolerance()`), `scripts/systems/seasonal_events.gd` (`get_all_events()`, `get_active_event()`, `get_upcoming_events()`)
**Tests:** `tests/unit/test_season_system.gd`

---

## Plain English

Seasons follow calendar months:

| Season | Months | Days |
| --- | --- | --- |
| Spring | March to May | About 92 |
| Summer | June to August | About 92 |
| Fall | September to November | About 91 |
| Winter | December to February | About 90 to 91 |

Each season changes several things at once: how many golfers arrive, upkeep costs, how much golfers will pay, tournament prestige and the weather.

**Themes change the pattern.** The same season can be a boom for one course and quiet for another. A Desert course peaks in winter. A Mountain course peaks in summer. A Woodland course peaks in summer and fall. A Tropical course is quiet in summer and busy in winter. See [Course Themes](../course-design/course-themes.md).

**Seasonal events.** Each season has two special events. They change revenue, spawn rates and reputation for a few days. See seasonal events (section 8 below).

**Smooth transitions.** Modifiers blend into the next season on the last day of a season and the first day of the next. The blend is 34%, so the change does not jump overnight.

**Turning it off.** Seasons are an option on the Start New Game screen. With seasons off the calendar still ticks and every modifier stays neutral, so the course plays as one year-round season. The Season row then leaves the HUD status column (`scripts/ui/hud_status_column.gd`, `_update_feature_rows()`) instead of reading "Year-round".

---

## Algorithm

### 1. Season and day lookup

```
season       = season_for_month(month of the current game date)
day_in_season = days since the first day of this season + 1
season_length = number of days in the season (about 90)
```

Winter that starts in December counts from 1 December of the previous calendar year. That is why its day index can be negative.

### 2. Transition blend

```
TRANSITION_BLEND_FACTOR = 0.34

last day of a season:   value = lerp(current, next season's value, 0.34)
first day of a season:  value = lerp(current, previous season's value, 0.34)
otherwise:              value = current
```

### 3. Spawn modifiers (theme × season)

Season order is Spring, Summer, Fall, Winter.

| Theme | Spring | Summer | Fall | Winter | Peak |
| --- | --- | --- | --- | --- | --- |
| Parkland | 0.9 | 1.4 | 0.8 | 0.3 | Summer |
| Desert | 0.6 | 0.3 | 0.9 | 1.4 | Winter |
| Links | 0.8 | 1.3 | 0.9 | 0.4 | Summer |
| Mountain | 1.0 | 1.5 | 0.7 | 0.1 | Summer |
| City | 0.9 | 1.2 | 1.0 | 0.6 | Summer |
| Resort | 1.0 | 1.3 | 0.8 | 1.2 | Summer and winter |
| Heathland | 0.8 | 1.3 | 0.9 | 0.3 | Summer |
| Woodland | 1.0 | 1.4 | 1.1 | 0.2 | Summer |
| Tropical | 1.1 | 0.8 | 1.2 | 1.3 | Winter |
| Marshland | 0.7 | 0.9 | 0.8 | 0.4 | Summer |

### 4. Maintenance modifiers (theme × season)

| Theme | Spring | Summer | Fall | Winter |
| --- | --- | --- | --- | --- |
| Parkland | 1.1 | 1.4 | 0.7 | 1.1 |
| Desert | 0.8 | 0.6 | 0.8 | 1.0 |
| Links | 1.0 | 1.1 | 0.8 | 1.3 |
| Mountain | 1.2 | 1.3 | 0.8 | 1.5 |
| City | 1.0 | 1.2 | 0.9 | 1.0 |
| Resort | 1.1 | 1.3 | 0.9 | 1.2 |
| Heathland | 0.9 | 1.1 | 0.8 | 1.0 |
| Woodland | 1.0 | 1.2 | 1.0 | 0.9 |
| Tropical | 1.3 | 1.5 | 1.1 | 0.9 |
| Marshland | 1.2 | 1.4 | 0.9 | 1.0 |

### 5. Fee tolerance

Fee tolerance is the seasonal change in what golfers think a fair price is. It is calculated from the spawn modifier.

```
fee_tolerance = clamp(0.5 + spawn_modifier × 0.55, 0.7, 1.3)
```

- At 1.3, golfers accept prices up to 30% higher than normal.
- At 0.7, golfers expect prices 30% lower.

The value rating multiplies its fair price by this figure. See [Course Rating](../ratings-and-reputation/course-rating.md).

### 6. Tournament prestige (theme × season)

Hosting a tournament earns more reputation in a theme's prestige season. Multipliers apply to reputation gained.

| Theme | Spring | Summer | Fall | Winter |
| --- | --- | --- | --- | --- |
| Parkland | 1.0 | 1.0 | 1.2 | 0.5 |
| Desert | 0.8 | 0.5 | 1.2 | 1.0 |
| Links | 0.8 | 1.2 | 1.0 | 0.5 |
| Mountain | 1.0 | 1.2 | 0.8 | 0.5 |
| City | 1.0 | 1.0 | 1.2 | 0.8 |
| Resort | 0.8 | 1.0 | 1.0 | 1.2 |
| Heathland | 0.8 | 1.2 | 1.0 | 0.5 |
| Woodland | 1.0 | 1.0 | 1.2 | 0.5 |
| Tropical | 0.8 | 0.5 | 1.0 | 1.2 |
| Marshland | 0.8 | 0.8 | 1.2 | 0.5 |

### 7. Weather modifiers by theme

| Theme | Wind | Rain |
| --- | --- | --- |
| Desert | 0.8× | 0.3× |
| Links | 1.5× | 1.2× |
| Mountain | 1.2× | 1.3× |
| Tropical | 0.7× | 1.8× |
| Marshland | 0.9× | 1.4× |
| Others | 1.0× | 1.0× |

The rain multiplier shifts the seasonal weather weights toward more rain or less rain. See [Weather System](weather-system.md).

### 8. Seasonal events

Each event starts on a set day within its season (day 1 is the first day of the season) and lasts a set number of days. While it is running, it multiplies revenue and spawns and adds reputation. `get_upcoming_events()` lists events up to 14 days ahead.

| Event | Season | Starts on day | Days | Revenue | Spawns | Reputation |
| --- | --- | --- | --- | --- | --- | --- |
| Spring Opening Week | Spring | 1 | 7 | 1.5× | 1.5× | +2 |
| Charity Scramble | Spring | 45 | 4 | 1.2× | 1.3× | +3 |
| Peak Season | Summer | 1 | 10 | 1.5× | 1.0× | 0 |
| Junior Golf Week | Summer | 60 | 7 | 0.8× | 1.8× | +2 |
| Fall Classic Invitational | Fall | 15 | 5 | 1.3× | 1.4× | +5 |
| Twilight Golf Special | Fall | 75 | 5 | 0.9× | 1.6× | +1 |
| Winter Open | Winter | 30 | 6 | 1.0× | 0.8× | +1 |
| Maintenance Fortnight | Winter | 60 | 8 | 0.5× | 0.3× | 0 |

### 9. Integration points

| System | Function | Used by |
| --- | --- | --- |
| Golfer spawning | `get_spawn_modifier(season, theme)` | `golfer_manager.gd` |
| Maintenance costs | `get_maintenance_modifier(season, theme)` | `game_manager.gd` |
| Value rating | `get_fee_tolerance(day, theme)` | `course_rating_system.gd` |
| Tournament reputation | `get_tournament_prestige(day, theme)` | `tournament_manager.gd` |
| Weather | `get_blended_weather_weights(day, theme)` | `weather_system.gd` |

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Spawn modifier tables | `season_system.gd` `THEME_SPAWN_MODIFIERS` | 0.1 to 1.5 | More or fewer golfers in a season |
| Maintenance tables | `season_system.gd` `THEME_MAINTENANCE_MODIFIERS` | 0.6 to 1.5 | Upkeep by season |
| Fee tolerance | `season_system.gd` `get_fee_tolerance()` | 0.7 to 1.3 | Seasonal pricing pressure |
| Prestige tables | `season_system.gd` `THEME_TOURNAMENT_PRESTIGE` | 0.5 to 1.2 | Reputation from tournaments |
| Weather modifiers | `season_system.gd` `THEME_WEATHER_MODIFIERS` | Wind and rain per theme | How weather differs by theme |
| Blend factor | `season_system.gd` `TRANSITION_BLEND_FACTOR` | `0.34` | Size of the change at a season boundary |
| Event list | `seasonal_events.gd` `get_all_events()` | 8 events | Days, durations and effects |
| Event lookahead | `seasonal_events.gd` `get_upcoming_events()` | 14 days | How far ahead events are listed |

---

## Related

- [Game Calendar](game-calendar.md) covers the dates and day length.
- [Weather System](weather-system.md) uses the seasonal weather weights.
- [Economy](../economy-and-land/economy.md) uses the spawn, maintenance and fee modifiers.
- [Course Themes](../course-design/course-themes.md) lists the ten themes.
