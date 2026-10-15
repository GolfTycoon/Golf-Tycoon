# UI & Controls

> The screens, panels and keyboard, mouse and touch controls. The keyboard list comes from the in-game hotkey panel, which is the source of truth.

**Source:** `scripts/ui/hotkey_panel.gd` (in-game shortcut list), `scripts/main/main.gd` (key handling), `scripts/autoload/touch_input.gd`, `scripts/autoload/screen_manager.gd`, `scripts/ui/hud_status_column.gd` (status column), `scripts/ui/main_menu.gd`, `scripts/ui/components/pixel_button_style.gd`, `scripts/ui/components/pixel_icon.gd`, `scripts/ui/components/setup_glyph.gd`, `scripts/ui/components/course_plan_preview.gd`, `scripts/ui/start_new_game_screen.gd`, `scripts/ui/save_load_panel.gd`, `scripts/ui/settings_menu.gd`, `project.godot` (input actions)
**Tests:** `tests/unit/test_pause_system.gd`, `tests/unit/test_touch_input.gd`, `tests/unit/test_responsive_panels.gd`, `tests/unit/ui_and_controls/test_hud_status_column.gd`, `tests/unit/test_save_load_settings_layout.gd`, `tests/unit/ui_and_controls/test_pixel_button_style.gd`, `tests/unit/ui_and_controls/test_pixel_icon.gd`, `tests/unit/ui_and_controls/test_main_menu_typography.gd`, `tests/unit/ui_and_controls/test_start_new_game_layout.gd`, `tests/unit/ui_and_controls/test_start_new_game_visual_style.gd`, `tests/harness/save_settings_layout_harness.tscn`

---

## Screens

- **Boot splash.** The engine's boot splash (`application/boot_splash/*` in `project.godot`) shows `assets/ui/boot_splash.png` before the main scene loads: the same clubhouse artwork the out-of-game screens sit on (`assets/ui/background.jpeg`, drawn the same cover-fit way), the game logo on top of it, and a "Made with" line beside the Godot logo near the bottom edge. The image is read straight from the PNG file, so it is on screen before any resource is imported, and it stretches in Cover mode (`boot_splash/stretch_mode=4`) so the artwork fills any window shape with no letterbox bars, cropping the overflow exactly like `MenuBackdrop` does in-game. While it is up the window clears to the deep clubhouse green (`boot_splash/bg_color`). (Godot's web exporter never shows the boot splash — there the HTML shell's own loader screen stands in for it, see `web/custom_shell.html`.)
- **Main menu.** Headed by the game logo (`assets/ui/logo.png`). Start New Game, Quick Start, Continue, Load Game, Settings and Quit. Every card and tile is a pixel-art sprite window (`PixelButtonStyle`): notched corners instead of rounded ones, an ink outline, a two-pixel accent trim and a bevel lit from above over a flat translucent fill, generated as nine-patch textures so the border stays crisp at any window size. Hover brightens the trim, pressing flips the bevel so the card sinks, focus floats a notched ring clear of the frame, and a disabled card greys out. Each action also carries a 16x16 sprite of its own (`PixelIcon`), painted in the card's accent: a pennant for Start New Game, a lightning bolt for Quick Start, the play triangle for Continue, a floppy disk for Load Game, a polo shirt for Golfer Skins, a cog for Settings and a doorway arrow for Quit. Sprites scale in whole multiples of their grid so their pixels stay square; the squat and phone layouts drop them together with the tile captions, because a tile too narrow for a sentence is too narrow for an emblem. Every word on the screen is set in Pixelify Sans (`assets/fonts/`, SIL Open Font License 1.1): the hero and Continue card titles in the bold weight, the compact utility tiles in the semibold one, and the card captions, the rail kicker and the version line in the regular one, so the type reads as part of the same pixel art.
- **Start New Game.** Company name (or roll for a random one), difficulty (Easy, Normal or Hard), starting money ($100K, $150K, $200K or Unlimited), generated holes, the Weather, Wind and Seasons options, and a **Guided tutorial** switch. It shares the title menu's `MenuBackdrop`, notched `PixelButtonStyle` frames, Pixelify Sans typography and nearest-filtered sprite art; its choice cards light their accent when selected, the company field and course plan sit in recessed pixel frames, and the gold Choose Location action keeps the same chunky bevel. Setup-specific icons (difficulty, money, weather, wind, seasons, dice, check, switch, arrow and tutorial book) are hard-edged character-grid sprites. The switch sits in the title bar on the wide and landscape layouts and under its own heading on tablets and phones. The tutorial only walks an empty first course, so with generated holes the switch is faded and the summary reads "Not used". See [World Map](systems/economy-and-land/world-map.md#the-guided-tutorial).
- **Quick Start.** Uses the defaults (random company name, Normal, $100,000, all features off, 3 generated holes), buys a random location the company can afford and starts playing it straight away.
- **World Map.** A spinning globe with a pin for each destination, a list of locations each with a **Buy & Play** button (or **Play** once owned), a selected-site dossier with **Buy** beside **Buy & Play**, and Reset World — dressed in the same pixel-art language as the title screen and Start New Game: notched `PixelButtonStyle` frames on every card, button and field, Pixelify Sans throughout (bold for the heading, treasury and call to action, semibold for names, kickers and buttons, regular for captions), `PixelIcon` sprites for the treasury coin, the per-location pennants and the map legend, and the golf-flag `MenuFlagMark` itself drawn as a 16x16 sprite. The globe is the planet shader run in `GlobeMap.LandStyle.PIXEL`: every fragment resolves into a chunky hard-edged cell in the menu palette (deep ink-teal sea, golf-green land, sandy tropics), using detailed Natural Earth 1:50m coastlines with islands and lake rings; destinations are sprite pins (gold-bracketed when selected) whose hover tags are little notched pixel frames. It opens from the **World Maps** button under **Manage → Maps**, and from Start New Game / Quick Start. The course behind it freezes while the globe is up, so switching sites never loses a day's work. See [World Map](systems/economy-and-land/world-map.md).
- **Pause menu.** Resume, Save Game, Load Game, Settings, Quit to Menu and Quit to Desktop. The camera still moves while paused.
- **Settings.** Four categories (Audio, Display, Gameplay, Controls) laid out for each window size. Desktop uses a category rail, the control cards and an "at a glance" panel. Tablets keep the rail beside or above the cards. Phones use four equal category tiles and one scrolling column. Changes apply immediately and save to `user://settings.cfg`. The Controls category includes the keyboard shortcut reference.
- **Save and Load.** One archive with a Save or Load mode. Save names a checkpoint and asks before replacing one. Load shows the selected course's day, balance, holes and last-played time, and asks before replacing the live course. Saving is offered only from the pause menu. The title screen and game-over panel can only load.
- **Golfer Skins studio.** Paint the golfers' clothing. See [Golfer Skins](golfer-skins.md).

## In-Game Panels

| Panel | How to open |
| --- | --- |
| Financial dashboard | Manage → Review → Financial Overview, or click the money display |
| Tournament panel | From the HUD |
| Event feed | From the HUD |
| Hotkey reference | `F1` |
| Year in Review | Opens automatically at year end |
| Tool palette | Tool buttons along the bottom bar |

### Bottom dock

The bottom-left corner uses small pixel-art circle buttons for **Menu**, **Feed**,
**Inspect**, both rotation directions, and **Pause / Play / Fast**. The fast button
cycles between 3× and 8×; a cream tick marks Ultra and a lit ring marks the active
speed. The heading letter stays between the rotation arrows. Feed lights a gold
unread indicator, with the count in its tooltip.

Three larger circles curve around these controls: **Build** (largest), **Manage**,
and **Golfers**. Each opens a bottom shelf with small icon tabs down its left edge.
The selected section and tab stay lit, and the shelf heading names the current
page. Switching sections remembers the last tab used in each.

| Section | Tabs and actions |
| --- | --- |
| Build | Terrain, Improvements, Buildings, Elevations, Holes |
| Manage | Maps (World Maps, Land); Review (Review, Scorecard, Financial Overview); Milestone; Marketing; Staff |
| Golfers | Visiting Golfers, Play Course, Edit Player Golfer, Player Golfer Skills |

The player pages share the existing live round and retain their state when tabs
change. Unspent skill points appear on the skills tab. Keyboard shortcuts still
work; selecting a build tool reveals its section automatically. Shelves scroll
horizontally while the circle controls remain fixed. Hover/focus states, tooltips
and accessible names identify every icon; Tab and Enter can navigate the dock.

### Status column

The top-right corner carries a compact status column (`HUDStatusColumn`) instead of a full-width top bar, so the whole top edge stays free for the course view. Its rows, top to bottom:

| Row | Shows |
| --- | --- |
| Game mode | `PLAYING` or `PAUSED`, with the collapse toggle (`-` / `+`) beside it |
| Funds | The balance, clickable for the financial dashboard |
| Date | The calendar date |
| Season | The current season |
| Reputation | Course reputation, clickable for the rating details |
| Rating | The star rating, clickable for details |
| Weather | The current conditions |
| Wind | Direction and speed |

The Weather, Wind and Seasons rows appear only while their feature is on: with a feature off (the Start New Game options — all three start off on a quick start) that row is left out of the column rather than shown reading "Off" or "Year-round", and the divider that introduces the weather and wind pair goes with the last of the two rows. The column collapses to its header and Funds rows on compact windows, or when the player presses the collapse toggle; the full set of rows is still there, minus the features that are off.

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
- **Touch.** A tap is a click. One-finger drag pans, or paints terrain while a tool is active. Two-finger drag pans and pinches to zoom; a two-finger tap cancels or closes menus. Dragging a scrollable shelf or panel scrolls it instead of moving or painting the course, and dragging off a button cancels its tap. The minimap can be scrubbed with a finger, and the paused game's dimmed backdrop still supports pan and pinch. Compact windows and touchscreen devices get 44px utility controls, larger toolbar tabs, and a taller dock so the controls are easier to reach.

## Layout

`Screen` chooses a compact layout on small windows. Panels then take the full width, and the bottom bar grows to fit touch. The main window is 1600 × 1000 on desktop.

## Related

- [Architecture](architecture.md) explains how the HUD fits into the scene.
- [Systems Index](systems/README.md) links to the systems behind each panel.
