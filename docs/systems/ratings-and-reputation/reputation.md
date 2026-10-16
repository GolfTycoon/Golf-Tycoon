# Reputation System

> Reputation is the company's standing. It rises when golfers have good rounds, falls with stagnation and daily decay, and is also gained through tournaments.

**Source:** `scripts/autoload/game_manager.gd` (`modify_reputation()`, stagnation, daily decay), `scripts/systems/course_rating_system.gd` (prestige)

---


> **Source:** `scripts/autoload/game_manager.gd` and `scripts/managers/golfer_manager.gd`

## Plain English

Reputation is a 0–100 score that represents how well-known and respected the golf course is. It starts at 50 and is the primary driver of golfer attraction — higher reputation brings more golfers and higher-tier golfers (serious players, pros).

Reputation changes through two mechanisms:

### Daily Decay (Automatic)

Every night, reputation decays slightly. The rate depends on the course's star rating — poorly-rated courses decay faster, excellent courses decay very slowly. This creates constant pressure to maintain quality and ensures that a course can't coast on past success forever.

### Golfer Attitude (Per Golfer)

When a golfer finishes their round, they contribute positive or negative reputation based on their attitude (status level 0.0–1.0). Happy golfers (attitude > 0.6) spread the word and increase reputation. Unhappy golfers (attitude < 0.4) hurt reputation. Neutral golfers (0.4–0.6) provide a small positive contribution.

The reputation gain is scaled by:
- **Golfer tier** — Pro golfers have 10x the reputation impact of beginners
- **Prestige multiplier** — Harder courses with good ratings earn bonus reputation
- **Pro performance bonus** — A pro who scores under par gives double reputation

This means the optimal strategy is building a challenging, well-rated course that attracts and satisfies pro golfers — each happy pro is worth 10 beginners.

---

## Algorithm

### 1. Reputation Range

```
reputation: float = 50.0    # Starting value
range: [0.0, 100.0]         # Clamped on every modification
```

### 2. Daily Decay

Called during `advance_to_next_day()`:

```
if reputation > 0:
    stars = course_rating.stars    # Integer 1-5

    if stars < 3:    decay = 1.0     # Poor course: fast decay
    elif stars == 3: decay = 0.5     # Average: moderate decay
    elif stars == 4: decay = 0.25    # Good: slow decay
    else:            decay = 0.1     # Excellent: minimal decay

    # Difficulty preset can scale decay
    decay *= difficulty_preset.reputation_decay_multiplier

    reputation -= decay
```

**Daily decay examples:**

| Stars | Base Decay | After 30 days |
| ----- | ---------- | ------------- |
| 1-2 | -1.0/day | -30 points |
| 3 | -0.5/day | -15 points |
| 4 | -0.25/day | -7.5 points |
| 5 | -0.1/day | -3 points |

### 2b. Stagnation Penalty

If the player maintains the same hole count for more than 28 consecutive days
and reputation is above 40, an additional -0.3/day decay is applied. This
prevents coasting on a small number of holes indefinitely — golfers get bored
of the same course layout.

```
if stagnation_days > 28 and reputation > 40:
    reputation -= 0.3
```

The stagnation counter resets whenever the open hole count changes (new hole
built or existing hole removed).

### 3. Per-Golfer Reputation Gain

Called when a golfer finishes their round:

```
# Step 1: Base reputation from tier
base_rep = GolferTier.get_reputation_gain(tier)
    BEGINNER:  1
    CASUAL:    2
    SERIOUS:   4
    PRO:       10

# Step 2: Pro performance bonus
if tier == PRO and total_strokes <= total_par:
    base_rep *= 2    # Double reputation for pro under par

# Step 3: Prestige multiplier (see course-rating.md)
prestige = CourseRatingSystem.get_prestige_multiplier(course_rating)
base_rep = int(base_rep * prestige)

# Step 4: Scale by golfer attitude
attitude = golfer.attitude    # 0.0 to 1.0

if attitude >= 0.6:
    # Happy golfer: positive reputation (scales 0.5x to 1.0x of base)
    reputation_gain = base_rep * lerp(0.5, 1.0, (attitude - 0.6) / 0.4)

elif attitude >= 0.4:
    # Neutral golfer: small positive gain
    reputation_gain = base_rep * 0.25

else:
    # Unhappy golfer: negative reputation (scales 0x to -1.0x of base)
    reputation_gain = -base_rep * lerp(0.0, 1.0, (0.4 - attitude) / 0.4)

reputation += reputation_gain
```

### 4. Reputation Impact Examples

| Golfer | Attitude | Base | Prestige | Final Gain |
| ------ | ---- | ---- | -------- | ---------- |
| Happy Beginner (0.8) | 0.8 | 1 | 1.0x | +0.75 |
| Happy Casual (0.7) | 0.7 | 2 | 1.0x | +1.25 |
| Happy Pro (0.9) | 0.9 | 10 | 1.5x | +11.25 |
| Neutral Casual (0.5) | 0.5 | 2 | 1.0x | +0.5 |
| Unhappy Pro (0.2) | 0.2 | 10 | 1.0x | -5.0 |
| Pro under par (0.8) | 0.8 | 20 | 1.5x | +22.5 |

### 5. Tournament Reputation

Tournaments award a flat reputation bonus on completion (bypasses the attitude system):

```
LOCAL:        +15 reputation
REGIONAL:     +40 reputation
NATIONAL:     +100 reputation
CHAMPIONSHIP: +300 reputation
```

### 6. Reputation Effects on Gameplay

Reputation influences several systems:

- **Golfer spawn rate**: Higher reputation = more golfers visit (see [golfer-spawning.md](../golfers/golfer-spawning.md))
- **Tier attraction**: Pro golfers require 70+ reputation, serious golfers are filtered below 50 (see [golfer-spawning.md](../golfers/golfer-spawning.md))
- **Value rating**: Fair pricing is based on reputation (see [course-rating.md](course-rating.md))
- **Tournament qualification**: Indirectly, through course rating which depends on value rating

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| Starting reputation | `game_manager.gd` | 50.0 | Higher = earlier access to better golfers |
| Decay by star level | `game_manager.gd` | 1.0/0.5/0.25/0.1 | Higher = faster reputation loss |
| Tier reputation gains | `golfer_tier.gd` | 1/2/4/10 | Higher = faster reputation growth |
| Pro under-par bonus | `golfer_manager.gd` | 2x | Higher = more reward for satisfying pros |
| Happy attitude threshold | `golfer_manager.gd` | 0.6 | Lower = easier to get positive rep |
| Unhappy attitude threshold | `golfer_manager.gd` | 0.4 | Higher = more golfers hurt reputation |
| Neutral gain multiplier | `golfer_manager.gd` | 0.25 | Higher = more rep from neutral golfers |
| Tournament rep rewards | `tournament_system.gd` | 15/40/100/300 | Higher = more tournament incentive |
| Stagnation threshold | `game_manager.gd` | 28 days | Lower = faster pressure to expand |
| Stagnation penalty | `game_manager.gd` | -0.3/day | Higher = more punishing to coast |
| Stagnation rep floor | `game_manager.gd` | 40.0 | Lower = penalty applies at lower rep |

## Reputation Attitude Cap

Completed-round tier rewards are multiplied by 0.1 before prestige, retaining fractional values. The attitude used for reputation is capped at `value_rating / 5 + .15`: a pleasant round cannot fully erase poor value. Existing milestone and tournament rewards are separate. This slows a new club's rise to maximum reputation and ties recommendations to the price paid.

---

## Related

- [Course Rating](course-rating.md) sets the prestige multiplier.
- [Golfer Spawning](../golfers/golfer-spawning.md) covers which golfers the reputation attracts.
- [Tournament System](../events/tournament-system.md) covers tournament reputation rewards.
- [Economy](../economy-and-land/economy.md) covers stagnation and the money side of growth.
