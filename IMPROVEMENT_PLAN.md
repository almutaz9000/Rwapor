# Rwapor Improvement Plan

**Version**: 0.9.9 → Target 1.0.0  
**Date**: 2026-08-27  
**Status**: Phase 1.1-1.3 complete; 1.4 tiled engine has a tested resumable COG/VRT slice; 1.5 L3 core APIs are on `feat/l3-mosaic-tiled-core`

---

## Executive Summary

Rwapor is an R package first and a dashboard second. Version 1.0 work starts with a correct, resumable, tile-first geospatial engine for long time series and high-resolution rasters. Dashboard work is deferred until the core functions produce complete, provenance-bearing GeoTIFF outputs reliably.

### 2026-09 Core-First Revision

**Implementation order**:
1. Replace the current tiled wrapper with real tile-by-tile GeoTIFF processing, beginning with local inputs and seasonal AETI.
2. Add deterministic target-grid, tile-manifest, completeness, and resume contracts; then extend the tiled reducer to all requested indicators.
3. Replace silent first-L3 selection with an explicit policy: user-selected L3 region or `mosaic_all` of every AOI-intersecting L3 region, saved as a mosaicked output with coverage provenance.
4. Add COG-ready atomic output writing, source/output manifests, strict validation, and benchmark fixtures.
5. Only then make the Shiny dashboard submit and monitor those core jobs. Dashboard redesign is not on the critical path.

**Non-negotiable correctness rules**:
- A complete result must never omit planned time slices or intersecting L3 coverage.
- Partial temporal or spatial coverage fails by default; it requires explicit opt-in and a machine-readable coverage report.
- The engine never silently chooses the first discovered L3 region.
- Tile output is immutable and resumable: a tile is marked complete only after it is readable, validates against the target grid, and is recorded in the manifest.

---

## Phase 1: Critical Improvements (Scientific Correctness & Architecture)

### 1.1 Latitude-Aware Area Weighting (Port from waporbox)
**Priority**: CRITICAL  
**Effort**: 3-4 days  
**Files**: `R/analysis_indicators.R`, `R/analysis_engine.R`, `R/analysis_utils.R`  
**Status**: DONE 2026-08-28

**Problem**: Rwapor computes `pixel_area_ha` from template `ymin` only (scalar), then `pixel_count * scalar`. On EPSG:4326 grids spanning wide latitude ranges (Jordan Valley ~31-33°N, Savola Egypt ~30-31°N), this biases class means and CWP/BWP by 2-5%.

**Tasks**:
- [x] Add `wapor_pixel_area_ha(x)` in `analysis_utils.R` (port waporbox's `cos(lat)` formula)
- [x] Replace scalar `pixel_area_ha` in `analysis_engine.R` with latitude-aware zonal sum
- [x] Update `wapor_masked_global_mean` to accept an optional area raster
- [x] Update `wapor_weighted_class_mean` to use `area_ha` when present, else pixel_count
- [x] Area-weight CWP/BWP AOI means in the engine
- [x] Tests in `tests/testthat/test-pixel-area.R`

**Verification**:
```r
# Test: 100km x 100km grid at 30°N vs 40°N
template_30 <- create_template(30, 31, 100000, 100000, res = 100)
template_40 <- create_template(40, 41, 100000, 100000, res = 100)
area_30 <- pixel_area_ha(template_30)  # matrix, varies by row
area_40 <- pixel_area_ha(template_40)  # smaller values
# Mean of constant raster should be identical regardless of latitude
```

---

### 1.2 Extract Indicator Math from terra (Testable Pure R)
**Priority**: CRITICAL  
**Effort**: 4-5 days  
**Files**: `R/indicators_math.R` (new), `R/analysis_indicators.R`  
**Status**: DONE 2026-08-28

**Problem**: Indicator functions (adequacy, Peff, green/blue, CWP) are embedded in terra/SpatRaster code. Unit tests require SpatRaster objects, making them slow and brittle.

**Tasks**:
- [x] Create `indicators_math.R` with pure numeric functions:
  - `wapor_math_adequacy_etc`
  - `wapor_math_beneficial_fraction`
  - `wapor_math_peff_usda`
  - `wapor_math_green_water`, `wapor_math_blue_water`
  - `wapor_math_npp_to_biomass`, `wapor_math_yield_from_npp`
  - `wapor_math_cwp`, `wapor_math_bwp`
  - `wapor_math_zonal_mean_by_class`
  - `wapor_math_area_weighted_mean`
- [x] Refactor numeric paths in `analysis_indicators.R` to call the math layer
- [x] Add unit tests on small matrices (no terra dependency): `tests/testthat/test-indicators-math.R`

**Verification**:
```r
# Unit test example
aeti <- matrix(c(400, 500, 600, NA), 2, 2)
etc  <- matrix(c(500, 500, 500, 500), 2, 2)
expect_equal(adequacy_etc(aeti, etc), c(0.8, 1.0, 1.2, NA))
```

---

### 1.3 Step-Registry Architecture for Indicators (Port from waporbox)
**Priority**: HIGH  
**Effort**: 3-4 days  
**Files**: `R/analysis_engine.R`, `R/analysis_registry.R`  
**Status**: DONE 2026-09-04 (extra registered steps run from the engine; built-in indicators still computed in-engine to protect existing assertions)

**Problem**: Adding a new indicator requires editing the monolithic `wapor_run_seasonal_analysis` engine. waporbox uses `INDICATOR_STEPS` registry — one function per indicator, auto-ordered by dependency.

**Tasks**:
- [x] Registry in `R/analysis_registry.R` (`wapor_register_indicator_step`, `wapor_list_indicator_steps`, `wapor_get_indicator_step`)
- [x] Topological order: `wapor_ordered_indicator_steps()` (cycle error)
- [x] Shared runner: `wapor_run_indicator_steps(ctx, skip = ...)`
- [x] Engine runs extra registered steps after built-in calculations
- [x] Dummy-indicator test: register a step, request it in `indicators`, raster mean = 42
- [ ] Optional later: migrate built-in indicators out of the engine body into the loop (not required for the dummy-step verification)

**Verification**:
```r
wapor_register_indicator_step("dummy", function(ctx) {
  if (!"dummy" %in% ctx$indicators) return()
  r <- ctx$results$seasonal_aeti$raster
  ctx$results$dummy <- r * 0 + 42
}, depends = "agg_aeti")
results <- wapor_run_seasonal_analysis(..., indicators = c("agg_aeti", "dummy"))
expect_equal(terra::global(results$dummy, "mean", na.rm = TRUE)$mean, 42)
```

---

### 1.4 Tiled / Windowed GeoTIFF Engine
**Priority**: CRITICAL
**Effort**: 10-15 days total
**Files**: `R/analysis_tiled.R`, `R/analysis_engine.R`, `R/analysis_utils.R`, `tests/testthat/test-analysis-tiled.R`
**Status**: DONE 2026-09-14 — square tiles, versioned run manifest, resume, windowed sources, tile-local block reducers, VRT assembly, atomic COG publish, remote-COG and memory benchmarks

**Problem**: Rwapor materializes full `(time, y, x)` SpatRasters. At L1 global (~5.6B pixels/layer) this is impossible. The previous `wapor_run_seasonal_analysis_tiled()` accepted `tile_size` but delegated to the full-grid engine.

**Completed**:
- [x] Deterministic square tile enumeration from the crop-mask target grid
- [x] Per-tile crop of local or `/vsicurl/` source rasters before seasonal calculation
- [x] Per-tile compressed, tiled GeoTIFF/COG output with temporary-file publication and geometry validation
- [x] Versioned JSON run manifest: source identities, target-grid signature, config hash, package/GDAL versions, checksums, and coverage
- [x] Resume completed tiles safely; retry only pending or failed tiles; refuse mismatched manifests
- [x] Windowed temporal weighted-sum reducer for block-level aggregation
- [x] Direct block-level temporal reducers for tiled indicators (AETI, RET, PCP, Peff, ETc, adequacy, biomass, green/blue, beneficial fraction)
- [x] Assemble validated tile assets into VRT/mosaic products
- [x] Local fixture tests for resume, tiled-versus-full numerical parity, and windowed sources
- [x] Remote-COG fixtures and memory/HTTP benchmarks

**Acceptance criteria**:
- Peak working memory is bounded by tile dimensions, active workers, and one temporal reducer state, not full AOI dimensions.
- Tiled results match the standard engine within a documented tolerance on the same target grid.
- No tile is listed as complete until it is readable and its geometry matches the target tile.
- A resumed job reuses validated completed tiles and reports incomplete temporal/spatial coverage as failure by default.

---

### 1.5 Explicit L3 Selection and Mosaic-All Coverage Policy
**Priority**: CRITICAL
**Effort**: 5-7 days
**Files**: `R/wapor_map.R`, `R/wapor_ts.R`, `R/seasonal_download.R`, `R/utils.R`, `inst/shiny/mod_download.R`, `inst/shiny/mod_analysis.R`, tests

**Problem**: when an AOI intersects multiple Level 3 mosaics, core functions silently choose the first code. This can return an incomplete but apparently successful analysis.

**Tasks**:
- [ ] Add one shared core resolver that returns all AOI-intersecting L3 codes and their coverage metadata.
- [ ] Require an explicit policy for multiple matches: `l3_region = "CODE"` or `l3_mode = "mosaic_all"`; default is an error with the discovered choices.
- [ ] For `mosaic_all`, process every intersecting source on one declared target grid, write the source tiles separately, and save a validated mosaicked asset plus coverage manifest.
- [ ] Fail when selected regions do not provide full requested temporal coverage unless `partial = TRUE` is explicit.
- [ ] In Shiny, present the discovered codes as a required selection and a separate **Mosaic all intersecting L3 regions** option. Do not preselect the first match.
- [ ] Display the selected/mosaicked codes, spatial coverage, missing slices, and mosaic output path in the job result.

**Acceptance criteria**:
- A multi-L3 AOI cannot silently use only one region.
- Selecting one L3 creates an asset attributable to that code.
- Mosaic-all creates a saved mosaic/VRT and records every contributing L3 code, source URL, grid signature, and coverage status.

---

### 1.6 Explicit Alignment Reference (Mask vs AETI vs Custom) (DONE, verified 2026-09-18)
**Priority**: HIGH  
**Effort**: 2 days  
**Files**: `R/analysis.R`, `R/analysis_engine.R`

**Problem**: Dashboard silently warps everything to AETI grid. waporbox lets caller choose `reference = "crop_mask"` (upsample WaPOR) or `reference = "aeti"` (downsample mask).

**Tasks**:
- [x] Add `reference_layer = c("aeti", "crop_mask", "ret", "pcp", "npp", "template")`
      parameter -- exact match found in `R/analysis_engine.R:106-110`
      (`match.arg(reference_layer, c("aeti","crop_mask","ret","pcp","npp","template"))`).
- [x] Add `resampling_method` per layer -- verified implemented at `R/analysis_engine.R:111-119`
      with `get_resampling_method()` closure and defaults for aeti/crop_mask/ret/pcp/npp/season_start/season_end.
- [x] Default: `reference_layer = "aeti"` -- verified
      (`config$reference_layer %||% "aeti"`, analysis_engine.R:98), documented
      in the function's roxygen (`R/analysis.R:14`).
- [ ] Overlap validation error -- not checked; verify before marking done or open.

---

## Phase 2: Scale & Memory Hardening

### 2.1 Disk URL Cache with TTL (Port from waporbox)
**Priority**: HIGH  
**Effort**: 2 days  
**Files**: `R/api_client.R`, `R/metadata.R`

**Problem**: `memoise` only caches in session. waporbox has 24h on-disk cache surviving restarts.

**Tasks**:
- [x] Add `cache_dir = tools::R_user_dir("Rwapor", "cache")`
- [x] `cache_key <- digest::digest(url_query, "sha256")` (was a collision-prone
      byte-sum checksum; fixed in 0.9.9, see NEWS.md)
- [x] Save extracted items as `.rds`
- [x] TTL = 24h (configurable via `options(Rwapor.cache_ttl = 86400)`)
- [x] `wapor_clear_url_cache()` function

---

### 2.2 COG Write Support (MOSTLY DONE, verified 2026-09-17)
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/wapor_map.R`, `R/analysis_engine.R`

**Problem**: Only standard GeoTIFF. COG enables cloud/HTTP range reads.

**Tasks**:
- [x] `wapor_write_cog(r, path)` implemented in `R/wapor_cog.R`, exported, used
      by `wapor_map.R`, `analysis_tiled.R`, `analysis_utils.R`.
- [x] `cog = FALSE` parameter -- verified in `wapor_map()`
      (`R/wapor_map.R:116`). **Not found** in `wapor_run_seasonal_analysis()`
      (`R/analysis_engine.R`) despite the task naming both -- gap.
- [ ] GDAL < 3.1 fallback -- **verified absent** in `R/wapor_cog.R`.

---

### 2.3 Memory Benchmark Suite
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `tests/testthat/test-memory-scaling.R` (new)

**Tasks**:
- [ ] Parameterized test: grid 1k→10k, measure peak memory (`profvis` or `bench`)
- [ ] Gate: fail if memory grows > 2x for 4x grid (current engine)
- [ ] Tiled engine: verify flat memory

---

## Phase 3: Developer Experience & Parity

### 3.1 Extra Crop Defaults (Port from waporbox) (DONE, verified 2026-09-17)
**Priority**: HIGH  
**Effort**: 1 day  
**Files**: `R/crop_defaults.R`

**Tasks**:
- [x] All 9 FAO-56 crops present -- verified: Maize, Rice, Cotton, Potato,
      Soybean, Sunflower, Barley, Alfalfa, Sugarcane all appear in the
      `crop_name` vector (`R/crop_defaults.R:27`), alongside the pre-existing
      Winter Wheat, Sorghum, Sugarbeet.
- [x] Same structure retained (columns consistent with the pre-existing
      table).

---

### 3.2 Build Crop Assignments + Validation (Already Strong ✓)
**Status**: COMPLETE — `wapor_build_crop_assignments`, `wapor_validate_crop_params` exist.

**Remaining**: Ensure validation checks HI/MC in [0,1], Kc >= 0, stage lengths > 0.

---

### 3.3 Publication Map Helpers (Port from waporbox viz) (PARTIALLY DONE, verified 2026-09-18)
**Priority**: MEDIUM  
**Effort**: 3 days  
**Files**: `R/viz.R` (exists)

**Tasks**:
- [x] `wapor_plot_map(array, indicator, title, save, dpi = 300)` — implemented, exported, in NAMESPACE
- [x] `wapor_plot_comparison(arrays, titles, indicator, suptitle, save)` — implemented, exported
- [x] `wapor_plot_timeseries(df, value, group, save)` — implemented, exported
- [x] `wapor_plot_kc_curve(kc_daily, save)` — implemented, exported
- [x] `wapor_plot_anomaly(zscore_array, save)` — implemented, exported
- [ ] Colorblind palettes per indicator (RdYlGn for adequacy, viridis for CWP, etc.) — **still open**: current implementation uses single blue-to-red gradient for all indicators
- [ ] Scale bar (km), north arrow — **still open**: `ggspatial` in Suggests but not called
- [ ] 300 dpi output — implemented via `dpi` parameter

Core functions delivered; scientific plotting quality (palettes, scale, north arrow) still pending.

---

### 3.4 Anomaly & Trend Module (Port from waporbox) (MOSTLY DONE, verified 2026-09-17)
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/anomaly.R` (exists, 103 lines)

**Tasks**:
- [x] `wapor_calc_zscore(stack)` -- implemented, exported, documented.
- [x] `wapor_calc_spatial_hotspots(zscore_layer, low=-1.96, high=1.96)` --
      implemented, exported, documented.
- [x] `wapor_calc_anomaly_baseline(current, baseline_mean, baseline_sd)` --
      implemented, exported, documented.
- [x] `linear_trend(stack, times = NULL)` -- verified implemented at `R/anomaly.R:111`,
      exported in NAMESPACE, tested in `tests/testthat/test-anomaly-trend.R`.
      Deliverable complete.

---

### 3.5 Preflight Validation Module (DONE, verified 2026-09-18)
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/analysis_validation.R` (existing)

**Tasks**:
- [x] `wapor_preflight_check(config, data_source, folder)` — variable exists, period valid, L3 intersects, disk space (implemented at `analysis_validation.R:250`)
- [x] `wapor_validate_data_coverage(folder, variables, period, l3_code)` (implemented at `analysis_validation.R:179`)
- [x] Return structured report (pass/fail/warnings)
Deliverable complete, just in `R/analysis_validation.R` instead of a new `R/preflight.R`.

---

## Phase 4: Dashboard & Monitoring Hardening

### 4.1 Dashboard: Indicator Selection from Registry
**Priority**: LOW  
**Effort**: 2 days  
**Files**: `inst/shiny/app.R`, `inst/shiny/mod_analysis.R`

**Tasks**:
- [ ] Read indicator list from `INDICATOR_STEPS` registry (single source of truth)
- [ ] Auto-generate checkbox UI from registry metadata (label, description, required inputs)

---

### 4.2 DuckDB Monitoring: Area-Weighted Stats
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/wapor_monitoring.R`

**Tasks**:
- [ ] Store per-farm area (ha) in `farm_timeseries`
- [ ] Dashboard stress index: use area-weighted means
- [ ] Migration script for existing DBs

---

### 4.3 Generated Reproducible Script (Already Exists ✓)
**Status**: COMPLETE — `wapor_generate_shiny_script` in `analysis_utils.R`.

---

## Phase 5: Testing & CI Hardening

### 5.1 Expand Unit Tests (Pure Math Layer) (PARTIALLY DONE, verified 2026-09-17)
**Priority**: HIGH  
**Effort**: 3 days  
**Files**: `tests/testthat/test-indicators-math.R` (exists, 65 lines)

**Tasks**:
- [~] File exists, covers ~10 math functions (adequacy_etc, beneficial_fraction,
      peff_usda, green/blue water, npp_to_biomass, yield_from_npp, cwp, bwp,
      area_weighted_mean, zonal_mean_by_class) with basic value checks and a
      few `is.na()` guards -- not yet the systematic "every function, every
      edge case" coverage the task specifies.
- [ ] Zero-division/single-pixel edge cases -- only partially covered.
- [ ] Compare against waporbox Python reference values -- **verified absent**.

---

### 5.2 Integration Test: Full Seasonal Pipeline (PARTIALLY DONE, verified 2026-09-17)
**Priority**: HIGH  
**Effort**: 2 days  
**Files**: `tests/testthat/test-analysis-engine.R` (exists, 314 lines, 3
`test_that` blocks)

**Tasks**:
- [~] Substantial engine tests exist (local-raster indicator computation,
      crop-mask exclusion, indicator-registry extensibility) but were not
      confirmed this pass to specifically cover a 100x100 synthetic grid,
      multi-season batch mode, or local-vs-API parity -- needs a closer read
      before marking fully done or fully open.

---

### 5.3 CI: R-CMD-check + Coverage + Linting (Already Exists ✓)
**Status**: COMPLETE — `.github/workflows/R-CMD-check.yaml`, `test-coverage.yaml`.
- R-CMD-check job on 5 platform/R-version combinations
- Coverage job with covr
- **Lint job** at `.github/workflows/R-CMD-check.yaml:64-80` running `lintr::lint_package()` and `styler::style_pkg(dry="on")` — verified 2026-09-18.

---

## Phase 6: Documentation

### 6.1 Vignettes Matching waporbox Notebooks (DIFFERENT SHAPE THAN SPEC'D, verified 2026-09-17)
**Priority**: MEDIUM  
**Effort**: 3 days  
**Files**: `vignettes/` -- 4 `.Rmd` files exist: `advanced-analysis.Rmd`,
`data-catalog.Rmd`, `getting-started.Rmd`, `shiny-dashboard.Rmd`.

**Tasks**: none of the originally-specified 5 vignettes exist under these
exact names/scopes (`admin-timeseries`, `crop-mask-seasonal`,
`mixed-resolution`, `season-comparison`, `global-tiled`) -- the package is
not vignette-free, but the existing set covers different topics than this
task originally scoped. Needs a maintainer decision: keep the current 4 and
close this task, or still add the 5 originally-specified ones.

---

### 6.2 First-Time User Install Guide (Match waporbox) (MOSTLY DONE, verified 2026-09-17)
**Priority**: MEDIUM  
**Effort**: 1 day  
**Files**: `README.md`

**Tasks**:
- [x] System deps documented -- `libgdal-dev libproj-dev libgeos-dev
      libudunits2-dev` (`README.md:38`).
- [ ] `remotes::install_github("r-spatial/terra")` for latest GDAL --
      **verified absent**.
- [x] Verify step present -- `wapor_variable_metadata("L1-AETI-D")`
      (`README.md:71`), matching the spec exactly.

---

## Phase 7: Metadata & API Module Architecture

Scope reviewed: `R/api_client.R`, `R/wapor_res_key.R`, `R/metadata.R`,
`R/wapor_metadata_cache.R`, `R/plan_wapor_time_slices.R`. Builds on
`ISS-20260916-001` (2026-09-16), which already unified the metadata API,
separated level/temporal/spatial resolution, and added atomic snapshots +
manifest. None of these five files is wholly redundant -- each owns a
distinct responsibility (HTTP transport, spatial grouping, static+dynamic
metadata, metadata caching service, temporal planning) -- but real
duplication and mixed-responsibility issues remain within and across them.

### 7.0 Deduplicate `%||%` and the level->workspace-URL mapping (DONE 2026-09-16)
**Priority**: CRITICAL (correctness) / HIGH (duplication)
**Effort**: <1 day (completed)
**Files**: `R/utils.R`, `R/api_client.R`, `R/wapor_metadata_cache.R`

**Problem**: `%||%` was defined twice with *different* semantics --
`R/utils.R:8` checked `is.null()` only, `R/wapor_metadata_cache.R` (bottom of
file) also checked `length() > 0`. With no `Collate:` field in `DESCRIPTION`,
R loads files alphabetically, so the stricter definition silently won and
governed ~40 call sites package-wide. Separately, the FAO catalogue
workspace URL for a level (`L1`/`L2` -> `WAPOR-3/mapsets`, `L3` ->
`WAPOR-3/mosaicsets`, `AGERA5` -> `C3S/mapsets`) was hardcoded independently
in three places: `wapor_generate_urls_internal()` (api_client.R),
the `url_map` inside `wapor_update_metadata()` (wapor_metadata_cache.R), and
a `switch()` inside `.fetch_metadata_api_variable()` (metadata.R) -- already
drifted (the `url_map` copy silently omitted `AGERA5`).

**Tasks**:
- [x] Keep one canonical `%||%` in `R/utils.R`; delete the duplicate in
      `R/wapor_metadata_cache.R`.
- [x] Verify semantics with the full test suite before picking a winner --
      `tests/testthat/test-wapor_metadata_cache.R:104` proved the
      length-aware behavior is the one actually relied upon (a `NULL` list
      element round-tripped through `jsonlite::write_json()` /
      `fromJSON()` comes back as an empty *non-`NULL`* list, not `NULL`).
      Made the canonical `%||%` length-aware to match, with a doc comment
      explaining why.
- [x] Add `.wapor_level_workspace_url(level)` (api_client.R, internal/`@noRd`)
      as the single source of truth; route all three call sites through it.
      *Correction, 2026-09-17*: the initial 2026-09-16 pass only routed 2 of
      the 3 call sites (api_client.R, wapor_metadata_cache.R) despite being
      reported as all 3 -- `.fetch_metadata_api_variable()` in `metadata.R`
      still had its own hardcoded `switch()`. Caught during self-review
      while implementing 7.1 and fixed then; all 3 sites are genuinely
      consolidated now.
- [x] Verify: `devtools::load_all()` clean, `devtools::document()` produced
      no unexpected NAMESPACE/man diffs, full suite `0 fail / 1019 passed`.

---

### 7.1 Deduplicate the RET/PCP level-fallback rule (DONE 2026-09-17)
**Priority**: MEDIUM
**Effort**: <1 day (completed)
**Files**: `R/api_client.R`, `R/metadata.R`

**Problem**: "RET and PCP are not published at L2/L3; resolve to the L1
code" is implemented three times independently, with different regex/scope:
twice inline in `wapor_generate_urls_internal()` (api_client.R:223-224 and
231-234) and once in `get_variable_metadata_internal()` (metadata.R:373-377,
via `parts[1] %in% c("L2","L3") && grepl(...)`). If FAO ever publishes L3-RET
or adds another fallback-eligible variable, all three sites must change in
lockstep and nothing enforces that today.

**Tasks**:
- [x] Add `.wapor_resolve_level_fallback(variable)` (api_client.R, internal/
      `@noRd`) -- returns the L1-substituted code, or `variable` unchanged
      when no fallback applies. (Callers that need to know whether a
      fallback happened already hold `variable` and can compare with
      `!identical()`, as `wapor_generate_urls_internal()`'s L3 branch does
      to pick the right base URL -- no separate flag return needed.)
      Called from `wapor_generate_urls_internal()` (both L1/L2 and L3
      branches) and `get_variable_metadata_internal()`.
- [x] Regression test: direct check of `L1-RET-D`, `L2-RET-D`, `L2-PCP-D`,
      `L3-RET-D`, `L3-PCP-D`, `L3-AETI-D`, `AGERA5-ET0-E` all resolve
      identically to pre-refactor behavior; full suite `0 fail / 1019
      passed`; `devtools::document()` produced no new NAMESPACE/man diffs.

---

### 7.2 Stop re-deriving spatial resolution in `wapor_res_key()`
**Priority**: LOW
**Effort**: <1 day
**Files**: `R/wapor_res_key.R`

**Problem**: `.parse_spatial_resolution_m()` (wapor_metadata_cache.R) parses
a `"300 m"`/`"5 km"`-style string into metres, with NA guards.
`wapor_res_key()` re-implements the same regex inline (wapor_res_key.R:94-99)
without reusing it, even though `wapor_variable_metadata()` already computes
and caches `spatial_resolution_m` via that helper.

**Tasks**:
- [ ] `wapor_res_key()` reads `meta$spatial_resolution_m` directly instead of
      re-parsing `meta$spatial_resolution`; falls through to
      `.WAPOR_RES_LOOKUP` unchanged when unavailable.
- [ ] Delete the now-redundant inline parsing.

---

### 7.3 Memoise `.load_metadata_catalog()`
**Priority**: MEDIUM (efficiency)
**Effort**: <1 day
**Files**: `R/wapor_metadata_cache.R`, `R/plan_wapor_time_slices.R`

**Problem**: `wapor_temporal_codes()` (plan_wapor_time_slices.R:360) calls
`.load_metadata_catalog(level)` directly, bypassing the memoised
`wapor_variable_metadata()` wrapper. Every call re-reads and re-parses
`wapor_L1.json`/`L2`/`L3` from disk with `jsonlite::fromJSON()`, even though
the catalogue only changes when `wapor_update_metadata()` runs. In a seasonal
download loop this is a repeated, avoidable disk read + JSON parse per
variable.

**Tasks**:
- [ ] Wrap `.load_metadata_catalog()` with `memoise::memoise()`.
- [ ] Add its `memoise::forget()` call alongside the existing
      `wapor_variable_metadata` one inside `wapor_update_metadata()`, so a
      metadata refresh busts both caches together.
- [ ] Optional hardening: fold a small schema-version tag into the disk
      URL-cache key (`.wapor_url_hash()` in api_client.R) so a future API
      response-shape change can't silently serve a stale-shaped payload for
      up to 24h.

---

### 7.4 (Future, deferred) Split `metadata.R` / `wapor_metadata_cache.R` by responsibility
**Priority**: LOW -- explicitly deferred; pure churn with no user-facing
benefit until a maintainer wants it. *Correction, 2026-09-17*: this was
originally justified as "package is on the version-0.9.9 release branch."
That premise was checked this session and found stale: `DESCRIPTION` already
says `Version: 1.0.0` (committed, not part of any uncommitted work) and
`NEWS.md`'s top entry is `# Rwapor 1.0.0 (development)` -- the package is
mid-development toward 1.0.0, not sitting on a frozen 0.9.9 release
candidate. The git branch is still literally named `version-0.9.9`, which is
just stale relative to that. Net effect: there is more room for this kind of
churn than originally assumed, though staying conservative pre-1.0.0 release
is still reasonable -- this remains a maintainer call, not upgraded to
"do it now."
**Effort**: 2-3 days
**Files**: `R/metadata.R`, `R/wapor_metadata_cache.R`

**Problem** (deep-module read): `metadata.R` (495 lines) mixes four
concerns -- static data tables (`WAPOR3_VARS`, `AGERA5_VARS`, `L3_REGIONS`),
live L3-region fetch, variable-metadata resolution with fallback, and public
listing helpers. `wapor_metadata_cache.R` (382 lines) mixes disk-cache I/O,
JSON normalization, and the `wapor_update_metadata()` fetch/write/manifest
service. Two files, four-plus responsibilities, and a newcomer cannot tell
from the filenames alone which file owns "how do I get a variable's units."
`wapor_res_key.R` (135 lines, one exported function + one lookup table) is
the shape to converge toward.

**Not done now** -- captured as an option, not a commitment:
- [ ] `R/wapor_metadata_static.R` -- `WAPOR3_VARS`, `AGERA5_VARS`,
      `L3_REGIONS`, `wapor_l3_regions_to_df()`.
- [ ] `R/wapor_metadata_resolve.R` -- `get_variable_metadata_internal()`,
      `wapor_variable_metadata()`, `.wapor_resolve_level_fallback()` (7.1).
- [ ] `R/wapor_metadata_service.R` (renamed from `wapor_metadata_cache.R`) --
      `.load_metadata_catalog()`, `wapor_fetch_metadata()`,
      `wapor_update_metadata()`, normalization helpers.
- [ ] Consistent naming across the module going forward:
      `wapor_<domain>_<role>.R` (e.g. `wapor_spatial_key.R` for
      `wapor_res_key.R`, `wapor_temporal_plan.R` for
      `plan_wapor_time_slices.R`, `wapor_url_builder.R` for the URL-building
      half of `api_client.R`).
- [ ] Requires a `Collate:` field in `DESCRIPTION` if any cross-file
      load-order assumption is ever (re-)introduced -- none should be, but
      pin it explicitly if this split happens, to prevent a repeat of 7.0's
      `%||%` failure mode.

**Acceptance criteria** (if/when undertaken): no exported function's
signature or behavior changes; `git blame` history preserved via
`git mv`; full suite stays `0 fail`.

---

## Verification Strategy (Per Change)

### Before Every PR
```r
# 1. Unit tests (fast, no network)
devtools::test(filter = "test-indicators-math|test-temporal|test-internal")

# 2. Lintr + styler
lintr::lint_package()
styler::style_pkg()

# 3. Key integration tests
devtools::test(filter = "test-analysis-engine")
```

### After Major Feature (e.g., area weighting)
```r
# 1. Full test suite
devtools::test()

# 2. Coverage
covr::package_coverage()

# 3. Vignette build
devtools::build_vignettes()

# 4. Memory benchmark
Rscript tests/testthat/test-memory-scaling.R

# 5. Dashboard smoke test (interactive)
run_wapor()  # manual: load project, run analysis, verify outputs
```

### Release Checklist (1.0.0)
- [ ] All Phase 1 items complete and tested
- [ ] NEWS.md updated (R convention)
- [ ] Version bump in `DESCRIPTION`
- [ ] `R CMD check --as-cran` passes locally
- [ ] GitHub Actions CI green
- [ ] Tag `v1.0.0`, GitHub Release with binary wheels

---

## Dependencies Between Phases

```
1.1 (Area weighting) ──→ 1.2 (Math layer) ──→ 1.3 (Step registry) ──→ 1.4 (Tiled engine)
         │                    │                    │
         │                    └──→ 3.4 (Anomaly)  │
         │                                         │
         └──→ 3.3 (Viz uses area-weighted means)  └──→ 4.2 (Monitoring)
```

**Critical Path**: 1.1 → 1.2 → 1.3 → 1.4 (enables country/global runs in R)

---

## Resource Estimates

| Phase | Person-Days | Parallelizable |
|-------|-------------|----------------|
| Phase 1 | 14-17 | Partial (1.1, 1.2, 1.5 independent) |
| Phase 2 | 6-8 | Yes |
| Phase 3 | 8 | Yes |
| Phase 4 | 4 | Partial |
| Phase 5 | 5 | Yes |
| Phase 6 | 4 | Yes |
| **Total** | **41-46** | |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| terra VRT lazy reprojection not equivalent to WarpedVRT | Medium | Tiled engine incorrect | Prototype 1 tile first; compare pixel values |
| Step registry breaks existing indicator order | Low | Wrong results | Topological sort of dependencies; test full pipeline |
| Dashboard refactor breaks Shiny reactivity | Medium | Dashboard unusable | Keep UI separate; only feed indicator list from registry |
| GDAL/PROJ on CRAN Windows build | High | Package rejected | Test `R CMD check --as-cran` on win-builder early |
| FAO API changes break catalog | Low | Downloads fail | Version-pin static catalogs; fallback works |

---

## Cross-Library Coordination

| Feature | waporbox | Rwapor | Sync Point |
|---------|----------|--------|------------|
| Area weighting | ✓ Done | Phase 1.1 | Verify identical class means on same grid |
| Per-profile ETc | Phase 1.3 | ✓ Done | Port R logic to Python |
| Seasonal planner | Phase 1.2 | ✓ Done | Port R logic to Python |
| Vector→Season rasters | Phase 1.4 | ✓ Done | Port R logic to Python |
| Monthly indicators | Phase 1.6 | ✓ Done | Port R logic to Python |
| Tiled engine | ✓ Done | Phase 1.4 | Verify identical results on test grid |
| Anomaly/Trend | ✓ Done | Phase 3.4 | Port Python logic to R |
| COG write | ✓ Done | Phase 2.2 | Verify interop |
| Viz helpers | ✓ Done | Phase 3.3 | Match palettes/labels |

**Sync Protocol**: After each port, run cross-validation notebook/script comparing outputs on identical inputs.

---

## Sign-Off

- [ ] Plan reviewed by FAO team
- [ ] Phase 1 scope locked
- [ ] Resources allocated (developer days)
- [ ] Target date for 1.0.0: **2026-11-01**