# Course Aura

> Where golfers spoke up on the course, and how they felt about it: every comment is kept against the ground it was made on, so the map of the course has a mood layer painted on it.

**Source:** `scripts/systems/course_aura.gd` (`CELL_SIZE`, `MAX_SAMPLES`, `HOTSPOT_MIN_SAMPLES`, `TRIGGER_LABELS`, `record_at()`, `cell_counts()`, `hotspots()`, `describe()`), `scripts/autoload/game_manager.gd` (`course_aura`), `scripts/autoload/save_manager.gd` (`course_aura`), `scripts/ui/components/course_map_aura_panel.gd` (the Course Map's Aura panel)
**Tests:** `tests/unit/course_design/test_course_aura.gd`, `tests/integration/ui_and_controls/test_course_map_screen.gd`

---

## Plain English

Golfers complain and compliment as they play — about slow play, weeds, water, a
green fee, the lack of a drinks cart — and every one of those comments is
announced on `EventBus.golfer_thought` with the trigger that produced it and
whether it was good or bad news. Course Aura is the listener that also remembers
**where** the golfer was standing.

The course is cut into square cells, four tiles a side, and each cell keeps a
tally of the happy, the unhappy and the neutral comments heard in it. The Course
Map's **Course Aura** mode paints those cells green where golfers were happy,
amber where it is mixed, red where they were not, and lists the hotspots with the
complaints behind them. The golfer's ground the owner works is shown the same
way in the Staff mode.

Two things are deliberate:

- **The window is recent, not lifelong.** Only the newest 600 comments are kept,
  so the aura follows how the course is playing *lately*: a corner that used to
  be a walk in the park cools off once the weeds come in, and a stretch the staff
  now work warms back up. It is not a record of everything ever said.
- **Quiet is not the same as happy.** Golfers only comment sometimes, so an
  empty cell means nobody spoke there, not that everybody was content. The panel
  says so in as many words.

---

## Algorithm

### 1. Recording

`Golfer._say()` announces every comment; Course Aura turns each one into a
sample:

```
tile      = terrain_grid.screen_to_grid(golfer.global_position)
cell      = cell_of(tile)                     # floor(tile / 4), tile by tile
sentiment = "positive" | "negative" | "neutral"
hole      = golfer.current_hole + 1           # 0 when the golfer is not on a hole
day       = GameManager.current_day
```

A comment made off the course (an invalid tile) is dropped. `record_at()` does
the keeping and is separate from the signal handler, so the rules below can be
exercised without a golfer.

`cell_of()` uses `floori`, not `int`: `int()` truncates towards zero, which would
fold the tiles just west and north of the origin into cell 0.

### 2. The rolling window

Samples are kept newest-last in one array, and the oldest is dropped whenever the
array grows past `MAX_SAMPLES` (600). Nothing is aged out by the calendar: a
sample leaves the window because newer comments arrived, not because a day
passed, so a quiet week keeps its mood and a busy one rolls over quickly.

### 3. Scores

For a cell (or the whole course), the balance of feeling is

```
score = (positive − negative) / (positive + negative)
```

which is +1 for a cell of nothing but compliments, −1 for nothing but
complaints, and 0 both for a dead heat and for a cell where nobody has judged
anything. Neutral comments count towards the cell's total, but not towards the
score: they say the golfer spoke without taking a side.

The Aura mode's colours come from that number: red at −1, through amber at 0, to
green at +1.

### 4. Hotspots

A cell is a hotspot when it has heard at least `HOTSPOT_MIN_SAMPLES` (3)
comments in total:

```
hotspot if counts.total >= 3
ranked by the count of the sentiment asked for, then by score
```

The threshold is what stops one grumpy golfer repainting the map. Each hotspot
reports its cell, its counts, its score, the triggers heard most often in it
(with plain names from `TRIGGER_LABELS`), the hole most of its comments were made
on, and a plain-language place: `describe()` names the nearest hole landmark
("Hole 7 green"), and falls back to the tiles the cell covers when the course has
no holes yet.

### 5. Saving

The aura is saved with the site (the whole sample list, so the map is as warm
after a load as it was before). A save written before the system existed simply
has no aura and starts empty. Starting a new game clears it.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Cell size | `course_aura.gd` `CELL_SIZE` | `4` tiles | Smaller cells point at a single green, larger ones read a whole stretch |
| Window | `course_aura.gd` `MAX_SAMPLES` | `600` comments | How far back the aura remembers; smaller means the mood turns over faster |
| Hotspot threshold | `course_aura.gd` `HOTSPOT_MIN_SAMPLES` | `3` comments | Comments a cell needs before it can be called a hotspot |
| Trigger names | `course_aura.gd` `TRIGGER_LABELS` | 23 entries | The words the hotspot lists use; unknown triggers fall back to "Comment" |
| Cell colours | `course_map_view.gd` `AURA_HAPPY` / `AURA_MIXED` / `AURA_UNHAPPY` | green / amber / red | What the map paints |

---

## Related

- [Satisfaction & Feedback](../golfers/satisfaction-feedback.md) covers the thought bubbles and the daily satisfaction the same comments feed.
- [Course Map](../course-design/course-map.md) covers the Aura mode and the rest of the screen.
- [Golfer Needs and Statuses](../golfers/golfer-needs.md) covers the needs (fun, energy, hunger, thirst) behind many of the complaints.
- [Course Rating](../ratings-and-reputation/course-rating.md) covers the star rating, which is a course-wide summary rather than a map.
