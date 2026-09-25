# Rwapor improvements learned from the WaPOR training case studies

- **Date**: 2026-09-24
- **Status**: PROPOSED, needs review before any implementation
- **Source**: building and running `training/water-productivity-training.qmd`
  (citrus, North Jordan Valley, L3 JVA, 2024-03-01 to 2025-02-28; winter wheat,
  Jendouba, L3 JEN, 2023-11-01 to 2024-05-31) with Rwapor 1.0.2 (local,
  uncommitted) on Windows, R 4.5.3.
- **Board tasks**: `ti-01` to `ti-16` in `agent-workflow/agents-board.json`,
  all `pending` with notes "REVIEW FIRST".
- **Related issues**: ISS-20260923-003, ISS-20260923-004, ISS-20260923-005,
  ISS-20260924-006, ISS-20260925-007, ISS-20260925-008, ISS-20260925-009 in
  `agent-workflow/issues-log.md`.
- **Lessons register**: see the table at the end of this document (L1 to L21,
  implemented or not).

## How to review this plan

For each item decide: accept / change / reject, the target release, and any
open question listed under the item. Record decisions in the item's board
task (notes) before anyone starts coding. Items are ordered by priority:

| Priority | Meaning | Items |
|---|---|---|
| P0 | Wrong results or crashes; fix before the training / next push | ti-01 to ti-05 |
| P1 | Performance and disk use observed in the case studies | ti-06 to ti-08 |
| P2 | Features the training had to write by hand | ti-09 to ti-16 |

Every P0 fix must come with a regression test that fails before the fix.

---

## P0: correctness and crashes

### ti-01: `wapor_map(separate_files = TRUE)` drops the WaPOR scale factor (ISS-20260924-006)

- **Evidence**: per-dekad files written by `wapor_map(seasonal = FALSE,
  separate_files = TRUE)` hold raw integers as Float32 with scale 1
  (L3-AETI-D values 1 to 30 instead of 0.1 to 3.0 mm/day; the remote COG is
  Int16 with `Scale: 0.1`). A local analysis on these files gave seasonal
  AETI 10,557 mm instead of 1,035.86 mm (JVA citrus).
- **Proposed change**: in the per-layer write path of `R/wapor_map.R`
  (around lines 557 to 570) write physical values (read with the scale
  applied, or apply `terra::scoff()`), or keep Int16 and write the scale/offset
  metadata. Check the multi-band path (`separate_files = FALSE`) the same way.
- **Tests**: write a one-layer Int16 raster with scale 0.1, pass it through
  the write path, assert the stored values read back scaled; a live smoke test
  comparing one dekad against `terra::rast("/vsicurl/...")`.
- **Files**: `R/wapor_map.R`, `tests/testthat/test-wapor_map*.R`.
- **Effort / risk**: small / low. Users with files saved by 1.0.x must
  re-download: note it in NEWS.
- **Open question**: store Int16 + scale (small files) or Float32 (simple)?

### ti-02: `ref_year = 1970` rejected by the 1.0.1 kernel (ISS-20260923-003)

- **Evidence**: `wapor_run_seasonal_analysis(config = list(ref_year = 1970, ...))`
  stops with "Season start/end values must lie between -1000 and 999 days;
  found 19784 to 20148" (`.wapor_profile_key_raster`, `R/processing_kernel.R`).
  Callers still pass 1970: `inst/shiny/mod_analysis.R:1340`,
  `vignettes/advanced-analysis.Rmd:82`, `vignettes/wheat-water-productivity.Rmd:96`,
  default in `R/analysis.R:1078`. The dashboard's seasonal analysis therefore fails.
- **Proposed change**: inside the kernel job, rebase start/end rasters to the
  season-start year (the key only needs relative days), so any `ref_year` works;
  also drop the 1970 defaults from the callers.
- **Tests**: same analysis with `ref_year` NULL, 1970 and the season year gives
  identical results; Shiny analysis smoke test.
- **Files**: `R/processing_kernel.R`, `R/analysis_engine.R`, `R/analysis.R`,
  `inst/shiny/mod_analysis.R`, the two vignettes.
- **Effort / risk**: small to medium / medium (touches the kernel key).

### ti-03: `wapor_export_analysis_outputs()` crashes on a single-season result (ISS-20260923-004)

- **Evidence**: "[subset] invalid name(s)" from `results[[1]]$h_mask`
  (`R/analysis_utils.R:826`): for a single season `results[[1]]` is the
  `h_mask` SpatRaster, and `$` on a SpatRaster is a layer-name subset.
- **Proposed change**: detect multi-season input with
  `is.list(results[[1]]) && !inherits(results[[1]], "SpatRaster") && !is.null(results[[1]]$h_mask)`.
- **Tests**: export a single result whose mask layer is named `crop_mask`;
  export a named list of two seasons.
- **Files**: `R/analysis_utils.R`, `tests/testthat/test-export*.R`.
- **Effort / risk**: small / low.

### ti-04: a supplied crop mask is ignored unless `use_crop_mask = TRUE`

- **Evidence**: `R/analysis_engine.R` (harmonize mask block) uses the mask only
  when `config$use_crop_mask` is TRUE; otherwise every AOI pixel becomes class 1.
  With a rectangular AOI (Jendouba wheat) all land would have been analysed as
  wheat, silently.
- **Proposed change**: default `use_crop_mask` to TRUE when
  `rasters$crop_mask` is a SpatRaster; warn when a mask is supplied but
  `use_crop_mask = FALSE` is set explicitly.
- **Tests**: mask supplied without the flag gives the masked result; explicit
  FALSE gives a warning.
- **Files**: `R/analysis_engine.R`, `R/analysis_validation.R` (preflight message).
- **Effort / risk**: small / low (behaviour change: document in NEWS).

### ti-05: release 1.0.2 and align the unused green/blue registry step (ISS-20260923-005)

- **Evidence**: the monthly green/blue fix (Jendouba wheat blue water 136 mm
  monthly vs 4 mm with the old seasonal-total split) exists only in the local,
  uncommitted 1.0.2. GitHub still serves 1.0.1; the training notebook and
  `check_setup.R` require 1.0.2. `step_peff_green_blue` in
  `R/analysis_registry.R` (skipped by the engine) still splits seasonal totals.
- **Proposed change**: commit and push 1.0.2 (after ti-01 to ti-04 if they
  are accepted for the same release); make the registry step sum monthly
  splits or remove it.
- **Tests**: existing "seasonal green/blue water sum the monthly splits" test;
  add one for the registry step if kept.
- **Files**: `R/analysis_registry.R`, `DESCRIPTION`, `NEWS.md`.
- **Effort / risk**: small / low. **Deadline**: before the note to
  participants is sent (they install from GitHub).

---

## P1: performance and disk use

### ti-06: download once, analyse many (built-in offline cache)

- **Evidence**: the API-streaming seasonal analysis of the small citrus AOI
  (0.93 M cells, 36 dekads, 4 variables) took about 30 minutes; downloading the
  same dekads as files took 55 s per variable (11 MB) and the local analysis
  gave identical results (AETI 1,035.86 mm, ETc 1,056.4 mm, adequacy 0.98).
  The training had to add its own `download_wapor()` helper (crop, mask for L3,
  no mask for coarse L1, skip existing files, offline fallback).
  Also: the local reader (`wapor_local_rasters`) scans both `<folder>/<VAR>`
  and `<folder>/<VAR>_seasonal`, so a seasonal file saved by `wapor_map` next to
  the dekadal files can be picked up with the dekads.
- **Proposed change**:
  1. export `wapor_download(variable, region, period, folder, l3_region, mask)`
     writing one scaled GeoTIFF per date (`WAPOR-3.<VAR>.<date>.tif`), skipping
     existing files, working offline from the cache;
  2. add `config$cache_dir` to `wapor_run_seasonal_analysis`: fill the cache
     on first use, then read locally;
  3. make the local reader ignore `_seasonal` files unless explicitly asked.
- **Tests**: local vs API equality on a small AOI; offline run with a dead proxy;
  reader ignores a seasonal file placed next to dekads.
- **Files**: new `R/download_cache.R`, `R/analysis_engine.R`, `R/analysis.R`
  (`wapor_local_rasters`).
- **Effort / risk**: medium / medium.
- **Open question**: default cache location (project folder vs user cache dir).

### ti-07: faster remote opening

- **Evidence**: opening 36 remote L3 layers took 95 s before any cropping
  (`wapor_map` log, JVA).
- **Proposed change**: open layers in parallel (future) or batch with GDAL
  HTTP/2 multiplexing (`GDAL_HTTP_MULTIPLEX=YES`, `GDAL_HTTP_VERSION=2`) and a
  larger VSI cache; measure with `inst/bench/`.
- **Files**: `R/gdal_config.R`, `R/wapor_map.R`, `R/processing_kernel.R`.
- **Effort / risk**: medium / low. Benchmark before and after.

### ti-08: disk footprint of large L3 runs

- **Evidence**: the Jendouba wheat run (5.1 M cells, 21 dekads, 5 variables)
  failed with "No space left on device" at 8 GB free; it passed after setting
  `keep_intermediates = FALSE` and `include_dekadal = FALSE`. `keep_intermediates`
  defaults to TRUE in memory mode and materialises every dekadal stack;
  derived rasters use FLT8S; the exports took 400 MB.
- **Proposed change**: default `keep_intermediates = FALSE` and
  `include_dekadal = FALSE`; write intermediates and exports as compressed
  Float32; extend `wapor_preflight_check()` / `wapor_plan_processing()` with an
  estimate of temporary disk space and a warning when free space is too low.
- **Tests**: planner reports disk estimate; results identical with FLT4S
  within 1e-4 relative.
- **Files**: `R/analysis_engine.R`, `R/processing_plan.R`, `R/analysis_utils.R`,
  `R/analysis_validation.R`.
- **Effort / risk**: medium / low. Behaviour change for users who rely on
  `dekadal_stacks` being returned: document.

---

## P2: features the training had to build by hand

### ti-09: irrigation performance indicators (Chukalla et al., 2022)

- **Reference**: Chukalla, A.D. et al. (2022). A framework for irrigation
  performance assessment using WaPOR data. HESS 26, 2759 to 2778,
  https://doi.org/10.5194/hess-26-2759-2022 (Table A1).
- **Evidence**: the notebook computes by hand: adequacy classes (good
  0.8 < A <= 1, acceptable 0.68 to 0.8, poor <= 0.68), uniformity (1 - CV of AETI
  within a field), equity (CV of field means; good <= 10%, fair 10 to 25%,
  poor > 25%), climate normalization f_norm = mean RET / RET_i. Without field
  boundaries it uses 1 km blocks; connected pixel patches were tried and
  rejected (6 minutes, merged fields into one 12,656 ha patch).
- **Proposed change**: `wapor_classify_adequacy()`, `wapor_calc_uniformity(aeti, units)`,
  `wapor_calc_equity(aeti, units)`, `wapor_climate_norm(ret)`, where `units`
  is field polygons or a block size in metres; optional registration as
  indicator steps.
- **Files**: `R/analysis_indicators.R`, `R/indicators_math.R`, docs.
- **Effort / risk**: medium / low.

### ti-10: farm-level extraction and survey join helpers

- **Evidence**: 113 surveyed farms are 177 polygons; the notebook dissolves by
  farm ID (`terra::aggregate(by = "Name")`), extracts area-weighted means, and
  joins the survey on normalised IDs (`toupper(trimws())`).
- **Proposed change**: `wapor_extract_farms(stack, polygons, id, dissolve = TRUE,
  weights = TRUE)` returning a tidy table; optionally monthly series per farm.
- **Files**: new `R/farm_extract.R`.
- **Effort / risk**: small to medium / low.

### ti-11: perennial (tree) crop support

- **Evidence**: `FAO_CROP_DEFAULTS` has no citrus; the yield chain
  (HI, MC, fc, AOT) is for field crops and must not be applied to trees; FAO-56
  Table 12 has several citrus rows (ground cover vs no ground cover, 70/50/20%
  canopy); stage names in the notebook follow the tree's year (flowering, fruit
  set, fruit development, maturation and harvest). The package documents `fc`
  as ground cover, while the WaPOR methodology and the training define it as
  the light use efficiency correction factor (1 for C3 crops).
- **Proposed change**: add citrus (and other tree) profiles with the Table 12
  variants; a `crop_type = "perennial" / "annual"` field that disables
  `yield_npp` and `cwp_bwp` for perennials unless yields are supplied; stage
  name fields; correct the `fc` documentation.
- **Files**: `R/crop_defaults.R`, `inst/extdata/fao_growth_stages.csv`,
  `R/analysis_engine.R`.
- **Effort / risk**: medium / low.
- **Open question**: allow survey yields as an input raster/table for CWP?

### ti-12: crop mask helpers

- **Evidence**: L3 grids are UTM, so polygons must be reprojected before
  `terra::rasterize` (a lon/lat polygon on a UTM grid gives an empty mask);
  raster crop maps from other projects need the fraction method (binary,
  average, threshold); the notebook checks mask area against polygon area.
- **Proposed change**: `wapor_rasterize_mask(polygons, template, field)` that
  reprojects automatically, `wapor_harmonize_mask(crop_map, template, class,
  min_fraction = 0.5)`, and an area check in the preflight report.
- **Files**: `R/analysis.R` or new `R/mask_helpers.R`.
- **Effort / risk**: small / low.

### ti-13: export useful internal functions and add bright/dark spots

- **Evidence**: `wapor_calc_cv` and effective rain on raster stacks
  (`wapor_calc_peff`) are internal; the training needs CV, monthly Peff and a
  bright/dark spot classification (CWP and yield at or above P95 = bright;
  at or below the low threshold = dark).
- **Proposed change**: export `wapor_calc_cv`, a raster-stack Peff function,
  and `wapor_classify_spots(cwp, yield, high = 0.95, low = 0.05)`.
- **Files**: `R/analysis_indicators.R`, `NAMESPACE`.
- **Effort / risk**: small / low.

### ti-14: plotting

- **Evidence**: `wapor_plot_map()` and `wapor_plot_kc_curve()` use deprecated
  `aes_string()` (ggplot2 warning) and `geom_raster` prints "Raster pixels are
  placed at uneven horizontal intervals"; `terra::plot` draws only 500,000 cells
  by default (a 5 M-cell map showed 10% of its pixels); the Kc plot has a day
  axis and fixed FAO stage names.
- **Proposed change**: terra-based `wapor_plot_map(..., maxcell = ncell(r))`
  with unit legend; `wapor_plot_kc_curve(kc, start, stage_days, stage_names)`
  with a calendar axis; replace `aes_string()` with `aes()`.
- **Files**: `R/viz.R`.
- **Effort / risk**: small / low.

### ti-15: offline behaviour of metadata calls

- **Evidence**: `wapor_fetch_l3_regions()` and URL generation need the server;
  the training saves the region list to CSV and falls back to saved files.
- **Proposed change**: disk cache for the L3 region list and generated URL
  lists (with a timestamp), used automatically when offline, with a clear
  message.
- **Files**: `R/metadata.R`, `R/api_client.R`, `R/wapor_metadata_cache.R`.
- **Effort / risk**: small / low.

### ti-16: robust area calculation for field polygons

- **Evidence**: `sf::st_area()` on the citrus polygons (EPSG:4326) failed in
  the s2 engine ("Loop 0 is not valid: Edge 6 is degenerate") although GEOS
  reports them valid; measuring in the local UTM zone works.
- **Proposed change**: area helpers inside Rwapor always measure in a
  projected (UTM) CRS, or disable s2 locally; add a test with duplicate
  vertices.
- **Files**: `R/utils.R` and any area helper.
- **Effort / risk**: small / low.

---

## Environment notes (not package changes, keep for the training)

- A full L3 render needs 15 to 20 GB free disk.
- `Rscript -e` with sf/terra can segfault in Git Bash when a PostgreSQL PROJ
  database is on PATH; use script files.
- EPSG lookups in `terra::project(x, "EPSG:4326")` fail in that shell; the
  notebook uses `sf::st_transform()` for that step.

---

## Lessons learned register (session 2026-09-23 to 2026-09-25)

Status of every lesson from building the training. "Package" means the fix
lives in Rwapor itself; "notebook" means only the training works around it.

| # | Lesson | Package status | Where it is handled now | Task / issue |
|---|---|---|---|---|
| L1 | Seasonal green/blue water must be split month by month, then summed (seasonal-total split: Jendouba blue 4 mm instead of 136 mm) | **Implemented** in 1.0.2, with a failing-first regression test; **not committed or pushed** | `R/analysis_engine.R`, `tests/testthat/test-analysis-engine.R`, `NEWS.md` | ISS-20260923-005, ti-05 |
| L2 | `wapor_map(separate_files = TRUE)` drops the 0.1 scale factor (offline AETI 10x too high) | Not implemented | Notebook `download_wapor()` reads via terra and writes scaled values | ISS-20260924-006, ti-01 |
| L3 | Kernel rejects `ref_year = 1970`; Shiny and vignettes still pass it | Not implemented | Notebook leaves `ref_year` unset | ISS-20260923-003, ti-02 |
| L4 | Single-season export crashes | Not implemented | Notebook passes a named list | ISS-20260923-004, ti-03 |
| L5 | A crop mask is silently ignored without `use_crop_mask = TRUE` | Not implemented | Notebook sets the flag, Watch out box | ISS-20260925-007, ti-04 |
| L6 | Streaming from the API is slow; download once and analyse locally (local = API exactly) | Not implemented | Notebook download step + `data_source = "local"` | ti-06 |
| L7 | Local reader also scans `<VAR>_seasonal` next to `<VAR>` | Not implemented | Notebook keeps dekadal data in `wapor_data/<case>/dekadal/` | ISS-20260925-008, ti-06 |
| L8 | Opening many remote layers is slow (36 layers, 95 s) | Not implemented | Nowhere yet | ti-07 |
| L9 | Large L3 runs fill the disk (`keep_intermediates` default TRUE in memory mode, FLT8S, dekadal exports) | Not implemented | Notebook sets `keep_intermediates = FALSE`, `include_dekadal = FALSE`; note asks for 20 GB | ISS-20260925-009, ti-08 |
| L10 | Irrigation performance indicators (Chukalla et al. 2022) | Not implemented | Notebook wheat Step 8 (adequacy classes, 1 km block uniformity/equity, f_norm) | ti-09 |
| L11 | Farm-level extraction with multi-polygon farms and survey join | Not implemented | Notebook citrus Steps 9 and 10 | ti-10 |
| L12 | Tree crops: no citrus profile, no perennial flag, yield chain must be off, stage names, `fc` is the LUE correction factor | Not implemented | Notebook citrus Step 3 (Table 12 Kc, no HI/MC/fc/AOT), wheat yield factors table | ti-11 |
| L13 | Mask helpers: reproject polygons to the L3 UTM grid, fraction harmonization, area check | Not implemented | Notebook Steps 5 (both parts) | ti-12 |
| L14 | `wapor_calc_cv`, raster Peff, bright/dark spots not exported | Not implemented | Notebook computes CV by hand | ti-13 |
| L15 | Plotting: `aes_string()` deprecation, `geom_raster` uneven-interval warning, terra `maxcell` 500,000, day-axis Kc plot | Not implemented | Notebook `plot_map()`, `two_maps()`, `plot_kc_months()` helpers | ti-14 |
| L16 | Metadata calls need internet (L3 regions, URLs) | Not implemented | Notebook saves `data/wapor_l3_regions.csv`, reuses saved maps | ti-15 |
| L17 | sf s2 area fails on field polygons with duplicate vertices | Not implemented | Notebook measures areas in UTM | ti-16 |
| L18 | `/btw` side questions never reach the main agent | Implemented (process) | `wapor-training-builder` skill: recover from `~/.claude/history.jsonl` into a requirements ledger | n/a |
| L19 | Training material needs a repeatable method (concepts, checkpoints, sketches, offline data, participant note) | Implemented (process) | User-level skill `~/.claude/skills/wapor-training-builder/` | n/a |
| L20 | Editing notebooks with Python heredocs can turn `\f`, `\t`, `\n` into control characters | Implemented (process) | Skill recipe note; build backslashes with `chr(92)` | n/a |
| L21 | Git Bash: `Rscript -e` with sf/terra can segfault and `terra::project(x, "EPSG:4326")` fails (PostgreSQL PROJ on PATH) | Environment, documented | `agent-workflow/project-memory.md`; use script files and `sf::st_transform()` | n/a |
