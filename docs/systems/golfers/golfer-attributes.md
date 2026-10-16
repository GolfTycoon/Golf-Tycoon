# Golfer Attributes

> **Source:** `scripts/systems/golfer_attributes.gd` (`GolferAttributes`), generated and applied via `scripts/entities/golfer.gd` and `scripts/managers/golfer_manager.gd`, shown in `scripts/ui/golfer_info_popup.gd`

## Plain English

Every golfer in Golf Tycoon - a visiting guest, a tournament player, or the course owner - carries the same attribute block. Click a golfer on the course to see all of it.

**Name** and **Profession** are text. **Marital Status** is Single, Married, Divorced, or Widowed. **Age** is a number. **Gender** is Male or Female.

**Golfer Traits** are five personality switches, each either On or Off:

- **Neat** — cares about upkeep. A tidy, weed-free course delights them; weeds sour the end of their round.
- **Outgoing** — speaks up more often (more comments) and enjoys greeters more.
- **Active** — walks the course faster and tires more slowly.
- **Playful** — enjoys the good moments more; positive comments lift their Fun further.
- **Nice** — shrugs off the bad moments; negative comments and waiting hurt their Fun less.

**Golfer Skills** are three aptitude switches, each either On or Off:

- **Length** — how far a golfer is able to drive the ball (+10% distance when On).
- **Accuracy** — the ability to control how and where the ball lands (tightens shot dispersion).
- **Imagination** — the ability to control the behaviour of the ball in order to overcome obstacles or hazards. Without it a golfer cannot play draw, fade or high backspin shots at all.

**Golf Skills** are ten trained skills, bought with points. Each point increases that golf skill by 10% and each skill can go up to 990% (99 points):

| Golf Skill | What it does |
| --- | --- |
| Power Hitter | Influences how much power fuels your shots (distance on full swings) |
| Long Driver | Affects the length of the drive |
| Accurate Driver | Affects how precisely you hit the ball towards the hole when teeing off |
| Accurate Irons | Indicates how accurate your golf irons are |
| Accurate Putter | Affects how precisely you hit the ball towards the hole when putting on the green |
| Draw Shot (R to L) | Curves the ball from right to left to avoid hazards - generally performed by those with the Imagination skill |
| Fade Shot (L to R) | Curves the ball from left to right to avoid hazards - generally performed by those with the Imagination skill |
| High Backspin Shot | A high shot near the green that rolls back slightly on landing, overshooting gently while avoiding a hazard |
| Recovery Skills | Affects your ability to recover a ball from a course obstacle |
| Luck | Indicates how much luck you possess while executing tricky shots |

**Golfer Statuses** are five percentages that live through the round. Golfers start the course with each Golfer Status at 50%:

- **Fun** — based on the accumulation of the golfer's comments made while playing your course.
- **Attitude** — a golfer's attitude is based on the amount of fun he or she is having at your resort.
- **Energy** — goes down while the golfer is on the course and goes up when using a bench.
- **Hunger** — goes down while the golfer is on the course and goes up when using a Snack Bar.
- **Thirst** — goes down while the golfer is on the course and goes up when using a Drink Vendor.

**Golfer Comments** are the remarks a golfer makes as they play the course. Each is Positive, Neutral, or Negative, and each one lands on the golfer's record and feeds their Fun status.

---

## How It Works

### Identity generation

Random golfers roll identity when they spawn (visiting golfers keep the name of their visitor card; the course owner takes their name and profession from the player profile):

- **Gender** is a coin flip; **Age** 18-80 by tier (Pro golfers are 20-40, Serious 22-62).
- **Profession** comes from a pool of common professions.
- **Marital Status** odds shift with age: the young are mostly Single, mid-life mostly Married, and Widowed grows after 66.
- **Name** is drawn from gendered first-name and surname pools, so the name matches the gender rolled.

### Traits and skills generation

Each Golfer Trait is an independent coin flip (On or Off). Each Golfer Skill is On with tier-weighted odds (beginners 20-30%, pros 65-75%). The ten Golf Skills are rolled as points from a tier range - Beginner 0-5, Casual 3-10, Serious 8-18, Pro 14-30 per skill - with bonus points where the matching Golfer Skill is On. Draw, Fade and High Backspin points are halved without Imagination (such a golfer cannot use the shots anyway).

The owner's ten Golf Skills are the points they allocate on the Player Skills screen (a pool of 10 at creation, each point +10%); both are the same `Golf Skill` values.

### Playing abilities (derived, not stored)

There is no separate set of Playing Skills. Each golfer's playable form is derived on demand from their Golf Skill points through the curve `ability(bonus) = 1 - 0.5 / (1 + bonus)` (0.5 at zero points, approaching 1.0):

| Ability | Derived from |
| --- | --- |
| Driving | the average of Power Hitter and Long Driver |
| Accuracy | the average of Accurate Driver and Accurate Irons |
| Putting | Accurate Putter |
| Recovery | Recovery Skills |

The same derivation applies to every golfer, the owner included (the owner's points live on the player profile). Tournament simulations carry the four derived abilities directly, and hand them to live golfers as the equivalent Golf Skill points.

### How the Golf Skills change shots

Every formula reads the skill as `bonus = points * 0.1` (so 12 points = +120%):

| Effect | Formula |
| --- | --- |
| Drive distance | `factor * (1 + min(0.30, 0.05 * Power Hitter))`, and drivers add `1 + min(0.25, 0.06 * Long Driver)`, then `* 1.1` when Length is On |
| Club accuracy | `1 - 0.5 / (1 + bonus)` of the club's Accurate skill - Driver/Fairway Wood → Accurate Driver, Iron/Wedge → Accurate Irons, Putter → Accurate Putter (the derived ability above) |
| Shaped shot accuracy | `1 - (1 - accuracy) / (1 + bonus)` on the shape's skill (Draw/Fade/Backspin) when the shape is played |
| Draw / fade bend | `8° * (0.4 + min(1.2, 0.12 * bonus))` of the matching skill - requires Imagination |
| High backspin roll-back | `min(1.5, 0.25 * (1 + High Backspin bonus))` tiles back from the landing point on greens and fairways |
| Bad-lie recovery | `1 - (1 - lie) / (1 + Recovery Skills bonus)` |
| Putting | the Accurate Putter ability sharpens make-rate and miss size, and Luck rounds the stroke out |
| Luck | Smooths every shot's accuracy and halves the worst shank odds at high bonus |

The Accuracy golfer skill divides the whole shot dispersion by 1.35 when On. AI golfers with Imagination pick their shape while aiming: a hazard to the left of the line invites a Fade, to the right a Draw, and a pin within 3.5 tiles invites a High Backspin Shot - each only where the matching Golf Skill has points.

### Statuses during the round

Statuses move through the round exactly as described above: Energy, Hunger and Thirst decay per hole (0.018 / 0.012 / 0.015 for a Casual golfer, scaled by tier demand and the Resort Hotel bonus) and recover at amenities - a bench (+0.20 Energy), a Snack Bar (+0.30 Hunger, +0.20 Thirst), a Pub (+0.50 Hunger, +0.25 Thirst), a Drink Vendor service, and the clubhouse at the end of the round (+0.15 each). A golfer considers a nearby amenity when the matching status drops below 0.3 (guaranteed stop), between 0.3-0.7 (coin flip) or above 0.7 (20% chance).

Fun moves with comments: Positive `+0.02` (x1.5 when Playful), Neutral `+0.002`, Negative `-0.02` (x0.7 when Nice). Waiting in traffic drains Fun slowly too (`0.0012` per second, x0.75 when Nice). Attitude then follows the fun being had: `attitude += (fun - attitude) * 0.3` after every comment, hole and wait. Service shocks (greeters, marshals, drinks) and critically low statuses adjust Attitude directly.

Overall visit satisfaction is `Fun 0.25 + Attitude 0.25 + Energy 0.20 + Hunger 0.15 + Thirst 0.15`.

### Comments

Every thought a golfer produces while playing is a comment: score reactions (Hole in One!, Birdie!, Tough hole...), hazard and lie remarks, need complaints (Getting tired..., Need a drink), price and pace remarks, and staff-service thanks. Each comment is stored on the golfer with its sentiment and hole, capped at the 40 most recent, and counted Positive/Neutral/Negative for the golfer panel. Outgoing golfers pass the comment probability roll 1.5x as often; Nice golfers' negative comments cost less Fun. Neat golfers add a closing remark about the upkeep (weeds trigger a Negative comment; a clean course a Positive one).

---

## Algorithm

### 1. Golf Skill value

```
bonus(index)   = points[index] * 0.1        # 0.0 - 9.9 (up to +990%)
percent(index) = points[index] * 10         # 0% - 990% as the player sees it

# Playing abilities are derived from the points - never stored:
ability(bonus)     = 1 - 0.5 / (1 + bonus)  # 0.5 at zero points, → 1.0
driving            = ability(avg(Power Hitter, Long Driver))
accuracy           = ability(avg(Accurate Driver, Accurate Irons))
putting            = ability(Accurate Putter)
recovery           = ability(Recovery Skills)
```

### 2. Status decay per hole (casual; tier 0.8-1.3 multiplier)

```
energy  -= 0.018 * tier * energy_decay_modifier * (0.8 if Active else 1.0)
hunger  -= 0.012 * tier
thirst  -= 0.015 * tier
fun     <- comments (see below); waiting drains 0.0012/s
attitude += (fun - attitude) * 0.3
```

### 3. Comment -> Fun

```
positive: fun += 0.02 * (1.5 if Playful else 1.0)
neutral:  fun += 0.002
negative: fun -= 0.02 * (0.7 if Nice else 1.0)
comments.append({text, sentiment, hole, day})   # keep last 40
```

## Tuning Levers

| Parameter | Location | Current Value | Effect |
| --- | --- | --- | --- |
| STATUS_START | `golfer_attributes.gd` | 0.5 | Every golfer status starts the course at 50% |
| ENERGY_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.018 | Higher = golfers tire faster |
| HUNGER_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.012 | Higher = golfers get hungry sooner |
| THIRST_DECAY_PER_HOLE | `golfer_attributes.gd` | 0.015 | Higher = golfers get thirsty sooner |
| FUN_PER_POSITIVE/NEGATIVE_COMMENT | `golfer_attributes.gd` | +0.02 / -0.02 | How much each comment moves Fun |
| ATTITUDE_FOLLOW_RATE | `golfer_attributes.gd` | 0.3 | How fast Attitude settles toward Fun |
| POINTS_PER_GOLF_SKILL | `golfer_attributes.gd` | 99 | The 990% cap on any Golf Skill |
| TIER_POINT_RANGE | `golfer_attributes.gd` | 0-16 | Points per Golf Skill by tier |
| TIER_GOLFER_SKILL_ODDS | `golfer_attributes.gd` | 0.2-0.75 | Odds a Golfer Skill is On by tier |
| MAX_COMMENTS | `golfer_attributes.gd` | 40 | Comments kept per golfer |
| Owner point pool | `player_golfer_profile.gd` | 10 | Points the owner allocates at creation |

---

## Related

- [Golfer Needs and Statuses](golfer-needs.md) details the status decay, amenity restoration and complaint triggers.
- [Golfer Spawning](golfer-spawning.md) covers arrival, tiers and visiting-golfer pools.
- [Satisfaction and Feedback](satisfaction-feedback.md) covers how comments roll up into daily reviews.
- [Player Rounds](../golf-play/player-rounds.md) covers the owner's own Golf Skills screen.
