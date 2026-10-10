# Game Calendar & Time

> The game runs on the real Gregorian calendar, starting Saturday 1 January 2000. Each game day lasts 3.5 real seconds at normal speed, and the year closes with a summary and loan interest.

**Source:** `scripts/systems/game_calendar.gd` (`get_date()`, `get_weekday()`, `format_date()`), `scripts/autoload/game_manager.gd` (`SECONDS_PER_GAME_DAY`, `LEGACY_DAY_SECONDS`, `DAILY_RATE_SCALE`, `advance_to_next_day()`, `apply_daily_charge()`, `GameSpeed`), `scripts/main/main.gd` (year summary), `scripts/ui/year_summary.gd`
**Tests:** `tests/unit/test_game_calendar.gd`

---

## Plain English

- **Start date.** A new game begins on the morning of **Saturday, 1 January 2000**. Day 1 is that day.
- **Day length.** A game day lasts **3.5 real seconds** at normal speed. Faster speeds shorten it: FAST takes about 1.17 s and ULTRA about 0.44 s.
- **Time keeps going.** Golfers arrive and play all the time. Economies settle, weeds grow and weather changes as each day rolls over. The game only pauses at the end of the year.
- **Year in review.** When 31 December ends, the game pauses and shows the year's revenue, costs, profit, satisfaction and notable scores. Annual loan interest is charged then. See [Economy](../economy-and-land/economy.md).
- **Autosave.** The game autosaves about every 30 game days and at year end. See [Save & Load](../../save-and-load.md).

**Why the rates are scaled.** The old clock ran a day of 14 open hours at 2 real minutes an hour, so one day took 1,680 seconds. The new day takes 3.5 seconds, which is about 1/480 of that. Per-day rates tuned for the old clock would therefore run 480 times too fast. They are multiplied by `DAILY_RATE_SCALE` (about 1/480), which keeps the money, weed and reputation changes per real second as they were tuned. Small charges that would round to nothing each day (for example, $0.04 a day in wages on a municipal nine) accumulate in a per-category carry, so small courses still pay.

---

## Algorithm

### 1. Date arithmetic

`GameCalendar` uses Howard Hinnant's civil-date algorithms, anchored to the proleptic Gregorian calendar.

```
_EPOCH_DAYS       = days from 1970-01-01 to 2000-01-01 = 10957
get_date(day)     = civil_from_days(day − 1 + _EPOCH_DAYS)
get_weekday(day)  = (day − 1 + 6) mod 7        # day 1 is a Saturday (6)
is_leap_year(y)   = y mod 4 = 0 and (y mod 100 ≠ 0 or y mod 400 = 0)
```

Formatting helpers produce strings such as `Sat 1 Jan 2000` (`format_date()`), `1 Jan 2000` (`format_date_short()`), `Saturday, January 1, 2000` (`format_date_long()`) and `January 2000` (`format_month()`).

### 2. Day rollover

```
day_progress += delta                  # delta is already scaled by Engine.time_scale
while day_progress ≥ SECONDS_PER_GAME_DAY and not paused:
    day_progress −= SECONDS_PER_GAME_DAY
    emit end_of_day(current_day)       # costs, payroll, weeds, weather, wind
    advance_to_next_day()              # archive stats, check year boundary
```

`advance_to_next_day()` checks for a new year. When the new day is 1 January, it stores the finished year as `previous_year_stats`, charges annual loan interest, and emits `year_ended`. `main.gd` answers by pausing and opening the Year in Review panel.

### 3. Yearly totals

Daily figures reset each day. On each rollover, the day's figures are added to the year totals, along with the day's satisfaction sample. At year end:

```
previous_year_stats        = yearly_stats            # one prior year is kept for trends
previous_year_satisfaction = yearly_satisfaction_sum / yearly_days
yearly_stats, yearly_days, yearly_satisfaction_sum are reset
```

### 4. Game speed

| Speed | Multiplier | Seconds per game day |
| --- | --- | --- |
| Paused | 0 | — |
| Normal | 1 | 3.5 |
| Fast | 3 | about 1.17 |
| Ultra | 8 | about 0.44 |

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Seconds per game day | `game_manager.gd` `SECONDS_PER_GAME_DAY` | `3.5` s | Overall pace of time at normal speed |
| Legacy day length | `game_manager.gd` `LEGACY_DAY_SECONDS` | `1680` s | Reference for rate scaling |
| Rate scale | `game_manager.gd` `DAILY_RATE_SCALE` | About 1/480 | Converts old per-day rates to the new clock |
| Speed multipliers | `game_manager.gd` `GameSpeed` | 0, 1, 3, 8 | Pause, normal, fast and ultra |
| Autosave interval | `game_manager.gd` `AUTOSAVE_INTERVAL_DAYS` | `30` days | How often autosave runs (also at year end) |
| Start date | `game_manager.gd` | 1 January 2000 | First day of a new game |

---

## Related

- [Seasonal Calendar](seasonal-calendar.md) explains how the months set the seasons.
- [Weather System](weather-system.md) and [Wind System](wind-system.md) change daily.
- [Economy](../economy-and-land/economy.md) covers the daily charges and the loan.
