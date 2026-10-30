# Architecture

> How Golf Tycoon is put together: a Godot 4.6 project in GDScript, one main scene, fifteen autoload singletons, and systems that talk to each other through signals on `EventBus`.

**Source:** `project.godot` (autoloads, input map), `scenes/main/main.tscn` (scene tree), `scripts/main/main.gd` (game controller), `scripts/autoload/event_bus.gd` (signal hub)

---

## Plain English

The game has three layers:

1. **Autoloads** hold global state and services. These include the game manager, the save manager, the event bus and the screen layout.
2. **The main scene** draws the course. `main.gd` runs the scene, the camera, the HUD and the tool palette.
3. **Systems and managers** do the work. Systems are mostly stateless calculators, such as shot physics, weather and ratings. Managers own groups of live objects, such as golfers, balls and holes.

Systems announce what happened with signals on `EventBus`, so they do not need direct references to each other. For example, a golfer finishing a hole emits `golfer_finished_hole`, and the scorecard, the event feed and the tournament board all listen for it.

---

## Folder Layout

| Folder | Contents | Files |
| --- | --- | --- |
| `scripts/autoload/` | Global singletons | 13 |
| `scripts/systems/` | Stateless rules and calculators | 37 |
| `scripts/managers/` | Owners of live groups (golfers, land, staff, weeds, tournaments) | 14 |
| `scripts/entities/` | Scene objects: golfers, balls, buildings, staff | 10 |
| `scripts/terrain/` | Course surface, grid, overlays and generation | 30 |
| `scripts/course/` | Hole routes, routing overlay and entity layer | 9 |
| `scripts/ui/` | Menus, panels, HUD and components | 53 |
| `scripts/effects/` | Particles and cosmetic effects | 11 |
| `scripts/tools/` | Course-building tools such as hole creation | 5 |
| `scripts/utils/` | Shared helpers | 5 |
| `scripts/audio/` | Audio helpers | 1 |
| `scripts/main/` | `main.gd`, the game controller | 1 |
| `shaders/` | Course, elevation, planet and foliage shaders | 5 |
| `data/` | JSON data for buildings, decorations, terrain and visitors | See [Data Reference](data-reference.md) |
| `scenes/` | `main.tscn` and the golfer scene | 2 |
| `tests/` | Unit, integration and harness scenes | See [Testing](development/testing.md) |
| `tools/` | Editor and build scripts | 2 |

---

## Autoloads

These singletons are registered in `project.godot`. They are loaded in this order.

| Name | Script | Role |
| --- | --- | --- |
| `Screen` | `scripts/autoload/screen_manager.gd` | Responsive layout: window size, panel rectangles, compact mode |
| `InputManager` | `scripts/autoload/input_manager.gd` | Device tracking, focus scopes and keyboard/gamepad navigation |
| `TouchInput` | `scripts/autoload/touch_input.gd` | Turns touch gestures into clicks, pans and pinch zoom |
| `GameManager` | `scripts/autoload/game_manager.gd` | Money, reputation, day and time, game mode, speed, economy rules |
| `EventBus` | `scripts/autoload/event_bus.gd` | Signal hub for all cross-system events |
| `WorldMap` | `scripts/autoload/world_map_state.gd` | Company world: owned locations, unlocked land, active site |
| `SaveManager` | `scripts/autoload/save_manager.gd` | Saves and loads the game (see [Save & Load](save-and-load.md)) |
| `InputBindings` | `scripts/autoload/input_bindings.gd` | Rebindable course controls, their defaults and saved overrides |
| `FeedbackManager` | `scripts/autoload/feedback_manager.gd` | Daily golfer satisfaction and feedback totals |
| `ShadowSystem` | `scripts/systems/shadow_system.gd` | Shared shadow direction and intensity |
| `UIConstants` | `scripts/autoload/ui_constants.gd` | Shared sizes, spacing and colours |
| `TooltipManager` | `scripts/autoload/tooltip_manager.gd` | Tooltip display |
| `SoundManager` | `scripts/autoload/sound_manager.gd` | Sound effects |
| `EventFeedManager` | `scripts/managers/event_feed_manager.gd` | Event feed log (see [Event Feed](systems/events/event-feed.md)) |
| `GolferSkins` | `scripts/autoload/golfer_skins.gd` | Loads and saves golfer skins (see [Golfer Skins](golfer-skins.md)) |

---

## Key Patterns

- **Signals over references.** Systems talk through `EventBus`. Past-tense names describe things that happened, such as `golfer_finished_hole`. Present-tense names describe state, such as `money_changed`.
- **Manager per entity group.** `GolferManager`, `BallManager` and `HoleManager` create, track and remove their objects. Managers are nodes in `main.tscn`.
- **Stateless systems.** `WindSystem`, `WeatherSystem` and `CourseRatingSystem` hold little or no state and expose calculations as static functions. This makes them easy to test.
- **Data-driven content.** Buildings, decorations, terrain and visiting golfers are loaded from JSON in `data/`. Terrain properties are the exception. They live in `terrain_types.gd`, and `terrain_types.json` only mirrors them.
- **Overlay per visual effect.** Each terrain effect (water, bunkers, fairways, trees) is its own overlay class, managed by `TerrainGrid`.
- **State machines.** Golfers move between `IDLE`, `WALKING`, `PREPARING_SHOT`, `SWINGING`, `WATCHING`, `LEAVING` and `FINISHED`, as defined in `golfer.gd`. Balls have their own states, such as in flight and rolling.

---

## Main Scene

`scenes/main/main.tscn` is the root scene. `scripts/main/main.gd` is attached to its `Main` node.

```
Main (Node2D)                      main.gd
├── TerrainGrid (Node2D)           terrain_grid.gd: draws the course surface and overlays
├── Entities (Node2D)
│   ├── Golfers, Balls, Buildings  containers for live objects
├── GolferManager, BallManager, HoleManager (Node)
├── PlayerGolferManager (Node)        the owner's own golfer and the ground they work
├── Holes (Node2D)                 hole visuals
├── IsometricCamera (Camera2D)
└── UI (CanvasLayer)
    └── HUD (Control)              status column, bottom bar, panels, toasts
```

The main scene is set in `project.godot` as `res://scenes/main/main.tscn`.

### Startup

`main.gd` builds the scene in seven steps (`STARTUP_STEPS`): the content
catalogs, the course layer, the managers, the HUD, the panels, the screens that
drive a course, and the title screen last. Every step is a group of setup calls
small enough to run between two frames, and `_ready()` walks them.

On a native build that walk is a plain sequence: it finishes inside `_ready()`
before the first frame, and with it the engine's boot splash stays up, so
nothing half-built is ever seen. On the web the scene spreads the same steps
over frames — one per step — because the loading screen there is the exported
page's own HTML (`web/custom_shell.html`): while the engine holds the thread the
page cannot repaint, so a startup that ran in one go would leave the loader
frozen on the last thing it painted. Between slices the game reports the step to
that page through `WebBoot` (`scripts/utils/web_boot.gd`, see
[UI & Controls](ui-and-controls.md#boot-splash)), which keeps the stage line
moving, and it tells the page when the title screen is really up — the engine's
own `startGame()` promise resolves as soon as the engine has set up its main
loop, long before the menu exists.

A native build can take the same path with the `--split-startup` command-line
argument (`godot --path . -- --split-startup`), which is how the browser's
behaviour is reproduced without a browser.
`tests/integration/ui_and_controls/test_startup_slices.gd` covers it.

---

## Draw Order

Canvas items are drawn by band, not by the order they are added: `z_index` resolves
against the parent's band (`z_as_relative` on by default), and items sharing a band
use world Y-sorting for standing sprites, and tree order for ground detail:

| Band | What paints there |
| --- | --- |
| 0 | The course surface (`CourseSurface`): turf, sand, water, stones — and the ground decals a golfer wears (the tier ring, `-2` from the golfer's band) |
| 1 | Ground detail painted over the surface, bottom-up in the order `TerrainGrid.GROUND_DETAIL_ORDER` ranks them: flowers, the walking trail (`WalkingPathOverlay`), and the wildlife that wanders through it all — plus a golfer's shadow and active-shot highlight ring (`-1`) |
| 2 | Entities: golfers (`scenes/entities/golfer.tscn`) trees, staff, and the buildings and decorations layer (`entity_layer.gd`) |
| 3 | Weeds |
| 4-6 | Course-editing helpers drawn over the ground: elevation preview (4), land boundary (5), cup (6) |
| 10 | Hole visuals (`hole_visualizer.gd`) and the routing overlay; a golfer's name label rides `+10` from its own band |
| 50 | Flags and shot trails |
| 100 | The ball, floating text, the rain overlay, and the UI that paints on the course (placement preview, tile inspector) |
| 150-300 | Impact and celebration effects |

The UI is a `CanvasLayer`, so it always draws over the world whatever band it uses.

Standing sprites share a Y-sort chain through Main, TerrainGrid/TreeOverlay,
Entities/Golfers/Staff, and EntityLayer/Buildings/Decorations. All standing bodies
resolve to z 2, allowing Godot to interleave them across containers. Higher screen
Y draws in front. Trees have one CanvasItem per tile, anchored at ground level;
building visuals sort at the footprint centre while their art keeps its original
placement. View rotation refreshes the anchors along with the sprites. Tree
materials additionally sample the same heightfield as the course surface: ground
in front of a tree clips only the covered sprite pixels, leaving a crown that
extends above or in front of a hill visible. Shadows, rings, labels, and gameplay
overlays retain their separate relative bands.

`tests/unit/golfers/test_golfer_draw_order.gd` protects ground visibility and
`tests/unit/course_design/test_terrain_draw_order.gd` covers tree anchors and bands.

---

## Related

- [UI & Controls](ui-and-controls.md) lists the screens and keys.
- [Save & Load](save-and-load.md) covers what is stored.
- [Data Reference](data-reference.md) lists the data files.
- [Systems Index](systems/README.md) lists every game system.
