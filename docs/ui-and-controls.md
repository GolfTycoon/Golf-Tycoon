# UI & Controls

> The screens, panels and keyboard, mouse and touch controls. The keyboard list comes from the in-game hotkey panel, which is the source of truth.

**Source:** `scripts/autoload/input_manager.gd` (device tracking, focus scopes and navigation), `scripts/autoload/input_bindings.gd` (the rebindable control registry and its saved overrides), `scripts/ui/components/gamepad_cursor.gd` (keyboard/controller pointer), `scripts/ui/components/input_hint_bar.gd` (device prompts), `scripts/ui/hotkey_panel.gd` (in-game shortcut list), `scripts/main/main.gd` (key and controller handling), `scripts/autoload/touch_input.gd`, `scripts/autoload/screen_manager.gd`, `scripts/ui/hud_status_column.gd` (status column), `scripts/ui/components/course_rating_stars.gd` (status column star strip), `scripts/ui/main_menu.gd`, `scripts/ui/generating_course_screen.gd`, `scripts/ui/components/pixel_button_style.gd`, `scripts/ui/components/pixel_icon.gd`, `scripts/ui/components/setup_glyph.gd`, `scripts/ui/components/course_plan_preview.gd`, `scripts/ui/start_new_game_screen.gd`, `scripts/ui/save_load_panel.gd`, `scripts/ui/settings_menu.gd`, `scripts/utils/isometric_camera.gd`, `scripts/systems/player_data_store.gd`, `scripts/systems/performance_benchmark.gd`, `scripts/systems/benchmark_history.gd`, `scripts/ui/benchmark_results_screen.gd`, `scripts/ui/components/benchmark_visuals.gd`, `project.godot` (input actions)
**Tests:** `tests/unit/ui_and_controls/test_input_manager.gd`, `tests/unit/ui_and_controls/test_input_bindings.gd`, `tests/integration/ui_and_controls/test_editable_controls.gd`, `tests/integration/ui_and_controls/test_gamepad_and_keyboard_screens.gd`, `tests/integration/ui_and_controls/test_gamepad_gameplay.gd`, `tests/integration/ui_and_controls/test_gamepad_every_screen.gd`, `tests/unit/test_pause_system.gd`, `tests/unit/test_touch_input.gd`, `tests/unit/ui_and_controls/test_pause_menu_touch.gd`, `tests/unit/ui_and_controls/test_game_over_touch.gd`, `tests/integration/ui_and_controls/test_touch_quit_to_menu.gd`, `tests/unit/test_responsive_panels.gd`, `tests/unit/ui_and_controls/test_hud_status_column.gd`, `tests/unit/ui_and_controls/test_course_rating_stars.gd`, `tests/unit/test_save_load_settings_layout.gd`, `tests/unit/ui_and_controls/test_pixel_button_style.gd`, `tests/unit/ui_and_controls/test_pixel_icon.gd`, `tests/unit/ui_and_controls/test_main_menu_typography.gd`, `tests/unit/ui_and_controls/test_start_new_game_layout.gd`, `tests/unit/ui_and_controls/test_start_new_game_visual_style.gd`, `tests/unit/ui_and_controls/test_performance_benchmark.gd`, `tests/unit/ui_and_controls/test_benchmark_history.gd`, `tests/unit/ui_and_controls/test_benchmark_results_screen.gd`, `tests/integration/ui_and_controls/test_save_and_settings_screens.gd`, `tests/unit/ui_and_controls/test_graphics_quality_settings.gd`, `tests/unit/ui_and_controls/test_camera_edge_panning.gd`, `tests/unit/ui_and_controls/test_player_data_store.gd`, `tests/harness/save_settings_layout_harness.tscn`

---

## Screens

**Shared screen chrome.** Every in-game screen (Start New Game, World Map, Course Map, Settings, Save and Load, Benchmark Results, Milestones, Achievements, Financial Overview, Golfer Skins, Generating Course, Credits and the pause and game-over panels) is built from the same parts in `scripts/ui/components/menu_screen_kit.gd` (`MenuScreenKit`), so the screens share one layout and one look:

- **Layout modes.** One `MenuScreenKit.LayoutMode` with five shapes: `DESKTOP`, `TABLET_LANDSCAPE`, `TABLET_PORTRAIT`, `PHONE_LANDSCAPE` and `PHONE_PORTRAIT`, picked by `layout_mode_for(view)` from the same breakpoints everywhere. `is_tablet` and `is_compact` group the shapes; `outer_padding` and `page_separation` set the spacing for each.
- **Screen header.** `make_screen_header` builds the same top bar on every screen: a **Back** button on the left (`BackButton`, a utility card with a `‹` chevron), the golf-flag `MenuFlagMark`, a title block (gold kicker, bold title, subtitle) and an optional trailing group on the right (a treasury chip, an autosave chip, a tab row or a switch). Node names are fixed (`ScreenHeader`, `BackButton`, `FlagMark`, `TitleBlock`, `Kicker`, `Title`, `Subtitle`, `Trailing`).
- **Buttons.** `paint_utility_button` for secondary actions and Back, `paint_action` for the gold primary call to action, `paint_danger_button` for destructive actions such as Delete and Quit and `paint_toggle` for on/off switches. All of them use the notched `PixelButtonStyle` frames.
- **Cards and panels.** `make_panel` and `padded_panel` build the notched pixel frame. `MenuStyle.panel`, `paint_card`, `paint_choice` and `paint_primary` delegate to `PixelButtonStyle`, so the older helpers draw the same frames.
- **Type.** Pixelify Sans throughout. `make_title_label` for titles, `make_kicker` for the small gold captions above a section, and `make_label` for body text.
- **Chips and sprites.** `make_chip` for status chips, `make_track_switch` for the track switch, `make_sprite` for `PixelIcon` sprites, and `PixelBar` for meters. Money is formatted with `format_money` and `format_money_compact`.
- **Backdrop.** Each screen sits over the same `MenuBackdrop` clubhouse artwork as the title screen.

- **Boot splash.** The engine's boot splash (`application/boot_splash/*` in `project.godot`) shows `assets/ui/boot_splash.png` before the main scene loads: the same clubhouse artwork the out-of-game screens sit on (`assets/ui/background.jpeg`, drawn the same cover-fit way), the game logo on top of it, and a "Made with" line beside the Godot logo near the bottom edge. The image is read straight from the PNG file, so it is on screen before any resource is imported, and it stretches in Cover mode (`boot_splash/stretch_mode=4`) so the artwork fills any window shape with no letterbox bars, cropping the overflow exactly like `MenuBackdrop` does in-game. While it is up the window clears to the deep clubhouse green (`boot_splash/bg_color`). (Godot's web exporter never shows the boot splash — there the HTML shell's own loader screen stands in for it, see `web/custom_shell.html`.) The game drives that loader through `WebBoot` (`scripts/utils/web_boot.gd`): the main scene builds itself in seven steps, a frame apart, reporting each one between slices, so the loader's stage line — *Loading the clubhouse*, *Surveying the grounds*, *Setting up the clubhouse*, *Opening the first tee* — keeps moving instead of freezing on the last thing the page painted before the engine took the thread. The loader stays up until the game says the title screen is really there (the engine's own start signal fires as soon as the engine is up, long before the menu exists), adds a word of reassurance after a long wait, and hands the canvas back regardless after a minute. See [Architecture](architecture.md#startup).
- **Main menu.** Headed by the game logo (`assets/ui/logo.png`). Start New Game, Quick Start, Continue, Load Game, Settings and Quit. Every card and tile is a pixel-art sprite window (`PixelButtonStyle`): notched corners instead of rounded ones, an ink outline, a two-pixel accent trim and a bevel lit from above over a flat translucent fill, generated as nine-patch textures so the border stays crisp at any window size. Hover brightens the trim, pressing flips the bevel so the card sinks, and keyboard/controller focus adds an ink-edged cream outline and a light wash across the card. This focus highlight is distinct from hover and from an already-chosen option; disabled cards grey out and are skipped by navigation. Each action also carries a 16x16 sprite of its own (`PixelIcon`), painted in the card's accent: a pennant for Start New Game, a lightning bolt for Quick Start, the play triangle for Continue, a floppy disk for Load Game, a polo shirt for Golfer Skins, a cog for Settings and a doorway arrow for Quit. Sprites scale in whole multiples of their grid so their pixels stay square; the squat and phone layouts drop them together with the tile captions, because a tile too narrow for a sentence is too narrow for an emblem. Every word on the screen is set in Pixelify Sans (`assets/fonts/`, SIL Open Font License 1.1): the hero and Continue card titles in the bold weight, the compact utility tiles in the semibold one, and the card captions and the version line in the regular one, with the rail kicker in the shared gold semibold caption style, so the type reads as part of the same pixel art.
- **Start New Game.** Company name (or roll for a random one), difficulty (Easy, Normal or Hard), starting money ($100K, $150K, $200K or Unlimited), generated holes, the Weather, Wind and Seasons options, and a **Guided tutorial** switch. It shares the title menu's `MenuBackdrop`, notched `PixelButtonStyle` frames, Pixelify Sans typography and nearest-filtered sprite art; its choice cards light their accent when selected, the company field and course plan sit in recessed pixel frames, and the gold Choose Location action keeps the same chunky bevel. Setup-specific icons (difficulty, money, weather, wind, seasons, dice, check, switch, arrow and tutorial book) are hard-edged character-grid sprites. The switch sits in the title bar on the wide and landscape layouts and under its own heading on tablets and phones. The tutorial only walks an empty first course, so with generated holes the switch is faded and the summary reads "Not used". See [World Map](systems/economy-and-land/world-map.md#the-guided-tutorial).
- **Quick Start.** Uses the defaults (random company name, Normal, $100,000, all features off, 3 generated holes), buys a random location the company can afford and starts playing it straight away. The Generating Course screen appears first with **Finding a location**, before the world and course are prepared; it then names the chosen course and follows the same job through generation. Repeated activation and gameplay shortcuts are ignored while it is loading. If no location is affordable, the loader closes and the World Map opens instead.
- **World Map.** A spinning globe with a pin for each destination, a list of locations each with a **Buy & Play** button (or **Play** once owned), a selected-site dossier with **Buy** beside **Buy & Play**, and Reset World — dressed in the same pixel-art language as the title screen and Start New Game: notched `PixelButtonStyle` frames on every card, button and field, Pixelify Sans throughout (bold for the heading, treasury and call to action, semibold for names, kickers and buttons, regular for captions), `PixelIcon` sprites for the treasury coin, the per-location pennants and the map legend, and the golf-flag `MenuFlagMark` itself drawn as a 16x16 sprite. The globe is the planet shader run in `GlobeMap.LandStyle.PIXEL`: every fragment resolves into a chunky hard-edged cell in the menu palette (deep ink-teal sea, golf-green land, sandy tropics), using detailed Natural Earth 1:50m coastlines with islands and lake rings; destinations are sprite pins (gold-bracketed when selected) whose hover tags are little notched pixel frames. It opens from the **World Maps** button under **Manage → Club → Maps**, from Start New Game, and from Quick Start if no location is affordable. The course behind it freezes while the globe is up, so switching sites never loses a day's work. On a touchscreen, one finger spins the globe and two fingers pinch open or closed to zoom, moving together to spin it as well; letting go of a pinch never selects the pin under a finger. See [World Map](systems/economy-and-land/world-map.md).
- **Financial Overview.** A fullscreen clubhouse dashboard over the same `MenuBackdrop` as the World Map. Desktop lays out the year-to-date ledger, course controls and status, and marketing campaigns side by side. Tablet and phone layouts use a fixed three-page rail (**Finances**, **Course**, **Marketing**) above a scrollable workspace; phone landscape keeps the same pages in a compact, short-screen composition. It carries forward the balance, revenue and expense breakdown, year-over-year comparison, booking interval, green-fee controls and warning, reputation, golfer count, loans, seasonal forecast and official course ratings, alongside marketing reach, daily spend, campaign history, active campaign timers and all five launch offers. Open it from the money display or **Manage → Club → Review → Financial Overview**; **M** opens it directly on the Marketing page. The World Map's clubhouse artwork, pixel-framed cards and Pixelify Sans styling are shared throughout.
- **Course Map.** The whole course in one isometric diamond, in the title screen's own dress. Its header is the shared screen header: Back on the left, and the mode tabs, treasury and Details on the right: the `MenuBackdrop` clubhouse artwork behind it, notched `PixelButtonStyle` frames, Pixelify Sans type. Four modes sit across the top on desktop and portrait shapes (a compact rail on landscape ones): **Land** (buy parcels, read the ones you own), **Routing** (reorder the holes, flip them, set par, open or shut them), **Aura** (green, amber and red cells where golfers were happy and unhappy) and **Staff** (each employee's working area, hiring, firing and posting them). One line under the map says what is picked or what the map is waiting for, with the mode's own **Buy** / **Cancel** / **Clear** beside it. Drag to pan, wheel or pinch to zoom, `F` to frame the course. On phones the panel is a bottom sheet that peeks and lifts (portrait) or slides in over the map (landscape); on a landscape tablet it folds away behind a **Hide**/**Show** toggle. The course freezes while the map is up. See [Course Map](systems/course-design/course-map.md).
- **Pause menu.** Resume, Save Game, Load Game, Settings, Quit to Menu and Quit to Desktop. The camera still moves while paused.
- **Settings.** Audio, Display, Controls and Data are laid out for each window size. Desktop uses a category rail beside the control cards. Tablets keep the rail beside or above the cards. Phones use equal category tiles and one scrolling column. Changes apply immediately and save to `user://settings.cfg`. The Controls category is the editor for every course control: click a keycap, press a key or controller button, and the change applies at once. It also carries screen-edge panning (**Edge Panning**: pan the camera by moving the pointer to the edge of the window, or leave the course still until you drag, press the keys or use the stick), the camera zoom inversion, the zoom limits, a reset per action and **Reset All Controls**. Display includes an **FPS Counter** card: the counter is off by default, and can be shown over menus and the course (even while paused) with a choice of position, text size and refresh interval (0.25, 0.5 or 1 second). It averages frames over real elapsed time, ignores mouse and touch input, and is independent of graphics presets. Display also has the **Course HUD** card (with the **Minimap** toggle to enable or disable the corner minimap), window mode, VSync, UI scale, colourblind palettes, the graphics quality preset and its individual controls (see [Graphics quality](#graphics-quality)), and the **Benchmark** card, which runs only when Settings was accessed from the Main Menu (Settings from the pause menu shows the last run and the past results but runs nothing, so a game in progress is never the test scene). The card carries two buttons: **Run Benchmark**, which closes the menus and runs the full course tour - a throwaway benchmark course prepared (preparation included in the measurement), then every fixed test course built and played on it, about 95 seconds - and **Past Results**, which opens the Benchmark Results screen over the menus. Above them the card shows the rating the last run earned - five stars and a segmented score meter. For fair comparisons, run the tour from Main Menu Settings at the same resolution, VSync and power mode. See [Device Benchmark](development/benchmark.md). The Data category is the on-device privacy page: it lists what is stored (saved courses, preferences, career records, benchmark reports and custom golfer skins), gives each group its own **Delete** button and offers one **Delete All Player Data** action at the end. Every deletion asks first on a confirm card whose safe answer has focus, the page is rebuilt afterwards so each line and button tells the truth about what is left, and the title screen's Continue card is refreshed from the save list that remains. Deleting the saved courses during a pause session closes the course and returns to the title screen, because it has nowhere left to autosave. Mods are left to the Mods screen, where they can be uninstalled safely; see [Save & Load](save-and-load.md#deleting-player-data).
- **Benchmark Results.** A fullscreen device dashboard over the same `MenuBackdrop` as the World Map, opened from the Display card's **Past Results**. Desktop spreads the report across three columns - the rating and the device dossier on the left, a frame-time oscilloscope with the GPU load ladder and the engine and memory read-out in the middle, the metric meters, the golf-style performance scorecard and the shelf of past runs on the right - and a full-height window shows all of it without scrolling. Tablets pair the rating with the meters above the charts; phones fold everything into one scroll, or into two columns when the phone is turned sideways. The charts are drawn in whole pixels (`BenchmarkVisuals`): one chunky column per sampled frame in mint, gold and muted red against the 60 FPS budget and the 33 ms stutter line, the GPU ladder and the run history as bars, and a segmented meter per metric. Reached from Main Menu Settings its **Run Benchmark** starts the tour again (from anywhere else it is read-only: Run stands down, and the report, the shelf and **Copy report** still work), it keeps the last twelve runs on a local shelf to compare against, and **Esc** closes it. Each run on that shelf is a button: press one and the whole screen becomes that run - its report, its oscilloscope, its scorecard, its tour table and its device dossier - with the picked row lit and a **PAST RUN** chip on the rating while an older run is on screen, and **Copy report** copies the run being read. A run recorded before reports were kept keeps its numbers and its bar on the chart but cannot be opened, and says so. See [Device Benchmark](development/benchmark.md).
- **Save and Load.** One archive with a Save or Load mode. Save names a checkpoint and asks before replacing one. Load shows the selected course's day, balance, holes and last-played time, and asks before replacing the live course. Saving is offered only from the pause menu. The title screen and game-over panel can only load.
- **Golfer Skins studio.** Paint the golfers' clothing. See [Golfer Skins](golfer-skins.md).

### Graphics quality

**Settings → Display → Performance & Scale** carries a **Graphics quality preset** and every component it writes. A preset sets them all at once; changing any one component turns the label to **Custom** and leaves the others alone. **Auto** picks Performance on phones, Web and four-core-or-smaller devices and Balanced everywhere else. Changes apply immediately and are saved to `user://settings.cfg` (`display/graphics_preset` and the `graphics` section), so an older settings file simply keeps the shipped values.

| Control | Choices | What it spends |
| --- | --- | --- |
| Terrain rendering | Fast, Full | The surface shader's heightfield ray and relief lighting |
| Grass blades | Off, Full | The per-tile grass overlay and its redraws |
| Terrain-aware tree occlusion | Off, On | The silhouette shader that hides a bare trunk behind a hill |
| Water shimmer detail | Reduced, Full | The animated water detail and its redraws |
| Wind flag outlines | Reduced, Full | The outlined flag outline pass |
| Prop & ball shadows | Off, Contact only, Full | One polygon per prop for the contact blob, a second for the stretched sun shadow |
| Course wildlife | Off, Reduced, Full | Duck families and butterflies: half the residents at Reduced, none at Off |
| Impact particle effects | Off, Reduced, Full | The sand, water and landing bursts, and the nodes and tweens each one builds |
| Decorative animation rate | Low, Standard, High (4, 15, 30 Hz) | How often flags, water, wildlife and golfer trims repaint |
| Camera redraw rate | Low, Standard, High (15, 30, 60 Hz) | How often the ground overlays repaint while the camera reaches new tiles (a pan inside one tile window repaints nothing) |
| Golfer coordination rate | Low, Standard, High (15, 30, 60 Hz) | How often the course-wide golfer group scheduling runs |

The **Performance** preset turns terrain rendering Fast, grass and tree occlusion off, water and wind flag detail reduced, prop and ball shadows off, wildlife off and impact bursts to half size, and all three rates to Low. **Balanced** and **High quality** keep every detail on, at Standard and High rates respectively.

The decoration controls reach the running course as soon as they change, with no reload: existing props rebuild their shadow polygons, the wildlife overlay clears or restores its residents (the habitat cache is kept, so switching them back on costs one refresh), and each new particle burst is built to the chosen size - at Off the burst is never created at all. The three rates throttle repainting rather than simulation: golfers keep walking and shots keep resolving at the same speed.

## Input methods

Every screen and panel is built from Godot `Control`s, so all five input methods drive the same controls. `InputManager` (autoload) tracks the method in use, gives a keyboard or controller a starting focus whenever a screen opens, builds a geometric focus graph for the D-pad and arrow keys, and keeps the focused control scrolled into view. The compact prompt bar above the bottom dock follows the active method; it is hidden for a mouse.

| Task | Mouse | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- | --- |
| Select a control | Click | `Enter` on the focused control, or `Tab`/arrows to focus | `A` on the focused control, D-pad/left stick to focus | Tap |
| Back / cancel | Right-click | `Esc` | `B` | Two-finger tap, or the screen's Back button |
| Scroll a list | Wheel over the list | Focus moves with the arrows and `Tab`; the list follows | D-pad / left stick, or `LB`/`RB` for the next control | One-finger drag |
| Change a slider | Drag | Focus it and use the arrows | Focus it and use the D-pad | Drag the slider |
| Pause on the course | `Esc`, or the Menu button | `Space` or `Esc` | `Start` | The dock's Menu button |
| Operate the course | Click, drag | Arrow keys move the pointer, `Enter` clicks, `WASD` pans | Right stick points, `A` clicks, left stick pans | Tap, one-finger drag, pinch open or closed |

**Screen-edge panning.** With a mouse, moving the pointer into the 24-pixel strip at any window edge pans the course at the keyboard's pan speed. It stands down when the pointer is over a HUD panel, during a middle-mouse drag, and when the pointer leaves the window; it also never runs before the first pointer event, so a window that opens with the OS cursor parked in a corner does not scroll on its own. Touch drags and the sticks pan the camera directly, so a finger at the edge never scrolls the course. The preference lives on **Settings → Controls → Camera → Edge Panning** and is saved to `user://settings.cfg` (`camera/edge_pan_enabled`); a settings file from before the option existed keeps panning on.

On the title screen and other pixel-framed menus, the focused action has a bold light outline and a subtle surface tint. The outline follows the D-pad, left stick or keyboard focus; it does not mean a toggle option has already been chosen. Ordinary menu buttons use a matching highlight.

On a screen, moving the right stick brings the pointer up and temporarily stands focus navigation down, so freeform surfaces (the world globe, the Course Map, the golfer-skin canvas) can be used with a controller. A D-pad nudge, a left-stick nudge or `B` returns to focus navigation and keeps the screen open. Switching to the keyboard restores its focus highlight; mouse or touch takes over without forcing focus onto a button. The same pointer draws its own reticle and clicks the control under it with `A`.

The pointer is the one shared implementation: `GamepadCursor` moves the real mouse pointer (right stick or arrow keys) and clicks it (`A` or `Enter`), so painting, placing, aiming, hole selection and every other mouse feature work unchanged. On the course `B` cancels; `View`/`Back` puts focus on the bottom-left dock so the HUD is reachable without a mouse, and `B` returns focus to the course. Opening any screen automatically hands focus to it and hides the pointer; closing it gives the course back.

### Controller map

| Input | Action |
| --- | --- |
| D-pad / left stick | Move focus in a screen; pan the camera on the course |
| `A` | Select the focused control, or click at the pointer on the course |
| `B` | Back / cancel / close, or return from the dock to the course |
| `X` / `Y` | Rotate the course counter-clockwise / clockwise |
| `LB` / `RB` | Previous / next control (tabs and long panel forms) |
| `LT` / `RT` | Zoom out / in |
| `Start` | Pause / resume on the course |
| `View` / `Back` button, or `LB` / `RB` | Focus the bottom-left dock |

`A` and `B` are bound to Godot's `ui_accept`/`ui_cancel` and to the game's `cancel` action in `project.godot`; the D-pad and left stick use Godot's built-in `ui_*` actions. A controller can therefore open the title screen, start a game, build a course and play a round without a mouse.

## In-Game Panels

| Panel | How to open |
| --- | --- |
| Financial Overview (fullscreen) | Manage → Club → Review → Financial Overview, or click the money display; `M` opens its Marketing page |
| Tournament panel | From the HUD |
| Event feed | `N`, or Manage → Club → Review → Feed |
| Hotkey reference | `F1` |
| Year in Review | Opens automatically at year end |
| Tool palette | Tool buttons along the bottom bar |
| Course Map | `Shift+M`, Manage → Club → Maps → Land Parcels, Manage → Holes → Holes Map (opens on Routing Holes), or Manage → Staff → Staff Map (opens on Staff) |
| Course Milestones screen (fullscreen) | `G`, or Manage → Club → Milestones → Course Milestones |
| World Milestones screen (fullscreen) | `Shift+G`, or Manage → Club → Milestones → World Milestones |
| Achievements screen (fullscreen) | `Shift+T`, Manage → Club → Milestones → Achievements, or the Achievements tile on the main menu |
| Course scorecard | `K`, or Manage → Holes → Scorecard |
| Benchmark Results screen (fullscreen) | Settings → Display → Past Results |

### Bottom dock

The bottom-left corner uses small pixel-art circle buttons for **Menu**,
**Pause** and **Speed**. The speed button
cycles through the three running speeds with each press — Normal (1×), Fast (3×),
Ultra (8×), then back to Normal — and its icon gains a triangle per tier (`>`, `>>`,
`>>>`). While paused it shows the single triangle of the Normal speed a press
resumes at; a lit ring marks the active control. The two **Rotate** arrows left this corner for the top-left [course location
banner](#course-location-banner), beside the course they turn. The **Feed** lives on
the Club tab (Manage → Club → Review → Feed, or `N`): its card lights a gold unread
badge with the count in its tooltip, and the same count rides on the Club tab and
Manage section buttons so unread events still show from anywhere. **Inspect** also
left this corner: every Build section tab (Terrain, Improvements, Buildings,
Elevations) pins an Inspect toggle to its bottom-right corner, beside the tiles it
reads, mirroring the Bulldozer's pinned corner button. The four toggles share one
mode — the medallion's ring stays lit while inspecting, and `Esc` or right-click
leaves it on every tab.

Three larger circles curve around these controls: **Build** (largest), **Manage**,
and **Golfers**. Each opens a bottom shelf whose small icon tabs follow a mirrored
curve along its left edge. The selected section and tab stay lit, and the shelf
heading names the current page. Switching sections remembers the last tab used in
each.

Behind the six circles the corner is a fan of mown turf cut to their arc
(`DockArcBackdrop`), not the bar's old rectangle: concentric mowing rings and
fainter chequer sectors spread from the corner hub, each medallion sits in a
dark socket, dotted ball-flight arcs join the circles through the gaps, and
a tiny flagstick stands in the pocket below **Menu**. The fan's rim is one
smooth arc swept across **Build**, **Manage** and **Golfers** rather than an
outline wrapped around each of them, banded ink, trim, bevel and sheen like
the pixel frames, with the trim in the open section's own colour — sage while
the shelf is hidden. The medallions sit astride the rim and poke out past it
over the course, which shows through above the arc where the bar used to be
dead space. The fan is regenerated from the circles' live geometry whenever
the dock reflows, so the touch layout's taller arc gets the same treatment.

The shelf's own backdrop (`ShelfFanBackdrop`) mirrors that quarter-ellipse:
its rim joins the dock and sweeps up past the tab medallions, then continues
along the top of the scrolling pages. It shares the
dock's mowing rings and section-coloured pixel trim; the course is visible and
accepts mouse and touch input in the space outside the curve. The rail narrows
on phones without shrinking its touch targets, and, when space is tight, Inspect
stacks above the pinned brush or Bulldozer rather than overlapping it.

Every tab scrolls in a window cut to that same curve (`ShelfPageWindow`): the
pages start at the shelf's own left padding and their left side is curved, so
each page reaches further left the lower it sits and slides under the curved
tab buttons instead of stopping at a straight edge beside them. The window is a
pixel-stepped mask a frame's width inside the rim, so the rim's ink, trim, bevel
and sheen bands stay whole beside the content and nothing spills over the rim
onto the course. The same shape gates input: the cut-out above the curve
stays course for the mouse, touch and hover, while the tiles below it are the
page. The pinned corner controls — the brush plate, the Bulldozer and Inspect —
stay a rail's width in from the page edge, in the body's corner where no
medallion can cover them, and the catalogue scrolls beneath them.

| Section | Tabs and actions |
| --- | --- |
| Build | Terrain, Improvements, Buildings, Elevations |
| Manage | Club (Maps: Land Parcels, World Maps; Review: Review, Financial Overview, Feed; Milestones: Course Milestones, World Milestones, Achievements); Holes (Holes Map, Scorecard, the hole buttons); Staff |
| Golfers | Visiting Golfers, Play Course, Edit Player Golfer, Player Golfer Skills |

The **Club** tab folds what were four separate Manage tabs — Maps, Review,
and Milestone — into one shelf. Each keeps a labelled column of its
own, so the company's maps, the course's review and records, its milestones and
its marketing campaigns still read as the groups they were. The Milestones
column carries three screens: **Course Milestones** (`G`, per-location goals
for this save), **World Milestones** (`Shift+G`, company goals across every
course location) and **Achievements** (`Shift+T`, career honours that stay
unlocked between saves). All three are fullscreen on the World Map's
background, freeze the day while they are up, and flip between each other
through the Course / World / Achievements switch they share. The Achievements
tile on the main menu opens the same trophy room over the title screen.

The player pages share the existing live round and retain their state when tabs
change. Unspent skill points appear on the skills tab. Keyboard shortcuts still
work; selecting a build tool reveals its section automatically. The Holes tab,
now in Manage, leads with a **Holes Map** card and a **Scorecard** card on the left,
followed by the hole buttons, each with a **Locate** button that centers the camera on that hole without
leaving the list. Clicking a hole button opens that hole's actions (move/place tee
and green, cycle par, open/close, locate, delete) and statistics (rating,
difficulty, revenue, stroke index, scoring averages and score distribution) in
place of the hole list — the same way clicking a golfer on the Visiting Golfers
tab opens their profile. The Staff tab carries a **Staff Map** card beside the roster.
The **Scorecard** card (also `K`) takes the shelf in place of the hole list: every
hole on its OUT and IN nines with par, yardage, stroke index and average score,
the course's name, rating and totals, and the course records beside them. Its
**< Holes** button returns to the hole list.
Both map cards open the Course Map straight into its Routing Holes and Staff
modes. Shelves scroll horizontally while the circle controls remain fixed.
Hover/focus states, tooltips and accessible names identify every icon; Tab and
Enter can navigate the dock.

The **Edit Player Golfer** page carries an **On the course** column. It names the
ground your own golfer works when they are not playing, and its **Move work area**
button turns the next click on the course into the new ground. See [The Owner's
Golfer on the Course](systems/golf-play/owner-on-the-course.md).

### Status column

The top-right corner carries a compact status column (`HUDStatusColumn`) instead of a full-width top bar, so the whole top edge stays free for the course view. Every stat is its own card — a rounded dark value background with a hairline sage border and a 32x32 pixel-art icon in a separate raised, accent-tinted circle on the right — so the cards themselves separate one row from the next. Each row hugs its value and icon and aligns to the right, rather than filling the column. The column has no panel or backdrop of its own: the cards float over the course, and the gaps between them are course view, where clicks reach the course. Its rows, top to bottom:

| Row | Icon | Shows |
| --- | --- | --- |
| Funds | Gold coin | The balance, with a `^` / `v` trend, clickable for the financial dashboard |
| Season | Leaf in the season's colour | The current season |
| Reputation | Heart | Course reputation, colour-coded, clickable for the rating details |
| Rating | Gold star | Five faceted star icons (`CourseRatingStars`, with partial fill and recessed unlit sockets) inside the value pill; hovering shows the numeric rating in the tooltip, clickable for details |
| Weather | Sky sprite | The current conditions; the sprite and its colour follow the weather type (sun, sun behind cloud, cloud, light rain, rain, heavy rain) |
| Wind | Wind gust | Direction and speed, colour-coded |

There is no game-mode (`PLAYING` / `PAUSED`) row: the bottom dock's pause and speed controls already show and set the running state. There is no collapse handle either, so every card is always shown.

The Weather, Wind and Seasons rows appear only while their feature is on: with a feature off (the Start New Game options — all three start off on a quick start) that row is left out of the column rather than shown reading "Off" or "Year-round", and the weather/wind block leaves with the last of the two cards. On compact windows the column narrows, but every card stays on screen. Every card that opens a panel is a normal keyboard-focusable control.

### Course location banner

The top-left corner carries the course location banner (`CourseLocationBanner`), a two-column postcard for the course being played. The first column is a square 1:1 pixel-art picture of the location inside a hairline photo frame with no background of its own — the course shows right up to the frame. `CourseLocationPicture` procedurally paints a different scene for every location from its theme and a seed derived from its id, so each of the world-map sites (and any mod-added location) gets its own deterministic picture: mesas and saguaros in the desert, snowcaps and pines in the mountains, a skyline in the city, palms and volcanic islands in the tropics, fescue dunes on links courses, and so on. The second column is the only part of the banner with a background, a dark card carrying the location's name and the calendar date (with a gold calendar icon; the full weekday date on desktop, a compact stamp on narrow windows). The banner hides while no location is active, swaps its picture and name with a short fade when the player moves between owned courses, and ignores the mouse so shots pass through the corner. The round-score dock stacks directly underneath it.

The two **Rotate** arrows stand in that same corner, on the right of the details card: each turns the course a quarter turn, the same as `Q` and `Shift+Q`, and they are drawn as mirrored pixel arrows rather than font glyphs. In the card's own top-right corner sits the **facing chip** (`OrientationToggleButton`) — a pixel arrow pointing the way the course faces beside its `N` / `E` / `S` / `W` letter, turned by the same quarter turn a press on either arrow gives. The chip doubles as the switch for the arrows: click it to fold them away when the corner should stay quiet, and click it again to bring them back. It stays in place either way — its arrow and rim are gold while the arrows are out and muted while they are stowed — and the banner narrows back into their room while they are hidden.

## Keyboard

### Screens and panels

| Key | Action |
| --- | --- |
| `Tab` / `Shift+Tab` | Next / previous control |
| Arrow keys | Move focus in the direction pressed |
| `Enter` | Activate the focused control |
| `Esc` | Back, cancel or close the screen |
| `Space` | Activate the focused control (and pause/resume when the course has focus) |

Focus starts on the screen's first action when the screen opens; `Esc` closes it. While a screen is open, `Tab` moves focus instead of toggling the minimap. Long screens scroll to keep the focused control visible, so the whole of Settings, Start New Game, the World Map and the benchmark report is reachable from the keyboard.

### Editing controls

Every course action listed in the `F1` sheet from **Camera**, **Game & saving**, **Clubhouse panels**, **Terrain palette**, **Course tools** and **Controller** is rebindable. Open **Settings → Controls** and click the keycap beside an action, or focus it and press `Enter`/`A`. The keycap reads *Press a key…* until the next key or controller button arrives.

- A key or button already used by another action moves to the action being bound. If that action had no other binding, it takes the binding the new action used, so nothing is left without a key by accident.
- `Backspace` (or `Delete`) unbinds an action. The keycap reads **Unbound** and the action's ↺ button restores its default.
- `Esc` cancels listening without closing Settings; `B` does the same on a controller. `Esc`, `Tab`, `Enter`, the arrow keys, `Backspace`/`Delete` and the controller's `A`, `B`, D-pad and bumpers are reserved for menus and unbinding, and the sticks stay with navigation and the pointer. Triggers and the other controller buttons are free.
- Bindings are applied to the running game immediately and saved to the `controls` section of `user://settings.cfg`. The `F1` sheet always shows the bindings you have now, not the defaults.

Mouse and touch controls are fixed: clicking, dragging, the wheel, pinch and the touch gestures in the table below always work. The menu keys stay fixed too. `Shift+Tab`, the controller's View/Back button and LB/RB focus the dock regardless of the course bindings.

### Camera

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | Pan the camera |
| Middle mouse drag | Pan the camera |
| Mouse wheel, `[` and `]` | Zoom |
| `Q` and `Shift+Q` | Rotate the view |
| `Tab` | Toggle the minimap |
| `Shift+Tab` | Focus the bottom-left dock (then arrows/Enter drive it; `Esc` returns) |
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
| `Shift+M` | Course Map. `1` to `4` pick its modes, `F` frames the course, `+`/`-` zoom, `Esc` backs out one step |
| `J` | Fairway width overlay |

### Tools

| Key | Action |
| --- | --- |
| `1` to `9`, `0` | Terrain tools |
| `Shift+2`, `Shift+5` to `Shift+9`, `Shift+0`, `Shift+F` | More terrain tools (Shift+9 Small Boulders, Shift+0 Large Boulders) |
| `T`, `B`, `O`, `H`, `X` | Tool shortcuts. `T` is the Tree tool and `H` is Open Hole. |
| `=`, `.`, `E` | Switch the toolbar tabs |
| `V`, `+`, `-` | Elevation tools |
| `F`, `U`, `M`, `Z`, `G`, `C`, `N` | Management shortcuts (`G` Course Milestones, `Shift+G` World Milestones, `Shift+T` Achievements) |

Every key in these tables is a default: change any of them in **Settings → Controls** (see [Editing controls](#editing-controls)). Tool shortcuts are also shown on each tool's tooltip, and the hotkey panel (`F1`) is the full, authoritative list, drawn from the bindings in force.

## Mouse and Touch

- **Mouse.** Left click places or selects. Right click cancels or opens a context menu. The wheel zooms. Every button, card, tile and slider is a normal control, so the pointer hovers, presses and drags exactly as it does on the desktop.
- **Touch.** A tap is a click. One-finger drag pans, or paints terrain while a tool is active. Two-finger drag pans and pinches to zoom — opening the fingers zooms in, closing them zooms out — on the course, the World Map globe and the Course Map alike; a two-finger tap cancels or closes menus. Dragging a scrollable shelf or panel scrolls it instead of moving or painting the course, and dragging off a button cancels its tap. Dragging a slider sets its value directly, without needing mouse emulation. The minimap can be scrubbed with a finger, and the paused game's dimmed backdrop still supports pan and pinch. Compact windows and touchscreen devices get 44px utility controls, larger toolbar tabs, and a taller dock so the controls are easier to reach. Every fullscreen screen keeps its content in a scroll region on phone-sized windows, so no action is out of reach.
- **Touch surfaces and what is on top of them.** The globe, the minimap and the Course Map read raw touches themselves, so they see a finger before the shared gesture adapter does. They only claim a touch that actually lands on them: anything drawn above them — a confirmation dialogue, a floating panel — gets the tap, so answers such as **Reset World**/Keep World on the World Map or **Quit to Menu**/Cancel stay tappable even when the dialogue opens over the globe.
- **Pause menu, game-over card and confirmations on small windows.** The pause menu clamps itself to the window and scrolls (a drag on the panel scrolls it) when its options do not fit, so **Quit to Menu** and **Quit to Desktop** never sit below the bottom edge on a phone held sideways; a short window also tightens the spacing, drops the gesture footnote and gives each option a 40px target. The game-over card and the confirmation dialogue that follows keep their answers pinned to the bottom and only scroll the text above them, so **Quit to Menu**, **Start New Game**, **Load Saved Game**, **Reset World** and Cancel can always be tapped or focused at any window shape.

## Layout

`Screen` chooses a compact layout on small windows. Panels then take the full width, and the bottom bar grows to fit touch. The main window is 1600 × 1000 on desktop.

## Related

- [Architecture](architecture.md) explains how the HUD fits into the scene.
- [Systems Index](systems/README.md) links to the systems behind each panel.
