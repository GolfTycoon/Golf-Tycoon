# UI & Controls

> The screens, panels and keyboard, mouse and touch controls. The keyboard list comes from the in-game hotkey panel, which is the source of truth.

**Source:** `scripts/autoload/input_manager.gd` (device tracking, focus scopes and navigation), `scripts/autoload/input_bindings.gd` (the rebindable control registry and its saved overrides), `scripts/ui/components/gamepad_cursor.gd` (keyboard/controller pointer), `scripts/ui/components/input_hint_bar.gd` (device prompts), `scripts/ui/hotkey_panel.gd` (in-game shortcut list), `scripts/main/main.gd` (key and controller handling), `scripts/autoload/touch_input.gd`, `scripts/autoload/screen_manager.gd`, `scripts/ui/hud_status_column.gd` (status column / portrait ledger), `scripts/ui/portrait_hud.gd` (portrait HUD coordinator), `scripts/ui/components/course_rating_stars.gd` (status column star strip), `scripts/ui/main_menu.gd`, `scripts/ui/generating_course_screen.gd`, `scripts/ui/components/pixel_button_style.gd`, `scripts/ui/components/pixel_icon.gd`, `scripts/ui/components/setup_glyph.gd`, `scripts/ui/components/course_plan_preview.gd`, `scripts/ui/start_new_game_screen.gd`, `scripts/ui/save_load_panel.gd`, `scripts/ui/settings_menu.gd`, `scripts/utils/isometric_camera.gd`, `scripts/systems/player_data_store.gd`, `scripts/systems/performance_benchmark.gd`, `scripts/systems/benchmark_history.gd`, `scripts/ui/benchmark_results_screen.gd`, `scripts/ui/components/benchmark_visuals.gd`, `project.godot` (input actions)
**Tests:** `tests/unit/ui_and_controls/test_input_manager.gd`, `tests/unit/ui_and_controls/test_input_bindings.gd`, `tests/integration/ui_and_controls/test_editable_controls.gd`, `tests/integration/ui_and_controls/test_gamepad_and_keyboard_screens.gd`, `tests/integration/ui_and_controls/test_gamepad_gameplay.gd`, `tests/integration/ui_and_controls/test_gamepad_every_screen.gd`, `tests/unit/test_pause_system.gd`, `tests/unit/test_touch_input.gd`, `tests/unit/ui_and_controls/test_pause_menu_touch.gd`, `tests/unit/ui_and_controls/test_pause_menu_pixel_cards.gd`, `tests/unit/ui_and_controls/test_game_over_touch.gd`, `tests/integration/ui_and_controls/test_touch_quit_to_menu.gd`, `tests/integration/ui_and_controls/test_portrait_hud.gd`, `tests/integration/ui_and_controls/test_responsive_layout.gd`, `tests/integration/ui_and_controls/test_bottom_dock.gd`, `tests/unit/test_responsive_panels.gd`, `tests/unit/ui_and_controls/test_screen_manager.gd`, `tests/unit/ui_and_controls/test_ui_scale_preferences.gd`, `tests/unit/ui_and_controls/test_hud_status_column.gd`, `tests/unit/ui_and_controls/test_course_rating_stars.gd`, `tests/unit/test_save_load_settings_layout.gd`, `tests/unit/ui_and_controls/test_pixel_button_style.gd`, `tests/unit/ui_and_controls/test_pixel_icon.gd`, `tests/unit/ui_and_controls/test_main_menu_typography.gd`, `tests/unit/ui_and_controls/test_start_new_game_layout.gd`, `tests/unit/ui_and_controls/test_start_new_game_visual_style.gd`, `tests/unit/ui_and_controls/test_performance_benchmark.gd`, `tests/unit/ui_and_controls/test_benchmark_history.gd`, `tests/unit/ui_and_controls/test_benchmark_results_screen.gd`, `tests/integration/ui_and_controls/test_save_and_settings_screens.gd`, `tests/unit/ui_and_controls/test_graphics_quality_settings.gd`, `tests/unit/ui_and_controls/test_camera_edge_panning.gd`, `tests/unit/ui_and_controls/test_player_data_store.gd`, `tests/harness/save_settings_layout_harness.tscn`

---

## Screens

**Shared screen chrome.** Every in-game screen (Start New Game, World Map, Course Map, Settings, Save and Load, Benchmark Results, Milestones, Achievements, Financial Overview, Golfer Skins, Generating Course, Credits, the pause menu and the game-over panel) is built from the same parts in `scripts/ui/components/menu_screen_kit.gd` (`MenuScreenKit`), so the screens share one layout and one look. The four Tournament Mode library screens (Save Course, Save Golfer, Choose Course, Choose Golfer) share `scripts/ui/tournament_library_screen.gd` on top of those parts: the same backdrop, header, split/stacked body and confirmation dialogue, one base for all four:

- **Layout modes.** One `MenuScreenKit.LayoutMode` with five shapes: `DESKTOP`, `TABLET_LANDSCAPE`, `TABLET_PORTRAIT`, `PHONE_LANDSCAPE` and `PHONE_PORTRAIT`, picked by `layout_mode_for(view)` from the same breakpoints everywhere. `is_tablet` and `is_compact` group the shapes; `outer_padding` and `page_separation` set the spacing for each.
- **Screen header.** `make_screen_header` builds the same top bar on every screen: a **Back** button on the left (`BackButton`, a utility card with a `‹` chevron), the golf-flag `MenuFlagMark`, a title block (gold kicker, bold title, subtitle) and an optional trailing group on the right (a treasury chip, an autosave chip, a tab row or a switch). The header's own parts carry fixed node names (`ScreenHeader`, `BackButton`, `FlagMark`, `TitleBlock`, `Kicker`, `Title`, `Subtitle`), and an unnamed trailing control takes the `Trailing` slot name; a trailing control a screen names for what it does keeps that name, as the tournament header's `StartTournamentButton` does in every layout.
- **Buttons.** `paint_utility_button` for secondary actions and Back, `paint_action` for the gold primary call to action, `paint_danger_button` for destructive actions such as Delete and Quit and `paint_toggle` for on/off switches. All of them use the rounded `PixelButtonStyle` frames.
- **Cards and panels.** `make_panel` and `padded_panel` build the rounded pixel frame. `MenuStyle.panel`, `paint_card`, `paint_choice` and `paint_primary` delegate to `PixelButtonStyle`, so the older helpers draw the same frames.
- **Rounded pixel frames.** `PixelButtonStyle` generates every card, button, panel and field as a rounded pill: one signed-distance rounded rectangle, rasterised per pixel with a one-pixel antialiased edge into a nine-patch texture, so the corners stay smooth and the interior stretches without smearing. The frame is built in layers, from the outside in: a soft contact shadow a little below the card, a dark ink outline, an accent rim whose top corners are lit warm and whose bottom edge drops into a rim shadow with a thin bounce-light line just inside it, a glass body that starts a shade lighter at the top and settles darker at the bottom, a gloss band under the top rim, and an inner bevel above the fill. The texture's margins (20 / 12 / 20 / 12 px, left / top / right / bottom) are wide enough to hold the whole corner curve, the gloss band and the contact shadow, so a nine-patch stretches only the flat middle and never smears the light; they are also kept tight enough that a small control - a filter chip, a row's action - still fits its own minimum size. `State.PRIMARY` paints the call to action on the same silhouette in a warm gold body with a cream rim; `State.INSET` sinks a recessed field into the surface; hover lifts the tint and the gloss, pressing darkens the body and drops the shadow, and disabled desaturates and fades the rim.
- **Focus ring.** Keyboard and controller focus draws in two parts: a translucent warm wash *inside* the card, under its label, so the words stay readable, and a cream `MenuFocusRing` around it (`MenuFocusRing`, a `Node2D` laid over the button, `RING_REACH` 4 px outside the card's edge, sharing the button's `focus` stylebox with `draw_center` off, visible only while the card has focus). The ring is deliberately not a `Control`: as a child it would join the card's minimum size, and a dense screen with fixed row heights cannot spend a few pixels per card on a highlight; and a `Control` rectangle is what the engine's mouse-hit test sees, so a ring drawn around a card would swallow its clicks. As a `Node2D` it does neither: it is parented to the card, so it travels with it into a docked bar or a scrolling column, and its measurement is read from the card's rect whenever it draws. Focus is distinct from hover and from an already-chosen option: a chosen toggle option is a lit card, not a ring.
- **Type.** Pixelify Sans throughout. `make_title_label` for titles, `make_kicker` for the small gold captions above a section, and `make_label` for body text.
- **Chips and sprites.** `make_chip` for status chips, `make_track_switch` for the track switch, `make_sprite` for `PixelIcon` sprites, and `PixelBar` for meters. Money is formatted with `format_money` and `format_money_compact`.
- **Backdrop.** Each screen sits over a `MenuBackdrop` - the picture and the overlay pattern the player picked in **Settings → Display → Background** (see [Menu background](#menu-background)). Out of the box that is the clubhouse artwork under no overlay, and **Auto** keeps it in step with the season and the course's theme.
- **Screens cover notices.** Toasts, the autosave badge and the round summary live in the `Notices` CanvasLayer beneath the `UI` layer, so they hover over the course and the HUD but never over a screen or panel. Opening the pause menu, the Save Course screen, Save/Load, Settings or any other screen covers a notice instead of letting it float on top; the notice waits behind the screen and is still there when it closes.

- **Boot splash.** The engine's boot splash (`application/boot_splash/*` in `project.godot`) shows `assets/ui/boot_splash.png` before the main scene loads: the same clubhouse artwork the out-of-game screens sit on (`assets/ui/background.jpeg`, drawn the same cover-fit way), the game logo on top of it, and a "Made with" line beside the Godot logo near the bottom edge. The image is read straight from the PNG file, so it is on screen before any resource is imported, and it stretches in Cover mode (`boot_splash/stretch_mode=4`) so the artwork fills any window shape with no letterbox bars, cropping the overflow exactly like `MenuBackdrop` does in-game. While it is up the window clears to the deep clubhouse green (`boot_splash/bg_color`). (Godot's web exporter never shows the boot splash — there the HTML shell's own loader screen stands in for it, see `web/custom_shell.html`.) The game drives that loader through `WebBoot` (`scripts/utils/web_boot.gd`): the main scene builds itself in seven steps, a frame apart, reporting each one between slices, so the loader's stage line — *Loading the clubhouse*, *Surveying the grounds*, *Setting up the clubhouse*, *Opening the first tee* — keeps moving instead of freezing on the last thing the page painted before the engine took the thread. The loader stays up until the game says the title screen is really there (the engine's own start signal fires as soon as the engine is up, long before the menu exists), adds a word of reassurance after a long wait, and hands the canvas back regardless after a minute. See [Architecture](architecture.md#startup).
- **Main menu.** Headed by the game logo (`assets/ui/logo.png`). Start New Game, Quick Start, Continue, Load Game, Settings and Quit. Every card and tile is a pixel-art sprite window (`PixelButtonStyle`): fully rounded pill corners, a dark ink outline, a lit accent rim, a glass fill with a gloss band under the top edge and a contact shadow beneath it, generated as nine-patch textures so the edges stay smooth and the corners round slightly further at any window size. Hover brightens the trim and the gloss, pressing darkens the body and drops the shadow so the card sinks, and keyboard/controller focus adds a cream ring around the card and a light wash across it. This focus highlight is distinct from hover and from an already-chosen option; disabled cards grey out and are skipped by navigation. Each action also carries a 16x16 sprite of its own (`PixelIcon`), painted in the card's accent: a pennant for Start New Game, a lightning bolt for Quick Start, the play triangle for Continue, a floppy disk for Load Game, a polo shirt for Golfer Skins, a cog for Settings and a doorway arrow for Quit. Sprites scale in whole multiples of their grid so their pixels stay square; the squat and phone layouts drop them, because a tile too narrow for a sentence is too narrow for an emblem. No button carries a sub-title except Continue, whose card names the newest save (course, day, slot) beneath its title. Every word on the screen is set in Pixelify Sans (`assets/fonts/`, SIL Open Font License 1.1): the hero and Continue card titles in the bold weight, the compact utility tiles in the semibold one, and Continue's sub-title and the version line in the regular one, with the rail kicker in the shared gold semibold caption style, so the type reads as part of the same pixel art.
- **Start New Game.** Company name (or roll for a random one), difficulty (Easy, Normal or Hard), starting money ($100K, $150K, $200K or Unlimited), generated holes, the Weather, Wind and Seasons options, and a **Guided tutorial** switch. It shares the title menu's `MenuBackdrop`, rounded `PixelButtonStyle` frames, Pixelify Sans typography and nearest-filtered sprite art; its choice cards light their accent when selected, the company field and course plan sit in recessed pixel frames, and the gold Choose Location action wears the warm primary frame. Setup-specific icons (difficulty, money, weather, wind, seasons, dice, check, switch, arrow and tutorial book) are hard-edged character-grid sprites. The switch sits in the title bar on the wide and landscape layouts and under its own heading on tablets and phones. The tutorial only walks an empty first course, so with generated holes the switch is faded and the summary reads "Not used". See [World Map](systems/economy-and-land/world-map.md#the-guided-tutorial).
- **Quick Start.** Uses the defaults (random company name, Normal, $100,000, all features off, 3 generated holes), buys a random location the company can afford and starts playing it straight away. The Generating Course screen appears first with **Finding a location**, before the world and course are prepared; it then names the chosen course and follows the same job through generation. Repeated activation and gameplay shortcuts are ignored while it is loading. If no location is affordable, the loader closes and the World Map opens instead.
- **World Map.** A spinning globe with a pin for each destination, a list of locations each with a **Buy & Play** button (or **Play** once owned), a selected-site dossier with **Buy** beside **Buy & Play**, and Reset World — dressed in the same pixel-art language as the title screen and Start New Game: rounded `PixelButtonStyle` frames on every card, button and field, Pixelify Sans throughout (bold for the heading, treasury and call to action, semibold for names, kickers and buttons, regular for captions), `PixelIcon` sprites for the treasury coin, the per-location pennants and the map legend, and the golf-flag `MenuFlagMark` itself drawn as a 16x16 sprite. The globe is the planet shader run in `GlobeMap.LandStyle.PIXEL`: every fragment resolves into a chunky hard-edged cell in the menu palette (deep ink-teal sea, golf-green land, sandy tropics), using detailed Natural Earth 1:50m coastlines with islands and lake rings; destinations are sprite pins (gold-bracketed when selected) whose hover tags are little rounded pixel frames. It opens from the **World Maps** button under **Manage → Club → Maps**, from Start New Game, and from Quick Start if no location is affordable. The course behind it freezes while the globe is up, so switching sites never loses a day's work. On a touchscreen, one finger spins the globe and two fingers pinch open or closed to zoom, moving together to spin it as well; letting go of a pinch never selects the pin under a finger. See [World Map](systems/economy-and-land/world-map.md).
- **Financial Overview.** A fullscreen clubhouse dashboard over the same `MenuBackdrop` as the World Map. Desktop lays out the year-to-date ledger, course controls and status, and marketing campaigns side by side. Tablet and phone layouts use a fixed three-page rail (**Finances**, **Course**, **Marketing**) above a scrollable workspace; phone landscape keeps the same pages in a compact, short-screen composition. It carries forward the balance, revenue and expense breakdown, year-over-year comparison, booking interval, green-fee controls and warning, reputation, golfer count, loans, seasonal forecast and official course ratings, alongside marketing reach, daily spend, campaign history, active campaign timers and all five launch offers. Open it from the money display or **Manage → Club → Review → Financial Overview**; **M** opens it directly on the Marketing page. The World Map's clubhouse artwork, pixel-framed cards and Pixelify Sans styling are shared throughout.
- **Course Map.** The whole course in one isometric diamond, in the title screen's own dress. Its header is the shared screen header: Back on the left, and the mode tabs, treasury and Details on the right: the `MenuBackdrop` clubhouse artwork behind it, rounded `PixelButtonStyle` frames, Pixelify Sans type. Four modes sit across the top on desktop and portrait shapes (a compact rail on landscape ones): **Land** (buy parcels, read the ones you own), **Routing** (reorder the holes, flip them, set par, open or shut them, and read the scorecard and records), **Aura** (green, amber and red cells where golfers were happy and unhappy) and **Staff** (each employee's working area, hiring, firing and posting them). One line under the map says what is picked or what the map is waiting for, with the mode's own **Buy** / **Cancel** / **Clear** beside it. Drag to pan, wheel or pinch to zoom, `F` to frame the course. On phones the panel is a bottom sheet that peeks and lifts (portrait) or slides in over the map (landscape); on a landscape tablet it folds away behind a **Hide**/**Show** toggle. The course freezes while the map is up. See [Course Map](systems/course-design/course-map.md).
- **Pause menu.** Resume, Save Game, Load Game, Save Course, Save Golfer, Settings, Quit to Menu and, on native builds, Quit to Desktop. **Save Course** and **Save Golfer** keep the open Career course and the owner's golfer for Main Menu → Tournament Mode; they are not Career save slots. They appear only in Career games and step the menu aside while their fullscreen screens are open; the pause menu returns when the screen closes. The web build omits application-exit actions (here and on the main menu) because the browser tab or window already provides them. The camera still moves while paused.

  The menu is drawn in the title screen's own language, so pausing looks like the screen the game was opened from: one column of `PixelButtonStyle` cards inside the same notched nine-patch panel the title screen builds its rail from, each card trimmed in the accent its family wears on the main menu — Resume is the gold call to action, Save Game and Load Game the green pair, Save Course and Save Golfer the blue Tournament Mode pair, Settings the quiet utility grey, and the two ways out the danger red — and each carrying its own `PixelIcon` sprite (a play triangle, a floppy, an archive, a flag, a golfer shirt, a cog, a map and a doorway). The heading is the golf-flag `MenuFlagMark` beside a bold Pixelify Sans title under a small gold kicker (**CAREER** or **TOURNAMENT**), over a gold rule, with the course and day beneath it. The two export cards open the Save Course and Save Golfer screens, where the keepsake is named, overwritten or deleted and the outcome is reported in the screen itself. In tournament mode the heading reads **Tournament Paused**: the save pair gives way to Restart Tournament and Tournament Setup, and the export cards step aside. Every option keeps the shared focus treatment (the cream ring drawn outside the card and the warm wash over it), a pointing-hand cursor and the ink-outlined label the title screen's cards use; see `tests/unit/ui_and_controls/test_pause_menu_pixel_cards.gd`.
- **Save Course** and **Save Golfer** (pause menu). Fullscreen screens in the same language: the work card on the left, the archive of keepsakes on the right (stacked on portrait windows). Save Course shows a top-down preview of the open course, its holes, par and star rating, a name field prefilled with the open course's name and the gold **Save Course** action; the Save Course archive lists the courses kept on this device, each one selectable for an overwrite or deletable with a question first. Save Golfer shows the golfer's recoloured portrait in the skin they wear, their identity, profession, age, gender and marital status, Age / Skill pts / Avg skill tiles, the four ability bars their Golf Skill points produce, the name field prefilled with the golfer's name and the gold **Save Golfer** action; the archive lists the golfers kept on this device the same way. Saving over an existing name asks first (**Replace course** / **Replace golfer**), the outcome is reported in the screen's own status line, and the screen stays open so the keepsake can be checked. Both write only to the Tournament Mode library, never to the Career save archive, and Back (or Esc / controller B) returns to the pause menu.
- **Start Tournament** (main menu). The Course and Golfer sections are summary cards — the current pick with its theme/holes/par or profession/age/skill, badged **DEFAULT** or **CAREER** — each opening its fullscreen chooser, each with a full-width **Choose Course** / **Choose Golfer** card beneath its section. The setup screen otherwise works as before: difficulty, format and rules, mod features, the Course and Golfer sections, and its preview and dossier column on the side.
- **Choose Course** and **Choose Golfer** (Start Tournament). The pickers opened from those cards. The built-in defaults and every Career-saved entry on this device are big, tappable rows — the course drawn as a top-down map, each golfer as their own recoloured sprite — scrolling independently beside the dossier of the highlighted entry: name, source line, tagline and Holes / Par / Theme tiles for courses, or the recoloured portrait with name, archetype, age, gender and marital status, Skin and Skin Colour chips, Golfer Traits, Golfer Skills, the four ability bars (Driving, Accuracy, Putting, Recovery) and Age / Skill pts / Avg skill tiles for golfers. The gold action emits the pick; the setup screen applies it to its summary cards and auto field size. Saved entries carry a **Del** button on their row with the same question-first delete; deleting the highlighted entry falls the highlight back to a valid one. Defaults wear the **DEFAULT** badge, saved entries the **CAREER** badge. Back (or Esc / controller B) leaves without changing the pick.
- **Settings.** Display, Controls, Audio and Data are four buttons in the header's top right corner, laid out the way the Course Map puts its mode buttons there: one tap swaps the page under the header, and the pressed button stays lit. Display leads the row and is the page Settings opens on. The page under them is the settings card itself - there is no category rail beside the cards and no strip over them, so the cards get the whole width at every window size. The selected button's page leads with its own heading and one scrolling column of cards. Changes apply immediately and save to `user://settings.cfg`. With nothing left to confirm, the page has no bottom row: `SettingsPage` is the shared `ScreenHeader` (its `HeaderActions` carry the four `Category_*` page buttons) over the `SettingsWorkspace`, which is the settings card itself - it runs down to the window's bottom margin, and Back (or Esc / controller B) returns to the Main Menu or the pause menu that opened the screen. On the narrowest portrait phones the header drops its screen mark so the four buttons never crowd the title. The Controls category is the editor for every course control: click a keycap, press a key or controller button, and the change applies at once. It also carries screen-edge panning (**Edge Panning**: pan the camera by moving the pointer to the edge of the window, or leave the course still until you drag, press the keys or use the stick), the camera zoom inversion, the zoom limits, a reset per action and **Reset All Controls**. Display leads with a **Background** card that sets the picture every menu sits on and the overlay pattern drawn over it, each with its own **Auto** switch (the default) - see [Menu background](#menu-background). Display also includes an **FPS Counter** card: the counter is off by default, and can be shown over menus and the course (even while paused) with a choice of position, text size and refresh interval (0.25, 0.5 or 1 second). It averages frames over real elapsed time, ignores mouse and touch input, and is independent of graphics presets. Display also has the **Course HUD** card (with the **Minimap** toggle to enable or disable the corner minimap), window mode, VSync, UI scale (automatic by default, following the system display scale; move the slider to pin a manual size), colourblind palettes, the graphics quality preset and its individual controls (see [Graphics quality](#graphics-quality)), and the **Benchmark** card, which runs only when Settings was accessed from the Main Menu (Settings from the pause menu shows the last run and the past results but runs nothing, so a game in progress is never the test scene). The card carries two buttons: **Run Benchmark**, which closes the menus and runs the full course tour - a throwaway benchmark course prepared (preparation included in the measurement), then every fixed test course built and played on it, about 95 seconds - and **Past Results**, which opens the Benchmark Results screen over the menus. Above them the card shows the rating the last run earned - five stars and a segmented score meter. For fair comparisons, run the tour from Main Menu Settings at the same resolution, VSync and power mode. See [Device Benchmark](development/benchmark.md). The Data category is the on-device privacy page: it lists what is stored (saved courses, preferences, career records, benchmark reports and custom golfer skins), gives each group its own **Delete** button and offers one **Delete All Player Data** action at the end. Every deletion asks first on a confirm card whose safe answer has focus, the page is rebuilt afterwards so each line and button tells the truth about what is left, and the title screen's Continue card is refreshed from the save list that remains. Deleting the saved courses during a pause session closes the course and returns to the title screen, because it has nowhere left to autosave. Mods are left to the Mods screen, where they can be uninstalled safely; see [Save & Load](save-and-load.md#deleting-player-data).
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

## Menu background

**Settings → Display → Background** chooses what the menus are made of: the picture behind them, and the overlay pattern laid over that picture. Both lists are built from the catalogue in `data/menu_backdrops.json` and `data/menu_overlays.json`, plus anything installed mods add, so a style a mod ships is offered beside the shipped ones with no code to write.

| Control | Choices | Default |
| --- | --- | --- |
| **Background picture** | Auto, the shipped pictures (Clubhouse, Golden Hour, Winter Course, Desert Links) and every picture a mod adds | Auto |
| **Background overlay** | Auto, None and every overlay (Vignette, Edge Scrim, Evening Wash, Sand Haze, Fairway Stripes, Clubhouse Lattice, Scanlines, Pixel Halftone, Dew Sparkle, Flag Glow, Split Light, Aurora Ribbons, Championship Rays, Course Contours, Gilded Deco, Heritage Argyle, Clubhouse Bokeh) plus any a mod adds | Auto (Edge Scrim) |
| **Auto** switches | One beside each picker | On |
| **Reset to Auto** | Puts both choices back on Auto | - |

Each picker shows a live preview of the pair as it is chosen - the real picture, cropped cover-fit, with the real overlay painted over it - so the card shows the result instead of describing it. A choice applies to every open menu the moment it is made (the title screen behind the card repaints on the same frame), and is written to `user://settings.cfg` (`display/menu_background`, `display/menu_overlay` and `display/menu_overlay_settings`) with the rest of the Display page.

**What Auto does.** With **Auto** on, the menu follows the game rather than a fixed picture. It prefers a picture tagged with the current course's theme, then one tagged with the current season, then the shipped clubhouse; overlays resolve the same way and fall back to **Edge Scrim**. On the title screen there is no course, so Auto starts from the season; with the seasons off as well it is just the clubhouse, still under Edge Scrim unless the overlay is set to None. The line under the pickers names what Auto picked and why ("Auto: a Mountain course picks Winter Course, with the Evening Wash overlay"), so the rule is visible without reading this page. Turning Auto off keeps whatever picture is on screen at that moment as the player's own choice, so the picture never changes under their hand; turning it back on hands the choice back to the season and the course.

A picture and an overlay are independent: any picture can wear any overlay. Overlays that have their own settings show them under the picker, and each overlay remembers its own values:

| Overlay setting | Chooses | Offered by |
| --- | --- | --- |
| **Angle** | The direction the pattern runs, 0° to 165° in 15° steps | Fairway Stripes, Clubhouse Lattice, Split Light, Aurora Ribbons, Championship Rays, Course Contours, Heritage Argyle |
| **Density** | Light, Medium or Heavy layered detail across the picture | Dew Sparkle, Aurora Ribbons, Championship Rays, Course Contours, Clubhouse Bokeh |

The six signature designs are drawn procedurally over any picture, including
modded ones. Hover a picker row for its description; the preview updates as
soon as its Angle or Density changes.

| Signature overlay | Look | Auto theme |
| --- | --- | --- |
| **Aurora Ribbons** | Layered mint light, luminous crests and tiny stars | Mountain |
| **Championship Rays** | Golden radial shafts fading from a soft sunrise | Resort |
| **Course Contours** | Fine topographic rings, index lines and a summit mark | Woodland, Heathland |
| **Gilded Deco** | Gold corner fans, jewel details and a double-rule frame | Manual choice |
| **Heritage Argyle** | Sheer diamond panels, fine outlines and stitched lozenges | Links |
| **Clubhouse Bokeh** | Soft golden light orbs with photographic rims | Tropical |

**What ships.** Four pictures (`assets/ui/backdrops/`) and eighteen overlays. **Edge Scrim** is the shading the menus used to draw under every picture whether the player chose it or not: the dark bands along the top and bottom that the heading and the version line sit on. It is an ordinary overlay now, and Auto's default, so the out-of-the-box look is unchanged - but it can be swapped for Vignette, Wash or **None**, and a bare picture really is bare. `data/menu_backdrops.json` and `data/menu_overlays.json` hold the catalogue: the file to draw, a name and description for the picker, the tint the screen multiplies over it, and optional `seasons` and `themes` tags that Auto reads. A mod adds entries to the same catalogues by declaring `menu_backdrops` and `menu_overlays` in its manifest's `content` block; a mod entry with a shipped id patches that style (change the clubhouse's tint, say), and a new id is namespaced under the mod's own id (`example.backgrounds:harbour_dusk`). Overlays are drawn by `MenuBackdropOverlay`, which paints each pattern with lightweight drawing primitives - crisp line work and antialiased curves, with no imported overlay textures - so the designs scale to any window size. `mods/example.backgrounds/` is a worked example: two pictures, three overlays and an overlay setting of its own. See [Modding](modding/manifest-and-packaging.md#menu-backgrounds) for the file format.

A picture whose file is missing or unreadable is dropped from the picker with a warning in the log rather than breaking a menu: if the player had chosen it, the menus fall back to the clubhouse and the card says the picture is gone.

## Input methods

Every screen and panel is built from Godot `Control`s, so all five input methods drive the same controls. `InputManager` (autoload) tracks the method in use, gives a keyboard or controller a starting focus whenever a screen opens, builds a geometric focus graph for the D-pad and arrow keys, and keeps the focused control scrolled into view. The graph is built per screen and every direction ends inside it: an edge control wraps round to the opposite edge (Down on the last option returns to the first), and one with nothing beside it in either direction holds the selection, so the D-pad never walks out of an open screen — the pause menu and the confirmations over the live HUD would otherwise hand focus to the bottom bar. The compact prompt bar above the bottom dock follows the active method; it is hidden for a mouse.

| Task | Mouse | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- | --- |
| Select a control | Click | `Enter` on the focused control, or `Tab`/arrows to focus | `A` on the focused control, D-pad/left stick to focus | Tap |
| Back / cancel | Right-click | `Esc` | `B` | Two-finger tap, or the screen's Back button |
| Scroll a list | Wheel over the list | Focus moves with the arrows and `Tab`; the list follows | D-pad / left stick, or `LB`/`RB` for the next control | One-finger drag |
| Change a slider | Drag | Focus it and use the arrows | Focus it and use the D-pad | Drag the slider |
| Pause on the course | `Esc`, or the Menu button | `Space` or `Esc` | `Start` | The dock's Menu button |
| Operate the course | Click, drag | `Shift` + arrows move the pointer when the HUD is unfocused, `Enter` clicks, `WASD` pans | Right stick points, `A` clicks, left stick pans | Tap, one-finger drag, pinch open or closed |

**Screen-edge panning.** With a mouse, moving the pointer into the 24-pixel strip at any window edge pans the course at the keyboard's pan speed. It stands down when the pointer is over a HUD panel, during a middle-mouse drag, and when the pointer leaves the window; it also never runs before the first pointer event, so a window that opens with the OS cursor parked in a corner does not scroll on its own. Touch drags and the sticks pan the camera directly, so a finger at the edge never scrolls the course. The preference lives on **Settings → Controls → Camera → Edge Panning** and is saved to `user://settings.cfg` (`camera/edge_pan_enabled`); a settings file from before the option existed keeps panning on.

On the title screen and other pixel-framed menus, the focused action has a cream focus ring drawn just outside its rounded card plus a subtle surface tint inside it (see the *Rounded pixel frames* and *Focus ring* notes under [Screens](#screens)). The ring follows the D-pad, left stick or keyboard focus; it does not mean a toggle option has already been chosen. Ordinary menu buttons use a matching highlight.

On a screen, moving the right stick brings the pointer up and temporarily stands focus navigation down, so freeform surfaces (the world globe, the Course Map, the golfer-skin canvas) can be used with a controller. A D-pad nudge, a left-stick nudge or `B` returns to focus navigation and keeps the screen open. Switching to the keyboard restores its focus highlight; mouse or touch takes over without forcing focus onto a button. The same pointer draws its own reticle and clicks the control under it with `A`.

The pointer is the one shared implementation: `GamepadCursor` moves the real mouse pointer (right stick or `Shift` + arrow keys) and clicks it (`A` or `Enter`), so painting, placing, aiming, hole selection and every other mouse feature work unchanged. On the course, unmodified arrows focus the last HUD control (or the dock if it is unavailable). Enter on a terrain tile selects it and returns focus to the course, so the next Enter clicks at the pointer. `Esc` leaves the HUD; `Shift` + arrows then move the pointer. `B` cancels; `View`/`Back` puts focus on the bottom-left dock so the HUD is reachable without a mouse, and `B` returns focus to the course. Opening any screen automatically hands focus to it and hides the pointer; closing it gives the course back.

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
| Course scorecard | `K`, or Manage → Holes → Holes Map → Scorecard |
| Benchmark Results screen (fullscreen) | Settings → Display → Past Results |

### Portrait HUD (phones)

Portrait windows narrower than 700 logical pixels use a dedicated thumb-first
composition (`PortraitHUD`); wider portrait tablets and every landscape window
keep the desktop fan/shelf. The coordinator **moves the live controls** into the
new layout rather than duplicating them, so bindings, signals, badges, focus and
tool state survive rotation. Rotating back restores the original parents/order.

- **Clubhouse ledger (top).** Menu owns the top-left corner as a 44 px target;
  the course identity strip sits to its right, above one row of money / rating /
  reputation cards. When the course uses Seasons,
  Weather or Wind, a second compact conditions row appears; otherwise the header
  shrinks to give the course more room. Money and rating remain tappable.
- **Thumb rail (bottom).** Five stable 44–52 px targets: Build, Manage, Golfers,
  Pause, Speed. The active section opens a full-width **tool tray**; tapping
  it again (or the collapsed context button) puts the tray away. The tray keeps
  all 11 pages, brush size/shape, bulldozer and Inspect, with 48 px page tabs and
  a horizontally scrollable catalogue that never pans or paints the course.
- **Course view (middle).** The camera rail exposes Rotate left/right, Zoom
  out/in and a course Overview toggle as five 44 px actions. Overview can open
  even when the desktop minimap preference is off, without changing that
  preference. Score cards, event feed and toasts dock below the ledger and clear
  the rail/tray.
- **Safe areas.** `Screen.safe_insets` (left/top/right/bottom, logical px) reads
  native display safe areas on Android/iOS and `window.GolfTycoonSafeArea` on the
  web. The web shell publishes CSS `env(safe-area-inset-*)` through a hidden
  probe and resize/orientation listeners. Header, rail, tray, camera rail and
  floating panels all reserve these insets; malformed reports are clamped to a
  fifth of each axis.

Contract: nav 64 px + bottom inset; tray 260 px; collapsed context 44 px; header
108 px (148 px with conditions) + top inset. `Screen.portrait_course_rect()` is
the shared playable rectangle. Regression coverage exercises 320×568 through
540×960, rotation restore, safe-area offsets, shelf dragging and live actions.

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
left this corner for the shelf header: the toolbar carries a single shared
Inspect toggle in a header row at the top-right of the shelf. One toggle
serves every Build tab — the medallion's ring stays lit while inspecting,
and `Esc` or right-click leaves it on every tab. The other header buttons
follow the shelf: Terrain shows the Terrain Brush Shape and Brush Size
buttons, Improvements and Buildings show the Bulldozer, and Elevation shows
its own Brush Shape and Brush Size buttons. Each Brush Size plate reads the
size in tiles as a plain number — `1`, `5`, `9` — rather than a `1x1` width by
height pair, since a square brush is the same across and down. Each Brush
Shape toggle draws the brush itself: a miniature of the exact tile footprint
it will paint at the current size and shape, which steps with the size plate
beside it — one chunky tile for a 1-tile brush, a clipped square for a round
one — instead of a fixed square or circle glyph.

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
the dock reflows, so a resized window re-cuts the arc around the medallions as
they now stand.

The shelf's own backdrop (`ShelfFanBackdrop`) mirrors that quarter-ellipse:
its rim joins the dock and sweeps up past the tab medallions, then continues
along the top of the scrolling pages. It shares the
dock's mowing rings and section-coloured pixel trim; the course is visible and
accepts mouse and touch input in the space outside the curve. The rail narrows
on phones while its 44px tab medallions stay whole, and, when a shelf is too
narrow for its own header row, the row hides so the tab rail keeps its room.

Every tab scrolls in a window cut to that same curve (`ShelfPageWindow`): the
pages start at the shelf's own left padding and their left side is curved, so
each page reaches further left the lower it sits and slides under the curved
tab buttons instead of stopping at a straight edge beside them. The window is a
pixel-stepped mask a frame's width inside the rim, so the rim's ink, trim, bevel
and sheen bands stay whole beside the content and nothing spills over the rim
onto the course. The same shape gates input: the cut-out above the curve
stays course for the mouse, touch and hover, while the tiles below it are the
page. The header row's controls — the Brush Size plate, the Brush Shape button,
the Bulldozer and Inspect — sit at the top-right of the shelf header, clear of
the scrolling catalogue below. Each Build shelf shows only the buttons it
needs: Terrain and Elevation carry their brush shape and size stepper, while
Improvements and Buildings carry the Bulldozer.

| Section | Tabs and actions |
| --- | --- |
| Build | Terrain, Improvements, Buildings, Elevations |
| Manage | Club (Maps: Land Parcels, World Maps; Review: Review, Financial Overview, Feed; Milestones: Course Milestones, World Milestones, Achievements); Holes (Holes Map and the hole buttons); Staff |
| Golfers | Visiting Golfers, Play Course, Edit Player Golfer, Player Golfer Skills |

The **Club** tab folds the former Maps, Review and Milestone tabs into one
shelf. Each keeps a labelled group of its own. The management actions are
compact tickets with their icons to the left of their labels, arranged up to
two high; the Holes Map and Staff Map use the same design. They do not show
shortcut text, but their keyboard
shortcuts still work. The Milestones
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
now in Manage, leads with a **Holes Map** card on the left, followed by the hole
buttons, each with a **Locate** button that centers the camera on that hole without
leaving the list. Clicking a hole button opens that hole's actions (move/place tee
and green, cycle par, open/close, locate, delete) and statistics (rating,
difficulty, revenue, stroke index, scoring averages and score distribution) in
place of the hole list — the same way clicking a golfer on the Visiting Golfers
tab opens their profile. The Staff tab leads with a **Staff Map** card on the left, before the roster.
The **Scorecard** page inside the Holes Map shows every hole on its OUT and IN
nines with par, yardage, stroke index and average score, together with the
course's name, rating, totals and records. Select a hole on the card to find it
on the map; **Routing** returns to the route controls. `K` opens the map directly
on its scorecard (and reveals the phone sheet); pressing it again closes the map.
The shortcut remains rebindable. Both map cards open the Course Map straight into
its Routing Holes and Staff modes. Shelves scroll horizontally while the circle controls remain fixed.
Hover/focus states, tooltips and accessible names identify every icon; Tab and
Enter can navigate the dock.

The **Edit Player Golfer** page leads with your own golfer: an animated sprite
standing in the first column, with the skin they wear chosen directly beneath it.
The picker has no title of its own — the golfer above it says what it dresses, its
entries name the skins and its tooltip explains them. A name too long for the
column is trimmed to an ellipsis in the button, while the opened menu lists every
skin in full. The whole shelf keeps a little air below its heading, so the golfer
and the columns beside it never rub against the header row above them.

Directly to the right of the sprite stands the **Group Colour** column: one plate
per Re-color Group of the skin being worn (Shirt, Pants, Cap, Hair, Skin, and any
groups the skin adds), stacked down the column so the palette reads beside the
golfer it dresses. The plates wear the **Visiting Golfers** design — the same pixel
font, cream caption and shared glass card, with the group's colour as a swatch on
the left and its name beside it. Pressing a plate opens the colour picker, and the
colour chosen re-colours that group and follows into the matching profile colour.
A long group name is fitted to the plate rather than widening the column, and a
skin carrying more groups than the column is tall continues in a second column to
the right, where the shelf already scrolls. Like the skin picker, the plates stay
reachable during a round: they only change how a golfer is drawn.
The **Golfer Skin** dropdown and **Move work area** action use the same
pixel-font card frames as the Golfer Traits. They retain their dropdown/action
behaviour rather than becoming On/Off toggles. **Move work area** stands in one
action column immediately to the right of all the Golfer Trait plates; the
Tournament Mode export that used to sit beneath it is now the Pause Menu's
**Save Golfer** card.

**Gender**, **Marital Status** and the five **Golfer Traits** wear the same card
plates as the Golfer Skills. Gender and Marital Status each take a single plate
that always reads the value the golfer has; pressing it steps to the next value
(Male/Female, or Single → Married → Divorced → Widowed → Single), so a whole
choice costs one card instead of a drop-down or a plate per option. Each Golfer
Trait is an independent On/Off plate. Every plate saves as soon as it is pressed,
the same way the name and profession fields do. **Age** uses a matching dark
card readout with separate **−** and **+** buttons. Each press subtracts or adds
one year and saves immediately; the buttons stop at ages 18 and 100. Click the
centre age card to type a number directly, then press Enter or click away to
save. Typed ages are clamped to 18–100; empty or invalid text keeps the last age.
The **Name** and **Profession** fields share the Age card’s dark unselected-Trait face, pixel
font and focus ring. Both remain directly editable and save as you type.
These identity controls share one column: Name at the top, Profession in the
middle, and Age, Gender and Marital Status side by side along the bottom. The
Name and Profession cards span the width of that bottom row. Gender and Marital
Status use narrower cards with Age-like caption padding, sized for their longest
value so cycling choices does not shift the row.

On Edit Player, Gender uses blue for Male and pink for Female. Name, Profession,
Age and Marital Status use the dark unselected Golfer Trait card colour and cream
text rather than the bright selected-Trait fill.

The page also carries an **On the course** column. It names the
ground your own golfer works when they are not playing, and its **Move work area**
button turns the next click on the course into the new ground. See [The Owner's
Golfer on the Course](systems/golf-play/owner-on-the-course.md).

**Play Course** gathers the round setup — your golfer beside the pros, the **+**
card that adds up to three of them, and the **Start Round** card — then the
tournaments the course can host. The shelf ends with those tournament cards: the
**Tournament Mode** exports have moved to the Pause Menu as **Save Course** and
**Save Golfer**, so the shelf no longer carries an export column or its heading.

**The tournament section** is a row of separated ticket cards standing in the
shelf itself: no heading, no note and no scroll view of its own, so the player
scrolls the dock once and the tournaments travel with the round-setup column
beside them. Each tier (`TournamentTierCard`) is the same 226px poster, so the
row reads as a set: a trophy in a recessed well with the tier's rank and field
size above the event's name, the purse in gold with the entry fee quiet at its
right, a perforated fold, the course bar (holes and star rating) with the
reputation the event pays, the **Host Tournament** card, and a gate line under
it. Every ticket wears the shared `PixelButtonStyle` frame the rest of the
dock's cards wear — the drawing is a non-interactive `PanelContainer`, so only
its Host card takes a press — with a prestige colour down the left spine and the
crest, rim and call to action: tier I fairway green, II sky blue, III flag gold,
IV orchid. A qualifying event shows the Host card in the gold call-to-action
frame and its gate line reports what the course keeps (*$800 GATE · $500
SPONSORS*); one that does not keeps the same silhouette with a muted rim, a
dimmed crest, a **Locked** card and the requirement in its gate line (*NEED 18
HOLES (HAVE 9)*), so a ticket never changes size as the course or the treasury
moves. During a cooldown every ticket opens on the same day (*OPENS IN 45 DAYS*),
which keeps the whole section on the shelf instead of emptying it. While an
event runs, the row shows the live board — flag crest, the event and its round,
the owner's scoreline and **Play It Out** — and, beside it, the champions' card
for the last event. In standalone Tournament Mode the post-event row carries the
result card and the three ways on.

Every golfer in that row stands in a square portrait slot sized to
draw the skin at the same height as the **Edit Player Golfer** preview, so the
owner and the pros look the same size on both shelves; the row grows sideways as
pros join it, where the shelf already scrolls.

Removing a pro is an overlay rather than a row of buttons: a small **×** chip
floats over the top-right corner of that pro's own skin sprite, so the shelf
reads as a row of golfers. The chip is transparent and out of the pointer's way
until the portrait is hovered, then it floats in over the golfer (and turns red
under the pointer); moving off the portrait clears it away again. A keyboard or
controller player reveals it by selecting it — the transparent chip stays in the
focus chain, and focusing it floats it back over the sprite, where **Enter**
removes the pro.

The shelf's one action card wears the **Visiting Golfers** card itself rather
than the plain controls of the round setup: the same visiting-green glass frame,
pixel font and cream caption as a visitor plate, widened to hold an action
caption, with the caption lighting under the pointer and the shared focus ring
for keyboard and controller players. **Start Round** is stretched across the
setup column under the golfer and the pros it tees off with. It is a momentary
action, not an On/Off plate. The Career course and golfer are kept from the
**Pause Menu** instead: **Save Course** and **Save Golfer** read the live game,
so Main Menu → Tournament Mode can offer them without the Career save, each
opening its own screen where the keepsake is named, kept or replaced. In
standalone Tournament Mode the owner's round setup steps aside.

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

The Weather, Wind and Seasons rows appear only while their feature is on: with a feature off (the Start New Game options — all three start off on a quick start) that row is left out of the column rather than shown reading "Off" or "Year-round", and the weather/wind block leaves with the last of the two cards. On compact windows the column narrows, but every card stays on screen. Value pills keep 20px of visible padding on each side and extend 20px behind their icon medallion. The compact rating strip packs its five 15x15 stars closer together by overlapping only their transparent texture edges, so it fits the narrower pill without shrinking or cropping the stars. Every card that opens a panel is a normal keyboard-focusable control.

### Course location banner

The top-left corner carries the course location banner (`CourseLocationBanner`), a two-column postcard for the course being played. The first column is a square 1:1 pixel-art picture of the location inside a hairline photo frame with no background of its own — the course shows right up to the frame. `CourseLocationPicture` procedurally paints a different scene for every location from its theme and a seed derived from its id, so each of the world-map sites (and any mod-added location) gets its own deterministic picture: mesas and saguaros in the desert, snowcaps and pines in the mountains, a skyline in the city, palms and volcanic islands in the tropics, fescue dunes on links courses, and so on. The second column is the only part of the banner with a background, a dark card carrying the location's name and the calendar date (with a gold calendar icon; the full weekday date on desktop, a compact stamp on narrow windows). The banner hides while no location is active, swaps its picture and name with a short fade when the player moves between owned courses, and ignores the mouse so shots pass through the corner. The round-score dock stacks directly underneath it.

The two **Rotate** arrows stand in that same corner, on the right of the details card: each turns the course a quarter turn, the same as `Q` and `E`, and they are drawn as mirrored pixel arrows rather than font glyphs. In the card's own top-right corner sits the **facing chip** (`OrientationToggleButton`) — a pixel arrow pointing the way the course faces beside its `N` / `E` / `S` / `W` letter, turned by the same quarter turn a press on either arrow gives. The chip doubles as the switch for the arrows: click it to fold them away when the corner should stay quiet, and click it again to bring them back. It stays in place either way — its arrow and rim are gold while the arrows are out and muted while they are stowed — and the banner narrows back into their room while they are hidden.

## Keyboard

### Screens and panels

| Key | Action |
| --- | --- |
| `Tab` / `Shift+Tab` | Next / previous control |
| Arrow keys | Move focus in the direction pressed |
| `Enter` | Activate the focused control |
| `Esc` | Back, cancel or close the screen |
| `Space` | Activate the focused control (and pause/resume when the course has focus) |

Focus starts on the screen's first action when the screen opens; `Esc` closes it. While a screen is open, `Tab` moves focus instead of toggling the minimap. Long screens scroll to keep the focused control visible, so the whole of Settings, Start New Game, the World Map and the benchmark report is reachable from the keyboard. Settings' four page buttons share the screen header with Back, so the arrow keys walk straight from one category to the next.

### Editing controls

Every course action listed in the `F1` sheet from **Camera**, **Game & saving**, **Clubhouse panels**, **Terrain palette**, **Course tools** and **Controller** is rebindable. Open **Settings → Controls** and click the keycap beside an action, or focus it and press `Enter`/`A`. The keycap reads *Press a key…* until the next key or controller button arrives.

- A key or button already used by another action moves to the action being bound. If that action had no other binding, it takes the binding the new action used, so nothing is left without a key by accident.
- `Backspace` (or `Delete`) unbinds an action. The keycap reads **Unbound** and the action's ↺ button restores its default.
- `Esc` cancels listening without closing Settings; `B` does the same on a controller. `Esc`, `Tab`, `Enter`, the arrow keys, `Backspace`/`Delete` and the controller's `A`, `B`, D-pad and bumpers are reserved for menus and unbinding, and the sticks stay with navigation and the pointer. Triggers and the other controller buttons are free.
- Bindings are applied to the running game immediately and saved to the `controls` section of `user://settings.cfg`. The `F1` sheet always shows the bindings you have now, not the defaults.

Mouse and touch controls are fixed: clicking, dragging, the wheel, pinch and the touch gestures in the table below always work. The menu keys stay fixed too. Arrow keys, `Shift+Tab`, the controller's View/Back button and LB/RB focus the HUD regardless of the course bindings.

### Camera

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | Pan the camera |
| Middle mouse drag | Pan the camera |
| Mouse wheel, `[` and `]` | Zoom |
| `Q` and `E` | Rotate the view counter-clockwise and clockwise |
| `Tab` | Toggle the minimap |
| Arrows | Focus the last HUD control, or move between controls |
| `Shift` + arrows | Move the course pointer when the HUD is unfocused |
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
| `=`, `.`, `R` | Switch the toolbar tabs |
| `V`, `+`, `-` | Elevation tools |
| `F`, `U`, `M`, `Z`, `G`, `C`, `N` | Management shortcuts (`G` Course Milestones, `Shift+G` World Milestones, `Shift+T` Achievements) |

Every key in these tables is a default: change any of them in **Settings → Controls** (see [Editing controls](#editing-controls)). Tool shortcuts are also shown on each tool's tooltip, and the hotkey panel (`F1`) is the full, authoritative list, drawn from the bindings in force.

## Mouse and Touch

- **Mouse.** Left click places or selects. Right click cancels or opens a context menu. The wheel zooms. Every button, card, tile and slider is a normal control, so the pointer hovers, presses and drags exactly as it does on the desktop.
- **Touch.** A tap is a click. One-finger drag pans, or paints terrain while a tool is active. Two-finger drag pans and pinches to zoom — opening the fingers zooms in, closing them zooms out — on the course, the World Map globe and the Course Map alike; a two-finger tap cancels or closes menus. Dragging a scrollable shelf or panel scrolls it instead of moving or painting the course, and dragging off a button cancels its tap. Dragging a slider sets its value directly, without needing mouse emulation. The minimap can be scrubbed with a finger, and the paused game's dimmed backdrop still supports pan and pinch. Compact windows and touchscreen devices get thumb-sized controls and full-width panels so the controls are easier to reach, while the bottom dock keeps its one desktop height in every landscape layout. Every fullscreen screen keeps its content in a scroll region on phone-sized windows, so no action is out of reach.
- **Touch surfaces and what is on top of them.** The globe, the minimap and the Course Map read raw touches themselves, so they see a finger before the shared gesture adapter does. They only claim a touch that actually lands on them: anything drawn above them — a confirmation dialogue, a floating panel — gets the tap, so answers such as **Reset World**/Keep World on the World Map or **Quit to Menu**/Cancel stay tappable even when the dialogue opens over the globe.
- **Pause menu, game-over card and confirmations on small windows.** The pause menu clamps itself to the window and scrolls (a drag on the panel scrolls it) when its options do not fit, so **Quit to Menu** and **Quit to Desktop** never sit below the bottom edge on a phone held sideways; a short window also tightens the spacing and drops the kicker and the course line, leaving up to eight 44px cards in Career mode. The scroll area keeps every card reachable. The game-over card and the confirmation dialogue that follows keep their answers pinned to the bottom and only scroll the text above them, so **Quit to Menu**, **Start New Game**, **Load Saved Game**, **Reset World** and Cancel can always be tapped or focused at any window shape.

## Layout

The portrait composition above is selected by `Screen.uses_portrait_hud()` and
reflowed from `Screen.changed`; desktop and landscape windows keep the same
composition.

`Screen` chooses a compact layout on small windows. Panels then take the full
width and their controls grow for touch, but the bottom dock keeps one height:
the desktop one. Narrowing a window narrows the shelf beside the dock (which
scrolls) instead of making the bar taller, so the dock only leaves the desktop
footprint when the portrait composition replaces it with its thumb rail. The
main window is 1600 × 1000 on desktop.

### UI scale

The game draws at the display's native pixels, so **Settings → Display → UI Scale** starts on **Match this display** and sizes the UI from the device's own system display scale: the Retina backing scale on macOS, the monitor's effective DPI on Windows (125%, 150%, 200%…), the screen density on Android and iOS, `devicePixelRatio` in a browser, and `GDK_SCALE` / `QT_SCALE_FACTOR` on X11 desktops. A 4K or Retina screen therefore gets the same comfortable physical UI size as the rest of the desktop instead of a tiny one, and a phone lays out in density-independent pixels. A windowed desktop window keeps at least a 1180 × 680 logical layout, so shrinking the window on a high-DPI display never leaves a giant, cramped UI; maximised and fullscreen windows use the display's full scale. The automatic scale is re-checked when the window is resized, moved to another monitor or rotated, and when the system scale changes.

Moving the slider pins a manual size (80%–400%). The choice is saved as `ui_scale_mode` and `ui_scale` under `[display]` in `user://settings.cfg`; **Match this display** returns to automatic sizing. The layout is logical, not physical: a 3840 × 2160 window at 200% lays out like a 1920 × 1080 one, and the camera's world scale follows that logical size.

## Related

- [Architecture](architecture.md) explains how the HUD fits into the scene.
- [Systems Index](systems/README.md) links to the systems behind each panel.
