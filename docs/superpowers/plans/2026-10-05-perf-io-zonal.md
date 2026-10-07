# Plan: perf-io-zonal — remote I/O settings and zonal engine speed

_Written by Claude on 2026-10-05 after reviewing an external list of improvement suggestions and
benchmarking the strongest candidates. Status: APPROVED by the maintainer on 2026-10-05 (perf-a first, then the proposed order). perf-a is IMPLEMENTED and verified, see section 8; perf-b waits for `p2-b2`.
Implementing agents: read `agent-workflow/START-HERE.md` first, then section 0 and your work package._

| | |
|---|---|
| **Board tasks** | `perf-a` (remote I/O settings), `perf-b` (zonal engine speed), `perf-c` (staging: measure first) |
| **Target release** | 1.0.6 (same release as P2) |
| **Order** | `perf-a` can start now on its own branch. `perf-b` starts only after `p2-b2` is done. `perf-c` starts after `perf-a` is merged. |
| **Evidence** | `docs/superpowers/plans/2026-10-05-perf-io-zonal-evidence/` (scripts and result tables) |
| **Related** | `ti-07` and `ti-06` in `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`; ISS-20261005-001, -002, -003 |

## 0. Summary for the maintainer

Three results, all measured on 2026-10-05 (Windows 11, R 4.5.3, terra 1.9.34, GDAL 3.12.1,
exactextractr 0.10.1, live WaPOR v3 data, 36 dekads of 2023, AETI):

1. **The package's own GDAL HTTP chunk setting is the main remote bottleneck.** `.onLoad` sets
   `CPL_VSIL_CURL_CHUNK_SIZE` to 10 MB. With it, a time series for 150 farm polygons from Level 2
   takes 415 s and requests 1,091 MB. Without it (and with a file-extension filter) the same call
   takes 21.5 s and requests 17 MB. Values are identical. (WP-A)
2. **`wapor_zonal_stats()` spends its time in R bookkeeping, not in extraction.** 400 zones and
   12 layers take 56 s; a restructured loop with identical output takes 6 s. With the default
   arguments (two id levels plus AOI) the current function takes 140 to 573 s on a 1500 x 1500
   raster. (WP-B)
3. **Whole-file staging of Level 3 data gives no first-run gain once WP-A is in.** 5.2 s against
   5.3 s. It only helps repeated and offline runs. `ti-06` should be re-measured after WP-A before
   anyone builds it. (WP-C)

Decisions needed from the maintainer are listed in section 6. Each has a safe default.

## 1. Review of the suggested improvements

| # | Suggestion | Verdict | Reason |
|---|---|---|---|
| 1 | terra and sf as the core | Already implemented | `DESCRIPTION` Imports |
| 2 | exactextractr for zonal statistics, exact fractional weighting | Already implemented | `R/wapor_ts.R`, `R/zonal_stats.R` (coverage area weights), `R/wapor_monitoring.R` |
| 3 | httr2 for the API | Already implemented | `R/api_client.R` |
| 4 | Lazy `/vsicurl/` stacks, chunked reads over long series | Already implemented | planner batches in `wapor_ts()` and `wapor_map()`; window kernel in `R/processing_kernel.R` |
| 5 | `wapor_set_gdal_options()` helper | Already implemented, but its defaults are harmful | `wapor_configure_gdal()` runs on load. See WP-A |
| 6 | `CPL_VSIL_CURL_ALLOWED_EXTENSIONS` | **Worth implementing** | removes 2 failed HTTP requests per file; Level 3 run 12.2 s to 9.7 s on its own |
| 7 | `GDAL_HTTP_MERGE_CONSECUTIVE_RANGES` | No measurable effect | request counts and megabytes were identical with and without it; harmless, not needed |
| 8 | NoData to NA without full scans | Already implemented | GDAL nodata (-9999) becomes NA on read; `NAflag` on write |
| 9 | Long tidy result tables | Already implemented | `wapor_ts()` and `wapor_zonal_stats()` return long data frames; a tibble class would add a dependency for no functional gain |
| 10 | gdalcubes or stars cube engine (`wapor_cube()`) | Not worth implementing | see 1.1 |
| 11 | Keep Int16 and set `scoff()` instead of scaling | Not worth implementing | see 1.2 |
| 12 | tmap, mapgl, arrow GeoParquet | Not worth implementing now | ggplot2, tidyterra and leaflet plots exist; no performance or robustness gain |
| 13 | `wapor_query()` returning a catalogue table | Partly implemented, low priority | `wapor_generate_urls()` plus `wapor_date_info()` hold the same information; an exported table is already planned as offline URL lists (P2 batch B5, `ti-15`) |
| 14 | Guard for very large areas at fine resolution | Partly implemented | `wapor_plan_processing()` chooses tiling for the seasonal engine and warns on disk space; `wapor_map()` and `wapor_ts()` have no volume message. Small addition, included in WP-A step 7 |

### 1.1 Why not gdalcubes or stars

- WaPOR dekads are not a regular 10-day grid (lengths 8, 9, 10 and 11 days). Mapping the 72 dekads
  of 2023 and 2024 onto `P10D` puts two dekads into one time cell (21 February and 1 March 2023)
  and leaves two cells empty. A cube built that way silently merges or drops a dekad
  (`evidence/dekad_bins.R`).
- All files of one WaPOR product share one grid, so the alignment work a cube engine does is not needed.
- The package has its own window kernel with 236 known-answer values across three processing modes.
  A second engine would need the same verification and adds a heavy dependency.

### 1.2 Why not `scoff()` on the returned rasters

ISS-20260928-010 showed that terra versions differ in when they apply a pending scale. That caused
values scaled twice. The package now clears the file scale on open and applies it exactly once
(`.wapor_detach_source_scale()`, `.wapor_apply_source_scale()`), with regression tests. Returning
rasters with a pending scale would bring the version dependence back. Outputs are already Float32
with LZW and a predictor.

## 2. Evidence

All tables: one run per row unless a range is given; identical checksums of the extracted means in
every configuration (5251.561769 for Level 3, 7689.98769 for Level 2).

### 2.1 Remote extraction, 150 polygons of 300 m, 36 dekads

| Settings | Level 3 (JVA, 20 m): time | requested | requests | Level 2 (100 m, global files): time | requested |
|---|---|---|---|---|---|
| GDAL defaults, nothing set | 18.4 to 18.7 s | 12.1 MB | 685 | 31.8 to 58.9 s | 15.1 MB |
| Rwapor now (10 MB chunk) | 12.0 to 12.4 s | 44.5 MB | 468 | 415 s | 1,090.6 MB |
| Rwapor now + suggested extension filter | 9.7 s | 44.5 MB | 396 | 388 to 402 s (see note) | 1,090.6 MB |
| Chunk setting removed | 8.7 to 9.3 s | 12.7 MB | 432 | 19.7 to 35.0 s | 17.4 MB |
| **Chunk removed + extension filter (proposed)** | **5.2 to 5.3 s** | **12.7 MB** | **360** | **17.4 to 22.3 s** | **17.4 MB** |
| Proposed + `CPL_VSIL_CURL_USE_HEAD=NO` | 6.7 s | 12.7 MB | 360 | 17.0 to 23.6 s | 17.4 MB |

Note: the two Level 2 runs with the extension filter and the 10 MB chunk were timed before the PROJ
correction in 2.4 and include about 12 s of unrelated overhead. Megabytes and request counts are
not affected.

One scheme-size polygon (8 km x 30 km), Level 3: 29.1 to 31.2 s now, 6.2 s proposed.
Level 2, proposed: 18.6 s (not measured with the current settings).

Why the 10 MB chunk hurts:

- GDAL reads remote files in whole chunks. Opening one global Level 2 file and reading a 1 km window
  requests 20 MB with the 10 MB chunk, 0.23 MB with GDAL's default (`evidence/sticky.R`).
- Level 3 files are 0.3 to 0.6 MB. With the 10 MB chunk each file was requested in full twice and
  then in 8 further partial requests.
- **The chunk size is fixed at the first remote read of the R session.** Changing it later has no
  effect, although `terra::getGDALconfig()` reports the new value. So the planner's per-job value
  (`.wapor_with_gdal_chunk()`, `plan$gdal_chunk_bytes`) has never applied: a job planned for
  256 KB still requested 10 MB chunks.

Why the extension filter helps: for every file terra asks the server for `<file>.tif.vat.dbf` and
`<file>.tif.aux.json`. Both return 404. The filter stops these requests before they are sent, and
it can be switched on and off at run time (`evidence/ext_runtime.R`), so it can be limited to the
package's own reads.

Cropping the stack into memory before extraction is not faster: with the same settings it took
17.9 s against 6.7 s at Level 3 and 22.0 s against 17.0 to 23.6 s at Level 2. The existing comment
in `R/wapor_ts.R:531` is right. No change.

### 2.2 `wapor_zonal_stats()`, synthetic 20 m rasters, zones cut cell borders

Farms only (`dissolve = FALSE, aoi = FALSE`), default statistics:

| Raster, layers, zones | Current | Restructured loop (identical output) |
|---|---|---|
| 800 x 800, 12, 400 | 56.3 s | 6.1 s |
| 800 x 800, 36, 400 | 153.0 s | 13.8 s |
| 1500 x 1500, 12, 2025 | 236.6 s | 21.6 s |

Eight statistics (mean, sd, cv, gini, min, max, quantiles, coverage): 106.3 s to 10.2 s,
309.0 s to 30.1 s, 536.7 s to 43.6 s. Output identical in all six cases (`all.equal`, tolerance 1e-12).

One zone covering a whole 1500 x 1500 raster with 36 layers (scheme or country case):
64.5 s and 1,442 MB now; 13.5 s and 826 MB with 4 layers per read. Identical output.

Default arguments (`id = c("scheme", "farm")`, dissolve, AOI) on 1500 x 1500:
140 s (12 layers, 400 farms), 458 s (36 layers), 573 s (12 layers, 2025 farms); peak R memory up to 2.45 GB.

Profile of the current function (2025 zones, 12 layers): 66% of the time in `data.frame()` called
once per output value, 11% in the final `rbind`, about 12% in statistics that were not requested
(Gini, Theil, DU, CU are computed for every zone and layer).

For reference, exactextractr's built-in operations (`mean`, `min`, `max`, `count`) take 0.3 to 0.9 s
on the 800 x 800 cases and 4.3 to 4.8 s on 1500 x 1500. The mean differs from the current function by
up to 4.8e-7, so it is not a drop-in replacement. See decision D-B1.

### 2.3 Whole-file staging of Level 3 (prototype for `ti-06`)

36 files (17.3 MB) fetched in parallel with `curl::multi_download()`, then read locally:
first run 4.8 to 5.6 s (three runs), repeat from the local copy 2.4 to 3.5 s. Streaming with the
proposed settings: 5.2 to 5.3 s. One earlier fetch took 46 s while other benchmarks were using the
network, so parallel fetching is not immune to stalls.

### 2.4 Side findings

- With `RWAPOR_AUTO_CONFIG=false` the PROJ fix is skipped as well. On a machine with PostGIS on the
  path every raster open then costs about 0.35 s (36 local files: 12.6 s instead of 0.3 s) and PROJ
  prints a database version warning. This also distorted my first benchmark round; all timings
  above are from the corrected rerun unless noted.
- `wapor_zonal_stats(format = "sf")` attaches wrong geometries when more than one statistic is
  requested: with 4 zones and 2 statistics, the rows of zone 2 carry the geometry of zone 3 and the
  rows of zones 3 and 4 have empty geometry (ISS-20261005-003, `evidence/sf_check.R`).

## 3. WP-A: remote I/O settings (`perf-a`)

- **Branch**: `perf/remote-io-1.0.6`, created from `version-1.0.6`. Do not commit or push unless asked.
- **Skills to load**: `rwapor-plan-executor`, `rwapor-r-dev`.

### Goal

Remote reads request only the bytes they need. Level 2 polygon time series become about 19 times
faster and Level 3 about 2.3 times faster, with unchanged values.

### Context

- `R/gdal_config.R:2-28` — `.RWAPOR_GDAL_DEFAULTS`; line 6 is the 10 MB chunk.
- `R/gdal_config.R:92-135` — `wapor_configure_gdal()`; `chunk_size` default `10485760L`.
- `R/gdal_config.R:218-229` — `.onLoad()`; returns before `wapor_fix_proj()` when auto-config is off.
- `R/processing_kernel.R:643-651` — `.wapor_with_gdal_chunk()`; sets a value GDAL ignores.
- `R/processing_plan.R:184, 202, 276-283, 396` — `gdal_chunk_bytes` in the plan and its print line.
- Call sites of `.wapor_with_gdal_chunk()`: `R/wapor_ts.R:629`, `R/wapor_map.R:647`,
  `R/seasonal_download.R:129`, `R/processing_kernel.R:696, 784`.
- Existing tests that assert the old behaviour: `tests/testthat/test-gdal_config.R:23-34, 103, 115-120`,
  `tests/testthat/test-processing.R:147-149`, `tests/testthat/test-analysis-tiled.R:237`.

### Files

| File | Change |
|---|---|
| `R/gdal_config.R` | steps 1, 2, 5 |
| `R/processing_kernel.R` | step 3 |
| `R/processing_plan.R` | step 4 |
| `R/wapor_ts.R`, `R/wapor_map.R`, `R/seasonal_download.R` | rename the wrapper call only (step 3); step 7 in `wapor_ts.R` and `wapor_map.R` |
| `tests/testthat/test-gdal_config.R`, `tests/testthat/test-processing.R`, `tests/testthat/test-analysis-tiled.R` | step 8 |
| `inst/bench/remote_io_benchmark.R` (new) | step 6 |
| `NEWS.md`, `man/*.Rd` (via `devtools::document()`) | step 9 |

Do not edit any other file. If another file must change, stop and report.

### Steps

1. **Remove the chunk default.** Delete `CPL_VSIL_CURL_CHUNK_SIZE` from `.RWAPOR_GDAL_DEFAULTS`.
   In `wapor_configure_gdal()` change the default to `chunk_size = NULL`. `NULL` means the variable
   is not set and not touched. A number is validated as now and must lie between 1024 and
   10485760 (GDAL's limits); set it as now. Document in roxygen: GDAL reads this value once, at
   the first remote read of the session, so it must be set before any remote read; large values
   make every file open download a whole chunk. Rewrite the "Why these settings matter" section
   with the numbers from section 2.1 of this plan.
2. **Add the scoped extension filter.** New internal constant
   `.RWAPOR_REMOTE_EXTENSIONS <- ".tif,.tiff,.TIF,.TIFF"`. Do not put
   `CPL_VSIL_CURL_ALLOWED_EXTENSIONS` in the load-time defaults: as a session-wide variable it
   would block the user's own `/vsicurl/` reads of other formats.
3. **Replace `.wapor_with_gdal_chunk()`** by `.wapor_with_remote_io(code)` in `R/processing_kernel.R`:

   ```r
   .wapor_with_remote_io <- function(code) {
     key <- "CPL_VSIL_CURL_ALLOWED_EXTENSIONS"
     if (!isTRUE(getOption("Rwapor.remote_extension_filter", TRUE))) return(force(code))
     old <- tryCatch(terra::getGDALconfig(key), error = function(e) "")
     if (is.null(old) || !length(old) || is.na(old)) old <- ""
     if (nzchar(old)) return(force(code))            # the user set a filter: keep it
     try(terra::setGDALconfig(key, .RWAPOR_REMOTE_EXTENSIONS), silent = TRUE)
     on.exit(try(terra::setGDALconfig(key, ""), silent = TRUE), add = TRUE)
     force(code)
   }
   ```

   Replace all five call sites; drop the chunk argument. In parallel runs the wrapper must also be
   entered inside the worker function (`process_batch` in `wapor_ts.R`, `process_chunk` in
   `wapor_map.R`, `run_one` in `processing_kernel.R`), because each worker is its own process.
   Local paths are not affected by the filter.
4. **Remove the unused chunk plan.** Delete `.wapor_gdal_chunk_bytes()`, the `gdal_chunk_bytes`
   element of the plan, the `bytes_per_file_window` argument of `.wapor_plan_core()` and its two
   callers, the "GDAL chunk" line in `print.wapor_plan()`, and the `gdal_chunk_bytes` mention in
   the roxygen `@return` of `wapor_plan_processing()`.
5. **PROJ fix independent of the GDAL switch** (decision D-A1, default as written here). In
   `.onLoad()`: run `wapor_fix_proj(verbose = FALSE)` unless
   `isFALSE(getOption("Rwapor.fix_proj", TRUE))`; then apply the GDAL settings only when
   auto-config is on. Update the comment above `.onLoad`.
6. **Benchmark script** `inst/bench/remote_io_benchmark.R`, ported from
   `evidence/net_worker.R` and `evidence/net_run.ps1`, in R only so it runs on every platform:
   for each configuration start a fresh `Rscript` with `system2(..., stderr = <log>)` and
   `CPL_CURL_VERBOSE=YES`, run the 150-polygon JVA extraction for Level 3 and Level 2, and parse
   the log for GET and HEAD counts, 404 counts and requested megabytes
   (`Range: bytes=a-b` lines). Configurations: the settings of the installed package, and the old
   settings (10 MB chunk, no filter) for comparison. Print one table and exit non-zero when a
   threshold in "Done criteria" is missed. Keep the PROJ variables set in the child process.
7. **Volume message.** In `wapor_ts()` and `wapor_map()`, after `.wapor_io_plan()`: when
   `io_plan$cells * length(urls) * 4` exceeds 2 GB, emit one `.wapor_inform()` line with the number
   of cells, layers and the estimated megabytes, and name the coarser level as an option when the
   variable is Level 2 or Level 3. No error and no change of behaviour. (`io_plan$cells` already
   holds the cells inside the region.)
8. **Tests.**
   - `test-gdal_config.R`: replace the two tests that expect a 10 MB chunk by: defaults do not
     contain `CPL_VSIL_CURL_CHUNK_SIZE`; `wapor_configure_gdal()` with defaults leaves an existing
     value of that variable unchanged and does not create it; an explicit `chunk_size` is still
     written; values outside 1024 to 10485760 error.
   - New: `.wapor_with_remote_io()` sets the filter during the call and clears it afterwards, also
     when the code errors; leaves a user-set filter untouched; does nothing when
     `options(Rwapor.remote_extension_filter = FALSE)`.
   - New: with `RWAPOR_AUTO_CONFIG=false`, `.onLoad()` still calls the PROJ fix (mock
     `wapor_fix_proj` with `testthat::local_mocked_bindings`) and does not set GDAL variables; with
     `options(Rwapor.fix_proj = FALSE)` it does not call it.
   - `test-processing.R`: remove the three `.wapor_gdal_chunk_bytes` expectations.
     `test-analysis-tiled.R:237`: drop `gdal_chunk_bytes` from the hand-built plan.
   - The local HTTP fixture tests in `test-analysis-tiled.R` must pass unchanged: they read `.tif`
     files through `/vsicurl/`, so they cover the filter.
9. `NEWS.md` under `# Rwapor 1.0.6 (development)`: the changed default, the measured effect, and
   that users who want the old value can call `wapor_configure_gdal(chunk_size = ...)` before the
   first remote read. Run `devtools::document()`.

### Validation (run in this order, report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'gdal_config')"
& $R -e "devtools::test(filter = 'processing')"
& $R -e "devtools::test(filter = 'analysis-tiled')"
& $R -e "devtools::test(filter = 'known-answer')"
& $R -e "devtools::test(filter = 'streaming-hardening')"
& $R inst\bench\remote_io_benchmark.R      # needs internet
& $R inst\bench\live_release_checks.R       # needs internet
```

### Done criteria (the verifier checks each)

- [ ] After `library(Rwapor)` in a fresh session `Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE")` is empty
      (unless the user set it).
- [ ] Benchmark, Level 2, 150 polygons, 36 dekads: requested at most 25 MB (was 1,091 MB) and at
      most 60 s (was 415 s).
- [ ] Benchmark, Level 3: requested at most 15 MB (was 44.5 MB), zero 404 responses (was 72), at
      most 9 s (was 12.2 s).
- [ ] Extracted values equal between old and new settings in the same benchmark run (difference 0).
- [ ] After any Rwapor remote call, `terra::getGDALconfig("CPL_VSIL_CURL_ALLOWED_EXTENSIONS")` is
      empty again.
- [ ] `known-answer` (236 golden values) and live release checks pass unchanged.
- [ ] No files changed outside the table.

### Out of scope

- Opening files in parallel, HTTP/2 settings, cache sizes. Not measured as bottlenecks.
- `R/zonal_stats.R` and all P2 files.
- `GDAL_HTTP_MERGE_CONSECUTIVE_RANGES` and `CPL_VSIL_CURL_USE_HEAD` (no gain measured).

## 4. WP-B: zonal engine speed (`perf-b`)

- **Starts after**: board task `p2-b2` is done (Hermes holds `R/zonal_stats.R` until then).
- **Branch**: `version-1.0.6` after the B2 gate, or a branch from it. Do not commit or push unless asked.
- **Skills to load**: `rwapor-plan-executor`, `rwapor-r-dev`.

### Goal

`wapor_zonal_stats()` returns exactly the same table about ten times faster, with memory bounded
by the layers read at once instead of the whole stack, and `format = "sf"` returns the right geometry.

### Context

- `R/zonal_stats.R:145-146` — one `exact_extract()` call returns every cell of every zone for all layers.
- `R/zonal_stats.R:177` — `add()` builds a ten-column data frame per output value.
- `R/zonal_stats.R:179` — `vals` computes all eleven statistics for every zone and layer.
- `R/zonal_stats.R:140` — `terra::values(weights)` reads the whole weights raster to check its range.
- `R/zonal_stats.R:213-214` — final `rbind`; `format = "sf"` indexes zone geometries with row
  positions of the result (ISS-20261005-003).
- Working prototype with identical output: `evidence/zonal_lean.R` (function `zonal_lean()`).

### Files

| File | Change |
|---|---|
| `R/zonal_stats.R` | steps 1 to 5 |
| `tests/testthat/helper-zonal-reference.R` (new) | step 6 |
| `tests/testthat/test-zonal-stats.R` | step 6 |
| `inst/bench/zonal_benchmark.R` (new) | step 7 |
| `NEWS.md` | one line |

### Steps

1. **Freeze the reference first.** Before changing anything, copy the current body of
   `wapor_zonal_stats()` verbatim into `tests/testthat/helper-zonal-reference.R` as
   `reference_zonal_stats()`. It is the oracle for step 6.
2. **Compute only what is requested.** Replace the eager `vals` list by guarded computation, as in
   the prototype (`need("sd")` and so on). `cv` needs mean and sd; the "fewer than 3 x 3 cells"
   warning needs `n_eff`, which is cheap and stays. Keep every formula helper
   (`.wapor_wmean()` to `.wapor_wtheil()`) unchanged.
3. **Collect results in vectors.** Remove `add()`. Append to growing atomic vectors per output
   column (level, zone index, layer index, stat, class, value, unit) held in lists of chunks, and
   build one data frame at the end. The row order must stay: zone, then layer, then
   `area_ha`, `mask_fraction`, `coverage`, the statistics in the order of `vals`, quantiles,
   `sum_volume`, class rows. Columns, classes and attributes of the result are unchanged.
4. **Read layers in chunks.** Loop over groups of value layers; each `exact_extract()` call gets
   `c(r[[chunk]], mask, weights)`. Chunk size:
   `max(1, min(nlyr, floor(0.25 * .wapor_memory_budget_bytes() / (8 * zone_cells))))` with
   `zone_cells = 1.3 * sum(st_area(z)) / cell_area` over all zone rows (dissolve levels and AOI
   included). Because chunks arrive layer-wise, write results into pre-sized positions
   (`(zone - 1) * nlyr + layer`) so the final order is the one of step 3. Per-zone quantities that
   do not depend on the layer (mask area, `geom_area`, zone key) are computed once.
5. **Two small fixes in the same function.**
   - `format = "sf"`: use `sf::st_geometry(z)[<zone index of each row>]` (keep the zone index from step 3).
   - Range check of `weights`: `terra::global(weights, "range", na.rm = TRUE)` instead of `terra::values()`.
6. **Tests** in `test-zonal-stats.R`:
   - Equivalence with `reference_zonal_stats()`: `expect_identical()` on the data frame (after
     dropping attributes) for: default statistics; all statistics including quantiles, `sum_volume`
     with `days`, and `class_share` with `breaks`; `mask` and `weights`; two id levels with
     dissolve and AOI; a zone with no overlap; a zone below `min_coverage`; a raster with NA cells;
     12 layers with a chunk size forced to 1 and to 5 (via `options(Rwapor.memory_budget_mb = ...)`).
     Use a 120 x 120 raster so the reference stays fast.
   - `format = "sf"` with two statistics: every row's geometry equals its zone's geometry
     (fails before the fix; do not compare this case with the reference).
   - Warnings are the same set as the reference for each case.
7. **Benchmark script** `inst/bench/zonal_benchmark.R` from `evidence/zonal_lean.R`: the three
   cases of section 2.2 plus the one-zone case; prints seconds and peak R memory.

### Validation

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'mask-helpers')"
& $R -e "devtools::test(filter = 'classify')"
& $R inst\bench\zonal_benchmark.R
```

### Done criteria

- [ ] All equivalence tests pass with `expect_identical()`.
- [ ] 800 x 800, 12 layers, 400 zones, default statistics, farms only: at most 10 s (was 56 s).
- [ ] 1500 x 1500, 12 layers, 2025 zones: at most 35 s (was 237 s).
- [ ] One zone over 1500 x 1500 x 36 layers with 4 layers per read: peak R memory at most 900 MB (was 1,442 MB).
- [ ] The `format = "sf"` test fails on the old code and passes on the new.
- [ ] All existing zonal, mask-helper and classify tests pass unchanged.
- [ ] No files changed outside the table.

### Out of scope

- A second, faster path on exactextractr's built-in operations (decision D-B1). Not part of this work package.
- Deriving the dissolve levels and the AOI row from the finest level instead of extracting them
  again. The default call extracts every cell once per level; this is the next lever after WP-B
  and needs its own plan.
- Any change to formulas, defaults, arguments or output columns.

## 5. WP-C: Level 3 staging, measure first (`perf-c`)

Not an implementation task yet. After WP-A is merged:

1. Rerun the `ti-06` case with the new settings: the citrus seasonal analysis that took about
   30 minutes with `data_source = "api"` (0.93 M cells, 36 dekads, 4 variables), and the same run
   from local files.
2. Rerun `ti-07`'s case (opening 36 remote Level 3 layers took 95 s in `wapor_map()`).
3. Record both in `issues-log.md`. If streaming is within a factor of two of the local run, close
   `ti-07` and reduce `ti-06` to its offline purpose (`wapor_download()` for work without internet).
   If it is still much slower, plan the cache with the kernel's repeated opens
   (`R/processing_kernel.R:211`, one open per file per window) as the first suspect.

## 6. Decisions for the maintainer

| ID | Question | Default used in this plan |
|---|---|---|
| D-A1 | Should `RWAPOR_AUTO_CONFIG=false` still skip the PROJ fix? | No. The PROJ fix gets its own switch `options(Rwapor.fix_proj = FALSE)`. |
| D-A2 | Extension filter scoped to Rwapor's own reads, or session-wide? | Scoped. Session-wide would block the user's other `/vsicurl/` formats. |
| D-B1 | Add a fast path on exactextractr's built-in operations (5 to 20 times faster again for mean, min, max, sd, coverage), accepting differences up to about 1e-6? | Not now. Decide after WP-B is measured. |
| D-O1 | Run WP-A before the remaining P2 batches? | Yes: it touches no P2 file and every live test and benchmark gets faster. |

## 7. Report format for implementing agents

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA
(each with evidence) / DEVIATIONS / QUESTIONS.

## 8. Implementation record

### perf-a (Claude, 2026-10-05, branch `perf/remote-io-1.0.6`, not committed)

All nine steps of section 3 are implemented. Deviations from the plan as written:

- `R/analysis_engine.R` also changed (one line): `.wapor_plan_for_job()` was a third caller of
  the removed `bytes_per_file_window` argument. `R/Rwapor-package.R` lists the two new options.
- `.wapor_io_plan()` opens its first file inside `.wapor_with_remote_io()` too.
- The volume message is a helper, `.wapor_volume_note()` in `R/processing_plan.R`, called from
  `wapor_ts()` and `wapor_map()`.
- **Time limits of the benchmark changed.** The limits in section 3 (Level 3 at most 9 s) came
  from a low-level extraction. Through the real `wapor_ts()` Level 3 takes longer both before and
  after the change, and the connection was two to three times slower in the afternoon than at
  midday. The benchmark now requires at most 60% of the time of the old settings (plus loose
  absolute limits of 60 s and 90 s); megabytes and 404 counts keep the tight limits.

Results (`Rscript inst/bench/remote_io_benchmark.R .`, real `wapor_ts()`, 150 polygons, 36 dekads):

| Level | Old settings | New settings | Values |
|---|---|---|---|
| 3 (JVA) | 66.3 s, 232.3 MB, 648 GET + 108 HEAD, 72 x 404 | 26.9 s, 14.3 MB, 477 GET + 36 HEAD, 0 x 404 | identical |
| 2 | 342.7 s, 1,090.6 MB, 72 x 404 | 20.7 s, 17.4 MB, 0 x 404 | identical |

Done criteria: chunk variable empty after load (yes); Level 2 at most 25 MB (17.4); Level 3 at most
15 MB and zero 404 (14.3, 0); values equal (yes); filter cleared after the call (yes, checked by the
benchmark and by tests); `known-answer` 4,251 expectations pass; live release checks 6 of 6;
full `devtools::test()` 0 failures (7 skips: 6 live tests that need `RWAPOR_RUN_LIVE_TESTS`, which
pass when switched on, 124 expectations; 1 zonal fixture test skipped by its author);
focused files `gdal_config` 57, `processing` 250, `analysis-tiled` 53, `streaming-hardening` 12.

Open observation for perf-c: in `wapor_ts()` at Level 3 the `exact_extract()` call takes 4 to 34 s
between otherwise equal runs (19 s of a 25 s profile). It is not caused by the settings changed
here. Suspects, not yet separated from connection speed: polygons passed in lon/lat to a UTM
raster, and the `max_cells_in_memory` value the planner derives.

Not done here: remote reads in `R/wapor_monitoring.R` are not wrapped by the extension filter
(correct, two extra failing requests per file).

### perf-c (Claude, 2026-10-05, measured on the perf-a branch)

| Case | Local files | API, new settings | API, old settings |
|---|---|---|---|
| `ti-06`: citrus seasonal analysis, JVA, 36 dekads, AETI and T at Level 3, RET and PCP at Level 1, 167,281 crop cells | 196 s | 220 s, 27.6 MB requested, 8 x 404 | 295 s, 556.4 MB requested, 288 x 404 |
| `ti-07`: `wapor_map()` of 36 Level 3 dekads for the citrus area (opening the layers / whole call) | not applicable | 4.9 s / 25.6 s | 8.8 s / 33.2 s |

Mean adequacy is 0.980 in all three analysis runs. The 30 minutes and the 95 s recorded on
2026-09-24 were not reproduced even with the old settings; the code has changed since (1.0.1 to
1.0.5) and the connection differs, so they cannot be attributed.

Conclusions, by the rule in section 5:

- Streaming is within 12% of the local run. A download cache is not needed for speed.
  `ti-06` is reduced to its offline purpose (an exported `wapor_download()` for work without
  internet). Maintainer decision.
- `ti-07` (faster remote opening) is closed: opening 36 layers takes 4.9 s.
- The analysis itself takes 196 s on local files for 167,281 crop cells. That is now the larger
  cost and is not a remote I/O question. Not investigated here.
- The 8 remaining 404 responses come from remote opens outside `.wapor_with_remote_io()`
  (the template open in `R/analysis_engine.R:181` and the planner's header reads). Harmless.

Scripts: `evidence/perf_c.R`, `evidence/perf_c_map.R`.

### perf-b (Claude, 2026-10-05, branch `perf/zonal-engine-1.0.6`, not committed)

The maintainer instructed on 2026-10-05 to implement perf-b, which releases `R/zonal_stats.R`
for this task. Hermes's `p2-b2` entry is unchanged: open B2 work must be rebased on this.

Implemented as in section 4: frozen reference (`tests/testthat/helper-zonal-reference.R`), only
requested statistics computed, results collected per zone and layer and bound once, layers read
in groups, `format = "sf"` geometry by zone, range check of `weights` with `terra::global()`.

Deviations:

- One group's table is sized to an eighth of the memory budget, not a quarter: measured peak use
  is about 2.5 times the table. The previous group is released and the garbage collector is run
  before each further group.
- Cells per zone are estimated from zone bounding boxes in raster units (works for lon/lat too),
  not from `st_area()`.
- The "no overlap" warning is raised where the original raised it (inside the loop, once per
  zone), so that it still appears when a later zone stops with an error.
- The benchmark reports peak memory above the level before the call, and its memory case is one
  zone over 900 x 900 cells with 72 layers.

Results (`Rscript inst/bench/zonal_benchmark.R .`):

| Case | Before | After |
|---|---|---|
| 800 x 800, 12 layers, 400 zones, default statistics | 56 s | 6.5 to 8.0 s |
| 800 x 800, 36 layers, 400 zones | 153 s | 10.9 to 13.0 s |
| 1500 x 1500, 12 layers, 2025 zones | 237 s | 25.3 to 26.6 s |
| 800 x 800, 12 layers, 400 zones, eight statistics | 106 s | 12.1 to 12.6 s |
| 1500 x 1500, 12 layers, 400 farms, two id levels and AOI | 140 s | 33.8 to 37.0 s |
| one zone over 900 x 900 cells, 72 layers, 512 MB budget | 118 s, 1,120 MB | 63.6 s, 690 MB |

Memory: with the garbage collector run at each group, memory in use is flat at 113 MB over all
nine groups of the 72-layer case and the peak is 517 MB; the benchmark run measured 690 MB. The
peak statistic depends on when R collects garbage, so the benchmark limit is 800 MB. Before, the
peak grew with the layer count (336, 580 and 1,120 MB for 12, 36 and 72 layers).

Done criteria: equivalence with the frozen reference by `expect_identical()` on tables and
warnings, 11 cases, plus 3 cases at two forced group sizes (yes); 800 x 800 x 12 at most 10 s
(6.5 to 8.0); 1500 x 1500 x 12 with 2025 zones at most 35 s (25.3 to 26.6); the `format = "sf"`
check gives 4 empty geometries of 8 on the old function and 0 on the new; `zonal` 74
expectations, `mask-helpers` 8, `classify` 35, full `devtools::test()` 0 failures (7 skips as
before). The plan's memory criterion (at most 900 MB at 36 layers) was replaced by the 72-layer
case above.

Found while testing, not fixed (behaviour of the B2 code, same in the frozen reference):
ISS-20261005-004 (lon/lat rasters need lwgeom) and ISS-20261005-005 (`class_share` with `breaks`
fails on zones with NoData).

Not done: the faster path on exactextractr's built-in operations (decision D-B1) and deriving
the dissolve levels from the finest level. The default call still extracts every cell once per
level, which is why it takes 34 to 37 s where farms only take 7.
