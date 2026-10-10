# Event Feed

> A running log of what happened on your course: records, money, weather, tournaments, construction and the daily month headers. Toasts pop up for important entries, and the feed keeps the full history for the session.

**Source:** `scripts/managers/event_feed_manager.gd` (autoload: `add_event()`, `CATEGORY_DATA`, batching, fast-forward summary, signal handlers), `scripts/ui/event_feed_panel.gd`, `scripts/ui/notification_toast.gd` (`DISPLAY_DURATION`, `DISPLAY_DURATION_HIGH`)
**Tests:** `tests/unit/test_event_feed_manager.gd`

---

## Plain English

Important things that happen in the game are logged to the **event feed**. The feed is a scrolling list you can open at any time. Unlike a toast, which disappears after a few seconds, the feed keeps every entry for the whole session, so you can catch up after fast-forwarding or after looking at another part of the course.

Entries fall into eight **categories**:

| Category | Colour | What it covers |
| --- | --- | --- |
| Records | Gold | Records broken, eagles and better, hole-in-ones |
| Economy | Green | Money milestones, bankruptcy warnings, reputation milestones, green fee changes |
| Golfers | Blue | Outstanding rounds, three or more under par |
| Weather | Cyan | Weather changes, season changes, upcoming seasonal events |
| Tournament | Purple | Scheduled, started and completed tournaments |
| Milestone | Orange | Achievements |
| Course | Yellow | Holes created or deleted, buildings placed, new game |
| Daily | Grey | Month headers and the year-end summary |

**Priority** controls how an entry is shown:

- **Info:** feed only, no toast.
- **Normal:** a toast for 3.5 seconds, plus the feed.
- **High:** a toast for 5 seconds, plus the feed. The feed button pulses.
- **Critical:** a toast that stays until you click it, plus the feed.

**Fast-forward.** At fast speeds, toasts are shorter (2 seconds). At ultra speed, only the first three normal entries per category per game day show toasts. The rest are stored in the feed without a toast. When you slow back down to normal or pause, the feed shows a summary of the fast-forward: the days that passed, the rounds finished, the records set and the money gained or lost.

**Click to navigate.** Some entries have a `>` button that takes the camera somewhere. It can centre a hole, a grid position (such as a new building), a golfer, or open a named panel such as Financial.

**Storage.** The feed holds the last **200** entries in memory and drops the oldest when full. It is not saved to disk, so it resets when the game is closed. The category filters you set are kept.

---

## Algorithm

### 1. Adding an entry

```
add_event(category, priority, message, navigate_type, navigate_value):
    return nothing if in the main menu or while a save is loading
    record fast-forward statistics

    if speed is ULTRA and priority is NORMAL:
        reset the per-category counts when the game day changes
        count[category] += 1
        if count[category] > 3:
            store the entry silently (no toast)
            return

    store the entry (oldest is dropped beyond MAX_EVENTS = 200)
    if the feed is closed: unread_count += 1
    emit event_added (shows the toast, subject to priority)
```

### 2. Toast duration

| Priority | Duration |
| --- | --- |
| Info | No toast |
| Normal | 3.5 s, or 2.0 s at fast speed |
| High | 5.0 s |
| Critical | Until clicked |

### 3. Fast-forward summary

```
on speed change to FAST or ULTRA:
    remember start day, money and counters

on speed change back to NORMAL or PAUSED:
    days    = current day − start day
    summary = days, rounds finished, records set, money change
    if days > 0 or rounds > 0: post the summary toast
```

### 4. What is logged

These are the signals the feed listens to, and what each one posts.

| Trigger | Category | Priority |
| --- | --- | --- |
| Record broken (hole-in-one, lowest round, best hole) | Records | High |
| Eagle or better on a hole | Records | High |
| Round finished three or more under par | Golfers | Normal |
| Money crosses $100K, $250K, $500K or $1M | Economy | Normal |
| Bankruptcy warning | Economy | Critical |
| Reputation crosses each 25-point bracket | Economy | Normal |
| Green fee changed | Economy | Info |
| Weather changed | Weather | Info |
| Season changed | Weather | Normal |
| Seasonal event tomorrow, or in two days | Weather | Normal, or Info |
| Tournament scheduled | Tournament | Normal |
| Tournament started or completed | Tournament | High |
| Hole created or deleted | Course | Normal |
| Building placed | Course | Info |
| New game started | Course | Normal |
| Month change (end of day) | Daily | Info |
| Year ended | Daily | Normal |

Course rating changes are not logged. The rating is recalculated at the end of every day, so a line about it would repeat every day and bury the important entries. The rating stays live in the HUD and in the Course Rating panel.

---

## Tuning Levers

| Parameter | Location | Current value | Effect |
| --- | --- | --- | --- |
| Stored entries | `event_feed_manager.gd` `MAX_EVENTS` | `200` | Scrollback length and memory use |
| Normal toast duration | `notification_toast.gd` `DISPLAY_DURATION` | `3.5` s | How long normal toasts stay |
| High toast duration | `notification_toast.gd` `DISPLAY_DURATION_HIGH` | `5.0` s | How long high-priority toasts stay |
| Fast-speed toast duration | `notification_toast.gd` | `2.0` s | How quickly toasts clear at fast speed |
| Ultra batch limit | `event_feed_manager.gd` `add_event()` | `3` per category per day | Toasts allowed before silent storage |
| Outstanding round threshold | `event_feed_manager.gd` `_on_golfer_finished_round()` | `−3` or better | Which rounds are logged |
| Money milestones | `event_feed_manager.gd` `_on_money_changed()` | $100K, $250K, $500K, $1M | Money entries |
| Reputation bracket | `event_feed_manager.gd` `_on_reputation_changed()` | `25` points | How often reputation entries appear |
| Panel width | `event_feed_panel.gd` | `340` px | Width of the feed panel |

---

## Related

- [Seasonal Calendar](../environment-and-time/seasonal-calendar.md) covers the seasonal events that are announced here.
- [Tournament System](tournament-system.md) covers the tournament entries.
- [Economy](../economy-and-land/economy.md) covers the money changes that are logged.
