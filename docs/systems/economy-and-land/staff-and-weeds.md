# Staff & Weeds

> Hired staff walk the course inside a designated area and do their job: groundskeepers pull weeds, greeters lift attitudes, marshals keep pace and vendors serve drinks. Weeds left on the course lower its condition.

**Source:** `scripts/managers/staff_manager.gd` (`STAFF_DATA`, `get_pace_modifier()`, `process_daily_maintenance()`, `serialize()`), `scripts/entities/staff_member.gd` (state machine, `SERVICE_RANGE_TILES`), `scripts/entities/owner_duty.gd` (the owner's own golfer doing the same work), `scripts/managers/weed_manager.gd` (`HOST_TURF`, `grow_daily()`, `MAX_WEEDS`, `DAILY_GROWTH`), `scripts/entities/weed.gd`, `scripts/entities/golfer.gd` (`STAFF_HELP_COOLDOWN_SECONDS`, `receive_*()`), `scripts/systems/golfer_attributes.gd` (thirst constants), `scripts/ui/staff_panel.gd`, `scripts/ui/staff_area_overlay.gd`
**Tests:** `tests/unit/economy_and_land/test_staff_manager.gd`, `tests/unit/economy_and_land/test_weed_manager.gd`, `tests/unit/economy_and_land/test_staff_panel.gd`, `tests/unit/economy_and_land/test_staff_service.gd`, `tests/unit/economy_and_land/test_staff_area_overlay.gd`, `tests/unit/golf_play/test_owner_on_course.gd`

---

## Plain English

Hiring an employee puts them on the course. They walk around their **designated area** looking for work. There are four jobs, and each has a standard hire and a premium hire. A premium hire costs more each day, but covers a bigger area, moves faster and works faster.

| Job | Standard | Premium | What they do |
| --- | --- | --- | --- |
| Groundskeeper | Groundskeeper | Technician | Pull weeds that sprout on the turf |
| Greeter | Club Pro | Celebrity | Chat with golfers to lift their attitude |
| Marshal | Ranger | Marshall | Talk to groups to keep the pace moving |
| Drinks vendor | Soda Vendor | Cart Refresher | Serve thirsty golfers a drink |

**Designated areas.** Each employee has a circle of tiles as their area. They only work on targets inside it, and they wander within it when there is nothing to do. Areas show as translucent rings on the course. On the **Staff** tab, press an employee's **Area** button, then left-click a tile to move their area there. Right-click or Esc cancels.

**Your own golfer works too.** The owner's own golfer is on the course between rounds, and does the groundskeeper and greeter jobs on a ground of their own: a gold ring you can move from the **Edit Player** page. See [The Owner's Golfer on the Course](../golf-play/owner-on-the-course.md).

**The Staff tab** has two sections. **Hire Staff** lists each job with a Standard and a Premium button, showing the daily wage and headcount. **Current Staff** shows the daily payroll, the number of weeds, and one row per employee with a name, staff type, wage, **Area** and **Fire** buttons.

**Weeds.** Weeds sprout overnight on owned turf: natural grass, fairways, firm fairways and the roughs. Greens, tees and hazards stay clear, so a weed never hides a cup or blocks a tee shot. Clumps grow taller each day they survive. A groundskeeper walks to the nearest clump in their area, pulls it, and it disappears.

**Course condition.** At the end of each day, condition is recalculated from the weeds left on the course, reduced by groundskeeper coverage. Condition feeds the Condition category of the star rating. An unstaffed course slowly gets scruffy. A well-staffed one stays in good shape.

---

## Algorithm

### 1. Staff types

Each of the eight staff types is one entry in `StaffManager.STAFF_DATA`.

| Type | Job | Tier | Wage per day | Area radius (tiles) | Move speed (px/s) | Work speed | Effect |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Groundskeeper | Groundskeeper | Standard | $80 | 6 | 46 | 1.0× | Pulls weeds |
| Technician | Groundskeeper | Premium | $155 | 11 | 70 | 1.9× | Pulls weeds |
| Club Pro | Greeter | Standard | $60 | 7 | 48 | 1.0× | +0.06 attitude |
| Celebrity | Greeter | Premium | $130 | 12 | 72 | 1.8× | +0.10 attitude |
| Ranger | Marshal | Standard | $50 | 8 | 50 | 1.0× | +0.28 pace |
| Marshall | Marshal | Premium | $110 | 13 | 74 | 1.8× | +0.45 pace |
| Soda Vendor | Drinks vendor | Standard | $40 | 6 | 52 | 1.0× | +0.35 thirst |
| Cart Refresher | Drinks vendor | Premium | $95 | 12 | 78 | 1.9× | +0.60 thirst |

Work speed does two things. The task takes `work_seconds / work_speed`, and the effect is multiplied by `work_speed`. A premium hire therefore reaches more golfers and gives a stronger service each time. Work times are between 2.0 and 2.6 seconds.

### 2. State machine

`StaffMember` moves between three states:

```
IDLE      countdown, then choose a target
WALKING   move toward the target at move_speed; on arrival, start working
          (or go idle if the target was just a wander point)
WORKING   countdown of work_seconds / work_speed; then apply the effect
```

**Choosing a target** (`_choose_task()`):

- **Groundskeeper:** the nearest weed inside the area (`WeedManager.find_closest_weed()`).
- **Greeter:** the golfer in the area with the lowest attitude.
- **Marshal:** the golfer in the area with the lowest pace. Groups blocked by traffic get a bonus.
- **Drinks vendor:** the golfer in the area with the lowest thirst.
- **Nothing to do:** a random point inside the area, so the employee wanders.

All distances use grid space (`TerrainGrid.screen_to_grid_point()`), so the area reads as a true circle even in the isometric view.

A service only takes effect if the golfer is still within `SERVICE_RANGE_TILES` = **2.5** tiles when the work finishes. Walking away mid-conversation means no effect.

### 3. Services to golfers

Each golfer can receive a service at most once every **20 seconds** (`STAFF_HELP_COOLDOWN_SECONDS`), so one employee cannot stand next to a golfer and spam effects.

```
receive_greeting(amount)   → attitude += amount                    + "cheered up" thought
receive_pace_help(amount)  → needs.restore_pace(amount)        + "paced up" thought
receive_drink(amount)      → needs.restore_thirst(amount)      + "refreshed" thought
```

`restore_thirst()` and `restore_pace()` add a small attitude bonus (0.04 and 0.03) only when the need actually improved. A fully quenched golfer gains nothing extra.

### 4. Weed growth

```
grow_daily(open_holes):
    every existing clump:  growth = min(1.0, growth + 0.22)
    wanted = max(1, round(open_holes × 0.5))
    for each new clump:
        try up to 80 random tiles
        accept the first that is:  a host turf type, not a cup or tee,
                                   free of entities, on owned land,
                                   and without a weed already
        stop at 80 clumps on the course (MAX_WEEDS)
```

`HOST_TURF` is grass, fairway, firm fairway, rough, heavy rough and deep rough.

### 5. Course condition

Recalculated at the end of each day in `StaffManager.process_daily_maintenance()`:

```
pressure = weeds / (open_holes × 4.0)             # 1.0 = fully overrun
coverage = min(1.0, groundskeepers / open_holes)  # 1.0 = one per hole
target   = clamp(1.0 − pressure × (1.0 − coverage × 0.7), 0.0, 1.0)
course_condition = target
```

A full crew of groundskeepers absorbs 70% of the weed pressure. Weeds spawned in the same day come after payroll, so the end-of-day summary shows the condition of the course as you left it.

### 6. Pace modifier

Marshals raise the pace rating (used by `CourseRatingSystem`, and by the waiting relief in `golfer.gd`):

```
modifier = min(1.0, 0.6 + 0.12 × standard_marshals + 0.20 × premium_marshals)
```

### 7. Saving

`StaffManager.serialize()` stores each employee's id, type, wage, name, area centre and radius, along with `course_condition` and `next_staff_id`. `WeedManager.serialize()` stores each clump as `"x,y": growth` under `weeds`. Loading rebuilds the staff and the weeds.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Staff data | `staff_manager.gd` `STAFF_DATA` | 8 entries | Wage, area, speed and effect for each type |
| Area radius | `STAFF_DATA` `area_radius` | 6 to 13 tiles | How much ground an employee covers |
| Move speed | `STAFF_DATA` `move_speed` | 46 to 78 px/s | How quickly they reach targets |
| Work speed | `STAFF_DATA` `work_speed` | 1.0 to 1.9 | Speeds up tasks and boosts their effect |
| Work time | `STAFF_DATA` `work_seconds` | 2.0 to 2.6 s | Base task time before work speed |
| Weed pressure | `weed_manager.gd` `WEEDS_PER_HOLE_FULL_PRESSURE` | `4.0` per hole | Lower means weeds hurt condition sooner |
| Weed cap | `weed_manager.gd` `MAX_WEEDS` | `80` | Maximum clumps on the course |
| Weed growth | `weed_manager.gd` `DAILY_GROWTH` | `0.22` per day | How much taller survivors get |
| Spawn attempts | `weed_manager.gd` `SPAWN_ATTEMPTS` | `80` | Random tiles tried per new clump |
| Host turf | `weed_manager.gd` `HOST_TURF` | 6 turf types | Where weeds can sprout |
| Groundskeeper relief | `staff_manager.gd` `process_daily_maintenance()` | `0.7` | Share of weed pressure a full crew ignores |
| Service range | `staff_member.gd` `SERVICE_RANGE_TILES` | `2.5` tiles | How close a golfer must stay |
| Service cooldown | `golfer.gd` `STAFF_HELP_COOLDOWN_SECONDS` | `20` s | Gap between services to one golfer |
| Thirst decay | `golfer_attributes.gd` `THIRST_DECAY_PER_HOLE` | `0.015` per hole | Higher means golfers get thirsty sooner |

---

## Related

- [Course Map](../course-design/course-map.md) shows every area on one map and is where hires, moves and fires are done from (Staff mode).
- [Economy](economy.md) covers payroll and daily costs.
- [The Owner's Golfer on the Course](../golf-play/owner-on-the-course.md) covers the same work done by the player's own golfer.
- [Course Rating](../ratings-and-reputation/course-rating.md) explains how condition and pace feed the star rating.
- [Golfer Needs and Statuses](../golfers/golfer-needs.md) covers thirst, pace and attitude.
- [Golfer Attributes](../golfers/golfer-attributes.md) covers the Neat trait, whose owners comment on (and dislike) weeds.
- [Satisfaction & Feedback](../golfers/satisfaction-feedback.md) covers how attitude affects reviews.
