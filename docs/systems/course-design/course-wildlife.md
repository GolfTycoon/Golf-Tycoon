# Course Wildlife

> Cosmetic residents that live on the course: duck families on ponds and butterflies over the wild flowers. They are purely decorative.

**Source:** `scripts/terrain/course_wildlife.gd` (habitat indexing, `_spaced_homes()`, family orbit, draw loop), `scripts/effects/decoration_atmosphere.gd` (fountain beads and ripples), `scripts/entities/decoration.gd`
**Tests:** `tests/unit/test_course_wildlife.gd`

---

## Plain English

- **Ducks.** A connected pond can host a family: an adult and two ducklings that swim in a small loop.
- **Butterflies.** Wild Flower tiles attract butterflies in daylight, outside winter and when it is not raining.
- **Fountains.** The fountain has moving droplets and ripples in the basin.
- **Seasons.** Flower-bed foliage and blooms change with the season. Tropical and resort gardens stay colourful in winter.

These are cosmetic. They do not block shots, cost upkeep, add rating bonuses or change the simulation's randomness. They are not saved. The existing costs, unlocks and aesthetic values of the improvements still apply.

---

## Algorithm

### 1. Habitat

`CourseWildlife` indexes water and flower tiles. A full scan runs at initial setup, after a successful load, and after a quiet generation refresh. Ordinary painting updates only the affected entries. Residents are re-selected at most four times a second while editing.

**Duck homes.** A duck home needs at least three cardinal water neighbours. Candidates are sorted by distance to the centre of the playable map, with a stable coordinate tie-break. Up to **12** homes are accepted, spaced at least **5** tiles apart.

**Garden homes.** Wild Flower tiles use the same method, with up to **24** homes spaced at least **2** tiles apart.

Resident lists do not depend on dictionary order, and they do not use random numbers.

### 2. Movement

Each duck family follows an ellipse inside its home tile:

```
offset(t) = (17 × cos(t), 5.5 × sin(t))
```

- The adult advances at **0.32** radians per real second.
- Each duckling trails by **0.65** radians.
- The body and beak stay inside the 64-pixel tile.

Before drawing, the game checks the current terrain. If the home's water has been painted over, the family is hidden at once, and the habitat rebuilds.

### 3. Time and weather

| Resident | Visible when |
| --- | --- |
| Butterflies | Outside winter, when not raining |
| Ducks | Shelter during heavy rain |

These conditions use the existing weather and season systems.

### 4. Animation and timing

- **Redraw cap:** 15 per second. This is the same on desktop and web.
- **Real time:** movement uses real time, dividing the scaled delta by `Engine.time_scale`. A faster game day does not make ducks race around the pond.
- **Pause** stops movement. Camera movement still redraws the frozen scene.
- **Input:** cosmetic nodes never capture input.
- **Culling:** offscreen detail is skipped.

### 5. Decoration atmosphere

`DecorationAtmosphere` attaches to the visual node of a fountain, so rebuilding or removing the fountain removes its effect too.

- Fountain droplets fall along a quadratic curve from the jet to the basin. Ripples stay inside the basin.
- The course surface uses the same weather lighting, so water, turf and residents match.

---

## Tuning Levers

| Lever | Location | Current value | Effect |
| --- | --- | --- | --- |
| Duck families | `course_wildlife.gd` `MAX_DUCK_FAMILIES` | `12` | Duck population cap |
| Garden homes | `course_wildlife.gd` `MAX_GARDENS` | `24` | Butterfly population cap |
| Duck spacing | `_spaced_homes()` call | `5` tiles | How close duck families can be |
| Garden spacing | `_spaced_homes()` call | `2` tiles | How close garden homes can be |
| Habitat refresh | `course_wildlife.gd` | `0.25` s | How often edits are coalesced |
| Redraw rate | `course_wildlife.gd` | `15` per second | Animation budget |
| Duck orbit | `course_wildlife.gd` | `17 × 5.5` px | Keeps the waterline inside its tile |
| Adult speed | `course_wildlife.gd` | `0.32` rad/s | Speed of the duck family |
| Duckling trail | `course_wildlife.gd` | `0.65` rad | Spacing of ducklings |

---

## Related

- [Improvement Catalog](garden-catalog.md) lists the improvements you can place.
- [Path Furniture](path-furniture.md) covers how benches and ball washers are placed beside walks.
- [Weather System](../environment-and-time/weather-system.md) and [Seasonal Calendar](../environment-and-time/seasonal-calendar.md) cover the rules that control visibility.
