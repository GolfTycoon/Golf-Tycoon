# Building & Running

> How to run Golf Tycoon from source, which Godot version it needs, the Make targets, and the export presets.

**Source:** `Makefile`, `scripts/resolve-godot.sh`, `export_presets.cfg`, `project.godot`, `web/custom_shell.html`

---

## Requirements

- **Godot 4.6** or later. The project targets the 4.6 engine.
- **Git**, to clone the repository.
- **Make** (optional). The Make targets are thin wrappers around the commands below.

## Run the Game

```bash
make run              # launch the game
make editor           # open the project in the Godot editor
```

If Make cannot find Godot, point it at your copy:

```bash
make run GODOT=/path/to/Godot
```

`scripts/resolve-godot.sh` finds Godot in this order: a bundled copy, the `GODOT` variable, your `PATH`, or a download.

## Make Targets

| Target | What it does |
| --- | --- |
| `make run` | Runs the game with `--path .` |
| `make editor` | Opens the project in the editor |
| `make test` | Runs the unit tests with `test.sh` (GUT). The first run imports the project. |
| `make warnings` | Runs `check-warnings.sh`, which fails if any project script has a GDScript warning |
| `make help` | Lists the targets |

## Tests

Run the unit suite:

```bash
make test
```

`test.sh` runs GUT in headless mode with `gutconfig.json`. Pass extra GUT arguments after the script name to narrow the run. The integration scenes and the harnesses are described in [Testing](testing.md).

## Warnings Check

```bash
make warnings
```

`check-warnings.sh` loads `tools/warning_scan.gd` as a temporary autoload, runs the scan and restores `project.godot` afterwards. The CI `warnings` job runs this check.

## Export

`export_presets.cfg` has four presets:

| Preset | Platform |
| --- | --- |
| Windows Desktop | Windows |
| macOS | macOS |
| Linux | Linux |
| Web | Browser, using `web/custom_shell.html` |

Export from the Godot editor under **Project → Export**, or with the Godot command line and the preset name.

The Web preset wraps the build in `web/custom_shell.html`, which carries its own
loading screen: artwork, a progress bar and a stage line over the canvas while
`index.wasm` and the `.pck` download. That page is what the player looks at
while the engine boots, so the game keeps it alive — the main scene builds itself
in slices on the web and reports each step to the page through `WebBoot`, and
tells it when the title screen is up. See
[Architecture](../architecture.md#startup).

## Display Settings

The main window is 1600 × 1000 with window mode 2 (maximised). The game also has a compact layout for small windows and touch screens. See [UI & Controls](../ui-and-controls.md).

## Related

- [Contributing](contributing.md) covers the workflow and the code conventions.
- [Testing](testing.md) covers the test suites.
