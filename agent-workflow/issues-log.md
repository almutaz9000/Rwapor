# Issues Log

_Operational issue tracker for agents. See `templates/issue-entry.md` for the
entry format. Stable IDs: `ISS-YYYYMMDD-###`._

## Open

### ISS-20261005-001 — RESOLVED 2026-10-05 (branch `perf/remote-io-1.0.6`, not yet merged): default GDAL HTTP chunk of 10 MB made remote reads download far more than needed

- **Where**: `R/gdal_config.R` `.RWAPOR_GDAL_DEFAULTS` (`CPL_VSIL_CURL_CHUNK_SIZE = 10485760`, set on
  load); `R/processing_kernel.R` `.wapor_with_gdal_chunk()`.
- **Root cause**: GDAL reads remote files in whole chunks, and fixes the chunk size at the first
  remote read of the session. Opening one global Level 2 file and reading a 1 km window requests
  20 MB (0.23 MB with GDAL's default). The planner's per-job chunk value is set too late and has
  never applied. In addition terra asks for `<file>.tif.vat.dbf` and `<file>.tif.aux.json` for
  every file (two 404 responses each).
- **Impact**: `wapor_ts()`-style extraction, 150 polygons x 36 dekads: Level 2 415 s and 1,091 MB
  requested (21.5 s and 17 MB without the chunk setting and with a `.tif` extension filter);
  Level 3 12.2 s against 5.3 s. Extracted values identical. Explains most of `ti-07`.
- **Fix / mitigation**: `perf-a` implemented (plan section 8): the chunk default is gone,
  `wapor_configure_gdal(chunk_size = NULL)`; `.wapor_with_remote_io()` limits `/vsicurl/` to
  `.tif` only while the package reads; the unused per-job chunk plan is removed; the PROJ fix no
  longer depends on `RWAPOR_AUTO_CONFIG`. Real `wapor_ts()`, 150 polygons x 36 dekads: Level 2
  342.7 s / 1,090.6 MB before, 20.7 s / 17.4 MB after; Level 3 66.3 s / 232.3 MB before,
  26.9 s / 14.3 MB after; values identical. Users of 1.0.5 can set
  `CPL_VSIL_CURL_CHUNK_SIZE=16384` in `.Renviron` until they upgrade.
- **Regression tests**: `test-gdal_config.R` (no chunk default, scoped filter, PROJ fix on load),
  `test-processing.R`; `inst/bench/remote_io_benchmark.R` (live, fails above 25 MB / 15 MB or any 404).
- **Verification**: 2026-10-05, GDAL 3.12.1, terra 1.9.34; scripts and CSVs in
  `docs/superpowers/plans/2026-10-05-perf-io-zonal-evidence/` (`net_worker.R`, `sticky.R`).

### ISS-20261005-002 — `wapor_zonal_stats()` is 9 to 12 times slower than needed and holds all layers in memory

- **Where**: `R/zonal_stats.R` (`add()` at line 177, `vals` at line 179, single `exact_extract()` at 145).
- **Root cause**: one `data.frame()` per output value (66% of run time), a final `rbind` of all of
  them (11%), and Gini, Theil, DU and CU computed for every zone and layer even when not requested.
  All layers are extracted in one call, so memory grows with the number of layers.
- **Impact**: 400 zones x 12 layers on 800 x 800 cells: 56 s (6 s with a restructured loop, output
  identical). Default call (two id levels, AOI) on 1500 x 1500: 140 to 573 s, up to 2.45 GB.
- **Fix / mitigation**: not fixed yet. Planned as `perf-b` (plan section 4), after `p2-b2`.
- **Regression tests**: none yet (equivalence tests against the frozen current function, plan step 6).
- **Verification**: 2026-10-05, evidence folder (`zonal_bench.R`, `zonal_prof.R`, `zonal_lean.R`).

### ISS-20261005-003 — `wapor_zonal_stats(format = "sf")` attaches wrong or empty geometries

- **Where**: `R/zonal_stats.R:214`.
- **Root cause**: zone geometries are indexed with row positions of the result
  (`match(ans$zone_key, ans$zone_key)`) instead of zone positions.
- **Impact**: with more than one statistic per zone. 4 zones x 2 statistics: rows of zone 2 carry
  the geometry of zone 3; rows of zones 3 and 4 have empty geometry. One statistic is correct.
- **Fix / mitigation**: not fixed yet. Included in `perf-b` step 5; can also be fixed inside `p2-b2`.
- **Regression tests**: none yet.
- **Verification**: 2026-10-05, evidence folder (`sf_check.R`).

### ISS-20260929-018 — RESOLVED 2026-09-29: monitoring layers lost silently, scale depends on terra

- **Where**: `R/wapor_monitoring.R` `wapor_save_raster_blobs()`.
- **Root cause**: (1) relied on terra keeping the COG scale through crop/convert/metadata
  (correct on terra 1.9.34, version-dependent per ISS-20260928-010); (2) failed layers were
  counted as "already saved"; (3) an undated URL was stored under `Sys.Date()`; (4) failed
  per-layer opens were dropped uncounted; (5) errors became log lines only.
  Found while fixing: early `return()` inside `tryCatch({ ... })` left the whole function,
  so a batch that failed entirely was still silent; `paste0("undated:", character(0))`
  returns `"undated:"` (a false failure on every run).
- **Fix**: detach/apply the source scale once (same helpers as `wapor_map()`); separate
  `existing`/`failed`; undated -> `failed`; body wrapped in a local function so the summary
  log and `warning()` always run; returns `list(variable, saved, existing, failed)`.
  Tests: `test-monitoring-blobs.R` (Int16 + GDAL scale 0.1 written with `gdal_translate`;
  scale once, existing, loud failure, no invented date), 15 expectations, 0 skips.

### ISS-20260929-017 — RESOLVED 2026-09-29: kernel ETc uses a shifted Kc curve (ETc too low / zero)

- **Where**: `R/processing_kernel.R` `.wapor_build_kernel_job()`: `.wapor_profile_kc()`
  was called with `dekad_table`/`reference_year` while `profiles$start_jd` and the
  weights use the rebased `kernel_dekad_table`/`kernel_reference_year` (since `94b1533`).
- **Symptom**: training notebook, local data: citrus ETc 962 mm instead of 1056 mm
  (adequacy 1.08 instead of 0.98, share below 0.8 18% instead of 22%); wheat
  (season from 1 November) ETc 0 mm, adequacy NaN, empty adequacy-class table.
  Independent check: sum(daily Kc x RET) = 1057.7 mm.
- **Bisect**: v1.0.2 and v1.0.3 correct (1056.45); `94b1533` and 1.0.5 wrong.
- **Fix**: pass `kernel_dekad_table`, `kernel_reference_year`. Regression test in
  `test-processing.R` (1 March season; old code 85.7 vs expected 447.9).

### ISS-20260929-016 — RESOLVED 2026-09-29: training setup check reports "server reachable" when offline

- **Where**: `training/check_setup.R` (connectivity check) and the `l3-regions`
  chunk of `training/water-productivity-training.qmd`.
- **Root cause**: offline, `wapor_fetch_l3_regions()` only *warns* and returns the
  static `L3_REGIONS` list; both callers caught errors only, so check_setup printed
  `[PASS] WaPOR server reachable` and the notebook overwrote
  `data/wapor_l3_regions.csv` with the fallback list.
- **Fix**: treat the warning as offline (`warning = function(w) ...`). Also the
  "values are in mm/day" checkpoint now has a lower bound (>1), so a double-scaled
  (10x too low) download fails the check instead of passing.
- **Note**: participants received check_setup.R before this fix; re-share it.

### ISS-20260929-015 — RESOLVED 2026-09-29: `wapor_ts()` polygon stats fail for single-layer batches

- **Where**: `R/wapor_ts.R`, zonal extraction (`exact_extract(..., c("mean","min","max"))`).
- **Root cause**: exactextractr names columns `mean/min/max` (no `.L1` suffix) for a
  one-layer raster; the reshaping expected `mean.L1`. Any polygon `wapor_ts()` whose
  batch holds one layer (one-dekad period, or planner batch size 1) failed.
- **Found by**: new live-API CI gate (run 36521899036, Windows and Linux,
  `test-wapor.R:420`); the live test had never run in CI.
- **Fix**: normalise single-layer names to `.L1`. Offline regression test in
  `test-internal-helpers.R` (errors on the old code).

### ISS-20260928-013 — RESOLVED 2026-09-28: `wapor_map()` returned a status list instead of paths

- **Where**: `R/wapor_map.R`, `process_single_var()` return (since `5cf44fb`, 2026-09-17).
- **Symptom**: `terra::rast(wapor_map(...))` (vignette getting-started 4.1) failed
  ("none of the elements of x are a SpatRaster"); the dashboard's
  `file.exists(unlist(result))` tested "ok"/variable names and showed
  "Download failed ... expected files were not found" after every successful
  non-seasonal download.
- **Fix**: return the documented character paths (named list for several
  variables); run details in `attr(x, "wapor_status")`. Commit `e52dc5e`.
- **Regression test**: `test-internal-helpers.R` "wapor_map returns file paths
  usable by terra::rast and the dashboard" (errors on the old code).

### ISS-20260928-014 — RESOLVED 2026-09-28: Windows CI red on `version-1.0.4`

- **Where**: `R/analysis_tiled.R` `.wapor_remote_cog_fixture()` (test helper).
- **Root cause**: `port.txt` existed before its content was written; R polled
  for existence only and read an empty file on the slow Windows runner
  (run 36397653719, "subscript out of bounds").
- **Fix**: atomic publish (`os.replace`) and wait for a parsable port. Commit
  `312e1ed`; CI run 36417147780 green on all 6 jobs.

### ISS-20260928-010 — RESOLVED 2026-09-28: `wapor_map()` scaled values twice after the 1.0.4 fix

- **Where**: `R/wapor_map.R` `.wapor_prepare_map_output()` (added in `94b1533`).
- **Root cause**: when the raster carried no pending scale/offset, the helper
  multiplied by the catalogue scale. terra (1.7.65 and 1.9.50) has already
  applied the file scale by that point (crop, unit conversion, temp-stack
  write), so values were scaled a second time. It would also rescale local
  Float32 copies, which are already physical.
- **Evidence**: synthetic Int16 COGs with GDAL scale 0.1 through the full
  `wapor_map()` (URL generator stubbed): HEAD wrote 2.5 instead of 25 mm/dekad
  and 0.25 instead of 2.5 mm/day, stack and separate files, on both terra
  versions.
- **Fix**: `.wapor_detach_source_scale()` clears the file scale when the
  sources are opened (terra then returns raw values),
  `.wapor_apply_source_scale()` applies it once after the crop; the catalogue
  scale is no longer used. Same outputs on terra 1.7 and 1.9.
- **Regression tests**: `test-internal-helpers.R` "map output applies the source
  file scale exactly once" and "... does not rescale files without a stored scale".

### ISS-20260928-011 — RESOLVED 2026-09-28: `wapor_write_cog()` truncated floats

- **Where**: `R/wapor_cog.R` `.wapor_probe_datatype()`.
- **Root cause**: the integer probe read only the first rows of the first layer.
  A band of zeros (masked edge, early-season layer) made a float raster INT4U.
- **Evidence**: 1000 x 1000 raster, 20 zero rows on top: mean 2.45 written as 1.96.
  Affects `wapor_export_analysis_outputs(cog = TRUE)`, monitoring COGs, L3 mosaics.
- **Fix**: all values checked up to 5 million, otherwise a regular sample across
  all layers. Regression test in `test-streaming-hardening.R`.

### ISS-20260928-012 — Dashboard install/run gaps (fixed)

- Visualisation tab called `raster::raster()` although `raster` was neither in
  the dashboard's required-package check nor in the README install list; now
  passes SpatRaster to leaflet (>= 2.1.2). `raster`/`pkgdown` removed from Suggests.
- Startup blocked ~30 s on L3-region retries when the API was unreachable;
  `wapor_fetch_l3_regions(timeout, retry)` added, app uses 10 s / no retry.
- Analysis tab defaulted to annual `AGERA5-ET0-A` / `AGERA5-PF-A` (first
  alphabetical match); now `L1-RET-D` / `L1-PCP-D`.
- README 3.2 lacked `knitr`/`rmarkdown` needed by `build_vignettes = TRUE`.
- `test-multi-season.R` hit the live API without a skip.

### ISS-20260925-007 — RESOLVED 2026-09-28: supplied crop mask default

- **Where**: `R/analysis_engine.R`, harmonize-mask block (`if (isTRUE(config$use_crop_mask))`).
- **Root cause**: without the flag the engine replaces the mask with `template * 0 + 1`,
  so every AOI pixel becomes class 1, with no message.
- **Impact**: with a rectangular AOI (Jendouba wheat) every land pixel would be analysed
  as the crop. Found while testing the training notebook (2026-09-23).
- **Fix / mitigation**: a supplied SpatRaster is now used by default; an explicit
  `use_crop_mask = FALSE` warns. Regression test added.

### ISS-20260925-008 — RESOLVED 2026-09-28: Local reader also picks up `<VAR>_seasonal` files next to the dekads

- **Where**: `R/analysis.R` `wapor_local_rasters()` (scans `<folder>/<VAR>` and
  `<folder>/<VAR>_seasonal`).
- **Impact**: a seasonal file written by `wapor_map(seasonal = TRUE)` into the same
  folder as the dekadal files can be read as an extra layer by
  `data_source = "local"` runs.
- **Fix / mitigation**: 2026-09-28 — `wapor_local_rasters()` reads
  `<VAR>_seasonal` only when `<VAR>` has no .tif files.
- **Regression tests**: `test-processing.R` "wapor_local_rasters ignores
  _seasonal aggregates next to dekadal files".

### ISS-20260925-009 — RESOLVED 2026-09-28: Large L3 runs fill the disk

- **Where**: `R/analysis_engine.R` (`keep_intermediates` defaults to TRUE in memory
  mode and materialises every dekadal stack; derived rasters FLT8S),
  `wapor_export_analysis_outputs(include_dekadal = TRUE)`.
- **Evidence**: Jendouba wheat (5.1 M cells, 21 dekads, 5 variables) failed with
  "No space left on device" at 8 GB free; passed with `keep_intermediates = FALSE`
  and `include_dekadal = FALSE` (2026-09-24).
- **Fix / mitigation**: 1.0.5 (WP1, `fe75e5a`): `keep_intermediates` and
  `include_dekadal` default FALSE, Float32 file-backed/exported rasters with
  LZW + predictor, disk estimate and low-space warning. 1 M-cell benchmark:
  1,288 -> 715 MB, results identical.
- **Regression tests**: `test-processing.R` disk-estimate test; mode-equivalence
  tests at 1e-6 with Float32.

### ISS-20260924-006 — RESOLVED 2026-09-28: map output retains physical WaPOR values

- **Where**: `R/wapor_map.R` per-layer write path (around lines 557-570,
  `terra::writeRaster(r_out, out_path, ...)`).
- **Symptom**: saved files hold raw WaPOR integers as Float32 with scale 1
  (L3-AETI-D values 1 to 30 instead of 0.1 to 3.0 mm/day; the remote COG is
  Int16 with `Scale: 0.1`). Reading them with `data_source = "local"` gives
  seasonal AETI about 10 times too high (JVA citrus 2024/25: 10,557 mm vs
  1,035.86 mm from the API run).
- **Impact**: any offline workflow built on `wapor_map(separate_files = TRUE)`
  downloads; the seasonal (`seasonal = TRUE`) path is not affected.
- **Fix / mitigation**: map output now materialises an existing source scale or
  applies the catalogue scale before output metadata is assigned, for both
  separate-file and multi-band paths. Regression test added.
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

### ISS-20260923-004 — RESOLVED 2026-09-28: direct single-season export

- **Where**: `R/analysis_utils.R:826`, multi-season detection
  `!is.null(results[[1]]$h_mask)`.
- **Root cause**: for a single-season result `results[[1]]` is the `h_mask`
  SpatRaster; `$h_mask` on a SpatRaster is a layer-name subset, and terra errors
  ("[subset] invalid name(s)") unless the layer happens to be called `h_mask`.
- **Impact**: the documented single-season call
  `wapor_export_analysis_outputs(results = season, season_label = ...)` fails
  whenever the crop mask layer has any other name (e.g. `crop_mask`).
- **Fix / mitigation**: multi-season detection now verifies a nested result
  list before accessing `$h_mask`; direct single-season exports work.
  Regression test added.
- **Verification**: reproduced in `training/water-productivity-training.qmd`
  chunk `citrus-export` with installed Rwapor 1.0.1.

### ISS-20260923-003 — RESOLVED 2026-09-28: historic `ref_year` kernel compatibility

- **Where**: `R/processing_kernel.R` `.wapor_profile_key_raster()` (range check
  "Season start/end values must lie between -1000 and 999 days"), introduced in
  `e10ba99`. Callers still passing 1970: `inst/shiny/mod_analysis.R:1340`,
  `vignettes/advanced-analysis.Rmd:82`, `vignettes/wheat-water-productivity.Rmd:96`,
  default in `R/analysis.R:1078`.
- **Root cause**: season start/end are day offsets from `ref_year`; with 1970 a
  2024 season is ~19 800 days, outside the packed profile-key span.
- **Impact**: `wapor_run_seasonal_analysis()` errors for any config with
  `ref_year = 1970` — worked in 1.0.0.
- **Fix / mitigation**: the kernel rebases its compact profile-key and dekad
  coordinate system internally while keeping source-file dates unchanged.
  Existing 1970-anchored season rasters are accepted. Regression test added.
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
