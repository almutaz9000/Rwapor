# Issues Log

_Operational issue tracker for agents. See `templates/issue-entry.md` for the
entry format. Stable IDs: `ISS-YYYYMMDD-###`._

## Open

### ISS-20260925-007 — A supplied crop mask is silently ignored unless `use_crop_mask = TRUE`

- **Where**: `R/analysis_engine.R`, harmonize-mask block (`if (isTRUE(config$use_crop_mask))`).
- **Root cause**: without the flag the engine replaces the mask with `template * 0 + 1`,
  so every AOI pixel becomes class 1, with no message.
- **Impact**: with a rectangular AOI (Jendouba wheat) every land pixel would be analysed
  as the crop. Found while testing the training notebook (2026-09-23).
- **Fix / mitigation**: not fixed in the package. Notebook sets `use_crop_mask = TRUE`
  and explains it in a Watch out box. Proposed: default TRUE when `rasters$crop_mask`
  is a SpatRaster, warn on explicit FALSE (task ti-04).
- **Regression tests**: none yet.

### ISS-20260925-008 — Local reader also picks up `<VAR>_seasonal` files next to the dekads

- **Where**: `R/analysis.R` `wapor_local_rasters()` (scans `<folder>/<VAR>` and
  `<folder>/<VAR>_seasonal`).
- **Impact**: a seasonal file written by `wapor_map(seasonal = TRUE)` into the same
  folder as the dekadal files can be read as an extra layer by
  `data_source = "local"` runs.
- **Fix / mitigation**: not fixed in the package. Notebook keeps dekadal data in
  `wapor_data/<case>/dekadal/`, separate from the first-look seasonal maps.
  Proposed: ignore `_seasonal` unless asked (task ti-06).
- **Regression tests**: none yet.

### ISS-20260925-009 — Large L3 runs fill the disk

- **Where**: `R/analysis_engine.R` (`keep_intermediates` defaults to TRUE in memory
  mode and materialises every dekadal stack; derived rasters FLT8S),
  `wapor_export_analysis_outputs(include_dekadal = TRUE)`.
- **Evidence**: Jendouba wheat (5.1 M cells, 21 dekads, 5 variables) failed with
  "No space left on device" at 8 GB free; passed with `keep_intermediates = FALSE`
  and `include_dekadal = FALSE` (2026-09-24).
- **Fix / mitigation**: not fixed in the package; notebook sets both flags and the
  participant note asks for 20 GB free. Proposed: new defaults, Float32, a disk-space
  estimate in the planner (task ti-08).
- **Regression tests**: none yet.

### ISS-20260924-006 — `wapor_map(seasonal = FALSE, separate_files = TRUE)` drops the WaPOR scale factor

- **Where**: `R/wapor_map.R` per-layer write path (around lines 557-570,
  `terra::writeRaster(r_out, out_path, ...)`).
- **Symptom**: saved files hold raw WaPOR integers as Float32 with scale 1
  (L3-AETI-D values 1 to 30 instead of 0.1 to 3.0 mm/day; the remote COG is
  Int16 with `Scale: 0.1`). Reading them with `data_source = "local"` gives
  seasonal AETI about 10 times too high (JVA citrus 2024/25: 10,557 mm vs
  1,035.86 mm from the API run).
- **Impact**: any offline workflow built on `wapor_map(separate_files = TRUE)`
  downloads; the seasonal (`seasonal = TRUE`) path is not affected.
- **Fix / mitigation**: not fixed in the package. The training notebook
  downloads with `terra::rast("/vsicurl/...")` + `crop` + `writeRaster`
  (terra applies the scale on read); the local run then matches the API run
  exactly (1,035.86 mm, ETc 1,056.4 mm, adequacy 0.98). Suggested package fix:
  apply `terra::scoff()` before writing, or write Int16 with the scale kept.
- **Regression tests**: none yet (write a one-layer Int16 raster with scale
  0.1, save via the separate-files path, assert values are scaled).
- **Verification**: reproduced 2026-09-24 with installed Rwapor 1.0.2.

### ISS-20260923-005 — Seasonal green/blue water computed from seasonal totals (methodology)

- **Where**: `R/analysis_engine.R:486-489` —
  `results$green_water` / `results$blue_water` call `wapor_calc_green_water()` /
  `wapor_calc_blue_water()` on `seasonal_aeti` and `seasonal_peff`.
- **Root cause**: `min(AETI, Peff)` is applied to seasonal sums. The correct
  method (raised by the user, 2026-09-23) splits per month and sums:
  `green = Σ_m min(AETI_m, Peff_m)`, `blue = Σ_m max(0, AETI_m − Peff_m)`.
  Monthly because the USDA-SCS Peff formula is monthly.
- **Impact**: seasonal green water is overestimated and blue water
  underestimated whenever wet-month surplus rain coincides with dry-month
  irrigation (Σ min ≤ min Σ). Affects exports, Shiny outputs, and anything
  reading `results$green_water` / `results$blue_water`.
- **Fix / mitigation**: FIXED in 1.0.2 (user approved 2026-09-23): the engine's
  seasonal `green_water` / `blue_water` are now `Reduce("+", monthly_*$rasters)`.
  The unused registry step `step_peff_green_blue` (`R/analysis_registry.R:524`,
  skipped by the engine) still splits seasonal totals — align it if it is ever
  re-enabled.
- **Regression tests**: `tests/testthat/test-analysis-engine.R` — "seasonal
  green/blue water sum the monthly splits" (wet Jan / dry Feb: expects green 31,
  blue 140; old code gave 156 / 15). Failed before the fix, passes after.
- **Verification**: engine, processing, indicators, shiny-analysis and export
  test files pass after the change.

### ISS-20260923-004 — `wapor_export_analysis_outputs()` errors on a single-season result

- **Where**: `R/analysis_utils.R:826`, multi-season detection
  `!is.null(results[[1]]$h_mask)`.
- **Root cause**: for a single-season result `results[[1]]` is the `h_mask`
  SpatRaster; `$h_mask` on a SpatRaster is a layer-name subset, and terra errors
  ("[subset] invalid name(s)") unless the layer happens to be called `h_mask`.
- **Impact**: the documented single-season call
  `wapor_export_analysis_outputs(results = season, season_label = ...)` fails
  whenever the crop mask layer has any other name (e.g. `crop_mask`).
- **Fix / mitigation**: not fixed in the package. Training notebook passes
  `results = list(<label> = season)`. Suggested fix: test
  `is.list(results[[1]]) && !inherits(results[[1]], "SpatRaster")` before `$`.
- **Regression tests**: none yet.
- **Verification**: reproduced in `training/water-productivity-training.qmd`
  chunk `citrus-export` with installed Rwapor 1.0.1.

### ISS-20260923-003 — 1.0.1 kernel rejects `ref_year = 1970` (Shiny app + vignettes still pass it)

- **Where**: `R/processing_kernel.R` `.wapor_profile_key_raster()` (range check
  "Season start/end values must lie between -1000 and 999 days"), introduced in
  `e10ba99`. Callers still passing 1970: `inst/shiny/mod_analysis.R:1340`,
  `vignettes/advanced-analysis.Rmd:82`, `vignettes/wheat-water-productivity.Rmd:96`,
  default in `R/analysis.R:1078`.
- **Root cause**: season start/end are day offsets from `ref_year`; with 1970 a
  2024 season is ~19 800 days, outside the packed profile-key span.
- **Impact**: `wapor_run_seasonal_analysis()` errors for any config with
  `ref_year = 1970` — worked in 1.0.0.
- **Fix / mitigation**: not fixed yet (found while testing the training notebook;
  package change not in that task's scope). Notebook omits `ref_year` so the
  engine derives it from the season start year. Suggested package fix: rebase
  start/end rasters to the season-start year inside the kernel job, or drop the
  1970 defaults.
- **Regression tests**: none yet.
- **Verification**: reproduced by rendering `training/water-productivity-training.qmd`
  (chunk `citrus-run-analysis`) with installed Rwapor 1.0.1.

### ISS-20260923-002 — Monitoring stores whole rasters as DuckDB blobs

- **Where**: `R/wapor_monitoring.R` (around lines 982-985 and 1054-1059):
  `monitoring_rasters.raster_blob` / `farm_rasters.raster_blob`, read back with
  `wapor_raster_from_blob()`.
- **Root cause**: each monitoring raster is serialised into the database; every
  query deserialises the whole raster before `terra::crop()` to the farm.
- **Impact**: memory and time grow with the stored raster size, not the farm
  size; windowed reads are impossible.
- **Fix / mitigation**: not fixed (out of scope for 1.0.1 by user decision Q9;
  it changes the storage format and needs a migration). Suggested: store COG
  file paths (or object-store URLs) in the table and read windows with terra.
- **Regression tests**: none yet.
- **Verification**: code reading during the 2026-09-23 performance review.

### ISS-20260922-001 — `vignettes/wheat-water-productivity.Rmd` references non-working/non-existent function calls

- **Where**: `vignettes/wheat-water-productivity.Rmd`.
- **Found during**: building an independent training notebook
  (`training/water-productivity-training.qmd`) that had to call the real
  seasonal-analysis pipeline end-to-end, which required tracing every
  indicator code and helper function against `R/analysis_engine.R`,
  `R/analysis_registry.R`, and `NAMESPACE` rather than copying the vignette.
- **What was found** (not fixed here — the vignette itself was left
  untouched per this session's "don't modify Rwapor" scope):
  1. Step 3's `indicators` vector includes `"peff"`, but
     `R/analysis_engine.R` only checks for the string `"agg_peff"`
     (`.wapor_builtin_indicator_steps()` also lists `"agg_peff"`, not
     `"peff"`). `"peff"` is silently inert — it never populates
     `results$seasonal_peff`.
  2. Step 7 reads `wheat_season$summary_table` and
     `s$summary_table$cwp_bwp_mean` — grepped the entire `R/` tree for
     `summary_table` and found no assignment anywhere. This field does not
     exist on the list returned by `wapor_run_seasonal_analysis()`. The real
     productivity outputs are the scalars `results$cwp` / `results$bwp`
     (area-weighted global means) plus the various `*_by_class` data frames
     (e.g. `seasonal_aeti_by_class`).
  3. Step 5's closing paragraph points to `wapor_compare_seasons()` for
     multi-season CV/Theil comparison — this function is not in `NAMESPACE`
     and does not exist anywhere in `R/`. The real (exported) multi-season
     tools are `wapor_calc_zscore()`, `wapor_calc_spatial_hotspots()`, and
     `wapor_calc_anomaly_baseline()` (see `vignette("advanced-analysis")`
     §4, which already demonstrates the correct pathway).
  4. Separately (not a vignette bug, a usability gap): `wapor_run_seasonal_analysis()`
     accepts an `aoi_region` argument that scopes every streamed raster to
     the AOI before loading it; the vignette's examples never pass it, so
     copying them verbatim for a real `data_source = "api"` run downloads
     the *full extent* of each WaPOR tile before the `crop_mask` narrows it
     down. Worth flagging in the vignette or defaulting `aoi_region` from
     `rasters$crop_mask`'s extent when omitted. **Item 4 is addressed in 1.0.1**:
     `wapor_run_seasonal_analysis()` now defaults `aoi_region` to the crop mask /
     season raster extent and logs it (branch `perf/large-raster-1.0.1`).
- **Suggested fix**: change `"peff"` → `"agg_peff"` in Step 3; replace the
  `summary_table` references in Step 7 with `$cwp`/`$bwp`/`*_by_class`;
  replace the `wapor_compare_seasons()` mention with the three real
  functions above; add an `aoi_region` example (or a callout) to Step 3.

## Resolved

### ISS-20260923-001 — Tiled engine read source layers with template row/col indices (silent all-NA output)

- **Where**: `R/analysis_tiled.R` (`.wapor_crop_raster_window()` via
  `.wapor_window_source_rasters()` / `.wapor_read_window_layer()`), v1.0.0.
- **Root cause**: tile windows were row/col ranges on the template grid but were
  applied as `layer[r0:r1, c0:c1]` to source layers on other grids, so the crop
  landed at the source's top-left corner; `resample(near)` then found no
  overlap and the tile was all NaN, without an error.
- **Impact**: every tiled run on remote WaPOR files or mixed-resolution inputs.
- **Fix / mitigation**: tiling moved into the shared kernel
  (`R/processing_kernel.R`); sources are read by extent plus a halo of native
  cells. The buggy helpers were removed.
- **Regression tests**: `test-processing.R` ("an offset source is read at the
  right place"), mode-equivalence tests, rewritten `test-analysis-tiled.R`.
- **Verification**: offset read returns `4041 4042 4043`; full suite 0 failures;
  live L1 run: tiled equals memory, max |diff| 0 (2026-09-23).

### ISS-20260923-003 — Remote seasonal analysis could not match WaPOR dekad file names

- **Where**: `.wapor_ymd_from_name()` (`R/analysis_tiled.R`) used by the engine's
  dekad alignment.
- **Root cause**: WaPOR remote files are named `YYYY-MM-D1/D2/D3`; only
  `YYYY-MM-DD` and 8/12-digit dates were parsed.
- **Impact**: `wapor_run_seasonal_analysis(data_source = "api")` stopped with
  "Missing data for some dekads in the analysis period" for every request.
- **Fix / mitigation**: `D1/D2/D3` map to days 01/11/21.
- **Regression tests**: `test-processing.R` ("WaPOR dekad labels are parsed").
- **Verification**: live, 2026-09-23: `v1.0.0-final` worktree fails with the
  message above; branch `perf/large-raster-1.0.1` runs (5/5 smoke checks).

### ISS-20260923-004 — GDAL curl capability probe always reported "missing"

- **Where**: `.wapor_check_gdal_capabilities()` (`R/gdal_config.R`) and
  `wapor_remote_capabilities()` (`R/remote_capabilities.R`).
- **Root cause**: both searched `gdal_drivers$longname` for "vsicurl"; the
  column is `long.name`, and `/vsicurl/` is a virtual file system, not a driver.
- **Impact**: a false "streaming will fail" warning on every package load; with
  `options(Rwapor.remote_fallback = "download")` whole files were always
  downloaded.
- **Fix / mitigation**: curl support is detected from GDAL's `HTTP` driver.
- **Regression tests**: `test-gdal_config.R` (resolver error and stream modes,
  capabilities set explicitly).
- **Verification**: live `/vsicurl/` reads succeed and the probe reports
  streaming available (2026-09-23).

### ISS-20260917-001 — Dashboard crashes on every `board_claim.ps1` update (UTF-8 BOM)

- **Where**: `agent-workflow/dashboard/app.py`.
- **Root cause**: `load_board()` decoded `agents-board.json` as plain
  `utf-8`. `board_claim.ps1` (`Set-Content -Encoding utf8` on Windows
  PowerShell) always writes a UTF-8 BOM, which `json.loads`/`.read_text()`
  reject outright. This meant the dashboard had been broken since the very
  first `board_claim.ps1` call ever made against the file -- the original
  `coord-board-v1` smoke test passed because it ran before any
  `board_claim.ps1` write existed (hand-authored JSON has no BOM).
- **Fix**: Decode with `utf-8-sig` instead (tolerates a BOM or no BOM).
- **Verification**: relaunched the dashboard on a test port, confirmed
  `HTTP 200` with no traceback in the log (previously a full
  `JSONDecodeError` traceback rendered in-page); a direct script using the
  same load path confirmed correct task/status data (42 tasks, correct
  done/pending counts).

### ISS-20260917-002 — Task tracker (task-status.md / agents-board.json / IMPROVEMENT_PLAN.md) drifted from actual code state

- **Where**: `agent-workflow/task-status.md`, `agent-workflow/agents-board.json`,
  `IMPROVEMENT_PLAN.md`.
- **Found during**: a critical re-review of "pending" tasks requested by the
  user, cross-checking each task's described deliverable directly against
  the codebase (grep for the named functions/files) rather than trusting the
  tracker.
- **What was found**: several tasks listed as fully "pending" were actually
  substantially or fully implemented already:
  - **2.2 (COG write support)** -- fully done (`wapor_write_cog()` exported
    and used throughout) except `cog=FALSE` missing from
    `wapor_run_seasonal_analysis()` and no GDAL<3.1 fallback.
  - **3.1 (9 extra FAO-56 crops)** -- fully done, all 9 crops present.
  - **1.6 (reference_layer param)** -- the core parameter is done, exact
    match to spec; missing `resampling_method` per layer.
  - **3.4 (anomaly module)** -- 3 of 4 functions done and exported; missing
    `linear_trend`.
  - **5.1 / 5.2 (test coverage)** -- both test files already exist with
    real coverage, just short of the full spec (Python parity, 100x100
    grid / multi-season / local-vs-API specifics not confirmed).
  - **6.1 (vignettes)** -- 4 vignettes exist, but none under the 5
    originally-specified names/scopes.
  - **6.2 (README install guide)** -- system deps and verify step present;
    missing only the terra-from-GitHub install note.
- **Likely cause**: `IMPROVEMENT_PLAN.md`'s task list predates a lot of
  since-landed work (`feat/l3-mosaic-tiled-core`, the 2026-09-15 production
  hardening pass, etc.) and was never swept for completions; the
  2026-09-16 `agents-board.json` back-filled these as "pending" from the
  stale prose file without independently checking the code.
- **Fix**: Corrected task status/notes in `IMPROVEMENT_PLAN.md` (checkboxes)
  and `agents-board.json` (2.2, 3.1 -> done; 1.6, 3.4, 5.1, 5.2, 6.1, 6.2 ->
  notes updated with exactly what's done vs missing, status kept pending
  for the genuine remaining gap).
- **Lesson**: before starting any "pending" task from this tracker, grep
  the codebase for its named deliverable first -- the tracker is a lagging
  indicator, not ground truth. See `project-memory.md`.

### ISS-20260916-002 — Duplicate `%||%` with conflicting semantics; triplicated level->URL mapping

- **Where**: `R/utils.R`, `R/wapor_metadata_cache.R`, `R/api_client.R`,
  `R/metadata.R`.
- **Root cause**: `%||%` was defined twice -- `R/utils.R:8`
  (`is.null()`-only) and `R/wapor_metadata_cache.R` (also `length() > 0`).
  `DESCRIPTION` has no `Collate:` field, so R loads `R/*.R` alphabetically;
  `wapor_metadata_cache.R` loads after `utils.R` and its definition silently
  overwrote the package-wide `%||%` binding for ~40 call sites across
  `crop_defaults.R`, `wapor_ts.R`, `wapor_map.R`, `analysis_engine.R`,
  `analysis_tiled.R`, `wapor_monitoring.R`, `wapor_cog.R`,
  `rwapor_favorites.R`, `analysis_utils.R`. Separately, the FAO catalogue
  workspace URL for a level was hardcoded independently in three files
  (`wapor_generate_urls_internal()`, the `url_map` inside
  `wapor_update_metadata()`, and a `switch()` inside
  `.fetch_metadata_api_variable()`); the `wapor_update_metadata()` copy had
  already drifted (missing `AGERA5`).
- **Fix**: Deleted the duplicate `%||%`; kept one canonical definition in
  `R/utils.R`. Verified against the full test suite which one is correct --
  `tests/testthat/test-wapor_metadata_cache.R:104` requires the
  length-aware behavior, because `jsonlite::write_json()` round-trips a
  `NULL` list element as an empty *non-`NULL`* list, not `NULL`, so a plain
  `is.null()` check would have kept the empty list instead of falling
  through to the real default. Added `.wapor_level_workspace_url(level)` in
  `R/api_client.R` as the single source of truth for the URL mapping.
  **Correction (2026-09-17)**: the 2026-09-16 fix was reported as routing
  all three call sites through the helper but actually only did 2 of 3 --
  `.fetch_metadata_api_variable()` in `metadata.R` still had its own
  hardcoded `switch()`. Caught via diff self-review while implementing
  Phase 7.1 the next day and fixed then; all three sites are genuinely
  consolidated as of 2026-09-17.
- **Verification**: `devtools::load_all()` clean; `devtools::document()`
  produced no unexpected `NAMESPACE`/`man/` diffs; full test suite
  `0 fail / 1019 passed` (an intermediate `1 fail / 1018 passed` was caught
  and fixed before this was considered done).

### ISS-20260916-001 — Metadata service duplication and resolution ambiguity

- **Where**: `R/metadata.R`, `R/wapor_metadata_cache.R`,
  `R/plan_wapor_time_slices.R`, `R/wapor_res_key.R`.
- **Fix**: Unified API and bundled metadata normalization, separated level,
  temporal resolution, and spatial resolution, added atomic snapshots and a
  manifest, and routed temporal planning and resolution grouping through the
  validated catalogue.
- **Verification**: Full test suite passed with 0 failures; bundled L1/L2/L3
  snapshots validated for unique codes and matching level/temporal fields.

### ISS-20260903-002 — L3 seasonal planning trusts a static, region-blind availability list

- **Where**: `wapor_temporal_codes()` in `R/plan_wapor_time_slices.R`.
- **Resolution**: Temporal availability now starts from the validated metadata
  catalogue and, for L3 requests with a region and period, checks actual URLs
  for each candidate resolution before planning. Static metadata remains only
  as a controlled fallback.
- **Verification**: Planner and full test suites pass; region-filtered temporal
  availability is covered by regression tests.

### ISS-20260903-001 — Seasonal download pipeline could silently serve wrong or incomplete data

- **Reported/found**: 2026-09-03, during a robustness audit of the WaPOR
  smart seasonal download path (`R/api_client.R`, `R/seasonal_download.R`,
  `R/plan_wapor_time_slices.R`).
- **Root causes** (three related defects):
  1. `.wapor_url_hash()` used a byte-sum + length checksum as the disk-cache
     key. Two different date-range queries whose request strings are
     character permutations of equal length collided, so the wrong cached
     URL list could be served within the 24h TTL. `IMPROVEMENT_PLAN.md` had
     already specified `digest::digest(url_query, "sha256")` for this; the
     shipped code diverged from that spec.
  2. `download_seasonal_rasters()` had no retry on `terra::rast(vsicurl_urls)`
     (unlike the non-seasonal path in `wapor_ts.R`), so one transient network
     failure dropped an entire resolution group (e.g. all monthly slices).
  3. Both the "no URLs for a code group" and "no URL match for a plan row"
     cases were `warning()`-and-`next` with no reconciliation against the
     plan, so the returned seasonal sum could silently under-represent the
     requested period.
- **Fix**: `.wapor_url_hash()` now uses `digest::digest(x, "sha256")`
  (`digest` added to `Imports`). Added retry-with-backoff (3 attempts) to the
  seasonal raster loader, matching `wapor_ts.R`'s existing pattern. Added
  `missing_period_ids` tracking across all three failure points in
  `download_seasonal_rasters()`, with a single aggregated warning (exact
  missing period IDs + day-coverage shortfall) and a `missing_periods` field
  on the return value, exposed to callers via
  `attr(wapor_ts(seasonal=TRUE) result, "missing_periods")`. Also upgraded
  the shared API retry policy (`.wapor_req_retry()`) to exponential backoff
  with `Retry-After` header support.
- **Regression tests**: `tests/testthat/test-url-cache.R` (hash collision +
  determinism), `tests/testthat/test-seasonal_download.R` (aggregated warning
  + `missing_periods` on partial failure; clean `missing_periods` on full
  success).
- **Verification**: `devtools::test()` — 638 passed, 0 failed, 0 warnings,
  6 skipped (live-API tests, no network in this environment).

### ISS-20260917-003 — Remote COG streaming retries stopped before pixel I/O

- **Found**: 2026-09-17, during a terra/COG streaming audit against the Cloud
  Native Geo terra guidance.
- **Root causes**: retry loops covered `terra::rast()` metadata opening but not
  later crop, extraction, reduction, or output operations that force pixel I/O;
  non-seasonal map/time-series paths could return partial batches by default;
  datatype probing used `terra::values()` and could materialize a full layer;
  fallback COG documentation overclaimed overview support.
- **Fix**: added `.wapor_retry_remote_operation()` and applied it around crop,
  zonal extraction, global reduction, tiled window reads, and output writes;
  default `partial = FALSE` now refuses incomplete map/time-series results;
  partial time-series results carry `partial` and `failed_layers` attributes;
  datatype probing uses a bounded `readValues()` window; fallback output is
  documented as tiled compressed GeoTIFF when the COG driver is unavailable.
  - **Verification**: all scoped R files parse; direct retry-helper execution
    passes; `git diff --check` passes. Full R tests are blocked in this working
    environment because `terra`, `devtools`, and `testthat` are not installed.

  - **2026-09-21 resolution (Codex)**: User reassigned ownership. A real local
    `terra`/GDAL environment is available. A live 12-layer JVA monthly stack
    opened in 2.81 seconds, so the 10 MB range-cache setting was not the
    observed bottleneck. The reported run looked frozen because no status was
    emitted during the later crop-and-write phase; granular console and Shiny
    progress were added. Parse, Shiny construction, 138 focused assertions,
    and a 12-layer live output run passed. A 72-layer temporary probe emitted
    chunk 1 and 2 progress but did not provide a completion line in this tool
    session; it is not claimed as a complete end-to-end result.
- **Remaining**: run the complete suite and local HTTP range fixture on an R
  environment with terra/GDAL; replace driver-table curl detection with a
  dedicated local capability probe; remove tiled-source duplicate remote reads.
