<p align="center">
  <img src="assets/ui/logo.png" alt="Golf Tycoon" width="520">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License: GPL-3.0"></a>
  <a href="https://godotengine.org"><img src="https://img.shields.io/badge/Godot-4.6%2B-478cbf.svg" alt="Godot 4.6+"></a>
  <a href="project.godot"><img src="https://img.shields.io/badge/version-0.1.0-green.svg" alt="Version 0.1.0"></a>
</p>

Build a golf course from the ground up, then run it as a business. Lay out tees, greens and bunkers, place buildings and decorations, hire staff, and watch golfers play your holes shot by shot.

Golf Tycoon is a 2D isometric simulation written in **GDScript** for **Godot 4.6**.

---

## Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Controls](#controls)
- [Project Structure](#project-structure)
- [Testing](#testing)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Course building.** Paint terrain such as fairways, bunkers, water, rough and trees. Create holes by painting a tee box and a cup, then open the hole.
- **Shot-by-shot golf.** Golfers choose targets, clubs and risks. Wind, lies, terrain and accuracy all affect every shot.
- **Ten themes.** Parkland, Desert, Links, Mountain, City, Resort, Heathland, Woodland, Tropical and Marshland each change the look, wind and costs.
- **Business management.** Set green fees, manage costs and loans, hire staff, and watch the daily accounts.
- **Star ratings.** Condition, design, value, pace and aesthetics combine into a five-star course rating that drives golfer demand.
- **Reputation and tournaments.** Host tournaments from local to championship level. Winning raises your reputation.
- **World map.** Buy course locations across 27 destinations, each with its own theme, land and price.
- **Living calendar.** Seasons, weather, wind and seasonal events change play throughout the year.
- **Golfer skins.** Paint and re-colour the golfers' clothing in the built-in studio.
- **Touch and desktop.** Responsive layout for small windows, touch screens and the web build.

## Quick Start

You need **Godot 4.6** or later.

```bash
git clone https://github.com/Antas500/Golf-Tycoon.git
cd Golf-Tycoon
make run          # launch the game
make editor       # open the project in the Godot editor
```

If Make cannot find Godot, set the path yourself:

```bash
make run GODOT=/path/to/Godot
```

To start a game, choose **Quick Start** on the main menu, or **Start New Game** to pick a company name, difficulty, starting money and a location. Full build and export notes are in [Building & Running](docs/development/building.md).

## Controls

| Action | Keys and mouse |
| --- | --- |
| Pan the camera | `W` `A` `S` `D`, or middle-mouse drag |
| Zoom | Mouse wheel, `[` and `]` |
| Rotate the view | `Q` and `Shift+Q` |
| Pause or resume | `Space` |
| Save | `Ctrl+S` |
| Undo and redo | `Ctrl+Z` and `Ctrl+Shift+Z` |
| Cancel | `Esc` or right-click |
| Hotkey help | `F1` |

The full list, including tools, panels and touch controls, is in [UI & Controls](docs/ui-and-controls.md).

## Project Structure

```
Golf-Tycoon/
├── addons/gut/              GUT unit-testing framework
├── assets/                  Sprites, the game theme and the logo
├── data/                    JSON: buildings, decorations, terrain, visiting golfers, skins
├── docs/                    Documentation (start at docs/README.md)
├── scenes/
│   ├── main/main.tscn       The main game scene
│   └── entities/golfer.tscn The golfer scene
├── scripts/
│   ├── autoload/            Global singletons (game state, saves, events, screen layout)
│   ├── course/              Hole routes, routing overlay, entity layer
│   ├── effects/             Particles and cosmetic effects
│   ├── entities/            Golfers, balls, buildings, staff
│   ├── main/                main.gd, the game controller
│   ├── managers/            Owners of live groups: golfers, land, staff, weeds, tournaments
│   ├── systems/             Rules and calculators: shots, weather, wind, ratings, economy
│   ├── terrain/             Course surface, grid, overlays and generation
│   ├── tools/               Course-building tools
│   ├── ui/                  Menus, panels and HUD
│   └── utils/               Shared helpers
├── shaders/                 Course, elevation, planet and foliage shaders
├── tests/
│   ├── unit/                Unit tests (test_*.gd)
│   ├── integration/         Flow tests that run through the game
│   └── harness/             Scenes for manual checks and simulations
├── tools/                   Godot tools: golfer skin generator and warning scanner
├── web/custom_shell.html    Web export shell
├── Makefile                 make run, editor, test, warnings
├── test.sh                  Runs the GUT unit tests
├── check-warnings.sh        Fails on GDScript warnings
├── gutconfig.json           GUT configuration
├── export_presets.cfg       Windows, macOS, Linux and Web export presets
└── project.godot            Godot project file
```

## Testing

```bash
make test       # unit tests (GUT): tests/unit/
make warnings   # fails if any project script has a GDScript warning
```

- **Unit tests** (`tests/unit/`) cover the rules and calculations: 73 test files.
- **Integration tests** (`tests/integration/`) run flows through `main.gd`, such as hole creation, tournaments and saves. There are 17 scripts.
- **Harnesses** (`tests/harness/`) are scenes for manual checks, simulations and previews. They include `ready_golf_harness`, `tournament_harness` and `sim_harness`.

Continuous integration runs the `unit` and `warnings` jobs. See [Testing](docs/development/testing.md) for the details.

## Documentation

- **[Documentation hub](docs/README.md)**: start here.
- **[Architecture](docs/architecture.md)**: how the project fits together.
- **[Systems index](docs/systems/README.md)**: every game system, with its rules and tuning values.
- **[Save & Load](docs/save-and-load.md)**, **[Data Reference](docs/data-reference.md)** and **[Golfer Skins](docs/golfer-skins.md)**.
- **[Contributing](docs/development/contributing.md)**: workflow, conventions and the documentation template.

## Contributing

Contributions are welcome. Read [Contributing](docs/development/contributing.md) first. Run `make test` and `make warnings` before you open a pull request, and update the docs for any system you change.

## License

Golf Tycoon is free software released under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.
