# The Owner's Golfer on the Course

> Your own golfer is never off the course. When they are not playing a round they work a ground of their own: they pull the weeds a groundskeeper would pull and chat with the golfers a greeter would cheer up. The ground is yours to move.

**Source:** `scripts/managers/player_golfer_manager.gd` (`ensure_golfer()`, `claim_for_round()`, `release_from_round()`, `owner_finished_round()`, `set_area_center()`, `serialize()`), `scripts/entities/owner_duty.gd` (the duty machine), `scripts/entities/golfer.gd` (`State.ON_DUTY`, `begin_course_duty()`, `end_course_duty()`, `begin_walk_to()`), `scripts/managers/golfer_manager.gd` (`join_course()`, `take_off_course()`), `scripts/ui/staff_area_overlay.gd`, `scripts/managers/player_round_manager.gd` (the **On the course** column), `scripts/main/main.gd` (the click-on-the-course mode), `scripts/autoload/save_manager.gd` (the `owner_duty` key)
**Tests:** `tests/unit/golf_play/test_owner_on_course.gd`, `tests/unit/golf_play/test_player_round.gd`, `tests/unit/economy_and_land/test_staff_area_overlay.gd`, `tests/unit/save_and_load/test_save_load_validation.gd`

---

## Plain English

The golfer you create in the game is a real person on your course. They stand on the first tee with you at the start of a round, and when the round is over they do not vanish: they walk back to the ground you gave them and get to work.

**The work.** Your golfer does the two jobs that keep a course running, in turn:

- **Groundskeeper:** they walk to the nearest weed on their ground and pull it.
- **Greeter:** they walk to the golfer on their ground who is least happy and chat with them, which lifts their attitude.

When there is nothing to do they wander about inside their ground, the way a hired employee does.

**The ground.** Their ground is a circle of tiles, **8 tiles** across by default. It shows as a **gold ring** on the course, so it reads as yours rather than as another employee's. Move it from the **Edit Player** page: press **Move work area**, then left-click a tile on the course. The ring follows. Right-click or Esc cancels the choice.

**A round is the same golfer.** When you start a round, the golfer who was working your ground is the golfer who tees off. They **walk to the tee** from wherever they were working, and the round waits for them: the turn system only ever plays a golfer who is standing still. When the round is over they **walk back to their ground** and pick the work up again.

**They are not a guest.** While they are working they are not one of the visiting golfers: the turn system never picks them, they do not pay a green fee, and they are not counted in the course's daily statistics. When their round is over they do not walk back to the clubhouse and leave, as a guest would: they stay on the course and go back to work.

---

## Algorithm

### The manager

`PlayerGolferManager` is a node the main scene creates and hands to `GameManager`. It owns three things:

| Field | What it is |
| --- | --- |
| `golfer` | The owner's golfer, a plain `Golfer` node in the course's **Golfers** container |
| `duty` | The `OwnerDuty` child that walks them and does the work |
| `area_center`, `area_radius` | The ground they work, in grid tiles |

The golfer's id is **−1** (`OWNER_GOLFER_ID`), so it never clashes with the guests the `GolferManager` numbers from zero.

`ensure_golfer()` creates the golfer the first time it is asked for, dresses them in `GameManager.player_profile` (name, colours and the skills the player allocated) and puts them on duty. `refresh_profile()` re-dresses them, and is called whenever the profile is edited.

### The duty machine

`OwnerDuty` is a child of the golfer it drives, and it runs the same three-state machine the hired staff use:

```
IDLE      countdown, then choose a task
WALKING   move toward the target; on arrival, start working
WORKING   countdown of the work time; then apply the effect
```

The machine only runs between rounds: `running` is false while the owner is playing, so the work stops the moment the round takes them and cannot start again in the middle of it. The duty also holds a **commute** — `NONE`, `TO_TEE` or `HOME` — the walk the owner is on, which is the golfer's own (see below).

**Choosing a task** (`_choose_task()`): the jobs alternate, so the owner keeps the course tidy and keeps the guests cheerful in turn. If the job they are after has nothing to do, they take the other one instead. If neither has anything to do, they walk to a random point inside their ground.

- **Groundskeeper:** the nearest weed inside the ground (`WeedManager.get_weed_positions()`).
- **Greeter:** the golfer inside the ground with the lowest attitude who is still available for service.

**Walking.** The owner walks at `WORK_WALK_SPEED` (60 px/s), a slower, steadier pace than a golfer on the course. Movement uses `move_and_collide()`, and a blocked step slides along the obstacle instead of stopping dead. A walk that takes longer than `WALK_TIMEOUT_SECONDS` (12 s) is given up on and another task is chosen.

**Working.** A weed takes `WEED_WORK_SECONDS` (2.6 s) to pull and a chat takes `GREET_WORK_SECONDS` (2.0 s). A chat only counts if the golfer is still within `SERVICE_RANGE_TILES` (2.5 tiles) when it ends — the same rule the hired greeters work to, and the same 20-second service cooldown per golfer.

### The state on the golfer

`Golfer.State.ON_DUTY` is the state the owner's golfer holds while they work. In that state the golfer's own `_process()` does nothing: the turn system, the shot logic and the departure logic all leave them alone, and the sprite plays its idle animation while the duty walks them.

### A round

`PlayerRoundManager.start_round()` claims the owner instead of spawning a second golfer:

```
claim_for_round(group_id, tee):
    the owner joins the course's group (GolferManager.join_course)
    the duty stops
    the golfer leaves the ON_DUTY state
    the owner walks to the tee (duty.walk_to_tee)
```

**The walk to the tee** is the golfer's own: `Golfer.begin_walk_to()` uses the same pathfinding the guests use, so the owner follows the trails and goes around obstacles. Their ball is on the tee from the start, and because the turn system only ever picks a golfer who is standing still (IDLE), the round waits for them to arrive.

**The walk back** is the same walk in reverse. When the round is over the duty checks whether the owner is still on the ground they work; if they are not, it sends them home (`commute = HOME`) and the work starts again when they arrive. A round abandoned on the way to the tee cancels that walk and sends them home instead.

**The owner never leaves.** `Golfer.is_course_owner` marks the one golfer on the course who is not a guest: they do not walk back to the clubhouse when their round is over, they are not recorded as a customer visit, and they leave the group (`GolferManager.take_off_course()`) rather than the course. `round_complete` — not the FINISHED state — is what says their round is over, and it is what the round manager watches for the results.

A course with no owner manager — a tool running the game on its own — falls back to spawning a golfer for the round, as before.

### The ground in the UI

`PlayerRoundManager` gives the **Edit Player** page an **On the course** column. It names the tile the owner works and the width of the ground, and its button asks `main.gd` for a click on the course. `main.gd` then puts the game into a click-on-the-course mode: the next click on the terrain moves the ground, and any other tool, right-click or Esc cancels the mode.

`StaffAreaOverlay` draws the ground as a ring, in the owner's gold rather than the green used for hired staff, and redraws when the ground moves.

### Saving

The ground belongs to the course, not the company, so it is saved with the site under the `owner_duty` key: the centre as `{"x":…, "y":…}` and the radius. A course saved before this existed has no `owner_duty` key, and the owner simply starts on the middle of the course.

---

## Tuning Levers

| Lever | Where | Default |
| --- | --- | --- |
| Ground radius | `player_golfer_manager.gd` `AREA_RADIUS` | 8 tiles |
| The owner's golfer id | `player_golfer_manager.gd` `OWNER_GOLFER_ID` | −1 |
| Work walk speed | `owner_duty.gd` `WORK_WALK_SPEED` | 60 px/s |
| Weed work time | `owner_duty.gd` `WEED_WORK_SECONDS` | 2.6 s |
| Chat work time | `owner_duty.gd` `GREET_WORK_SECONDS` | 2.0 s |
| Cheer given by a chat | `owner_duty.gd` `GREET_EFFECT` | +0.1 attitude |
| Service range | `owner_duty.gd` `SERVICE_RANGE_TILES` | 2.5 tiles |
| Walk timeout | `owner_duty.gd` `WALK_TIMEOUT_SECONDS` | 12 s |
| Pause between jobs | `owner_duty.gd` `IDLE_PAUSE_MIN` / `IDLE_PAUSE_MAX` | 0.4 s / 1.6 s |
| Ring colour | `staff_area_overlay.gd` `OWNER_FILL_ALPHA` / `OWNER_OUTLINE_ALPHA` | 0.12 / 0.7 |

---

## Related

- [Player Rounds](player-rounds.md) covers the round your golfer plays.
- [Staff and Weeds](../economy-and-land/staff-and-weeds.md) covers the hired staff whose work this mirrors.
- [Golfer Needs and Statuses](../golfers/golfer-needs.md) covers the attitude a chat lifts.
- [Save & Load](../../save-and-load.md) covers where the ground is stored.
