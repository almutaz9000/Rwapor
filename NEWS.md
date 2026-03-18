# Rwapor 0.1.0

## Initial Release

This is the first release of Rwapor, an R package for downloading and processing
WaPOR and AgERA5 data from the FAO GIS Manager API.

### Core Download and Extraction Functions

* `wapor_map()`: Download and save raster maps for specified regions and time periods. Supports optional batching and parallel chunk processing.
* `wapor_ts()`: Extract time series with zonal statistics for polygons. Supports parallel batching and custom polygon identifiers.
* `run_wapor()`: Launch an interactive Shiny application for data selection and visualization.
* `wapor_generate_urls()`: Generate download URLs for WaPOR/AgERA5 resources (memoized).
* `parse_region()`: Parse region inputs (bounding box, vector file, or L3 code).
* `get_date_info()`: Extract date information from WaPOR URL filenames.
* `df_unit_convertor()`: Convert DataFrame values between temporal units.
* `raster_unit_convertor()`: Convert raster values between temporal units.
* `get_variable_metadata()`: Retrieve variable metadata with memoization.
* `plan_wapor_time_slices()`: Plan optimal raster time slices for seasonal aggregation.
* `get_available_temporal_codes()`: Retrieve available temporal resolution codes for a variable.

### Agricultural Analysis Functions

#### Crop Mask and Season Raster Utilities

* `rwapor_load_crop_mask()`: Load a crop mask raster from disk.
* `rwapor_load_season_raster()`: Load a season start/end raster from disk.
* `rwapor_harmonize_to_template()`: Reproject and resample a raster to match a template grid.
* `rwapor_harmonize_crop_mask()`: Harmonize a crop mask to AETI raster geometry.
* `rwapor_extract_crop_classes()`: Extract unique crop classes with pixel counts and areas.
* `rwapor_build_crop_assignment_table()`: Build a crop parameter assignment table per class.
* `rwapor_check_local_files()`: Check which WaPOR raster files are available locally.

#### Season Mask and Weights

* `rwapor_continuous_julian()`: Convert a date to a continuous Julian day index relative to a reference year.
* `rwapor_build_season_mask_daily()`: Build a daily binary season mask raster.
* `rwapor_build_season_weights_dekad()`: Build dekadal fractional season weights.
* `rwapor_compute_total_days_raster()`: Compute total season duration per pixel.
* `rwapor_compute_ldev_raster()`: Derive development stage length per pixel.

#### Kc Curve Generation

* `rwapor_build_daily_kc()`: Build a daily FAO-56 four-stage Kc curve.
* `rwapor_build_kc_by_class()`: Build Kc curves for each crop class.
* `rwapor_aggregate_kc_dekad()`: Aggregate daily Kc values to dekadal means.

#### Water Productivity Indicators

* `rwapor_apply_masked_sum()`: Apply dekadal season weights to a raster time series.
* `rwapor_calc_seasonal_aeti_masked()`: Compute season-masked AETI, optionally by crop class.
* `rwapor_calc_seasonal_ret_masked()`: Compute season-masked RET, optionally by crop class.
* `rwapor_calc_etc_dekad()`: Compute dekadal crop evapotranspiration (ETc = RET * Kc).
* `rwapor_calc_adequacy_etc()`: Compute ETc-based adequacy (AETI / ETc).
* `rwapor_calc_class_p95_aeti()`: Compute 95th percentile of AETI within each crop class.
* `rwapor_calc_adequacy_p95()`: Compute P95-based adequacy.
* `rwapor_aggregate_precip_monthly()`: Aggregate precipitation to monthly totals.
* `rwapor_calc_peff_usda_monthly()`: Compute monthly effective precipitation (FAO USDA method).
* `rwapor_calc_peff_seasonal()`: Sum monthly effective precipitation over a season.
* `rwapor_calc_cwp()`: Compute Crop Water Productivity (Yield / AETI).
* `rwapor_calc_bwp()`: Compute Biomass Water Productivity (Biomass / AETI).
* `rwapor_convert_npp_to_tbp()`: Convert NPP (gC/m2) to Total Biomass Production (kgDM/ha).
* `rwapor_calc_yield_npp()`: Calculate crop yield from NPP using the FAO WaPOR biomass model.
* `rwapor_prepare_analysis_ts()`: Fetch AETI, RET, and precipitation time series.
* `rwapor_merge_analysis_timeseries()`: Merge AETI, RET, and precipitation time series.

### GDAL Configuration

* `wapor_configure_gdal()`: Configure GDAL environment variables for efficient HTTP streaming.
* `wapor_gdal_settings()`: View current GDAL settings applied by the package.
* `wapor_fix_proj()`: Automatically resolve `PROJ_LIB` environment variable conflicts on Windows.

### Crop Defaults

* `FAO_CROP_DEFAULTS`: Built-in FAO Irrigation and Drainage Paper 56 crop parameters.
* `rwapor_list_crops()`: List available crop profiles.
* `rwapor_get_crop_defaults()`: Get parameters for a named crop.
* `rwapor_validate_crop_defaults()`: Validate a crop defaults data.frame.

### Data

* `WAPOR3_VARS`: Metadata for all WaPOR v3 variables (L1, L2, L3).
* `AGERA5_VARS`: Metadata for all AgERA5 climate variables.
* `L3_REGIONS`: Metadata for all WaPOR Level 3 region codes.

### Data Support

* WaPOR Level 1 (L1) variables: AETI, E, I, NPP, PCP, GBWP, NBWP, RET, RSM, T, TBP
* WaPOR Level 2 (L2) variables: AETI, E, I, NPP, T, GBWP, NBWP, RSM, TBP
* WaPOR Level 3 (L3) regional data: AETI, E, I, NPP, T, RSM, TBP, GBWP
* AgERA5 climate variables: ET0, TMIN, TMAX, SRF, WS, PF, RH06-RH18

### Temporal Resolutions

* Daily (E)
* Dekadal (D) - 10-day periods
* Monthly (M)
* Annual (A)

### Infrastructure

* Parallel processing via `future.apply` package
* API response caching via `memoise` package
* Unit conversion between day/dekad/month/year
* Persistent L3 region extent cache across sessions
