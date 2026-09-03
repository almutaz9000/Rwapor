# Rwapor Improvement Plan

**Version**: 0.9.9 → Target 1.0.0  
**Date**: 2026-08-27  
**Status**: Planning Phase  

---

## Executive Summary

Rwapor is a mature, stable R package (lifecycle badge: stable) with a comprehensive Shiny dashboard, DuckDB monitoring, and operational seasonal workflows. This plan focuses on hardening the analysis engine, extracting reusable components, and adopting scientific correctness improvements from waporbox.

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
**Files**: `R/analysis_engine.R`, `R/analysis_indicators.R`

**Problem**: Adding a new indicator requires editing the monolithic `wapor_run_seasonal_analysis` engine. waporbox uses `INDICATOR_STEPS` registry — one function per indicator, auto-ordered by dependency.

**Tasks**:
- [ ] Define `INDICATOR_STEPS` list: `list(agg_aeti = step_agg_aeti, etc = step_etc, ...)`
- [ ] Each step: `function(ctx) { if (!want) return(); ctx$res$etc <- ... }`
- [ ] Shared context `ctx` holds inputs, weights, intermediates, crop_params, want_set
- [ ] Engine loops `for (step in INDICATOR_STEPS) step(ctx)`
- [ ] New indicator = one step function + append to registry

**Verification**:
```r
# Add dummy indicator without touching engine
INDICATOR_STEPS$dummy <- function(ctx) {
  if (!"dummy" %in% ctx$want) return()
  ctx$res$rasters$dummy <- ctx$inputs$aeti[[1]] * 0 + 42
}
results <- wapor_run_seasonal_analysis(..., indicators = c("agg_aeti", "dummy"))
expect_true("dummy" %in% names(results$rasters))
```

---

### 1.4 Tiled / Windowed Global Engine (Port from waporbox)
**Priority**: HIGH  
**Effort**: 8-10 days  
**Files**: `R/analysis_tiled.R` (new), `R/analysis_engine.R`

**Problem**: Rwapor materializes full `(time, y, x)` SpatRasters. At L1 global (~5.6B pixels/layer) this is impossible. waporbox's `run_seasonal_analysis_tiled` streams tile-by-tile with `WarpedVRT`.

**Tasks**:
- [ ] `run_seasonal_analysis_tiled(period, reference_year, reference, crop_params, output_dir, ..., tile_size = 1024)`
- [ ] Use `terra::rast` with `vrt = TRUE` for lazy reprojection (equivalent to `WarpedVRT`)
- [ ] Pass 1: stream season-timing rasters → global per-class median season length (histogram method)
- [ ] Pass 2: for each tile window:
  - Read window from each aligned VRT
  - Run indicator math (pure R from 1.2) on tile arrays
  - Write tile block to output GeoTIFFs (`terra::writeRaster` with `window=`)
  - Accumulate class sums/weights online
- [ ] Progress callback per tile
- [ ] COG output option (`gdal:co:COMPRESS=LZW`, `gdal:co:COPY_SRC_OVERVIEWS=YES`)

**Verification**:
```r
# Benchmark: 2k x 2k grid, tile_size 512 vs 1024 vs full
# Peak memory should be ~tile_size^2 * n_layers * 4 bytes, not grid^2
```

---

### 1.5 Explicit Alignment Reference (Mask vs AETI vs Custom)
**Priority**: HIGH  
**Effort**: 2 days  
**Files**: `R/analysis.R`, `R/analysis_engine.R`

**Problem**: Dashboard silently warps everything to AETI grid. waporbox lets caller choose `reference = "crop_mask"` (upsample WaPOR) or `reference = "aeti"` (downsample mask).

**Tasks**:
- [ ] Add `reference_layer = c("aeti", "crop_mask", "ret", "pcp", "npp", "template")` parameter
- [ ] Add `resampling_method` per layer: `c(aeti = "bilinear", crop_mask = "near", ...)`
- [ ] Default: `reference_layer = "aeti"` (current behavior), but documented
- [ ] Overlap validation error as clear as waporbox's extent message

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

### 2.2 COG Write Support
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/wapor_map.R`, `R/analysis_engine.R`

**Problem**: Only standard GeoTIFF. COG enables cloud/HTTP range reads.

**Tasks**:
- [ ] `write_raster_cog(r, path)` using `gdalUtilities::gdal_translate(of = "COG")` or `terra::writeRaster(gdal = c("COMPRESS=LZW", "COPY_SRC_OVERVIEWS=YES"))`
- [ ] Add `cog = FALSE` parameter to `wapor_map`, `wapor_run_seasonal_analysis`
- [ ] Fallback to tiled GeoTIFF if GDAL < 3.1

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

### 3.1 Extra Crop Defaults (Port from waporbox)
**Priority**: HIGH  
**Effort**: 1 day  
**Files**: `R/crop_defaults.R`

**Tasks**:
- [ ] Add 9 missing FAO-56 crops: Maize, Rice, Cotton, Potato, Soybean, Sunflower, Barley, Alfalfa, Sugarcane
- [ ] Keep same structure: `crop_name, region, kc_ini, kc_mid, kc_end, l_ini_days, l_mid_days, l_late_days, max_height_m, HI, MC, fc, AOT, notes`

---

### 3.2 Build Crop Assignments + Validation (Already Strong ✓)
**Status**: COMPLETE — `wapor_build_crop_assignments`, `wapor_validate_crop_params` exist.

**Remaining**: Ensure validation checks HI/MC in [0,1], Kc >= 0, stage lengths > 0.

---

### 3.3 Publication Map Helpers (Port from waporbox viz)
**Priority**: MEDIUM  
**Effort**: 3 days  
**Files**: `R/viz.R` (new)

**Tasks**:
- [ ] `wapor_plot_map(array, indicator, title, save, dpi = 300)` with:
  - Colorblind palettes per indicator (RdYlGn for adequacy, viridis for CWP, etc.)
  - Scale bar (km), north arrow
  - 300 dpi output
- [ ] `wapor_plot_comparison(arrays, titles, indicator, suptitle, save)`
- [ ] `wapor_plot_timeseries(df, value, group, save)`
- [ ] `wapor_plot_kc_curve(kc_daily, save)`
- [ ] `wapor_plot_anomaly(zscore_array, save)`

---

### 3.4 Anomaly & Trend Module (Port from waporbox)
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/anomaly.R` (new)

**Tasks**:
- [ ] `zscore_anomaly(stack)` — per-pixel temporal z-scores
- [ ] `spatial_hotspots(zscore_layer, low = -1.96, high = 1.96)`
- [ ] `anomaly_vs_baseline(current, baseline_mean, baseline_std)`
- [ ] `linear_trend(stack, times = NULL)` — NaN-aware OLS, returns slope, intercept, r²
- [ ] Operate on SpatRaster (terra) but math in pure R from 1.2

---

### 3.5 Preflight Validation Module
**Priority**: MEDIUM  
**Effort**: 2 days  
**Files**: `R/preflight.R` (new)

**Tasks**:
- [ ] `wapor_preflight_check(config, data_source, folder)` — variable exists, period valid, L3 intersects, disk space
- [ ] `wapor_validate_data_coverage(folder, variables, period, l3_code)`
- [ ] Return structured report (pass/fail/warnings)

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

### 5.1 Expand Unit Tests (Pure Math Layer)
**Priority**: HIGH  
**Effort**: 3 days  
**Files**: `tests/testthat/test-indicators-math.R` (new)

**Tasks**:
- [ ] Test every function in `indicators_math.R` on small matrices
- [ ] Edge cases: NA propagation, zero division, single pixel
- [ ] Compare against waporbox Python reference values

---

### 5.2 Integration Test: Full Seasonal Pipeline
**Priority**: HIGH  
**Effort**: 2 days  
**Files**: `tests/testthat/test-analysis-engine.R`

**Tasks**:
- [ ] Synthetic 100x100 grid, 2 classes, known Kc → verify ETc, adequacy, CWP
- [ ] Multi-season batch mode
- [ ] Local vs API parity

---

### 5.3 CI: R-CMD-check + Coverage (Already Exists ✓)
**Status**: COMPLETE — `.github/workflows/R-CMD-check.yaml`, `test-coverage.yaml`.

**Remaining**: Add `lintr` check, `styler` check.

---

## Phase 6: Documentation

### 6.1 Vignettes Matching waporbox Notebooks
**Priority**: MEDIUM  
**Effort**: 3 days  
**Files**: `vignettes/` (new)

**Tasks**:
- [ ] `vignette("admin-timeseries")` — `wapor_ts` for bbox/vector
- [ ] `vignette("crop-mask-seasonal")` — `wapor_run_seasonal_analysis` with mask
- [ ] `vignette("mixed-resolution")` — `reference_layer`, `resampling_method`
- [ ] `vignette("season-comparison")` — multi-season batch
- [ ] `vignette("global-tiled")` — `wapor_run_seasonal_analysis_tiled` (when ready)

---

### 6.2 First-Time User Install Guide (Match waporbox)
**Priority**: MEDIUM  
**Effort**: 1 day  
**Files**: `README.md`

**Tasks**:
- [ ] Explicit system deps: `libgdal-dev`, `libproj-dev`, `libudunits2-dev` (Linux)
- [ ] `remotes::install_github("r-spatial/terra")` for latest GDAL
- [ ] Verify: `library(Rwapor); wapor_variable_metadata("L1-AETI-D")`

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