# Testing

> How the test suites are organised, how to run them, and which harness scenes to use for manual checks. Unit tests use GUT, and a separate warnings scan keeps GDScript clean.

**Source:** `test.sh`, `check-warnings.sh`, `gutconfig.json`, `tools/warning_scan.gd`, `Makefile`, `.github/workflows/test.yml`
**Tests:** `tests/unit/` (73 files), `tests/integration/` (17 scripts), `tests/harness/` (12 scenes and 2 preview scripts)

---

## Plain English

There are three kinds of test:

- **Unit tests** check one rule or calculation at a time, such as a price, a shot distance or a rating. They live in `tests/unit/`, and each file is named `test_<topic>.gd`.
- **Integration tests** run a whole flow through `main.gd`, such as creating a hole, hosting a tournament or saving and loading. They live in `tests/integration/`.
- **Harnesses** are scenes you run by hand to see a feature in action or check its layout at different window sizes. They live in `tests/harness/`.

A separate **warnings check** makes sure no project script has a GDScript warning.

## Algorithm

### Unit tests

Unit tests use the **GUT** framework (in `addons/gut/`). `gutconfig.json` points GUT at `res://tests/unit/`, looks for files named `test_*.gd`, and includes subfolders.

```bash
make test        # runs test.sh
./test.sh        # the same run, without make
```

`test.sh` finds Godot (a bundled copy, `$GODOT`, or your `PATH`), imports the project on the first run, and runs GUT headless. Pass extra GUT options after the script name.

### Warnings check

Godot only prints GDScript warnings while a debugger is attached, so normal test runs do not show them. `check-warnings.sh` loads `tools/warning_scan.gd` as a temporary autoload. The scan reloads every project script with the debugger flag, then the script restores `project.godot`. The check fails if Godot reports anything.

```bash
make warnings
./check-warnings.sh
```

Prefer a real fix to a suppression. Rename a shadowing variable, or use the parameter. Use `@warning_ignore` only where the construct is deliberate.

### Integration tests

Each script in `tests/integration/` runs through the real main scene. They are run with `-s`:

```bash
godot --headless --path . -s tests/integration/world_map_flow.gd
```

| Script | Covers |
| --- | --- |
| `hole_creation_flow.gd` | Tee and cup painting, opening a hole, undo and save round trip |
| `hole_path_preview.gd` | The potential hole preview and its route |
| `hole_tab_context_menu.gd` | The Course Holes tab and its context menu |
| `new_game_resets_course.gd` | A second new game starts from a clean grid |
| `generated_course_hole_layout.gd` | Quick Start and the prebuilt packages deliver every hole |
| `staff_on_course.gd` | Hiring staff, moving an area, and pulling a weed |
| `world_map_flow.gd` | Menu, setup, globe, buy, play, switch and quick start |
| `clubhouse_lifecycle.gd` | The clubhouse is created and kept |
| `tee_aim_arrows.gd` | Aiming arrows on tees |
| `management_loop.gd`, `guest_experience_campaign.gd`, `guest_experience_followup.gd` | Longer management and visitor flows |

### Harnesses

Run a harness with `godot --headless --path . res://tests/harness/<name>.tscn`. The main ones are:

| Harness | What it shows |
| --- | --- |
| `walking_path_harness.tscn` | Walking paths on the course |
| `bulldozer_harness.tscn` | The bulldozer removes improvements and buildings, but never course terrain |
| `speed_controls_harness.tscn` | Fast (3×) and Ultra (8×) speed controls |
| `ready_golf_harness.tscn` | Pace: one foursome over three holes, and the time spent waiting on a walking partner |
| `responsive_layout_harness.tscn` | Phone, tablet and desktop window sizes |
| `main_menu_layout_harness.tscn` | Title screen layout at several sizes |
| `edit_golfer_skins_harness.tscn` | The Golfer Skins studio at several sizes |
| `start_new_game_layout_harness.tscn` | The Start New Game screen at many sizes |
| `save_settings_layout_harness.tscn` | The Save / Load archive and the Settings screen at phone, tablet and desktop sizes, plus save, delete and toggle behaviour |
| `tournament_harness.tscn` | A two-round Regional event on a quick-start course |
| `sim_harness.tscn` | Hires one of each staff type, moves areas daily, and runs a save and load across several days |
| `elevation_tools_harness.tscn`, `inspect_harness.tscn` | Elevation tools and the inspect tool |

Two preview scripts write images to `tmp_preview/`. Run them with `-s`:

- `tests/harness/globe_preview.gd` writes the globe's land mask and a view.
- `tests/harness/planet_preview.gd` writes the planet views from a CPU port of the globe shader, for checking the look without a GPU.

## Tuning Levers

| Lever | Location | Effect |
| --- | --- | --- |
| Test folder and pattern | `gutconfig.json` | Which files GUT runs |
| Subfolder search | `gutconfig.json` `include_subdirs` | Whether tests in subfolders run |
| Godot path | `GODOT` variable, or `scripts/resolve-godot.sh` | Which Godot binary runs the tests |
| Warnings scan | `tools/warning_scan.gd` | What the warnings check reports |

## Related

- [Building & Running](building.md) covers the Make targets.
- [Contributing](contributing.md) covers when to run each check.
- [Systems Index](../systems/README.md) links each system to its tests.
