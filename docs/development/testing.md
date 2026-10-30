# Testing

> How the test suites are organised, how to run them, and which harness scenes to use for manual checks. Unit tests use GUT, and a separate warnings scan keeps GDScript clean.

**Source:** `test.sh`, `check-warnings.sh`, `gutconfig.json`, `tools/warning_scan.gd`, `Makefile`, `.github/workflows/test.yml`
**Tests:** `tests/unit/`, `tests/integration/`, and the manual previews in `tests/manual/`

---

## Plain English

There are three kinds of test:

- **Unit tests** check one rule or calculation at a time, such as a price, a shot distance or a rating. They live in `tests/unit/`, and each file is named `test_<topic>.gd`.
- **Integration tests** run a whole flow through `main.gd`, such as creating a hole, hosting a tournament or saving and loading. They live in `tests/integration/`.
- **Manual previews and reports** in `tests/manual/` show generated courses, rendering and simulation behaviour; they are not part of the automated suites.

A separate **warnings check** makes sure no project script has a GDScript warning.

## Algorithm

### Unit tests

Unit and integration tests use the **GUT** framework (in `addons/gut/`).
`gutconfig.json` looks for files named `test_*.gd` in both suites and includes
subfolders. `test.sh` chooses the requested suite (unit by default).

```bash
make test        # runs test.sh
./test.sh        # the same run, without make
```

`test.sh` finds Godot (a bundled copy, `$GODOT`, or your `PATH`), imports the project on the first run, and runs GUT headless. Pass extra GUT options after the suite name.

### Warnings check

Godot only prints GDScript warnings while a debugger is attached, so normal test runs do not show them. `check-warnings.sh` loads `tools/warning_scan.gd` as a temporary autoload. The scan reloads every project script with the debugger flag, then the script restores `project.godot`. The check fails if Godot reports anything.

```bash
make warnings
./check-warnings.sh
```

Prefer a real fix to a suppression. Rename a shadowing variable, or use the parameter. Use `@warning_ignore` only where the construct is deliberate.

### Integration tests

Integration tests live under `tests/integration/` and use GUT with the real
main scene (`MainSceneTest`). Run them alone, or run both suites together to
catch state leaking from one suite into the other:

```bash
./test.sh integration
./test.sh all
./test.sh integration -gselect=building_foundations_flow
```

CI runs the combined suite as well as the unit-only and warning checks.

Integration scripts build the real main scene through `MainSceneTest`, which
waits for the scene's startup to finish before the first test (a web build, and
any run with `--split-startup`, spreads it over several frames; see
[Architecture](../architecture.md#startup)). To see or profile that path on a
desktop, run the game with the argument:

```bash
godot --path . -- --split-startup
```

`tests/integration/ui_and_controls/test_startup_slices.gd` covers it
automatically: it forces the sliced startup on for its own scene and checks that
the scene really did build over several frames, that every step ran, and that
the title screen is up at the end.

### Manual previews and reports

The scripts and scene under `tests/manual/` are for inspection, not automated
GUT assertions. For example:

```bash
godot --headless --path . -s tests/manual/course_path_preview.gd -- quickstart
godot --headless --path . res://tests/manual/ready_golf_report.tscn
```

`course_path_preview.gd` prints a generated course and its walking-path
statistics; it also accepts `generated3`, `generated6`, `generated9`,
`generated18`, `starter`, `executive`, `standard9` or `championship18`.
`globe_preview.gd` and `planet_preview.gd` write images under `tmp_preview/`,
and the guest-experience scripts produce longer playtest reports.

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
