# Device Benchmark

> How the game measures the machine it is running on: frame pacing, a GPU fill-rate ladder, a fixed script-CPU workload, the five-star scorecard they add up to, the shelf of past runs, and the Benchmark Results screen that draws all of it.

**Source:** `scripts/systems/performance_benchmark.gd` (the runner, the GPU test, the scorecard), `scripts/systems/benchmark_history.gd` (the run shelf), `scripts/ui/benchmark_results_screen.gd` (the results screen), `scripts/ui/components/benchmark_visuals.gd` (the charts and meters), `scripts/ui/components/pixel_icon.gd` (the chip, graphics card, pulse and memory sprites), `scripts/ui/settings_menu.gd` (the Display card that starts it)
**Tests:** `tests/unit/ui_and_controls/test_performance_benchmark.gd`, `tests/unit/ui_and_controls/test_benchmark_history.gd`, `tests/unit/ui_and_controls/test_benchmark_results_screen.gd`, `tests/unit/ui_and_controls/test_pixel_icon.gd`, `tests/integration/ui_and_controls/test_save_and_settings_screens.gd`

---

## Plain English

**Settings → Display → Device Benchmark** measures this machine and rates it. One press runs four short tests, in about seven seconds, while the screen behind them stays responsive:

1. **Warm-up**, so the engine is settled before anything is timed.
2. **Frame pacing**, which samples the live scene: how long each frame took, how much of that was game script and how much was physics, and how many objects the renderer drew.
3. **The GPU fill test.** A pixel weave covers the window and is redrawn three times over at growing loads. How fast each load runs gives the graphics hardware's throughput in megapixels a second, and where it starts to fall away.
4. **A fixed script-CPU workload**, the same calculation on every machine, timed by the compute it actually did rather than by the frames it waited through.

Those four become a **performance scorecard**: each metric is graded Eagle, Birdie, Par, Bogey or Double, and together they give the device a rating out of 100 and a five-star tier, from Championship down to Practice Range.

**Full results** opens the **Benchmark Results screen**, which spreads the report out as instruments: an oscilloscope with one column per sampled frame, the GPU load ladder as bars, a segmented meter per metric, the scorecard, the machine's dossier, and a chart of the past runs kept on the shelf so a change of settings (or a different device) can be compared instead of guessed at.

Everything here stays on the machine. Copying a report puts it on the clipboard - it carries device and hardware details - and nothing is ever uploaded.

## Algorithm

### The runner

`PerformanceBenchmark` is a `Node` that walks `Phase`: `WARM_UP → FRAME_PACING → GPU_LOAD → CPU_WORKLOAD`, sliced per frame from `_process()`. It reports `progress_changed(message, fraction)` as it goes and `completed(result)` at the end, and refuses a second `start()` while one is running. `cancel()` stops it and takes the GPU canvas down.

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

`format_report()` writes the plain-text report the copy button puts on the clipboard: versions, device, GPU and renderer, resolution and VSync, the scene, frame pacing, game CPU times, the GPU ladder, memory, the rating and the scorecard. It is versioned - `BENCHMARK_VERSION` is `GTB-2` - because only reports of the same version are comparable.

`BenchmarkHistory` keeps the last `MAX_RUNS` runs as small records in `user://benchmark_history.json`. `record_from()` rounds what it keeps (score, stars, tier, the four metrics, the stutter percentage, memory, the scene, the machine) and `change_percent()`, `series_of()` and `best_of()` are what the screen's comparison chart and its "+12%" deltas are made of. A missing or malformed file is an empty shelf, never an error.

### The results screen

`BenchmarkResultsScreen` composes for the window shape using `MenuScreenKit.layout_mode_for()`, on the World Map's `MenuBackdrop` and in the menus' notched `PixelButtonStyle` frames, Pixelify Sans and `PixelIcon` sprites:

- **Desktop** - three columns: the rating and the device dossier on the left, the oscilloscope with the GPU ladder and the engine read-out under it in the middle, the meters, the scorecard and the shelf on the right. A full-height window shows the whole report without scrolling; a short one scrolls the columns as a page.
- **Tablet landscape** - the rating beside the meters, the charts beside the scorecard and the shelf.
- **Tablet portrait** - the rating and the meters side by side, then the charts, the scorecard, the shelf and the dossier in one scroll.
- **Phone landscape** - a rating and meter column beside a short scroll of the chart and the scorecard.
- **Phone portrait** - one scrolling column, rating first and the dossier last.

The charts are drawn, not themed, by `BenchmarkVisuals`: `FrameChart` (one quantised column per frame, mint under the 60 FPS budget, gold to 33 ms, muted red over it, with both budget lines dashed across it), `BarChart` (the GPU ladder and the shelf), `SegmentMeter` (a metric's meter, lit to its score in the colour that score earns) and `StarRow` (the rating, in the game's own star sprite). Chart heights track the window (`_chart_height()`), so a short window shrinks the oscilloscope instead of pushing the page off the bottom.

The screen runs a benchmark itself, so it can be opened cold and watched filling in, and it is reached from **Settings → Display → Full results** (`SettingsMenu.results_requested`, which `main.gd` opens over the settings menu).

## Tuning Levers

| Constant | Value | File |
| --- | --- | --- |
| `BENCHMARK_VERSION` | `GTB-2` | `performance_benchmark.gd` |
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
| `HISTORY_ROWS` | 5 | `benchmark_results_screen.gd` |

Comparing two reports is only fair when the run measured the same thing: the same course or save, the same camera view, resolution, VSync and power mode. Frame pacing and the GPU test measure the machine as it was at that moment; only the script-CPU score is a fixed workload.

## Related

- [UI & Controls](../ui-and-controls.md) covers the settings card the benchmark runs from and every other screen.
- [Testing](testing.md) covers the suites that check the maths here.
- [Architecture](../architecture.md) explains how systems and screens are separated.
