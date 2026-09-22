# Changelog

## Rwapor 1.0.0 (development)

### Core geospatial processing

- Tiled seasonal engine now uses deterministic square tiles, a versioned
  `run_manifest.json`, per-tile GeoTIFF/COG assets, checksums, and VRT
  assembly. Completed tiles can be resumed; mismatched manifests are
  refused.
- Source rasters are windowed onto each tile before analysis so the
  engine does not load the full AOI stack. Tile-local block reducers
  compute AETI, RET, PCP, Peff, ETc, adequacy, biomass, and related
  indicators one layer at a time. Remote-COG fixtures and a tile-vs-AOI
  memory benchmark cover `/vsicurl/` windowing.
- Incomplete seasonal coverage now fails unless `partial = TRUE`.
- `mosaic_all` supports multiple variables and periods, and
  [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
  extracts every intersecting L3 source. Shiny no longer preselects the
  first of several L3 codes and offers mosaic-all.
- Closing a dashboard browser tab no longer calls `stopApp()`.
- [`wapor_write_cog()`](https://almutaz9000.github.io/Rwapor/reference/wapor_write_cog.md)
  publishes atomically through a `.partial.tif` file and applies LZW
  compression, datatype predictors, overviews, and a BigTIFF policy.

### Monitoring database (DuckDB)

- [`wapor_save_raster_blobs()`](https://almutaz9000.github.io/Rwapor/reference/wapor_save_raster_blobs.md)
  rewritten: pending dates are resolved from URL metadata before any
  network open (avoids redundant vsicurl calls for already-saved dates),
  and remaining layers for one variable are opened as a single batched
  `/vsicurl/` multi-band stack instead of one dataset handle per layer.
- Each saved raster now writes both the existing in-memory compressed
  GeoTIFF blob (backward-compatible read path) and a file-backed COG
  under a new sibling `<db>_raster_store/` directory, recorded in
  `monitoring_rasters.raster_path` together with `gdal_version`,
  `terra_version`, and `band_count` provenance columns.
- `monitoring_metadata` now carries a `schema_version` with an automatic
  migration path (`.wapor_monitoring_migrate()`), and a
  `raster_grid_registry` table rejects mixed-resolution writes for the
  same variable.
- `farm_timeseries` gained a `season_id` column (part of the primary
  key) and now upserts via `INSERT OR REPLACE` instead of failing on
  overlapping reruns.

### Shiny dashboard

- The Download tab sidebar is now a 5-step numbered accordion wizard
  (Project, Variables, Period, L3 Region, Run) instead of a flat
  two-panel layout.
- New **Dual Compare** tab (`mod_dual_map.R`): two independent Leaflet
  maps kept in pan/zoom sync via
  [`leaflet.extras2::addLeafletsync()`](https://trafficonese.github.io/leaflet.extras2/reference/addLeafletsync.html),
  for side-by-side raster comparison distinct from the existing
  single-map overlay “Dual Compare” mode inside the Visualisation tab.
- `app.R` now guards all Shiny/dashboard package dependencies with a
  clear install message instead of a bare
  [`library()`](https://rdrr.io/r/base/library.html) failure, and
  `.onLoad` configures GDAL unconditionally rather than only when an
  environment variable is set.
- Dashboard: grouped variable choices, save/load analysis configuration
  to JSON, and user-adjustable stress thresholds for the monitoring
  module.

### Testing & documentation

- All network-dependent test files are guarded with
  `skip_if_wapor_offline()` so a machine without internet access gets a
  clean skip instead of a false failure.
- Fixed a stale live-API test (`wapor_map` no longer accepts multiple
  variables in seasonal mode by design; the test now asserts the
  documented error and exercises the multi-variable workflow via one
  [`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md)
  call per variable).
- Removed a redundant intermediate warning in
  `download_seasonal_rasters()` that duplicated information already in
  the final aggregated “INCOMPLETE” warning/error.
- Regenerated stale `man/` pages that had drifted from code (`wapor_ts`,
  `wapor_map`, `wapor_init_monitoring_db`, `wapor_save_raster_blobs`,
  `wapor_suggest_tile_size`).
- README installation section restructured to the install -\> verify -\>
  quick start convention, with a fixed CI badge branch reference and
  citation version bump to 1.0.0.

------------------------------------------------------------------------

## Rwapor 0.9.9

### Download Robustness

- Replaced the disk URL-cache key (`.wapor_url_hash()`) with a proper
  SHA-256 digest
  ([`digest::digest()`](https://eddelbuettel.github.io/digest/man/digest.html)).
  The previous byte-sum-based checksum could collide for different
  queries whose request strings were character permutations of each
  other, silently serving cached URLs for the wrong date range within
  the 24h cache TTL.
- Added retry-with-backoff to the seasonal raster loader
  (`download_seasonal_rasters()`), matching the retry behavior already
  used by the non-seasonal
  [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
  path, so a single transient `/vsicurl/` failure no longer drops an
  entire resolution group.
- `download_seasonal_rasters()` now reconciles the download plan against
  what was actually loaded: any code group with no URLs, any plan row
  that fails to match a URL, or any raster stack that fails to load
  after retries is tracked and surfaced as a single clear warning (with
  the exact missing period IDs and day-coverage shortfall) instead of
  being silently dropped. The missing periods are also exposed via
  `attr(result, "missing_periods")` on `wapor_ts(seasonal = TRUE)`
  output.
- API request retries (`collect_responses()`, metadata pagination) now
  use exponential backoff, honor a numeric `Retry-After` response
  header, and treat HTTP 429/5xx as transient, instead of a flat
  2-second delay.

### Fixes and Documentation

- Fixed broken code-fence in README Example 2 that caused Example 3 to
  render incorrectly on GitHub.
- Corrected README Example 3 to use `wapor_analysis_pipeline()` — the
  function
  [`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
  referenced previously does not exist.
- Removed two dead internal links in README
  (`.github/L3-AUTO-DETECTION.md` and `docs/REPOSITORY_STRUCTURE.md`).
- Removed stale `importFrom` directives for
  [`stats::coef`](https://rdrr.io/r/stats/coef.html),
  [`stats::lm`](https://rdrr.io/r/stats/lm.html),
  [`utils::capture.output`](https://rdrr.io/r/utils/capture.output.html),
  and
  [`utils::getFromNamespace`](https://rdrr.io/r/utils/getFromNamespace.html)
  that produced `R CMD CHECK` notes.
- Fixed `wapor_analysis_pipeline()` to respect `config$ref_year` instead
  of silently deriving it from the start date.
- Added [`on.exit()`](https://rdrr.io/r/base/on.exit.html) guard for
  temp-file cleanup in
  [`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md)
  to prevent orphaned files when an error occurs mid-processing.
- Fixed duplicate `ID` / identifier column in
  [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
  output.
- Added [`.Deprecated()`](https://rdrr.io/r/base/Deprecated.html) call
  for the `download_locally` parameter in
  [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md).
- Resolved `@export` + `@keywords internal` contradiction on internal
  helpers.

------------------------------------------------------------------------

## Rwapor 0.9.8

### Download and Unit Conversion

- Hardened unit-conversion behavior for
  [`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md)
  and
  [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
  to correctly handle dekadal, monthly, and annual products without
  double-scaling.

------------------------------------------------------------------------

## Rwapor 0.9.7

### Major Synchronization and Optimization

This release synchronizes the local development features with the latest
remote optimizations. It includes optimized zonal statistics, enhanced
monitoring module, and improved unit conversion logic.

#### Breaking Changes

- All public functions now use the `wapor_*` prefix consistently. The
  old `rwapor_*` aliases (e.g. `rwapor_harmonize_crop_mask`,
  `rwapor_build_daily_kc`) have been removed. See the migration guide
  below.

#### Function Renames (from pre-1.0 development versions)

| Old name | New name |
|----|----|
| `rwapor_harmonize_crop_mask()` | [`wapor_harmonize_raster()`](https://almutaz9000.github.io/Rwapor/reference/wapor_harmonize_raster.md) |
| `rwapor_harmonize_to_template()` | [`wapor_harmonize_raster()`](https://almutaz9000.github.io/Rwapor/reference/wapor_harmonize_raster.md) |
| `rwapor_build_season_weights_dekad()` | [`wapor_build_season_weights()`](https://almutaz9000.github.io/Rwapor/reference/wapor_build_season_weights.md) |
| `rwapor_calc_seasonal_aeti_masked()` | [`wapor_calc_seasonal_aeti()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_seasonal_aeti.md) |
| `rwapor_calc_seasonal_ret_masked()` | [`wapor_calc_seasonal_ret()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_seasonal_ret.md) |
| `rwapor_get_crop_defaults()` | [`wapor_crop_defaults()`](https://almutaz9000.github.io/Rwapor/reference/wapor_crop_defaults.md) |
| `rwapor_build_daily_kc()` | [`wapor_build_kc()`](https://almutaz9000.github.io/Rwapor/reference/wapor_build_kc.md) |
| `rwapor_calc_seasonal_etc_incremental()` | [`wapor_calc_seasonal_etc()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_seasonal_etc.md) |
| `rwapor_apply_masked_sum()` | [`wapor_masked_sum()`](https://almutaz9000.github.io/Rwapor/reference/wapor_masked_sum.md) |

#### Repository Cleanup

- Removed development-only test scripts from `tests/` root (ad hoc
  benchmarks, integration probes, fix verifications). Formal test suite
  lives in `tests/testthat/`.
- Removed `archived_reports/` development notes.
- Removed `memories/` agent session files.
- Removed root-level debug scripts (`check_db_summary.R`) and stray data
  files (`Pivots_savola2.geojson`).

#### Documentation

- Updated README with correct function names and a complete step-by-step
  seasonal analysis tutorial.
- Updated installation instructions (removed duplicate section).
- Added tidyverse lifecycle badge update from `experimental` to
  `stable`.

------------------------------------------------------------------------

## Rwapor 0.9.5

### Changes

#### Shiny Dashboard

- **REMOVED**: Split-screen slider (swipe) display mode from Dual Raster
  Comparison. The “Dual Raster Display” panel now offers “Overlay” and
  “Intersection Only” modes.
- **FIXED**: Debug [`cat()`](https://rdrr.io/r/base/cat.html) statements
  removed from Visualization module server-side renderUI outputs.
- **FIXED**: Added missing `viridisLite` and `RColorBrewer` packages to
  `Suggests` in DESCRIPTION.
- **FIXED**: Removed stale `raster_left`/`raster_right` layer-group
  clearing calls that were only used by the removed swipe mode.

------------------------------------------------------------------------

## Rwapor 0.9.3

### Major Enhancements

#### Shiny Dashboard Improvements

- **NEW**: L3 Region Auto-Detection System
  - Automatically detects which L3 regions overlap with user-defined AOI
  - Filters L3 region dropdown to show only relevant regions
  - Auto-selects when exactly one region overlaps
  - Provides real-time feedback messages about detection status
  - Supports vector files, raster files, and drawn geometries as AOI
  - Leverages
    [`wapor_guess_region()`](https://almutaz9000.github.io/Rwapor/reference/wapor_guess_region.md)
    for spatial intersection analysis
- **REORGANIZED**: Download workflow UI
  - AOI selection moved immediately after Project Folder
  - More intuitive linear workflow: Folder → AOI → Variables → Time
    Period
  - Better guidance for users selecting L3 variables
- **NEW**: Comprehensive Shiny dashboard documentation
  - New vignette:
    [`vignette("shiny-dashboard")`](https://almutaz9000.github.io/Rwapor/articles/shiny-dashboard.md)
  - Detailed L3 auto-detection usage guide
  - Troubleshooting tips and best practices

#### Analysis Pipeline Refactoring

- **NEW**: `wapor_analysis_pipeline()` - Modularized seasonal crop water
  productivity analysis pipeline
  - Orchestrates data loading, harmonization, seasonal aggregation, and
    indicator computation
  - Can be run from Shiny or standalone scripts
  - Supports both API streaming and local file modes
  - Enhanced error logging with detailed diagnostics
  - Progress callback support for integration with UI
  - Automatic output saving (rasters + CSV summaries)

#### Validation Framework

- **NEW**:
  [`wapor_validate_analysis_config()`](https://almutaz9000.github.io/Rwapor/reference/wapor_validate_analysis_config.md) -
  Pre-flight configuration validation
- **NEW**:
  [`wapor_validate_crop_params()`](https://almutaz9000.github.io/Rwapor/reference/wapor_validate_crop_params.md) -
  Crop parameter validation with range checks
- **NEW**:
  [`wapor_validate_data_coverage()`](https://almutaz9000.github.io/Rwapor/reference/wapor_validate_data_coverage.md) -
  Local data availability checking
- **NEW**:
  [`wapor_preflight_check()`](https://almutaz9000.github.io/Rwapor/reference/wapor_preflight_check.md) -
  Comprehensive pre-analysis diagnostics
  - Validates configuration, data coverage, raster compatibility
  - Provides actionable recommendations
  - Checks spatial overlap of input rasters
  - Validates crop parameter ranges (Kc, HI, MC, fc, AOT)

#### Spatial Anomaly Detection

- **NEW**: `wapor_detect_aeti_anomalies()` - Identify water stress
  anomalies
  - Flags pixels with AETI significantly below class median
  - Configurable threshold (default 50% of median)
  - Per-class anomaly statistics
  - Generates anomaly maps for visualization
- **NEW**: `wapor_detect_compound_anomalies()` - Multi-indicator anomaly
  detection
  - Combines AETI, adequacy, and yield indicators
  - Identifies areas with compound stress
- **NEW**: `wapor_detect_zscore_anomalies()` - Statistical anomaly
  detection using z-scores
- **NEW**: `wapor_detect_spatial_hotspots()` - Spatial cluster analysis
  for stress areas

#### Multi-Season Comparison

- **NEW**: `wapor_compare_seasons()` - Compare multiple season analysis
  results
  - Side-by-side comparison of indicators across seasons
  - Supports both overall and per-class comparisons
  - Automatic change percentage calculation for 2-season comparisons
- **NEW**: `wapor_trend_analysis()` - Linear trend analysis for 3+
  seasons
  - Computes slopes, R-squared, and p-values
  - Supports both overall and per-class trends
- **NEW**: `wapor_export_comparison_report()` - Export formatted
  comparison reports

#### Performance Improvements

- Parallel path resolution for multiple variables
- Enhanced harmonization caching with intelligent invalidation
- Memory-efficient incremental aggregation option
- Optimized ETc computation with unique profile deduplication

#### User Experience Enhancements

- Detailed progress feedback during analysis
- Enhanced error logging with stack traces and configuration snapshots
- Improved validation messages with specific recommendations
- Better handling of missing data with auto-download suggestions

#### Shiny Dashboard Improvements

- Modularized analysis module for easier maintenance
- Missing data detection with one-click download
- Pre-run validation with collapsible diagnostic panel
- Enhanced error recovery with log file generation
- Improved progress notifications with granular updates

### Bug Fixes

- Fixed raster harmonization cache invalidation on file re-upload
- Improved handling of cross-year seasons in Julian day calculations
- Better error messages for failed API requests
- Fixed memory leaks in long-running analysis sessions

### Documentation

- Added comprehensive examples for new validation functions
- Updated analysis workflow documentation
- Added anomaly detection vignette examples
- Improved function documentation with use case examples

## Rwapor 0.9.2

### Previous Release

See previous release notes for 0.9.2 and earlier versions.

------------------------------------------------------------------------

## Rwapor 0.1.0

### Initial Release

This is the first release of Rwapor, an R package for downloading and
processing WaPOR and AgERA5 data from the FAO GIS Manager API. \### New
Features

- [`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md):
  Download and save raster maps for specified regions and time periods.
  Now supports optional batching and parallel chunk processing.
- [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md):
  Extract time series with zonal statistics for polygons. Now supports
  parallel batching and custom polygon identifiers.
- [`run_wapor()`](https://almutaz9000.github.io/Rwapor/reference/run_wapor.md):
  Launch an interactive Shiny application for data selection and
  visualization.
- [`wapor_fix_proj()`](https://almutaz9000.github.io/Rwapor/reference/wapor_fix_proj.md):
  Automatically resolve `PROJ_LIB` environment variable conflicts on
  Windows.
- [`wapor_generate_urls()`](https://almutaz9000.github.io/Rwapor/reference/wapor_generate_urls.md):
  Generate download URLs for WaPOR/AgERA5 resources (memoized).
- `parse_region()`: Parse region inputs (bounding box, vector file, or
  L3 code).
- `get_date_info()`: Extract date information from WaPOR URL filenames.
- `df_unit_convertor()`: Convert DataFrame values between temporal
  units.
- `raster_unit_convertor()`: Convert raster values between temporal
  units.
- `get_variable_metadata()`: Retrieve variable metadata with
  memoization.

#### Data Support

- WaPOR Level 1 (L1) variables: AETI, E, I, NPP, PCP, GBWP, NBWP
- WaPOR Level 2 (L2) variables: AETI, E, I, NPP, T, GBWP, NBWP
- WaPOR Level 3 (L3) regional data support
- AgERA5 climate variables: ET0, TMIN, TMAX, SRF, WS, PF

#### Temporal Resolutions

- Daily (E)
- Dekadal (D) - 10-day periods
- Monthly (M)
- Annual (A)

#### Infrastructure

- Parallel download support via `furrr` package
- Progress reporting via `progressr` package
- API response caching via `memoise` package
- Unit conversion between day/dekad/month/year
