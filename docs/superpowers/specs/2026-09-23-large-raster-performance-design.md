# Large-Raster Performance and Size-Aware Processing — Design and Plan

- **Date**: 2026-09-23
- **Target version**: 1.0.1
- **Branch**: `perf/large-raster-1.0.1` (commit locally once the acceptance gate passes; no push)
- **Delivery**: one change set (decision Q1)
- **Source analysis**: large-raster bottleneck review, 2026-09-23 (findings #1–#18),
  `agent-workflow/issues-log.md` ISS-20260923-001

## 1. Goal

Make Rwapor choose how to process a job from its size. A small AOI runs fully in
memory with no tiling. A large AOI, a high-resolution (20 m) AOI, or a long time
series streams or tiles automatically. Results must be numerically the same
whichever mode runs.

## 2. Settled decisions

| ID | Decision |
|---|---|
| Q1 | One change set containing every workstream below. |
| Q2 | Take over `R/wapor_map.R`, `R/wapor_ts.R`, `R/utils.R` and the Shiny modules now. |
| Q3 | Export `wapor_plan_processing()`. Add `processing = c("auto", "memory", "stream", "tiled")` (default `"auto"`) to `wapor_run_seasonal_analysis()` (via `config$processing`), `wapor_map()` and `wapor_ts()`. |
| Q4 | Memory, stream and tiled modes agree within 1e-6 on identical inputs, enforced by tests. |
| Q5 | When `aoi_region` is missing, default it to the extent of `rasters$crop_mask` (or the season rasters) and log a message. |
| Q6 | Memory budget = `terra::free_RAM() × 0.5 ÷ workers`, overridable with `options(Rwapor.memory_budget_mb = …)`. |
| Q7 | `config$keep_intermediates` defaults to TRUE in memory mode and FALSE in stream and tiled modes. When FALSE, heavy fields are dropped. |
| Q8 | Cache lives in `tempdir()` and is deleted at session end. |
| Q9 | Monitoring DuckDB raster blobs (#18) go to a separate issue. Dashboard gets a minimal planner hook: mode, size estimate and reasons, plus an override. |
| Q10 | Version 1.0.1 with NEWS entries. |
| Q11 | **Aggregate at native resolution, then resample once** (the user's proposal). Linear steps run at native resolution, then one resample, then non-linear steps on the analysis grid. Per-pixel seasons are split by profile. |
| Q12 | Leave Codex's `seasonal-dashboard-semantics` board entry untouched. Claude adds its own task entry. |
| Q13 | Branch `perf/large-raster-1.0.1`, commit once all checks pass, no push. |
| Q14 | P95 is exact and uses bounded memory (block-wise histogram, then refine only the bin holding the percentile). Theil is exact and block-wise. |
| Q15 | Mode thresholds: memory below 25% of the budget; stream from 25% to 100%; tiled above 100% or when one layer exceeds 10%. Overridable with `options(Rwapor.plan_thresholds = …)`. |
| Q16 | Parallelism follows the user's `future::plan()`. Inside each worker, terra `memfrac` and the GDAL caches are divided by the worker count. |
| Q17 | Acceptance gate: see §8. |
| Q18 | Superseded by A–D below (the user puts accuracy first and does not want raw server data altered). |
| A | Default resampling for continuous variables becomes `near` (was `bilinear`); `bilinear` and `average` remain available through `config$resampling_method`. Every output value is then a raw server value or a sum of raw values, and the order of sum and resample gives identical results even at gaps (tested 2026-09-23). |
| B | Sum-then-resample is the only order; no `per_layer` switch. Under bilinear it is the more accurate order: its output always lies within the range of raw totals, whereas per-layer produced 42.5 next to raw totals of 40 and 20 in the test. |
| C | New valid-dekad coverage layer and `config$min_coverage` (default 1.0): a pixel is NA unless every dekad in its season has data. Missing dekads are no longer silently counted as 0 mm. The coverage raster is returned. |
| D | Tag the pre-change code as `v1.0.0-final` (a9176dd, done 2026-09-23). The name avoids the `version-1.0.0` branch and the existing published `v1.0.0` tag (82cd8b5, 2026-09-15). NEWS points users there to reproduce older results. |
| Q19 | Split by profile when there are ≤ 64 unique (class, start, end) profiles (`options(Rwapor.max_season_profiles = 64)`). Above that, fall back to per-dekad resampling (the v1.0.0 algorithm) through stream or tiled mode. |

## 3. Architecture

### 3.1 One window kernel shared by every mode (how Q4 holds)

All three modes call the same function:

```
.wapor_process_window(job, window_ext) -> list of analysis-grid rasters for that window
```

| Mode | Windows | Storage of intermediates |
|---|---|---|
| memory | one window = full AOI | terra in RAM |
| stream | one window = full AOI | layer-by-layer accumulation; outputs file-backed in the run folder |
| tiled | many windows (by **extent**, not row/col) | per-tile files, assembled with a VRT; parallel via `future` |

Each output pixel depends only on native pixels inside a fixed halo around it:
2 native cells for bilinear, 1 for nearest. Windows are read from the native
source with that halo, so a tile's pixels match the full-AOI result exactly.
This fixes ISS-20260923-001 by construction: sources are cropped by the
window's **extent**, never by template row/col indices.

### 3.2 Native-then-resample aggregation kernel (Q11)

For a variable V with dekadal layers x_i, per-layer multipliers m_i, and scalar
season weights w_i:

1. Read the native window (with halo) for each layer: a small raster.
2. Accumulate `S = Σ w_i · m_i · x_i` at native resolution, layer by layer
   (`na.rm` semantics as in v1.0.0).
3. Resample or project S once onto the analysis-grid window: `near` for masks
   and Julian days, `bilinear` for continuous variables. The per-variable
   `config$resampling_method` is kept.
4. Apply non-linear steps on the analysis grid: Peff (monthly), adequacy
   ratios, T/AETI, yield, CWP/BWP.

If the native grid equals the analysis grid, skip step 3.

**Per-pixel seasons (profile split)**

- Build a profile-ID raster once on the analysis grid from
  `terra::unique(c(mask, start, end))`.
- For each profile k (K ≤ 64), use its scalar dekad weights w_ik, run steps 1–3,
  and stack the K resampled results.
- Pick each pixel's own profile in one pass with `terra::selectRange(stack, pid)`.
- Uniform seasons are the special case K = 1.
- ETc uses the same path with multipliers `m_i · kc_ik`. This replaces the
  current loop over profiles × months × full grid (finding #6).
- Monthly outputs run the same kernel with the dekads restricted to each month.

**Fallback (K > 64)**: the retained per-dekad path. Resample each dekad onto
the analysis grid, then accumulate one layer at a time. This is the v1.0.0
algorithm, now streamed. The planner reports the path it chose.

### 3.3 Planner

```r
wapor_plan_processing(template = NULL, aoi = NULL, variables, period,
                      indicators = NULL, season_rasters = NULL,
                      workers = future::nbrOfWorkers(), processing = "auto")
```

It returns an object of class `wapor_plan` (with a print method) holding:

- `analysis_grid`: dimensions, resolution, CRS
- `cells`, `n_layers` (dekads per variable), `n_vars`, `n_profiles`
- `working_set_bytes`: `cells × n_layers × n_vars × 8 × 2.5`, plus the native
  footprint of each variable
- `budget_bytes` (Q6), `mode`, `reasons` (a character vector)
- `tile_size`, `batch_size`, `gdal_chunk_bytes`, `aggregation_path`
  (`"native_profile"` or `"per_dekad"`)

`processing` other than `"auto"` forces the mode, but the plan still records
the estimate and warns when a forced memory mode exceeds the budget.

**GDAL HTTP chunk size**: set from the estimated bytes per file window,
clamped to [256 KB, 10 MB]. It is applied through `terra::setGDALconfig()` for
the duration of the job, then restored (finding #12).

### 3.4 Workers and cache

- `.wapor_worker_init(n_workers)` runs at the top of every future worker
  function. It sets `terra::terraOptions(memfrac = 0.6 / n)` and GDAL
  `GDAL_CACHEMAX` / `VSI_CACHE_SIZE` divided by n (Q16).
- `.wapor_cache_dir()` returns `file.path(tempdir(), "rwapor-cache")`. Native
  cropped layers are keyed by
  `digest(variable, date, native window extent, source URL)`. Stream and tiled
  modes use the cache so RET and precipitation are read once for seasonal,
  monthly and ETc outputs. Memory mode keeps them in RAM. Everything is
  deleted with the session (Q8).

## 4. Workstreams (all in one change set)

### WS1: Correctness

- [ ] **#1** Replace the row/col source cropping in `R/analysis_tiled.R`
  (`.wapor_crop_raster_window`, `.wapor_window_source_rasters`,
  `.wapor_read_window_layer`) with extent-plus-halo reads through the shared
  kernel. Row/col slicing stays only for rasters already on the template grid.
- [ ] **#3 / Q5** In `wapor_run_seasonal_analysis()`, when `aoi_region` is
  NULL, derive it from the extent of `rasters$crop_mask` (or `season_start`)
  reprojected to EPSG:4326, and log it. Fall back to the old behaviour only when
  no raster is supplied.

- [ ] **False "no /vsicurl/" warning** at load (`.wapor_check_gdal_capabilities()`,
  `R/gdal_config.R:102`): it fires on this machine even though live
  `/vsicurl/` reads succeed. Detect curl support by capability, not by
  driver-list text, so users stop seeing a wrong and alarming warning.

### WS2: Planner and routing

- [ ] New `R/processing_plan.R`: `wapor_plan_processing()`, print method,
  budget, thresholds, options (`Rwapor.memory_budget_mb`,
  `Rwapor.plan_thresholds`, `Rwapor.max_season_profiles`).
- [ ] New `R/processing_kernel.R`: `.wapor_process_window()`, the native
  aggregation kernel, the profile split, the per-dekad fallback, halo
  arithmetic, and windows by extent.
- [ ] `wapor_run_seasonal_analysis()` becomes: resolve config → default AOI →
  plan → run windows → assemble → `keep_intermediates` (Q7).
  - `wapor_run_seasonal_analysis_tiled()` stays exported as a thin wrapper
    (`processing = "tiled"`) that keeps its manifest, resume, COG and VRT
    behaviour.
  - Multi-period lists re-plan per season.
- [ ] `wapor_suggest_tile_size()`: default to 8 bytes per value, add `n_vars`
  (default 1) and an overhead factor. Delegates to the planner (#15).

### WS3: Engine memory hotspots

- [ ] **#4** `wapor_build_season_weights()` returns scalar weight vectors per
  profile. The raster form is kept as a lazily materialised helper for callers
  that need it.
- [ ] **#5** `wapor_masked_sum()` always accumulates in a single pass (no
  `x * weights` copy of the whole stack). The `incremental` argument stays for
  compatibility but no longer changes results.
- [ ] **#6** ETc (seasonal and monthly) through the profile kernel. Removes the
  duplicate `profile_mask` construction (`R/analysis_engine.R:449`, `:473`).
- [ ] **#7** Fold the crop mask into the window's validity mask once, and
  delete the roughly 20 `.mask_result_raster` passes at the end of the engine.
- [ ] **#8** Replace full `terra::values()` reads:
  - `R/analysis.R:188` becomes `global(notNA)`
  - `R/analysis_validation.R:395` becomes `terra::unique()`
  - `wapor_pixel_area_ha()` becomes `terra::cellSize(unit = "ha")`
  - `R/indicators_math.R:110` becomes `terra::zonal()` / `global()` when given
    rasters
- [ ] **#9 / Q14** Exact P95:
  1. `zonal` min and max per class.
  2. Bin with `classify`, then block-wise `terra::crosstab(c(class, bin))`
     counts.
  3. Locate the bins that hold the order statistics ⌊h⌋ and ⌈h⌉ (type-7
     quantile).
  4. Pull only those bins' values per class, refining recursively until the bin
     has ≤ 1e6 values.
  5. Interpolate as `stats::quantile(type = 7)` does.
- [ ] **Theil** exact and block-wise:
  `T = Σx·ln x / (N·μ) − ln μ`, from `zonal` sums of x, x·ln x and N (for x > 0).
- [ ] **Q7** `keep_intermediates = FALSE` drops `dekadal_stacks` and
  `season_weights`. Monthly series stay, but file-backed.
  - `ctx$season_weights` for registry extra steps becomes an active binding
    (`makeActiveBinding`) that materialises only when a step reads it.
  - `wapor_export_*` with `include_dekadal = TRUE` forces
    `keep_intermediates = TRUE`.

### WS4: Download, time series and trend (files taken over from Codex, Q2)

- [ ] **#10** `download_seasonal_rasters()`: batch each temporal-code group by
  the plan's `batch_size`. `wapor_map()` seasonal mode accumulates weighted sum,
  weight and valid count per batch in one pass (removes the `r*mult`,
  `ifel(is.na)` and `!is.na` full stacks).
- [ ] **#11** `wapor_map()` non-seasonal: assemble chunk files with a VRT and
  write once. Remove redundant `classify(NA → -9999)` wherever `NAflag` is
  already set (about 6 sites). Default outputs use the tiled, compressed,
  predictor and BIGTIFF options from `wapor_write_cog()`.
- [ ] **#16** `wapor_ts()`: no `terra::crop` before `exact_extract` for polygon
  AOIs. Seasonal mode uses one pass of `c("mean", "count")` instead of two
  passes (mean, plus sum over `!is.na`). Set `max_cells_in_memory` from the
  plan.
- [ ] **#17** `linear_trend()`: closed-form, NA-aware layer arithmetic
  (n, Σt, Σy, Σty, Σt², Σy²) instead of an R closure per pixel. Must match the
  current output within 1e-6.
- [ ] `processing` argument wired through `wapor_map()` (chooses batch size and
  accumulation) and `wapor_ts()` (chooses batch size and `max_cells_in_memory`).

### WS5: I/O and parallelism

- [ ] **#12** Chunk size set per job by the plan (§3.3).
- [ ] **#13** Crop-once tempdir cache (§3.4). The tiled engine no longer
  writes per-tile copies of every source (`R/analysis_tiled.R:252-270`,
  `883-896`).
- [ ] **#14 / Q16** `.wapor_worker_init()` in the `wapor_map`, `wapor_ts` and
  tiled workers. Tiles run through `future.apply::future_lapply` under the
  user's `future::plan()`.

### WS6: Dashboard hook (Q9)

- [ ] `inst/shiny/mod_analysis.R`: before a run, show the `wapor_plan` summary
  (mode, estimated working set against the budget, and reasons), with a
  `selectInput` override (auto, memory, stream, tiled) passed as
  `config$processing`. The existing "incremental" checkbox is removed; the
  planner replaces it.

### WS7: Documentation, bookkeeping and version

- [ ] Roxygen for every new or changed export. Run `devtools::document()`.
- [ ] `vignettes/global-tiled.Rmd` rewritten around `processing = "auto"` and
  `wapor_plan_processing()`.
- [ ] `NEWS.md` 1.0.1 section covering:
  - the planner and the `processing` argument
  - the AOI default (Q5)
  - native-then-resample and the small differences near NA gaps (Q18)
  - the tiled-engine fix
  - the `wapor_suggest_tile_size()` default change
  - the removed "incremental" dashboard checkbox
- [ ] `DESCRIPTION`: version 1.0.1; add `ps` to Suggests (for the benchmark).
- [ ] New issue for #18 (DuckDB blobs). Resolve ISS-20260923-001 once fixed.
- [ ] Update `task-status.md`, `agents-board.json` (Claude's own task; Codex's
  entry untouched), `change-log.md` and `session-brief.md`.

## 5. Implementation order (within the single change)

1. Branch, then claim the board task.
2. WS2 kernel and planner skeleton, plus equivalence test scaffolding
   (tests first).
3. WS1 and WS3 through the kernel.
4. WS5.
5. WS4.
6. WS6.
7. WS7.
8. Acceptance gate.
9. Commit.

The v1.0.0 per-dekad path is kept as the internal fallback throughout, so
regression tests always have a reference implementation.

## 6. Tests (new or extended `tests/testthat/`)

- `test-processing-plan.R`
  - mode selection at the threshold boundaries
  - option overrides
  - forced mode warns when it exceeds the budget
  - chunk-size clamping
  - worker division
- `test-processing-equivalence.R`: memory, stream and tiled agree within 1e-6
  for:
  1. a source offset from the template
  2. a source at a different resolution (300 m to 20 m-style ratio of 15)
  3. per-pixel seasons (K > 1)
  4. a cross-year season
  5. K > 64 (fallback path)
  6. a different CRS (projected template)
- `test-native-resample-regression.R`: the new kernel matches the retained
  v1.0.0 per-dekad path within 1e-6 on gap-free data, with a bounded tolerance
  when there are NA gaps (Q18).
- ISS-20260923-001 reproduction: the offset-grid test from the issue must read
  `4041 4042 4043`.
- Exact P95 equals `stats::quantile(type = 7)` per class. Exact Theil equals
  the current `values()` implementation.
- `linear_trend()` closed form equals the current closure.
- `wapor_ts()` single-pass seasonal equals the two-pass result.
- The AOI default is derived from the crop mask and logged.
- `keep_intermediates` behaviour, and the lazy `ctx$season_weights` binding.

## 7. Benchmark and smoke-test assets

- `inst/bench/large_raster_benchmark.R`
  - Synthetic 20 m-scale grid (for example 5000 × 5000 cells, 36 dekads, 3
    variables; stream and tiled forced).
  - Measures peak process memory with `ps::ps_memory_info()`, sampled in a
    background process.
  - Compares the v1.0.0 path against v1.0.1 for memory, stream and tiled.
  - Also times a small in-memory job (500 × 500 cells).
- `inst/bench/remote_smoke_test.R`: a ready-to-run live `/vsicurl/` test for the
  user (L1 and L3, a small farm AOI and a large one). Prints the plan, mode,
  timing, and HTTP bytes when available.

## 8. Acceptance gate (Q17)

1. `devtools::test()` passes, including every test in §6.
2. `devtools::check()` gives 0 errors, 0 warnings and no new notes.
3. The benchmark shows stream and tiled peaks under budget, and the small
   in-memory job is no more than 10% slower than v1.0.0.
4. `inst/bench/remote_smoke_test.R` runs live against the WaPOR API from this
   machine (verified 2026-09-23: `/vsicurl/` works here; a crop of the global
   L1-AETI-D COG, 61440 x 122880 pixels, read in about 10 s). The script ships
   with the package so users can run it too.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Halo too small, so bilinear values at window edges differ | Halo derived from the resampling method plus a 1-cell safety margin. Equivalence test 1 checks tile edges explicitly. |
| terra spills to disk unpredictably, skewing memory estimates | Conservative 2.5× overhead factor; thresholds calibrated against measured benchmark peaks. |
| Profile split changes semantics for pixels outside any class | Validity mask applied once per window; tests with NA classes. |
| Third-party registry steps rely on eager `ctx$season_weights` / `stacks` | Active bindings materialise on access; the registry test suite runs unchanged. |
| Taking over Codex-claimed files (Q2) with Codex's entry left untouched (Q12) | Claude's own board task lists the files; `change-log.md` records the takeover so Codex sees it before editing. |
| Behaviour changes in 1.0.1 (AOI default, NA-gap differences, tile-size default, removed checkbox) | All listed in NEWS; regression tests bound the numeric differences. |

## 10. Implementation notes (2026-09-23)

Where the build differs from the plan above:

- **Profile split**: instead of stacking K resampled rasters and calling
  `terra::selectRange()`, the kernel accumulates native sums per unique weight
  vector with one matrix product per dekad batch, resamples one output at a
  time, and picks each pixel's column in R. Aligned sources skip resampling and
  sum each pixel with its own profile's weights, so they have no profile limit.
- **Read-once instead of a disk cache (Q8)**: every output that uses the same
  files (RET totals and ETc) is accumulated from a single read per window, and
  seasonal plus monthly totals come from the same pass. No separate tempdir
  cache of cropped layers was needed.
- **Memory control beyond the kernel**: in stream and tiled modes the engine
  sets terra `memmax` to the budget and `todisk = TRUE` (8-byte files) for the
  rest of the run, so derived indicators are file-backed; memory is released
  between tiles. The planner's working-set model carries a 1.5x factor for R
  temporaries.
- **Findings during implementation** (see NEWS 1.0.1): remote analysis never
  matched WaPOR `YYYY-MM-D1` file names in 1.0.0; the GDAL curl probe always
  reported "missing"; 1.0.0 bilinear resampling was biased at area edges by a
  crop before resampling; tiled windows on grids like 0.0002 deg needed
  nearest snapping.
- **Acceptance gate status**: items 1, 2 and 4 met. Item 3 partly: the full
  benchmark ran before the final memory fixes; after them, per-stage profiling
  of the benchmark job stayed within budget, but the final full rerun could not
  complete because the C: drive was full.
