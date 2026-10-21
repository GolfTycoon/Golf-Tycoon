# Wind System

> **Modding:** Wind simulation now ships in `mods/golf_tycoon.wind/wind_system.gd`.
The core `WindSystem` is the stable, calm base used when the mod is off. See [Modding](../../modding.md).

> Wind has a direction and a speed that change slowly over the days. It pushes shots sideways and changes how far they fly, with most effect on high, long shots.

**Source:** `scripts/systems/wind_system.gd` (`update_wind_daily()`, `get_wind_displacement()`, `get_distance_modifier()`, `get_strength_text()`, `get_direction_text()`, `force_calm()`), `scripts/systems/golf_rules.gd` (`get_club_wind_sensitivity()`), `scripts/systems/shot_ai.gd` (wind compensation)

---

## Plain English

- **Direction and speed.** Wind starts each day with a random direction and a speed from 2 to 20 mph. Most days it changes only a little. Now and then it changes completely.
- **Sideways push.** Crosswind pushes the ball off line. This is the most visible effect, and it makes aiming into the wind a real challenge.
- **Head and tail wind.** A headwind shortens the shot by up to 15% at 30 mph. A tailwind lengthens it by up to 10%. Headwinds hurt more than tailwinds help, as in real golf.
- **Club matters.** Drivers catch the wind fully, while putters are not affected at all. Shots that fly longer are pushed more.
- **Golfers compensate.** Golfers aim into the wind. Better golfers correct for about 80% of it, and beginners for about 20%.

You can turn wind off when you start a new game, on the Start New Game screen. With wind off, the air stays calm all game, and the Wind row leaves the HUD status column (`scripts/ui/hud_status_column.gd`, `_update_feature_rows()`) rather than sitting there reading "Off".

---

## Algorithm

### 1. Daily update

Wind is updated once per game day.

```
if randf() < 0.08:                        # rare full reshuffle
    direction = randf() × TAU             # any direction
    speed     = randf_range(2, 20) mph
else:                                     # usual day-to-day drift
    direction = direction + randf_range(−0.35, 0.35) rad
    speed     = clamp(speed + randf_range(−1.5, 1.5), 0, 30) mph
```

### 2. Wind vector

```
wind = (−sin(direction), cos(direction)) × speed
```

### 3. Splitting wind for a shot

For a shot heading in `shot_direction`:

```
headwind  = wind · shot_direction          # positive is a tailwind
crosswind = wind − shot_direction × headwind
```

### 4. Sideways push

```
distance_factor = distance_tiles / 20      # normalised to a driver shot
wind_factor     = club_sensitivity × distance_factor
displacement    = crosswind × wind_factor × 0.15
```

Longer shots and higher clubs are pushed further sideways.

### 5. Distance modifier

```
if headwind < 0:
    modifier = 1 − |headwind| / 30 × 0.15 × sensitivity    # up to −15% at 30 mph
else:
    modifier = 1 + headwind / 30 × 0.10 × sensitivity     # up to +10% at 30 mph

modifier = clamp(modifier, 0.75, 1.15)
```

At 30 mph with a driver (sensitivity 1.0):

| Wind | Modifier | Effect |
| --- | --- | --- |
| Direct headwind | 0.85 | −15% distance |
| Crosswind | 1.00 | No change (sideways push only) |
| Direct tailwind | 1.10 | +10% distance |

### 6. Club sensitivity

| Club | Sensitivity | Reason |
| --- | --- | --- |
| Driver | 1.00 | High flight, long time in the air |
| Fairway wood | 0.85 | Slightly lower flight |
| Iron | 0.70 | Medium flight |
| Wedge | 0.40 | High but short flight |
| Putter | 0.00 | Rolls along the ground |

### 7. Strength labels

| Speed | Label |
| --- | --- |
| Under 5 mph | Calm |
| 5 to 10 mph | Light |
| 10 to 15 mph | Moderate |
| 15 to 20 mph | Strong |
| 20 mph and up | Very strong |

### 8. Golfer compensation

When the AI aims, it moves the aim point against the wind by a fraction set by skill:

```
compensation = 0.2 + accuracy_skill × 0.6        # 0.2 for a beginner, 0.8 for a pro
aim_point    = target − wind_displacement × compensation
```

See [Shot AI: Target Finding](../golf-play/shot-ai-target-finding.md).

### 9. Compass

Direction is shown as one of eight points: N, NE, E, SE, S, SW, W, NW.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Starting speed range | `wind_system.gd` | 2 to 20 mph | Range of wind on a fresh day |
| Speed cap | `wind_system.gd` | 0 to 30 mph | Strongest possible wind |
| Direction drift | `wind_system.gd` | ±0.35 rad a day | How much direction shifts daily |
| Speed drift | `wind_system.gd` | ±1.5 mph a day | How gusty the wind is |
| Reshuffle chance | `wind_system.gd` `DAILY_RESHUFFLE_CHANCE` | 8% | How often wind changes completely |
| Crosswind multiplier | `wind_system.gd` | 0.15 | Strength of the sideways push |
| Distance normalisation | `wind_system.gd` | 20 tiles | Shorter means more effect on short shots |
| Headwind effect | `wind_system.gd` | Up to −15% at 30 mph | Distance lost into the wind |
| Tailwind effect | `wind_system.gd` | Up to +10% at 30 mph | Distance gained downwind |
| Distance clamp | `wind_system.gd` | 0.75 to 1.15 | Limits the distance modifier |
| Club sensitivities | `golf_rules.gd` `get_club_wind_sensitivity()` | See the table | How much each club feels the wind |
| Compensation | `shot_ai.gd` | 0.2 + skill × 0.6 | How well AI golfers allow for wind |

---

## Related

- [Weather System](weather-system.md) sets the day's weather alongside the wind.
- [Ball Physics](../golf-play/ball-physics.md) explains the flight the wind acts on.
- [Shot AI: Target Finding](../golf-play/shot-ai-target-finding.md) covers wind compensation.
