# Systems Index

> Every game system, grouped by area. Each page explains how the system works in plain English, gives its rules and formulas, and lists the constants you can tune.

**Source:** `docs/systems/` (this index)

---

## Golf Play

How shots, balls, putts and golfer turns work on the course.

| Doc | What it covers |
| --- | --- |
| [Shot Accuracy](golf-play/shot-accuracy.md) | Accuracy, lie and club modifiers, and the shot simulator |
| [Player Rounds](golf-play/player-rounds.md) | Playing your own golfer's round and scoring |
| [Ball Physics](golf-play/ball-physics.md) | Flight, bounce, roll and landing effects |
| [Group Turn Order](golf-play/group-turn-order.md) | Who plays next, and when a group is held up |
| [Putting System](golf-play/putting-system.md) | Make chances, misses and the putting model |
| [Shot AI: Target Finding](golf-play/shot-ai-target-finding.md) | How AI golfers choose targets, clubs and risks |

## Course Design

Building the course: terrain, holes, buildings, themes and ratings inputs.

| Doc | What it covers |
| --- | --- |
| [Builder Tools and Review](course-design/builder-and-review.md) | Building tools, undo and the course review |
| [Bunker Depth](course-design/bunker-depth.md) | Shallow and deep bunkers and how they play |
| [Clubhouse](course-design/clubhouse.md) | The required building and where golfers arrive and leave |
| [Landforms and Golfer Expressions](course-design/course-character.md) | Landforms, architecture and how golfers react to them |
| [Course Surface](course-design/course-surface.md) | How the course surface is drawn |
| [Difficulty Calculator](course-design/difficulty-calculator.md) | Hole difficulty from distance, terrain and layout |
| [Forced Carry](course-design/forced-carry.md) | Hazards that must be carried, and their effect |
| [Elevation Tools](course-design/elevation-tools.md) | Raising, lowering and smoothing ground |
| [Stroke Index](course-design/stroke-index.md) | Hole ranking by difficulty |
| [Improvement Catalog](course-design/garden-catalog.md) | Improvements and facilities you can place |
| [Path Furniture](course-design/path-furniture.md) | Benches, signs and other items beside walks |
| [Walking Paths](course-design/walking-paths.md) | Trails, the dirt-to-paved upgrade and quicker walking |
| [Generated Walking Paths](course-design/generated-walking-paths.md) | The path network a generated course arrives with |
| [Routing Overlay](course-design/routing-overlay.md) | Walking distance between holes |
| [Course Themes](course-design/course-themes.md) | The ten course themes and their effects |
| [Course Wildlife](course-design/course-wildlife.md) | Ducks, butterflies and fountain spray |
| [Hole Creation](course-design/hole-creation.md) | Tee boxes, cups and opening a hole |
| [Buildings on the Grid](course-design/isometric-buildings.md) | How buildings are drawn in isometric view |
| [Tee Aim Arrow](course-design/tee-aim-arrow.md) | The aiming arrow on each tee |
| [Terrain Types](course-design/terrain-types.md) | Every terrain type, its cost and its shot rules |

## Economy and Land

Money, land, staff and the world map.

| Doc | What it covers |
| --- | --- |
| [Economy](economy-and-land/economy.md) | Income, costs, loans, milestones and difficulty presets |
| [Premium Land](economy-and-land/premium-land.md) | Land parcels, tiers and prebuilt courses |
| [Staff and Weeds](economy-and-land/staff-and-weeds.md) | Hired staff, weeds and course condition |
| [World Map](economy-and-land/world-map.md) | Locations, the globe, company and site state |

## Environment and Time

The calendar, seasons, weather and wind.

| Doc | What it covers |
| --- | --- |
| [Game Calendar](environment-and-time/game-calendar.md) | Dates, day length and the year-end summary |
| [Seasonal Calendar](environment-and-time/seasonal-calendar.md) | Seasons, theme modifiers and seasonal events |
| [Weather System](environment-and-time/weather-system.md) | Daily weather, spells and their effects |
| [Wind System](environment-and-time/wind-system.md) | Wind direction, speed and effect on shots |

## Events

Things that happen during play and the log of them.

| Doc | What it covers |
| --- | --- |
| [Event Feed](events/event-feed.md) | The log, toasts and fast-forward summaries |
| [Tournament System](events/tournament-system.md) | Hosting tournaments, tiers, cuts and payouts |
| [Tournament Simulation](events/tournament-simulation.md) | Headless rounds and how fields are built |

## Golfers

Who visits the course and how they feel about it.

| Doc | What it covers |
| --- | --- |
| [Golfer Needs](golfers/golfer-needs.md) | Thirst, pace, comfort and how needs decay |
| [Golfer Spawning](golfers/golfer-spawning.md) | Arrival rate, tiers, group size and landing zones |
| [Satisfaction and Feedback](golfers/satisfaction-feedback.md) | Thought bubbles, daily satisfaction and visitor return |

## Ratings and Reputation

How the course is rated and how the company's reputation moves.

| Doc | What it covers |
| --- | --- |
| [Aesthetics Rating](ratings-and-reputation/aesthetics-rating.md) | Decorations and trees near holes |
| [Course Rating](ratings-and-reputation/course-rating.md) | The five-category star rating, difficulty and slope |
| [Reputation](ratings-and-reputation/reputation.md) | Reputation gains, decay and stagnation |

## Related Guides

- [Architecture](../architecture.md) explains how the systems connect.
- [Data Reference](../data-reference.md) lists the JSON data the systems read.
- [Testing](../development/testing.md) explains how the systems are tested.
