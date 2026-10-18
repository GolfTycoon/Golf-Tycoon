# Milestones & Achievements

> The game's three goal tracks: **Course Location Milestones** (per course location, per save), **World Milestones** (the whole company, per save) and **Achievements** (career honours that stay unlocked between saves).

**Source:** `scripts/systems/milestone_system.gd` (definitions), `scripts/managers/milestone_manager.gd` (progress and checks), `scripts/systems/achievement_store.gd` (the persistent career shelf), `scripts/ui/course_milestones_screen.gd`, `scripts/ui/world_milestones_screen.gd`, `scripts/ui/achievements_screen.gd` (the three screens)
**Tests:** `tests/unit/economy_and_land/test_milestones.gd`, `tests/unit/economy_and_land/test_achievement_store.gd`, `tests/unit/ui_and_controls/test_course_milestones_screen.gd`, `tests/unit/ui_and_controls/test_world_milestones_screen.gd`, `tests/unit/ui_and_controls/test_achievements_screen.gd`, `tests/integration/ui_and_controls/test_goal_screens.gd`

---

## Plain English

Goals are split into three tracks with different lifetimes:

| Track | Scope | Lifetime | Where it shows |
| --- | --- | --- | --- |
| **Course Location Milestones** | One set per course location | Unlocked again with every new save | Course Milestones screen |
| **World Milestones** | The company across all its locations | Unlocked again with every new save | World Milestones screen |
| **Achievements** | The player's whole career | Stay unlocked **between saves** | Achievements screen |

Starting a new company locks every milestone again; loading a save restores exactly what that save had earned. Achievements are written to `user://settings.cfg` the moment they unlock, so a new company begins with the trophy room still filled.

## Course Location Milestones

Every course location carries the same set. Progress is keyed on the world map's location id, so Monterey's milestones are Monterey's alone — a second site starts with its own locked set even mid-save.

| Category | Milestone | Requirement | Reward |
| --- | --- | --- | --- |
| Course Design | First Tee | Build 1 hole at this location | $300 |
| Course Design | Front Three | Build 3 holes | $600 |
| Course Design | The Front Nine | Build 9 holes | $2,000 |
| Course Design | Full Course | Build 18 holes | $4,000 |
| Course Design | Short Game Special | Every hole is a par 3 (3+ holes) | $2,000 and +5 rep |
| Course Design | Amenities | Place 1 building | $500 and +1 rep |
| Course Design | Full Service | Place 5 buildings | $2,000 and +5 rep |
| Golfers | Open for Business | A golfer finishes a round here | $250 |
| Golfers | Local Favorite | Serve 25 rounds here | $2,500 and +5 rep |
| Golfers | Tee Time Rush | Fill the course to its golfer capacity | $1,000 and +3 rep |
| Records | Ace! | Witness a hole-in-one here | $2,000 and +5 rep |
| Records | Eagle Eye | Witness an eagle here | $1,000 and +3 rep |
| Reputation | Four Stars Here | Earn a 4-star rating at this location | $3,000 and +5 rep |
| Reputation | Five Stars Here | Earn a 5-star rating at this location | $10,000 and +10 rep |

Rounds, holes-in-one and eagles are counted per location; hole and building counts read the live course. Reputation and star milestones need a recorded completed round first — construction alone is not an operating track record.

## World Milestones

One set per save, earned by the company across every course location it owns.

| Category | Milestone | Requirement | Reward |
| --- | --- | --- | --- |
| The Company | Second Site | Own 2 course locations | $2,000 |
| The Company | Chain Reaction | Own 3 course locations | $5,000 |
| The Company | Golf Empire | Own 5 course locations | $15,000 |
| The Company | Company Course Card | Build 18 holes across all locations | $3,000 |
| The Company | A Company of Holes | Build 36 holes across all locations | $8,000 |
| Economy | In the Black | Finish a day with positive profit | +2 rep |
| Economy | Making Money | $10,000 revenue in one year | $1,000 and +3 rep |
| Economy | Big Business | $50,000 revenue in one year | $5,000 and +5 rep |
| Economy | One-Year Milestone | Keep the company running 365 days | $3,000 and +5 rep |
| Economy | Seasoned Operator | Keep the company running 1,825 days | $10,000 and +10 rep |
| Economy | Debt Free | Reach $100,000 with no loans | +5 rep |
| Golfers | Getting Popular | Serve 50 golfers in one year | $2,000 and +5 rep |
| Golfers | Pro Tour Stop | Attract a Pro-tier golfer | $3,000 and +8 rep |
| Records | Ace Factory | Witness 5 holes-in-one across the company | $5,000 and +8 rep |
| Reputation | Getting Noticed | Reach 25 reputation | — |
| Reputation | Established Course | Reach 50 reputation | $2,000 |
| Reputation | Prestigious Club | Reach 75 reputation | $5,000 |
| Reputation | Legendary Course | Reach 100 reputation | $10,000 |

Company hole totals count the live course plus every course stored at another location. Completing a milestone pays its reward once; loading a save never pays again.

## Achievements

Career honours kept in the player's settings file (`[achievements]` in `user://settings.cfg`, see `AchievementStore`). Each reads a career counter that accumulates across every company ever run; threshold honours (reputation, the five-star rating) unlock the first time they are reached and stay unlocked.

| Category | Achievement | Requirement |
| --- | --- | --- |
| Course Design | First Steps | Build 1 hole (career) |
| Course Design | Master Builder | Build 100 holes (career) |
| Golfers | Opening Day | Complete 1 round (career) |
| Golfers | Club Classic | Complete 100 rounds (career) |
| Golfers | Grand Tour | Complete 500 rounds (career) |
| Records | Ace! | Witness 1 hole-in-one (career) |
| Records | Ace Hunter | Witness 10 holes-in-one (career) |
| Records | Eagle Eye | Witness 1 eagle (career) |
| Records | Sky High | Witness 50 eagles (career) |
| Economy | Tycoon | Earn $1,000,000 total revenue (career) |
| Economy | Mogul | Earn $10,000,000 total revenue (career) |
| The Company | Globetrotter | Buy 5 course locations (career) |
| The Company | Atlas Complete | Buy 10 course locations (career) |
| Reputation | One Year On | Run a company for 365 days |
| Reputation | Five Year Plan | Run a company for 1,825 days |
| Reputation | Living Legend | Reach 100 reputation |
| Reputation | Five Star Club | Earn a five-star course rating |
| Reputation | Champion | Win a tournament |
| Mastery | Hall of Fame | Unlock every other achievement |

Career counters are flushed to disk whenever one moves and again whenever a game is saved, so nothing is lost to a crash.

## The Screens

Each track has its own fullscreen screen on the **World Map's background**
(the shared `MenuBackdrop` artwork), wearing the same pixel look: Pixelify
Sans, `PixelButtonStyle`'s notched frames, `PixelIcon` sprites. All three
carry a shared **Course / World / Achievements** switch so the player hops
tracks without going back to the course. Open them from the **Club tab**
(Course Milestones / World Milestones / Achievements) or with **G** /
**Shift+G** / **Shift+T**; the **Achievements tile on the main menu** opens
the trophy room over the title screen. While a goal screen is up from the
Club tab the day freezes, exactly like the World Map and the Course Map;
Back (or Esc) hands the course back - or, from the main menu, returns to it.

**Course Milestones screen** — the per-location goal book:

* **Desktop:** a location rail (site chips with per-site progress), then the
  site's dossier (name, region, tally, rounds/aces/eagles) over a
  two-column ledger of its milestone cards, grouped by category.
* **Tablet landscape:** a location chip shelf and the dossier above the
  ledger.
* **Tablet portrait and phone landscape:** the same shelf and dossier with
  the cards two columns wide.
* **Phone portrait:** one scrolling column - shelf, dossier, cards.

**World Milestones screen** — the company goal book:

* **Desktop:** a company-record rail (the world tally and the numbers the
  goals are earned from: locations owned, holes across the company,
  reputation, days in business, revenue this year) beside the two-column
  goal ledger.
* **Tablet landscape and portrait:** the record as a summary strip of stat
  chips above the ledger.
* **Phone landscape:** the same strip, cards two columns wide; **phone
  portrait** scrolls them in one column.

**Achievements screen** — the trophy room:

* **Desktop:** a trophy-case rail (the newest honour big, then the career
  record: rounds, holes, revenue, locations, longest company) beside a
  three-column honour grid with All / Unlocked / Locked filters.
* **Tablet:** the case as a wide strip above the grid (three columns
  landscape, two portrait).
* **Phone landscape:** a compact featured row and the two-column filtered
  grid.
* **Phone portrait:** the featured honour, a one-line career summary, then
  the filtered single-column roll.

Locked honours keep their title and their counter progress but hide their
description behind a **LOCKED** stamp; unlocked honours show what they took
and the day they landed.

## Rules and Quirks

- **When a save begins.** `WorldMap.new_world()` (Start New Game, Quick Start) and the legacy new-game entry points reset the per-save tracks. Buying more locations in a company does **not** — the world track continues, and each new site simply starts with its own locked location set.
- **Old saves.** The pre-tracks format (`{"completed": [{"id": ...}]}`) migrates through `MilestoneSystem.migrate_legacy_id()`: old course ids land on the active location, old company ids on the world track. Unknown ids are dropped.
- **No double pay.** Rewards are paid only at completion time. Loading, migrating and location switching never re-pay them.

## Related

- [Economy](economy.md) — milestone rewards as income.
- [World Map](world-map.md) — course locations and the company/site split.
- [Save and Load](../../save-and-load.md) — what lives in a save versus the settings file.
