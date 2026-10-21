# Weather System

> **Modding:** Weather simulation and visuals now ship in `mods/golf_tycoon.weather/`.
The core `WeatherSystem` remains the stable, neutral base. Disable the mod
from the main menu’s Mods screen for permanent sun. See [Modding](../../modding.md).

> Weather is chosen each day from seasonal odds, then moves in multi-day spells through a set of states. Rain slows golfer arrivals and lowers shot accuracy, and each state tints the sky.

**Source:** `scripts/systems/weather_system.gd` (`generate_daily_weather()`, `update_weather_daily()`, `_maybe_change_weather()`, `_get_next_weather()`, `get_spawn_rate_modifier()`, `get_accuracy_modifier()`, `get_sky_tint()`, `is_raining()`), `scripts/systems/season_system.gd` (`get_weather_weights()`, `get_blended_weather_weights()`, `THEME_WEATHER_MODIFIERS`)

---

## Plain English

Weather changes once a day and stays put for a spell of several days. When a spell ends, the weather may move on to a related state. A sunny day can only become partly cloudy. A cloudy day can clear or turn to light rain. Heavy rain usually eases back to rain. Weather never skips a step, so a sunny day never turns straight into a downpour.

Weather affects three things:

1. **Golfer arrivals.** Rain keeps some golfers at home. Heavy rain cuts arrivals to 30% of normal.
2. **Shot accuracy.** Rain makes shots less precise. Light rain costs 5% accuracy and heavy rain costs 15%.
3. **Look and feel.** Each state tints the sky and dims the light a little. Weather also affects butterflies and ducks. See [Course Wildlife](../course-design/course-wildlife.md).

The weather you see is blended over time. Intensity eases from one state to the next instead of jumping.

**Turning it off.** Weather is an option on the Start New Game screen. With weather off the course stays clear all game, and the Weather row leaves the HUD status column (`scripts/ui/hud_status_column.gd`, `_update_feature_rows()`) rather than sitting there reading "Off".

---

## Algorithm

### 1. States

| State | Intensity | Golfer arrivals | Shot accuracy | Sky tint (R, G, B, alpha) |
| --- | --- | --- | --- | --- |
| Sunny | 0.00 | 100% | 100% | (1.00, 1.00, 1.00, 0.00) |
| Partly cloudy | 0.10 | 100% | 100% | (0.95, 0.95, 0.95, 0.10) |
| Cloudy | 0.25 | 90% | 100% | (0.85, 0.85, 0.90, 0.20) |
| Light rain | 0.40 | 70% | 95% | (0.75, 0.78, 0.85, 0.30) |
| Rain | 0.60 | 50% | 90% | (0.65, 0.68, 0.75, 0.35) |
| Heavy rain | 0.85 | 30% | 85% | (0.55, 0.58, 0.65, 0.40) |

### 2. Daily weather

Each game day, the day's weather is chosen with a random roll against cumulative seasonal weights.

```
weights = get_blended_weather_weights(day, theme)
roll    = randf()
state   = first state whose cumulative weight exceeds roll
          (sunny, partly cloudy, cloudy, light rain, rain, heavy rain)
```

The theme's rain multiplier shifts the weights toward more or less rain. The neutral weights are `0.40, 0.70, 0.85, 0.93, 0.98, 1.0`. Each season has its own set, and seasons blend at boundaries.

### 3. Spells and changes

Each state runs for a spell of days.

```
spell length       = random between 4 and 21 days (MIN and MAX_WEATHER_SPELL_DAYS)
when a spell ends:
    with 55% chance  → move to the next state (see section 4)
    otherwise        → extend the spell by 3 to 9 days
```

### 4. State transitions

Each change follows the pattern below. Probabilities sum to 1.

| From | Next state |
| --- | --- |
| Sunny | 70% partly cloudy, 30% stays sunny |
| Partly cloudy | 40% sunny, 40% cloudy, 20% stays partly cloudy |
| Cloudy | 30% partly cloudy, 40% light rain, 30% stays cloudy |
| Light rain | 40% cloudy, 30% rain, 30% stays light rain |
| Rain | 40% light rain, 20% heavy rain, 40% stays rain |
| Heavy rain | 70% rain, 30% stays heavy rain |

### 5. Blending

When the state changes, the game moves toward the new state over time:

```
TRANSITION_SPEED = 0.5 per game day     # about two days for a full change
intensity        = lerp(old intensity, new intensity, progress)
```

The state name changes once the transition is 80% complete. Sky tint and light follow the blended intensity.

### 6. Other effects

- `is_raining()` is true for light rain, rain and heavy rain.
- The weather icon and text on the HUD use the current state.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Spell length | `weather_system.gd` `MIN_WEATHER_SPELL_DAYS`, `MAX_WEATHER_SPELL_DAYS` | 4 to 21 days | Longer spells mean fewer changes |
| Change chance | `weather_system.gd` `_maybe_change_weather()` | 55% | Higher means more changes |
| Extension length | `weather_system.gd` `_maybe_change_weather()` | 3 to 9 days | How long a spell lasts when it continues |
| Transition speed | `weather_system.gd` `TRANSITION_SPEED` | `0.5` per day | Higher means faster visual change |
| Transition table | `weather_system.gd` `_get_next_weather()` | See section 4 | Which weather follows which |
| Seasonal weights | `season_system.gd` `get_weather_weights()` | Per season | How often each state happens |
| Theme rain and wind | `season_system.gd` `THEME_WEATHER_MODIFIERS` | Per theme | How rainy or windy a theme is |
| Arrival modifiers | `weather_system.gd` `get_spawn_rate_modifier()` | 1.0 to 0.3 | How much weather keeps golfers away |
| Accuracy modifiers | `weather_system.gd` `get_accuracy_modifier()` | 1.0 to 0.85 | How much rain hurts shots |
| Sky tints | `weather_system.gd` `get_sky_tint()` | See the table | Colour of each state |

---

## Related

- [Wind System](wind-system.md) works alongside weather.
- [Seasonal Calendar](seasonal-calendar.md) sets the seasonal weights.
- [Shot Accuracy](../golf-play/shot-accuracy.md) explains how accuracy feeds into a shot.
- [Course Wildlife](../course-design/course-wildlife.md) reacts to rain and time of day.
