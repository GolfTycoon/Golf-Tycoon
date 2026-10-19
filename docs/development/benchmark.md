# Device Benchmark

> How the game measures the machine it is running on: the course tour - the only benchmark there is - the frame pacing, GPU fill-rate ladder and fixed script-CPU workload it ends with, the five-star scorecard they add up to, the shelf of past runs, and the Benchmark Results screen that draws all of it.

**Source:** `scripts/systems/course_benchmark_tour.gd` (the tour, the only benchmark), `scripts/systems/course_benchmark_scenarios.gd` (the fixed course matrix it builds), `scripts/systems/performance_benchmark.gd` (the device check the tour ends with, the GPU test, the scorecard), `scripts/systems/benchmark_history.gd` (the run shelf), `scripts/ui/benchmark_results_screen.gd` (the results screen), `scripts/ui/components/benchmark_visuals.gd` (the charts and meters), `scripts/ui/components/pixel_icon.gd` (the chip, graphics card, pulse and memory sprites), `scripts/ui/settings_menu.gd` (the Display card that starts it)
**Tests:** `tests/unit/ui_and_controls/test_performance_benchmark.gd`, `tests/unit/ui_and_controls/test_course_benchmark.gd`, `tests/unit/ui_and_controls/test_benchmark_history.gd`, `tests/unit/ui_and_controls/test_benchmark_results_screen.gd`, `tests/unit/ui_and_controls/test_pixel_icon.gd`, `tests/integration/ui_and_controls/test_save_and_settings_screens.gd`, `tests/integration/ui_and_controls/test_course_benchmark_tour.gd`, `tests/integration/ui_and_controls/test_benchmark_from_main_menu.gd`

---

## Plain English

**The benchmark runs only from Main Menu Settings** (**Settings → Display** on the title screen). Measuring is a title-screen job: a game in progress is never the test scene, so Settings reached from the pause menu shows the last run and the past results but runs nothing.

There is one benchmark, and it is the **full course tour**. It prepares its own throwaway course (timed and sampled as part of the benchmark), then builds every fixed seeded course of `CourseBenchmarkScenarios` on it - preparing each one, camera moves, golfers at every game speed, terrain editing - then takes the course down and hands the Main Menu back. A game in progress is never opened, borrowed or written. One press of **Run Benchmark** runs the whole suite: eleven courses in about 95 seconds, every course type, hole count, field size and game speed, so two runs on two machines are the same work.

The tour ends on the course it built last with a short **device check** of the machine itself, four tests whose screen stays responsive while they run:

1. **Warm-up**, so the engine is settled before anything is timed.
2. **Frame pacing**, which samples the live scene: how long each frame took, how much of that was game script and how much was physics, and how many objects the renderer drew.
3. **The GPU fill test.** A pixel weave covers the window and is redrawn three times over at growing loads. How fast each load runs gives the graphics hardware's throughput in megapixels a second, and where it starts to fall away.
4. **A fixed script-CPU workload**, the same calculation on every machine, timed by the compute it actually did rather than by the frames it waited through.

Those four become a **performance scorecard**: each metric is graded Eagle, Birdie, Par, Bogey or Double, and together they give the device a rating out of 100 and a five-star tier, from Championship down to Practice Range.

**Past Results** opens the **Benchmark Results screen**, which spreads the last report out as instruments - an oscilloscope with one column per sampled frame, the GPU load ladder as bars, a segmented meter per metric, the scorecard, the machine's dossier - and charts the runs kept on the shelf beside it, so a change of settings (or a different device) can be compared instead of guessed at.

Everything here stays on the machine. Copying a report (from the results screen) puts it on the clipboard - it carries device and hardware details - and nothing is ever uploaded.

## Algorithm

### The runner

`CourseBenchmarkTour` owns the run: it walks `Phase` `PREPARE → BUILD → SETTLE → CAMERA → SIMULATE → EDIT → DEVICE` for every course of the suite, then `RESTORE` to take the throwaway course down (the tour's own header comment is the reference for those phases). The tour's last phase hands over to `PerformanceBenchmark`, a `Node` that walks `Phase`: `WARM_UP → FRAME_PACING → GPU_LOAD → CPU_WORKLOAD`, sliced per frame from `_process()`. It reports `progress_changed(message, fraction)` as it goes and `completed(result)` at the end, and refuses a second `start()` while one is running. `cancel()` stops it and takes the GPU canvas down.

Frame pacing samples `_sample_frame()`: the time since the previous frame, and `Performance.TIME_PROCESS` for the script's share. The samples are kept, bucketed down to at most `MAX_SERIES_SAMPLES` points by `downsample_series()`, and stored in the result as `frame.series_ms` - that is what the oscilloscope draws.

### The GPU fill test

`GpuStressCanvas` (an inner class) draws a hard-edged weave of large tiles over the window on a `CanvasLayer` above the UI, so the fill is the renderer's work and not the script's. The tile side is a quarter of the window's shorter edge (`GpuStressCanvas.tile_side_for()`, clamped 96–512 px), which keeps the per-tile cost small next to the pixels each tile fills.

The test runs `GPU_OVERDRAW_LEVELS` in turn. For each level:

```
fill_pixels  = tiles * tile_side^2       # tiles cover the window `overdraw` times
fps          = 1000 / average_frame_ms
megapixels/s = fill_pixels * fps / 1,000,000
gpu_ms       = average_frame_ms - average script ms
capped       = fps >= 0.95 * frame_cap   # the cap, not the hardware, limited it
```

`PerformanceBenchmark.gpu_step_result()` computes one rung and `summarize_gpu()` reduces the ladder to the report's `gpu` section: `levels` (for the chart), `peak_megapixels_per_second`, the `peak_overdraw` it was reached at, and `gpu_ms_per_frame`. A rung that lands on the frame cap is flagged `capped`, which makes the peak a floor rather than a limit - a 60 Hz display cannot show more than 60 frames a second however fast the GPU is.

The test is skipped, and says why, when there is no renderer to fill (`gpu_test_available()`: the headless server, or a run with no rendering driver). A skipped test reports `available: false` and a `reason` rather than zeros that would read as a result.

### The scorecard

Each metric is normalised on a **log scale** between a floor and a ceiling, so a mid-range machine lands near the middle of the range instead of everything clustering at one end:

```
normalize_log(value, floor, ceiling) = log(value / floor) / log(ceiling / floor)
```

| Metric | Floor | Ceiling | Score |
| --- | --- | --- | --- |
| Frame pacing | 20 FPS | 144 FPS | `100 * normalize_log(average_fps, ...)` |
| Script CPU | 120,000 units/s | 2,500,000 units/s | `100 * normalize_log(units_per_second, ...)` |
| GPU fill | 40 MPix/s | 1,200 MPix/s | `100 * normalize_log(peak_megapixels_per_second, ...)` |
| Consistency | - | - | `100 * (0.6 * evenness + 0.4 * smoothness)` |

Consistency (`consistency_score()`) reads two things: the 1% low against the average - a ratio of 0.45 is ragged, 0.90 is glass - and the share of frames that missed 33 ms, where 2% of them spends the whole budget.

The overall score is the weighted mean of the four, and a metric that was never measured drops out with its weight and the rest are scaled back up:

```
overall = Σ (part * weight) / Σ weight        # pacing .30, cpu .25, gpu .25, consistency .20
stars   = clamp(round(overall / 20), 0, 5)
```

`tier_name()` turns the stars into a name (5 Championship, 4 Tour, 3 Club, 2 Municipal, 1 Practice Range, 0 Unrated), `verdict_text()` writes the sentence under them, and `grade_for()` gives each 0–100 metric its golf grade (85+ Eagle, 70+ Birdie, 55+ Par, 35+ Bogey, else Double). `scorecard_rows()` is the table both the report and the screen print: the four graded metrics, then the scene the run measured as an ungraded line, because a heavy scene is not the device's fault.

### The report and the shelf

`format_report()` writes the plain-text report the copy button puts on the clipboard: versions, device, GPU and renderer, resolution and VSync, the scene, frame pacing, game CPU times, the GPU ladder, memory, the rating and the scorecard. It is versioned - `BENCHMARK_VERSION` is `GTB-5` - because only reports of the same version are comparable. GTB-5 is the full Main Menu tour, eleven courses with course preparation in the measured sample; GTB-4 ran the short four-course tour, GTB-3 toured a borrowed open course without those frames.

`BenchmarkHistory` keeps the last `MAX_RUNS` runs in `user://benchmark_history.json`. `record_from()` rounds what the comparison needs (score, stars, tier, the four metrics, the stutter percentage, memory, the scene, the machine) **and keeps the report the record came from**, so a past run is not just a bar on a chart - picking it on the shelf opens it again, report, oscilloscope, scorecard, tour table and dossier and all. `report_of()` / `has_report()` read that copy back (a record written before reports were kept has none, and says so rather than emptying the screen), and `shelf_report()` is what trims it on the way in: the report as it finished, minus the frame series of each tour phase, which nothing draws - the screen's oscilloscope is the run's pooled series - and which would otherwise double the file. A full shelf of twelve full-tour runs is a few hundred kilobytes of local JSON; `change_percent()`, `series_of()` and `best_of()` are what the screen's comparison chart and its "+12%" deltas are made of. A missing or malformed file is an empty shelf, never an error.

### The results screen

`BenchmarkResultsScreen` composes for the window shape using `MenuScreenKit.layout_mode_for()`, on the World Map's `MenuBackdrop` and in the menus' notched `PixelButtonStyle` frames, Pixelify Sans and `PixelIcon` sprites:

- **Desktop** - three columns: the rating and the device dossier on the left, the oscilloscope with the GPU ladder and the engine read-out under it in the middle, the meters, the scorecard and the shelf on the right. A full-height window shows the whole report without scrolling; a short one scrolls the columns as a page.
- **Tablet landscape** - the rating beside the meters, the charts beside the scorecard and the shelf.
- **Tablet portrait** - the rating and the meters side by side, then the charts, the scorecard, the shelf and the dossier in one scroll.
- **Phone landscape** - a rating and meter column beside a short scroll of the chart and the scorecard.
- **Phone portrait** - one scrolling column, rating first and the dossier last.

The charts are drawn, not themed, by `BenchmarkVisuals`: `FrameChart` (one quantised column per frame, mint under the 60 FPS budget, gold to 33 ms, muted red over it, with both budget lines dashed across it), `BarChart` (the GPU ladder and the shelf), `SegmentMeter` (a metric's meter, lit to its score in the colour that score earns) and `StarRow` (the rating, in the game's own star sprite). Chart heights track the window (`_chart_height()`), so a short window shrinks the oscilloscope instead of pushing the page off the bottom.

It is the **Past Results** of the Settings card (**Settings → Display → Past Results**, `SettingsMenu.results_requested`, which `main.gd` opens over the settings menu), and its **Run Benchmark** starts the tour itself, so it can be opened cold and watched filling in. Every row on the shelf is a button: pressing one opens that run - `_select_run(index)` swaps `_result` for the report the record kept and rebuilds, the picked row stays lit, the rating panel wears a **PAST RUN** chip while an older run is on screen, the delta compares against the run before *it*, and **Copy report** copies that run. Opened cold with nothing finished in this session, the screen shows the newest run the shelf can still reopen (`_show_latest_shelved_run()`) rather than an empty report. The Main Menu rule follows it: reached from pause-menu Settings the screen is read-only (`benchmarks_allowed` and `tour_available` are false and Run stands down), so the results screen is never a way around the gate - reading the last report, the shelf and copying always work. `SettingsMenu.origin` records where the menu was accessed from; `main.gd` sets it in `_on_main_menu_settings()` / `_show_settings_menu()` and refuses `start_course_benchmark()` unless the live menus descend from the Main Menu one.

## Tuning Levers

| Constant | Value | File |
| --- | --- | --- |
| `BENCHMARK_VERSION` | `GTB-5` | `performance_benchmark.gd` |
| `DEFAULT_WARMUP_USEC` | 350,000 (0.35 s) | `performance_benchmark.gd` |
| `DEFAULT_FRAME_SAMPLE_USEC` | 2,500,000 (2.5 s) | `performance_benchmark.gd` |
| `DEFAULT_GPU_STEP_USEC` | 700,000 per level (2.1 s total) | `performance_benchmark.gd` |
| `DEFAULT_CPU_SAMPLE_USEC` | 1,500,000 (1.5 s) | `performance_benchmark.gd` |
| `DEFAULT_CPU_BUDGET_USEC_PER_FRAME` | 1,200 | `performance_benchmark.gd` |
| `GPU_OVERDRAW_LEVELS` | `[1.0, 4.0, 10.0]` | `performance_benchmark.gd` |
| `GPU_TEXTURE_GRID` / `GPU_CANVAS_LAYER` | 32 / 100 | `performance_benchmark.gd` |
| `SLOW_FRAME_THRESHOLD_MS` | 33.3 | `performance_benchmark.gd` |
| `MAX_SERIES_SAMPLES` | 180 | `performance_benchmark.gd` |
| `CPU_FLOOR_UNITS` / `CPU_EAGLE_UNITS` | 120,000 / 2,500,000 | `performance_benchmark.gd` |
| `GPU_FLOOR_MEGAPIXELS` / `GPU_EAGLE_MEGAPIXELS` | 40 / 1,200 | `performance_benchmark.gd` |
| `FPS_FLOOR` / `FPS_EAGLE` | 20 / 144 | `performance_benchmark.gd` |
| `EVENNESS_FLOOR_RATIO` / `EVENNESS_EAGLE_RATIO` | 0.45 / 0.90 | `performance_benchmark.gd` |
| `STUTTER_BUDGET` | 0.02 | `performance_benchmark.gd` |
| `SCORE_WEIGHTS` | pacing .30, cpu .25, gpu .25, consistency .20 | `performance_benchmark.gd` |
| `MAX_RUNS` | 12 | `benchmark_history.gd` |
| `DEFAULT_HISTORY_PATH` | `user://benchmark_history.json` | `benchmark_history.gd` |
| `FILE_VERSION` | 2 (records carry their report) | `benchmark_history.gd` |
| `HISTORY_ROWS` | 5 | `benchmark_results_screen.gd` |
| `SUITE_FULL` / `SUITE_IDS` | `full` / `[full]` | `course_benchmark_scenarios.gd` |

Comparing two reports is only fair when the run measured the same thing: the tour run from Main Menu Settings at the same resolution, VSync and power mode (the benchmark prepares its own course, and the preparation, courses, seeds, golfers and camera moves are fixed, which is why every run is the full suite). Frame pacing and the GPU test measure the machine as it was at that moment; only the script-CPU score is a fixed workload.

## Related

- [UI & Controls](../ui-and-controls.md) covers the settings card the benchmark runs from and every other screen.
- [Testing](testing.md) covers the suites that check the maths here.
- [Architecture](../architecture.md) explains how systems and screens are separated.
