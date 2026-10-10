# UI & Controls

> The screens, panels and keyboard, mouse and touch controls. The keyboard list comes from the in-game hotkey panel, which is the source of truth.

**Source:** `scripts/ui/hotkey_panel.gd` (in-game shortcut list), `scripts/main/main.gd` (key handling), `scripts/autoload/touch_input.gd`, `scripts/autoload/screen_manager.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/start_new_game_screen.gd`, `project.godot` (input actions)
**Tests:** `tests/unit/test_pause_system.gd`, `tests/unit/test_touch_input.gd`, `tests/unit/test_responsive_panels.gd`

---

## Screens

- **Main menu.** Headed by the game logo (`assets/ui/logo.png`). Start New Game, Quick Start, Continue, Load Game, Settings and Quit.
- **Start New Game.** Company name (or roll for a random one), difficulty (Easy, Normal or Hard), starting money ($100K, $150K, $200K or Unlimited), generated holes, and the Weather, Wind and Seasons options.
- **Quick Start.** Jumps to the World Map with the defaults.
- **World Map.** A spinning globe with a pin for each destination, a list of locations, Buy and Play, and Reset World. See [World Map](systems/economy-and-land/world-map.md).
- **Pause menu.** Resume, Settings, Save and Quit. The camera still moves while paused.
- **Settings.** Display, audio and gameplay options.
- **Golfer Skins studio.** Paint the golfers' clothing. See [Golfer Skins](golfer-skins.md).

## In-Game Panels

| Panel | How to open |
| --- | --- |
| Financial dashboard | Click the money display |
| Tournament panel | From the HUD |
| Event feed | From the HUD |
| Hotkey reference | `F1` |
| Year in Review | Opens automatically at year end |
| Tool palette | Tool buttons along the bottom bar |

## Keyboard

### Camera

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | Pan the camera |
| Middle mouse drag | Pan the camera |
| Mouse wheel, `[` and `]` | Zoom |
| `Q` and `Shift+Q` | Rotate the view |
| `Tab` | Toggle the minimap |
| `V` | Toggle the heatmap. `Shift+V` changes the heatmap mode |

### Game

| Key | Action |
| --- | --- |
| `Space` | Pause or resume |
| `Ctrl+S` | Quick save |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Esc` | Cancel the current tool or close a panel |
| `F1` | Hotkey help |
| `F2` | Weather debug |
| `F3` | Debug overlay |
| `F4` | Season debug |
| `Shift+R` | Toggle the routing overlay |
| `J` | Fairway width overlay |

### Tools

| Key | Action |
| --- | --- |
| `1` to `9`, `0` | Terrain tools |
| `Shift+2`, `Shift+5` to `Shift+9`, `Shift+0`, `Shift+F` | More terrain tools (Shift+9 Small Boulders, Shift+0 Large Boulders) |
| `T`, `B`, `O`, `H`, `X` | Tool shortcuts. `T` is the Tee Box tool and `H` is Open Hole. |
| `=`, `.`, `E`, `P` | Switch the tabs |
| `V`, `+`, `-` | Elevation tools |
| `F`, `U`, `L`, `M`, `Z`, `G`, `C`, `N` | Management shortcuts |

Tool shortcuts are also shown on each tool's tooltip. The hotkey panel (`F1`) is the full, authoritative list.

## Mouse and Touch

- **Mouse.** Left click places or selects. Right click cancels or opens a context menu. The wheel zooms.
- **Touch.** A tap is a click. One-finger drag pans, or paints terrain while a tool is active. Two-finger drag pans and pinches to zoom. A two-finger tap cancels or closes menus.

## Layout

`Screen` chooses a compact layout on small windows. Panels then take the full width, and the bottom bar grows to fit touch. The main window is 1600 × 1000 on desktop.

## Related

- [Architecture](architecture.md) explains how the HUD fits into the scene.
- [Systems Index](systems/README.md) links to the systems behind each panel.
