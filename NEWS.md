# Rwapor 0.9.3

## Major Enhancements

### Shiny Dashboard Improvements
* **NEW**: L3 Region Auto-Detection System
  - Automatically detects which L3 regions overlap with user-defined AOI
  - Filters L3 region dropdown to show only relevant regions
  - Auto-selects when exactly one region overlaps
  - Provides real-time feedback messages about detection status
  - Supports vector files, raster files, and drawn geometries as AOI
  - Leverages `wapor_guess_region()` for spatial intersection analysis
* **REORGANIZED**: Download workflow UI
  - AOI selection moved immediately after Project Folder
  - More intuitive linear workflow: Folder → AOI → Variables → Time Period
  - Better guidance for users selecting L3 variables
* **NEW**: Comprehensive Shiny dashboard documentation
  - New vignette: `vignette("shiny-dashboard")`
  - Detailed L3 auto-detection usage guide
  - Troubleshooting tips and best practices

### Analysis Pipeline Refactoring
* **NEW**: `wapor_analysis_pipeline()` - Modularized seasonal crop water productivity analysis pipeline
  - Orchestrates data loading, harmonization, seasonal aggregation, and indicator computation
  - Can be run from Shiny or standalone scripts
  - Supports both API streaming and local file modes
  - Enhanced error logging with detailed diagnostics
  - Progress callback support for integration with UI
  - Automatic output saving (rasters + CSV summaries)

### Validation Framework
* **NEW**: `wapor_validate_analysis_config()` - Pre-flight configuration validation
* **NEW**: `wapor_validate_crop_params()` - Crop parameter validation with range checks
* **NEW**: `wapor_validate_data_coverage()` - Local data availability checking
* **NEW**: `wapor_preflight_check()` - Comprehensive pre-analysis diagnostics
  - Validates configuration, data coverage, raster compatibility
  - Provides actionable recommendations
  - Checks spatial overlap of input rasters
  - Validates crop parameter ranges (Kc, HI, MC, fc, AOT)

### Spatial Anomaly Detection
* **NEW**: `wapor_detect_aeti_anomalies()` - Identify water stress anomalies
  - Flags pixels with AETI significantly below class median
  - Configurable threshold (default 50% of median)
  - Per-class anomaly statistics
  - Generates anomaly maps for visualization
* **NEW**: `wapor_detect_compound_anomalies()` - Multi-indicator anomaly detection
  - Combines AETI, adequacy, and yield indicators
  - Identifies areas with compound stress
* **NEW**: `wapor_detect_zscore_anomalies()` - Statistical anomaly detection using z-scores
* **NEW**: `wapor_detect_spatial_hotspots()` - Spatial cluster analysis for stress areas

### Multi-Season Comparison
* **NEW**: `wapor_compare_seasons()` - Compare multiple season analysis results
  - Side-by-side comparison of indicators across seasons
  - Supports both overall and per-class comparisons
  - Automatic change percentage calculation for 2-season comparisons
* **NEW**: `wapor_trend_analysis()` - Linear trend analysis for 3+ seasons
  - Computes slopes, R-squared, and p-values
  - Supports both overall and per-class trends
* **NEW**: `wapor_export_comparison_report()` - Export formatted comparison reports

### Performance Improvements
* Parallel path resolution for multiple variables
* Enhanced harmonization caching with intelligent invalidation
* Memory-efficient incremental aggregation option
* Optimized ETc computation with unique profile deduplication

### User Experience Enhancements
* Detailed progress feedback during analysis
* Enhanced error logging with stack traces and configuration snapshots
* Improved validation messages with specific recommendations
* Better handling of missing data with auto-download suggestions

### Shiny Dashboard Improvements
* Modularized analysis module for easier maintenance
* Missing data detection with one-click download
* Pre-run validation with collapsible diagnostic panel
* Enhanced error recovery with log file generation
* Improved progress notifications with granular updates

## Bug Fixes
* Fixed raster harmonization cache invalidation on file re-upload
* Improved handling of cross-year seasons in Julian day calculations
* Better error messages for failed API requests
* Fixed memory leaks in long-running analysis sessions

## Documentation
* Added comprehensive examples for new validation functions
* Updated analysis workflow documentation
* Added anomaly detection vignette examples
* Improved function documentation with use case examples

# Rwapor 0.9.2

## Previous Release

See previous release notes for 0.9.2 and earlier versions.

---

# Rwapor 0.1.0

## Initial Release

This is the first release of Rwapor, an R package for downloading and processing
WaPOR and AgERA5 data from the FAO GIS Manager API.
### New Features

* `wapor_map()`: Download and save raster maps for specified regions and time periods. Now supports optional batching and parallel chunk processing.
* `wapor_ts()`: Extract time series with zonal statistics for polygons. Now supports parallel batching and custom polygon identifiers.
* `run_wapor()`: Launch an interactive Shiny application for data selection and visualization.
* `wapor_fix_proj()`: Automatically resolve `PROJ_LIB` environment variable conflicts on Windows.
* `wapor_generate_urls()`: Generate download URLs for WaPOR/AgERA5 resources (memoized).
* `parse_region()`: Parse region inputs (bounding box, vector file, or L3 code).
* `get_date_info()`: Extract date information from WaPOR URL filenames.
* `df_unit_convertor()`: Convert DataFrame values between temporal units.
* `raster_unit_convertor()`: Convert raster values between temporal units.
* `get_variable_metadata()`: Retrieve variable metadata with memoization.

### Data Support

* WaPOR Level 1 (L1) variables: AETI, E, I, NPP, PCP, GBWP, NBWP
* WaPOR Level 2 (L2) variables: AETI, E, I, NPP, T, GBWP, NBWP
* WaPOR Level 3 (L3) regional data support
* AgERA5 climate variables: ET0, TMIN, TMAX, SRF, WS, PF

### Temporal Resolutions

* Daily (E)
* Dekadal (D) - 10-day periods
* Monthly (M)
* Annual (A)

### Infrastructure

* Parallel download support via `furrr` package
* Progress reporting via `progressr` package
* API response caching via `memoise` package
* Unit conversion between day/dekad/month/year
