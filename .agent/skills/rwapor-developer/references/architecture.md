# Rwapor — Function-Level Architecture Map
_Last updated: 2026-03-26 — built from actual repo scan_

> Ground truth for which function lives in which file.
> Update whenever a function is added, renamed, moved, or removed.

---

## Repository Structure

```
Rwapor/
├── R/
│   ├── wapor_map.R
│   ├── wapor_ts.R
│   ├── plan_wapor_time_slices.R
│   ├── analysis.R
│   ├── analysis_indicators.R
│   ├── api_client.R
│   ├── metadata.R
│   ├── unit_convertor.R
│   ├── utils.R
│   ├── gdal_config.R
│   ├── crop_defaults.R
│   ├── seasonal_download.R
│   ├── interval_helpers.R
│   ├── run_dashboard.R
│   └── rwapor_favorites.R
├── inst/shiny/
│   ├── app.R
│   ├── mod_download.R
│   ├── mod_visualisation.R
│   ├── mod_analysis.R          ← ~2400 lines, largest module
│   ├── mod_aoi.R
│   └── utils_shiny.R
├── fao_crop_coefficients.csv   ← Kc values per crop
├── fao_growth_stages.csv       ← Stage lengths per crop
├── DESCRIPTION
├── NAMESPACE
└── NEWS.md
```

---

## R/wapor_map.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `wapor_map()` | Download & save raster maps for a region/period | `region`, `variable`, `period`, `folder`, `unit_conversion`, `seasonal`, `download_locally`, `parallel`, `batching`, `batch_size` | Writes GeoTIFF files; returns file paths |

**Notes:**
- Supports WaPOR L1/L2/L3 and AgERA5 variables
- `seasonal=TRUE` triggers `download_seasonal_rasters()` internally
- Parallel mode via `future.apply`

---

## R/wapor_ts.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `wapor_ts()` | Extract time series with zonal statistics for polygons/bbox | `region`, `variable`, `period`, `identifier`, `unit_conversion`, `seasonal`, `download_locally`, `parallel`, `batching`, `batch_size` | data.frame with date, value, [identifier] columns |

**Notes:**
- Uses `exactextractr` for pixel-weighted zonal statistics
- `identifier` names the polygon grouping column
- Supports same seasonal mode as `wapor_map()`

---

## R/plan_wapor_time_slices.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `plan_wapor_time_slices()` | Build optimal mixed-resolution download plan | `start_date`, `end_date`, `avail` (temporal codes), `inclusive` | data.frame: one row per raster slice, with `temporal_code`, `date`, `weight`, `multiplier` |
| `get_available_temporal_codes()` | List temporal codes available for a variable | `variable` | character vector e.g. `c("A","M","D")` |

**Notes:**
- Prefers coarser resolution (A > M > D > E) for fully-covered periods
- Minimises number of raster downloads while maintaining accuracy
- Does NOT download — downstream functions use the plan to fetch data

---

## R/analysis.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `rwapor_load_crop_mask()` | Load crop mask raster from file | `path` | SpatRaster |
| `rwapor_load_season_raster()` | Load season start/end raster from file | `path` | SpatRaster |
| `rwapor_harmonize_to_template()` | Reproject/resample raster to match template | `x`, `template`, `method` | SpatRaster |
| `rwapor_harmonize_crop_mask()` | Align crop mask to target raster grid | `crop_mask`, `target_raster` | SpatRaster |
| `rwapor_extract_crop_classes()` | Extract unique class values from crop mask | `crop_mask`, `exclude_nodata`, `min_pixels`, `nodata_values` | integer vector |
| `rwapor_build_crop_assignment_table()` | Map crop class values to crop defaults | `class_values`, `crop_defaults` | data.frame |
| `rwapor_continuous_julian()` | Convert date to continuous Julian day | `date`, `reference_year` | numeric |
| `rwapor_build_season_mask_daily()` | Build daily binary season mask raster | `dates`, `start_raster`, `end_raster` | SpatRaster (multi-layer) |
| `build_dekad_table()` | Build lookup table of dekadal periods | `start_date`, `end_date` | data.frame |
| `rwapor_build_season_weights_dekad()` | Compute dekadal season weights (0–1) | `start_date`, `end_date`, `start_raster`, `end_raster`, `variable` | SpatRaster |
| `rwapor_compute_total_days_raster()` | Total season days per pixel | `start_raster`, `end_raster` | SpatRaster |
| `rwapor_compute_ldev_raster()` | Compute Ldev (initial development length) | `total_days_raster`, `L_ini_days` | SpatRaster |
| `rwapor_build_daily_kc()` | Build daily Kc time series from FAO-56 parameters | `Kc_ini`, `Kc_mid`, `Kc_end`, `L_ini`, `L_dev`, `L_mid`, `L_late` | numeric vector |
| `rwapor_build_kc_by_class()` | Build Kc per crop class | `crop_assignment`, `total_days` | list of numeric vectors |
| `rwapor_aggregate_kc_dekad()` | Aggregate daily Kc to dekadal values | `kc_daily`, `dekad_table`, `season_start` | numeric vector |
| `rwapor_scan_local_variables()` | Scan folder for locally downloaded WaPOR files | `folder` | data.frame with variable, dates, paths |
| `rwapor_compare_geom()` | Check if two rasters share same geometry | `r1`, `r2` | logical |
| `rwapor_get_local_rasters()` | Get local raster paths for variable/date range | `folder`, `variable`, `start_date`, `end_date` | character vector of paths |
| `rwapor_check_local_files()` | Check which URLs already exist locally | `urls`, `var`, `folder` | list: present/missing |

---

## R/analysis_indicators.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `rwapor_apply_masked_sum()` | Weighted sum of raster stack (core aggregation engine) | `x`, `weights`, `layer_multipliers`, `incremental` | SpatRaster (1 layer) |
| `rwapor_calc_seasonal_aeti_masked()` | Seasonal AETI sum using dekadal weights | `aeti_dekad`, `season_weights`, `crop_mask`, `layer_multipliers`, `incremental` | list: `$raster`, `$by_class` |
| `rwapor_calc_seasonal_ret_masked()` | Seasonal RET sum using dekadal weights | `ret_dekad`, `season_weights`, `crop_mask`, `layer_multipliers`, `incremental` | list: `$raster`, `$by_class` |
| `rwapor_calc_etc_dekad()` | Dekadal ETc = RET × Kc | `ret_dekad`, `kc_dekad` | SpatRaster |
| `rwapor_calc_seasonal_etc_incremental()` | Seasonal ETc using incremental weighted sum | `ret_dekad`, `season_weights`, `kc_dekad`, `layer_multipliers` | SpatRaster (1 layer) |
| `rwapor_calc_adequacy_etc()` | Adequacy = AETI / ETc | `aeti_seasonal`, `etc_seasonal` | SpatRaster or numeric |
| `rwapor_calc_class_p95_aeti()` | P95 AETI per crop class (benchmark) | `aeti_seasonal`, `crop_mask`, `min_pixels` | data.frame: class, p95_aeti, n_pixels, valid |
| `rwapor_calc_adequacy_p95()` | P95-based adequacy raster | `aeti_seasonal`, `crop_mask`, `p95_table` | SpatRaster |
| `rwapor_aggregate_precip_monthly()` | Aggregate daily/dekadal precip to monthly totals | `precip_ts` (data.frame: date, value) | data.frame: year, month, p_monthly_mm |
| `rwapor_calc_peff_usda_monthly()` | USDA SCS effective rainfall from monthly totals | `p_monthly` (numeric vector, mm) | numeric vector of monthly Peff (mm) |
| `rwapor_calc_peff_seasonal()` | Seasonal Peff total from monthly Peff | `peff_monthly`, `start_date`/`end_date` OR `season_months`+`season_year` | numeric (mm) |
| `rwapor_calc_cwp()` | Crop Water Productivity = yield / AETI | `yield_value`, `aeti_mm`, `yield_unit` | numeric or SpatRaster (kg/m³) |
| `rwapor_calc_bwp()` | Biomass Water Productivity = biomass / AETI | `biomass_value`, `aeti_mm`, `biomass_unit` | numeric or SpatRaster (kg/m³) |
| `rwapor_convert_npp_to_tbp()` | Convert NPP (gC/m²) to TBP (kgDM/ha) | `npp_gc_m2` | numeric |
| `rwapor_calc_yield_npp()` | Estimate yield from NPP using harvest index | `npp_gc_m2`, `MC`, `fc`, `AOT`, `HI` | numeric |
| `rwapor_prepare_analysis_ts()` | Prepare AETI/RET/precip time series for analysis | `region`, `aeti_var`, `ret_var`, `precip_var`, ... | list of time series data.frames |
| `rwapor_merge_analysis_timeseries()` | Merge AETI, RET, precip time series by date | `aeti_ts`, `ret_ts`, `precip_ts` | merged data.frame |

---

## R/api_client.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `collect_responses()` | Fetch paginated WaPOR API responses | `url`, `info` | list of API results |
| `wapor_generate_urls_internal()` | Generate download URLs for WaPOR/AgERA5 resources | `variable`, `l3_region`, `period` | character vector of URLs |
| `wapor_generate_urls()` | Memoised wrapper for `wapor_generate_urls_internal()` | same | character vector (cached) |

---

## R/metadata.R

| Object / Function | Description |
|---|---|
| `WAPOR3_VARS` | Named list of all WaPOR v3 variables (L1/L2/L3) with units, scale factors |
| `AGERA5_VARS` | Named list of all AgERA5 variables with units, scale factors |
| `L3_REGIONS` | Named list of all L3 region codes with name + country |
| `FAO_CROP_DEFAULTS` | Named list of default FAO crop parameters |
| `get_variable_metadata()` | Memoised function: returns metadata for any variable code |
| `get_variable_metadata_internal()` | (internal) actual metadata fetcher from API + static lists |

**Key variable code format**: `"L1-AETI-D"`, `"L2-NPP-A"`, `"L3-AETI-D"`, `"AGERA5-ET0-D"`
**Temporal codes**: `E`=daily, `D`=dekadal, `M`=monthly, `A`=annual

---

## R/unit_convertor.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `df_unit_convertor()` | Convert data.frame values between temporal units | `df`, `unit_conversion` | data.frame with converted values |
| `raster_unit_convertor()` | Convert raster values between temporal units | `r`, `variable`, `urls`, `unit_conversion` | SpatRaster with converted values |

---

## R/utils.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `parse_region()` | Parse region input (bbox, vector file, L3 code) | `region` | list with `$type`, `$value` |
| `calculate_conversion_factor()` | Compute unit conversion multiplier | `source_time`, `target_unit`, `num_days`, ... | numeric |
| `extract_temporal_unit()` | Extract temporal unit string from units field | `units` | character |
| `resolve_output_unit_conversion()` | Determine unit conversion rule for variable | `variable`, `unit_conversion` | character |
| `get_seasonal_aggregation_rule()` | Get aggregation rule (sum/mean) for variable | `variable` | character |
| `get_seasonal_multiplier_values()` | Get per-layer multipliers for seasonal aggregation | `variable`, `plan_rows`, `aggregation_rule` | numeric vector |
| `get_analysis_layer_multipliers()` | Get multipliers for analysis pipeline layers | `variable`, `period_table` | numeric vector |
| `get_seasonal_output_units()` | Get output units after seasonal aggregation | `variable`, `aggregation_rule` | character |
| `get_date_info()` | Extract date from WaPOR URL filename | `url`, `tres` | list with date fields |
| `safe_project()` | Safe CRS projection with fallback | `x`, `y` | projected SpatRaster/SpatVector |
| `get_l3_raster_extent()` | Get L3 region raster extent (cached) | `url`, `code` | SpatExtent |
| `guess_l3_region()` | Infer L3 region code from variable + region info | `variable`, `reg_info`, `period` | character |
| `crop_to_region()` | Crop and optionally mask raster to region | `r`, `reg_info`, `do_mask` | SpatRaster |
| `get_url_chunks()` | Split URL list into batches | `urls`, `batching`, `batch_size` | list of URL vectors |
| `assign_raster_metadata()` | Assign units and variable metadata to raster | `r`, `variable`, `unit_conversion`, `units_override` | SpatRaster |

---

## R/gdal_config.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `wapor_configure_gdal()` | Configure GDAL settings for WaPOR downloads | many options | invisible (side effects) |
| `wapor_fix_proj()` | Fix PROJ_LIB conflicts on Windows | `verbose` | invisible |
| `wapor_gdal_settings()` | Display current GDAL/PROJ settings | — | prints to console |

---

## R/crop_defaults.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `rwapor_list_crops()` | List all available crop names | — | character vector |
| `rwapor_get_crop_defaults()` | Get FAO-56 default parameters for a crop | `crop_name` | list: Kc_ini, Kc_mid, Kc_end, L_ini, L_dev, L_mid, L_late |
| `rwapor_validate_crop_defaults()` | Validate a crop defaults data.frame | `df` | logical (with messages) |

---

## R/seasonal_download.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `download_seasonal_rasters()` | (internal) Download and match rasters to plan | `variable`, `period`, `l3_code`, `reg_info`, `folder`, `do_mask` | list: `$groups` (one per temporal code) with rasters + multipliers |

---

## R/interval_helpers.R

| Function | Description |
|---|---|
| `subtract_interval()` | Subtract covered intervals from a date range |
| `compute_overlap()` | Compute overlap days between two date ranges |
| `is_fully_within()` | Check if inner interval is fully within outer |
| `last_day_of_month()` | Get last day of a given year/month |

---

## R/rwapor_favorites.R

| Function | Description | Key inputs | Output |
|---|---|---|---|
| `rwapor_get_favorites()` | List saved favorite folders | — | character vector of paths |
| `rwapor_add_favorite()` | Add a path to favorites | `path`, `type` | invisible |
| `rwapor_remove_favorite()` | Remove a path from favorites | `path` | invisible |
| `rwapor_is_favorite()` | Check if a path is a favorite | `path` | logical |
| `get_favorites_path()` | (internal) Get favorites file path | — | character |

---

## inst/shiny/app.R — Dashboard Layout

**Framework**: `bslib::page_navbar` + Bootstrap 5 "flatly" theme  
**3 tabs**: Download | Visualisation | Analysis  
**Shared state**: `dl_out$folder` and `dl_out$region` passed from Download module to Analysis and Visualisation modules  
**Module wiring**:
```r
dl_out <- mod_download_server("dl", l3_regions_meta)
an_out <- mod_analysis_server("an", global_folder = dl_out$folder, aoi_region = dl_out$region)
mod_visualisation_server("vis", global_folder = dl_out$folder, aoi_region = dl_out$region, ...)
```

---

## inst/shiny/mod_download.R

**UI**: `mod_download_ui(id, all_vars, default_var, l3_region_choices)`  
**Server**: `mod_download_server(id, l3_regions_meta)`  
**Returns**: `list(folder = reactive, region = reactive)`  
**Key controls**: variable selector, period inputs, L3 region dropdown, local folder browser (`shinyFiles`), download button

---

## inst/shiny/mod_visualisation.R

**UI**: `mod_visualisation_ui(id)`  
**Server**: `mod_visualisation_server(id, global_folder, aoi_region, ...)`  
**Key feature**: Leaflet interactive map with dynamic raster layer rendering

---

## inst/shiny/mod_analysis.R (~2400 lines)

**UI**: `mod_analysis_ui(id, all_vars, l3_region_choices)`  
**Server**: `mod_analysis_server(id, global_folder, aoi_region)`

**Key UI controls:**
- Crop mask toggle (`an_use_crop_mask`)
- Pixel-wise season rasters toggle (`an_use_season_rasters`)
- Fixed season date inputs (start/end)
- L3 region selector
- Per-class crop parameter assignment (Kc_ini, Kc_mid, Kc_end, stage lengths)
- Yield/biomass inputs with unit selectors
- Memory optimization toggle (`an_incremental`)
- Save rasters checkbox (`an_save_rasters`)
- Validate, Run, Reset, Export buttons

**Key reactive state:**
```r
an_crop_mask_rast  # loaded crop mask
an_start_rast      # season start raster
an_end_rast        # season end raster
an_crop_classes    # extracted class values
an_crop_params     # per-class Kc parameters
an_results         # full analysis output
an_peff_monthly    # monthly Peff data.frame
an_local_vars      # scanned local variable inventory
```

**Results tabs (navset_card_tab):**
- Main Results | Adequacy | Eff. Precip | CWP/BWP
- Crop Mask preview | Season info | Classes table

---

## inst/shiny/mod_aoi.R

**UI**: `mod_aoi_ui(id)`  
**Server**: `mod_aoi_server(id, ...)`  
**Purpose**: AOI selection via bounding box drawing, vector file upload, or L3 code

---

## inst/shiny/utils_shiny.R

| Function | Description |
|---|---|
| `log_msg()` | Timestamped console logging |
| `null_default()` | Return default if value is NULL |
| `is_l3_code()` | Check if string matches L3 code pattern |
| `crop_to_region_shiny()` | Shiny-safe version of `crop_to_region()` |
| `extract_bbox_from_feature()` | Extract bounding box from Leaflet draw feature |
| `build_polygon_file()` | Build temporary vector file from coordinate matrix |
| `resolve_draw_fun()` | Resolve Leaflet draw function by package |

---

## Data Files

### fao_crop_coefficients.csv
Columns: `crop`, `Kc_ini`, `Kc_mid`, `Kc_end`  
Source: FAO-56 Table 12 (Allen et al. 1998)  
Used by: `rwapor_get_crop_defaults()`, Analysis module crop parameter UI

### fao_growth_stages.csv
Columns: `crop`, `L_ini`, `L_dev`, `L_mid`, `L_late` (days)  
Source: FAO-56 Table 11 (Allen et al. 1998)  
Used by: `rwapor_get_crop_defaults()`, `rwapor_build_daily_kc()`

---

## Key Dependencies

| Package | Usage |
|---|---|
| `terra` | All raster operations |
| `sf` | All vector/polygon operations |
| `exactextractr` | Pixel-weighted zonal statistics |
| `httr2` | WaPOR API calls |
| `memoise` | API response caching |
| `future.apply` | Parallel download |
| `dplyr`, `purrr` | Data manipulation |
| `lubridate` | Date arithmetic |
| `shiny`, `bslib` | Dashboard framework |
| `leaflet` | Interactive map |
| `shinyjs` | UI state control |
| `shinyFiles` | Folder browser widget |
