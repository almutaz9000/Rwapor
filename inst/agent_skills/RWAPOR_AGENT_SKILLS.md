# Rwapor Agent Skills Reference

> **For AI Agents**: This file is the canonical guide for using the Rwapor R package in automated analysis workflows. Read this first. It tells you which functions to call, in what order, with what inputs, and what to watch out for. All code blocks are executable R; copy-paste or adapt them directly.

**Package version**: 0.9.8  
**Access from R**: `system.file("agent_skills", "RWAPOR_AGENT_SKILLS.md", package = "Rwapor")`  
**WaPOR Portal**: https://wapor.apps.fao.org/  
**API Base**: https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/  
**ETLook Methodology Wiki**: https://github.com/un-fao/wapor-et-look/wiki  
**WaPOR Technical Documentation**: https://www.fao.org/3/ca9564en/CA9564EN.pdf

---

## 1. Package Purpose & Scope

Rwapor downloads and analyzes FAO WaPOR satellite remote sensing data and AgERA5 climate reanalysis data for agricultural water productivity analysis. It operates over Africa and the Near East.

**Methodology reference**: WaPOR AETI and component variables (T, E, I) are derived from the **ETLook** surface energy balance model. Agents designing workflows that involve ET disaggregation, interception modelling, or transpiration fractions should consult the ETLook wiki at https://github.com/un-fao/wapor-et-look/wiki for algorithm details and physical assumptions behind each variable.

**Core capability chain**:
```
Define AOI → Discover Variables → Download Rasters → Aggregate Seasonally →
Compute Indicators (ETc, Adequacy, CWP, Green/Blue Water) → Detect Anomalies → Report
```

**What it cannot do** (do not attempt):
- Download data outside Africa/Near East coverage (WaPOR L1/L2 limitation)
- Produce crop yield maps without an NPP layer and crop parameters (HI, MC, fc, AOT)
- Run seasonal analysis without a crop mask AND season start/end rasters
- Access real-time or near-real-time data (WaPOR data lag is ~6–8 weeks)

---

## 2. Quick Decision Tree

Use this to select the right workflow for a user's request.

```
User wants...
│
├─ "Download raster maps / imagery"
│   └─ → Workflow A: Raster Download
│
├─ "Extract time-series for fields / polygons"
│   └─ → Workflow B: Time-Series Extraction
│
├─ "Seasonal water productivity / crop analysis"
│   ├─ Has crop mask + season dates? → Workflow C: Full Seasonal Analysis
│   └─ No crop data? → Preprocess first (Section 5), then Workflow C
│
├─ "Compare multiple seasons / years"
│   └─ → Workflow D: Multi-Season Comparison (runs Workflow C per season)
│
├─ "Monitor farms / detect stress continuously"
│   └─ → Workflow E: Farm Monitoring (DuckDB-backed)
│
├─ "Calculate green water / blue water / Peff"
│   └─ → Workflow C with indicators = c("green_blue_water", "peff")
│
├─ "Detect anomalies / stressed areas"
│   └─ → Workflow C with anomaly detection, then wapor_detect_*() functions
│
└─ "Just explore what data is available"
    └─ → Section 3: Data Discovery
```

---

## 3. Data Sources & Discovery

### 3.1 WaPOR Data (Primary Source)

**Three spatial levels**:

| Level | Resolution | Coverage | Use Case |
|-------|-----------|----------|----------|
| L1 | **300 m** (ETLook variables); RET ~11 km; PCP ~5 km | All Africa + Near East | Continental / national analysis |
| L2 | 100 m | FAO-defined regions | Sub-national / irrigation scheme |
| L3 | **20 m** | Named irrigation schemes only (see Section 3.3) | Field-level precision |

> **Resolution note**: L1 ETLook-derived variables (AETI, T, E, I, NPP, RSM, GBWP, NBWP, TBP) are produced at 300 m. Reference Evapotranspiration (RET) is derived from AgERA5/ERA5 climate reanalysis at ~11 km (0.1°). Precipitation (PCP) is from CHIRPS at ~5 km. Both RET and PCP are only available at L1 — there are no L2 or L3 versions.

**Variable naming convention**: `{Level}-{Product}-{Temporal resolution}`  
Examples: `L1-AETI-D` (L1, Actual ET, Dekadal), `L1-RET-D`, `L3-AETI-E` (Daily)

**Temporal resolution codes**:
- `D` = Dekadal (10-day periods): ~3 per month
- `M` = Monthly
- `A` = Annual  
- `E` = Daily (only some L3 products)

**Variable availability by level** — CRITICAL for variable selection:

| Variable | Full Name | L1 | L2 | L3 | Unit (raw) | Auto-converted |
|----------|-----------|:--:|:--:|:--:|-----------|----------------|
| `AETI` | Actual ET & Interception | ✓ | ✓ | ✓ | mm/day | mm/dekad (D) |
| `T` | Transpiration | ✓ | ✓ | ✓ | mm/day | mm/dekad (D) |
| `E` | Soil Evaporation | ✓ | ✓ | ✓ | mm/day | mm/dekad (D) |
| `I` | Interception | ✓ | ✓ | ✓ (E only) | mm/day | mm/dekad (D) |
| `NPP` | Net Primary Production | ✓ | ✓ | ✓ | gC/m²/day | gC/m²/dekad (D) |
| `TBP` | Total Biomass Production | ✓ | ✓ | ✓ | kgDM/ha | — |
| `RSM` | Relative Soil Moisture | ✓ | ✓ | ✓ | % | — (intensive) |
| `GBWP` | Gross Biomass Water Productivity | ✓ | ✓ | ✓ | kg/m³ | — |
| `NBWP` | Net Biomass Water Productivity | ✓ | ✓ | — | kg/m³ | — |
| **`RET`** | **Reference Evapotranspiration** | **✓** | **✗** | **✗** | mm/day | mm/dekad (D) |
| **`PCP`** | **Precipitation (CHIRPS)** | **✓** | **✗** | **✗** | mm/day | mm/dekad (D) |

**AGENT RULE**: Always use `"L1-RET-D"` and `"L1-PCP-D"` regardless of the spatial level you use for AETI. Specifying `"L2-RET-D"` or `"L3-PCP-D"` will fail — these variables do not exist.

**Discover all available variables**:
```r
library(Rwapor)

# All WaPOR variables with metadata
str(WAPOR3_VARS, max.level = 2)

# Get metadata for a specific variable
wapor_variable_metadata("L1-AETI-D")
# Returns: list(code, long_name, unit, scale, temporal_resolution, level)

# Check what data exists locally
local_info <- wapor_scan_local(folder = "/path/to/downloads")
# Returns: data.frame(variable, n_files, min_date, max_date, folder)

# Validate data coverage before analysis
wapor_validate_data_coverage(
  folder = "/path/to/downloads",
  variable = "L1-AETI-D",
  start_date = "2023-10-01",
  end_date = "2024-05-31",
  min_percent = 80  # Warn if < 80% of expected dekads present
)
```

### 3.2 AgERA5 Climate Data (Secondary Source)

AgERA5 provides daily climate reanalysis data globally, hosted on FAO servers.

**Available variables**:

| Code | Full Name | Unit | Notes |
|------|-----------|------|-------|
| `ET0` | Reference Evapotranspiration | mm/day | Penman-Monteith based |
| `TMIN` | Minimum Temperature | K → **°C** auto-converted | Daily min |
| `TMAX` | Maximum Temperature | K → **°C** auto-converted | Daily max |
| `SRF` | Solar Radiation | J/m²/day | Downwelling shortwave |
| `WS` | Wind Speed | m/s | 10m height |
| `PF` | Precipitation Flux | mm/day | ERA5 precipitation |
| `RH` | Relative Humidity | % | Daily mean |

```r
# All AgERA5 variables
str(AGERA5_VARS, max.level = 2)

# Temperature: raw data is in Kelvin, package auto-converts to °C
# No manual conversion needed when using wapor_ts() or wapor_map()
```

### 3.3 L3 Irrigation Schemes (Named Regions)

```r
# List all available L3 regions
l3_df <- wapor_l3_regions_to_df(L3_REGIONS)
print(l3_df)  # Columns: code, name, country

# Example regions:
# AWA = Awash, Ethiopia
# JEN = Jendouba, Tunisia
# GEZ = Gezira, Sudan
# LAK = Lower Akagera, Rwanda
# MUV = Muvumba catchment, Rwanda
# ODN = Office du Niger, Mali

# Get bounding box for a region
wapor_l3_extent("AWA")  # Returns numeric vector c(xmin, ymin, xmax, ymax)

# Dynamically fetch current regions from API (slower, most up-to-date)
fresh_regions <- wapor_fetch_l3_regions()
```

---

## 4. Workflow Templates

### Workflow A: Raster Download

**Use when**: The user wants to save WaPOR imagery as GeoTIFF files for a region and time period.

**Prerequisites**: Know the variable code, region, and date range.

```r
library(Rwapor)

# Configure GDAL (required once per session)
wapor_configure_gdal()

# Option 1: Single-band GeoTIFF per dekad (separate_files = TRUE)
wapor_map(
  region   = c(36.0, 8.0, 38.5, 10.5),  # c(xmin, ymin, xmax, ymax) or L3 code
  variable = "L2-AETI-D",
  period   = c("2023-10-01", "2024-05-31"),
  folder   = "data/downloads/AETI",
  separate_files = TRUE,   # One file per dekad
  parallel = TRUE,         # Use parallel downloads
  batching = TRUE,
  batch_size = 12L         # Process 12 dekads at a time (memory management)
)

# Option 2: Multi-band GeoTIFF (all dekads in one file)
wapor_map(
  region   = "AWA",        # Named L3 region
  variable = "L3-AETI-D",
  period   = c("2023-10-01", "2024-03-31"),
  folder   = "data/downloads",
  filename = "AWA_AETI_2023_24.tif",
  separate_files = FALSE
)

# Option 3: Seasonal aggregate (one output raster with seasonal sum)
wapor_map(
  region   = c(36.0, 8.0, 38.5, 10.5),
  variable = "L1-AETI-D",
  period   = c("2023-10-01", "2024-05-31"),
  folder   = "data/seasonal",
  seasonal = TRUE          # Aggregates to single seasonal total
)
```

**AGENT NOTE**: For L3 variables, always pass `variable` with the L3 prefix (e.g., `"L3-AETI-D"`) AND ensure the region is either the L3 code string or a geometry that overlaps the L3 scheme. Use `wapor_guess_region()` if uncertain which L3 code applies to a given AOI.

---

### Workflow B: Time-Series Extraction

**Use when**: The user wants tabular time-series data for polygons (farms, administrative units, plots).

**Prerequisites**: Polygon(s) as an sf object or file path.

```r
library(Rwapor)
library(sf)

# Load your area of interest (polygon)
aoi <- st_read("my_fields.shp")  # Must be in WGS84 (EPSG:4326) or will be reprojected

# Extract AETI time-series for all polygons
aeti_ts <- wapor_ts(
  region   = aoi,              # sf object, file path, or bbox vector
  variable = "L2-AETI-D",
  period   = c("2022-01-01", "2023-12-31"),
  identifier = "field_id",     # Column name in aoi to use as row label
  parallel = TRUE
)
# Returns: data.frame(date, mean, min, max, sum, stdev, count, identifier)

# Extract multiple variables in one call
all_ts <- wapor_prepare_ts(
  region    = aoi,
  aeti_var  = "L2-AETI-D",
  ret_var   = "L1-RET-D",    # RET only available at L1
  precip_var = "L1-PCP-D",   # PCP only available at L1
  period    = c("2022-01-01", "2023-12-31")
)
# Returns: list(aeti = df, ret = df, precip = df)

# Merge all three time-series to a single data.frame
merged_ts <- wapor_merge_ts(
  aeti_ts   = all_ts$aeti,
  ret_ts    = all_ts$ret,
  precip_ts = all_ts$precip
)

# Unit conversion: mm/day → mm/dekad (for D variables, done automatically)
# If you need to convert manually:
converted <- wapor_convert_units(merged_ts, unit_conversion = "dekad_to_month")
```

---

### Workflow C: Full Seasonal Crop Water Productivity Analysis

**Use when**: Calculating seasonal indicators (ETc, Adequacy, CWP, Green/Blue Water) for a crop season with a crop mask.

**Prerequisites (all required)**:
1. Crop mask raster (integer class values per pixel, see Section 5.1)
2. Season start raster (Julian days, see Section 5.2)
3. Season end raster (Julian days, see Section 5.2)
4. Crop parameters per class (Kc stages, HI, MC; see Section 6.2)
5. AETI and RET data (downloaded via Workflow A or streamed from API)

```r
library(Rwapor)

# --- Step 1: Load spatial inputs ---
crop_mask    <- wapor_load_crop_mask("crop_mask.tif")        # Integer class raster
season_start <- wapor_load_season_raster("season_start.tif") # Julian day raster
season_end   <- wapor_load_season_raster("season_end.tif")   # Julian day raster

# --- Step 2: Inspect crop classes ---
classes <- wapor_extract_crop_classes(crop_mask)
# Returns: data.frame(class_value, pixel_count, area_ha)

# --- Step 3: Build crop assignment table ---
# Quick start: use FAO defaults for known crops
wapor_list_crops()  # See available defaults: "winter_wheat", "sorghum", "sugarbeet"

# Assign crop to each class value
crop_params <- wapor_build_crop_assignments(
  class_values = classes$class_value,
  crop_defaults = list(
    "1" = wapor_crop_defaults("sorghum"),
    "2" = wapor_crop_defaults("winter_wheat")
    # "3" = custom parameters (see Section 6.2)
  )
)

# --- Step 4: Configure the analysis pipeline ---
config <- list(
  ref_year    = 2023,                         # Year containing season start
  period      = c("2023-10-01", "2024-05-31"), # Download window (wider than season)
  aeti_var    = "L2-AETI-D",
  ret_var     = "L1-RET-D",   # RET only available at L1 — always use L1 prefix
  precip_var  = "L1-PCP-D",   # PCP only available at L1 — always use L1 prefix
  npp_var     = "L2-NPP-D",                   # Optional, needed for yield/CWP
  crop_params = crop_params,
  indicators  = c(
    "agg_aeti",       # Seasonal total AETI
    "agg_ret",        # Seasonal total RET
    "etc",            # ETc = RET × Kc (requires crop_params)
    "adequacy_etc",   # AETI / ETc
    "adequacy_p95",   # AETI / P95(AETI by class)
    "peff",           # Effective precipitation (requires precip_var)
    "green_blue_water", # Green = min(AETI,Peff), Blue = AETI - Peff
    "cwp_bwp"         # Crop/Biomass Water Productivity (requires npp_var)
  ),
  data_source = "api"  # "api" (stream) or "local" (use downloaded files)
)

# Validate configuration before running
wapor_validate_analysis_config(config, crop_mask, season_start, season_end)

# --- Step 5: Run the pipeline ---
results <- wapor_analysis_pipeline(
  config        = config,
  region        = c(36.0, 8.0, 38.5, 10.5),  # AOI bbox or L3 code
  crop_mask     = crop_mask,
  season_start  = season_start,
  season_end    = season_end,
  save_outputs  = TRUE,
  output_folder = "results/season_2023_24",
  output_prefix = "AWA_sorghum"
)

# --- Step 6: Inspect results ---
# results$rasters : named list of SpatRasters (one per indicator)
# results$summary : data.frame with per-class zonal statistics
# results$metadata: config + run timestamp

print(results$summary)
terra::plot(results$rasters$agg_aeti)

# --- Step 7: Anomaly detection (optional) ---
anomalies <- wapor_detect_aeti_anomalies(
  aeti_seasonal = results$rasters$agg_aeti,
  crop_mask     = crop_mask,
  threshold     = 0.5  # Flag pixels < 50% of class median
)

zscore_anom <- wapor_detect_zscore_anomalies(
  aeti_seasonal  = results$rasters$agg_aeti,
  crop_mask      = crop_mask,
  zscore_threshold = 1.5
)

compound_anom <- wapor_detect_compound_anomalies(
  indicators = list(
    aeti     = results$rasters$agg_aeti,
    adequacy = results$rasters$adequacy_etc
  ),
  crop_mask  = crop_mask,
  thresholds = list(aeti = 0.5, adequacy = 0.6)
)
```

---

### Workflow D: Multi-Season / Multi-Year Comparison

**Use when**: Comparing indicators across seasons or running trend analysis over multiple years.

```r
library(Rwapor)

# Run Workflow C for each season, collect results
seasons <- list(
  "2021_22" = list(period = c("2021-10-01", "2022-05-31"), ref_year = 2021),
  "2022_23" = list(period = c("2022-10-01", "2023-05-31"), ref_year = 2022),
  "2023_24" = list(period = c("2023-10-01", "2024-05-31"), ref_year = 2023)
)

season_results <- lapply(names(seasons), function(name) {
  cfg <- modifyList(config, seasons[[name]])  # Merge season dates into base config
  wapor_analysis_pipeline(
    config        = cfg,
    region        = my_region,
    crop_mask     = crop_mask,
    season_start  = season_start,
    season_end    = season_end
  )
})
names(season_results) <- names(seasons)

# Compare across seasons
comparison <- wapor_compare_seasons(
  season_results = season_results,
  indicators     = c("AETI", "ETc", "Adequacy"),
  by             = "crop_class"  # or "overall"
)

# Trend analysis
trend <- wapor_trend_analysis(
  timeseries_list = lapply(season_results, function(r) r$summary),
  variable        = "agg_aeti",
  method          = "lm"  # Linear regression; returns slope, p-value per class
)

# Export HTML report
wapor_export_comparison_report(
  comparison_table = comparison,
  output_folder    = "reports/",
  format           = "html"
)
```

---

### Workflow E: Farm-Level Monitoring

**Use when**: Continuously tracking water stress for a set of farm polygons (DuckDB-backed incremental updates).

```r
library(Rwapor)
library(DBI)
library(duckdb)
library(sf)

# Load farm polygons (must have a unique ID column)
farms <- st_read("farms.shp")  # Polygon sf object

# Initialize DuckDB database
con <- dbConnect(duckdb(), dbdir = "monitoring/farm_monitor.duckdb")
wapor_init_monitoring_db(con)  # Creates schema tables

# Run monitoring (fetches only missing dekads automatically)
wapor_run_monitoring(
  con       = con,
  farms_sf  = farms,
  variables = c("L2-AETI-D", "L1-RET-D", "L2-NPP-D"),  # RET is L1-only
  period    = c("2023-01-01", Sys.Date())  # Updates incrementally
)

# Query results
ts <- dbGetQuery(con, "
  SELECT farm_id, date, variable, mean_value
  FROM farm_timeseries
  ORDER BY farm_id, date
")
dbDisconnect(con)
```

---

## 5. Preprocessing Guide

This section tells agents what preprocessing is needed to bring user data into a format the package can consume.

### 5.1 Crop Mask Preparation

A crop mask is a **single-band integer GeoTIFF** where each unique integer value represents a crop class (e.g., 1 = wheat, 2 = maize, 0 = non-crop / NoData).

**Accepted input formats**:
- GeoTIFF (.tif) with integer values
- Any CRS (package will reproject to match AETI geometry)
- Any resolution (package will resample using nearest-neighbor)

**If the user provides a vector file (shapefile / GeoJSON) with crop types**:
```r
library(terra)
library(sf)

# Load vector crop map
crops_vec <- st_read("crop_map.shp")  # Must have a crop_type column

# Get the AETI raster as template (download a single dekad first)
template <- wapor_map(
  region   = my_region,
  variable = "L2-AETI-D",
  period   = c("2023-11-01", "2023-11-10"),
  folder   = tempdir()
)
template_r <- terra::rast(list.files(tempdir(), "*.tif", full.names = TRUE)[1])

# Convert crop classes to integer codes
crops_vec$class_int <- as.integer(factor(crops_vec$crop_type))

# Rasterize
crop_mask_r <- terra::rasterize(
  terra::vect(crops_vec),
  template_r,
  field = "class_int"
)
terra::writeRaster(crop_mask_r, "crop_mask.tif", overwrite = TRUE)

# Load via package validator
crop_mask <- wapor_load_crop_mask("crop_mask.tif")
```

**If the user provides a land use / land cover (LULC) raster (e.g., from ESA WorldCover, GlobCover)**:
```r
lulc <- terra::rast("esa_worldcover.tif")

# Reclassify to crop / non-crop (WorldCover class 40 = cropland)
rcl <- matrix(c(40, 1,   # Cropland → class 1
                NA, NA), # Everything else → NA
              ncol = 2, byrow = TRUE)
# Better: keep sub-classes if available
crop_mask <- terra::classify(lulc, rcl, others = NA)
terra::writeRaster(crop_mask, "crop_mask.tif", overwrite = TRUE)
```

**Minimum requirements**:
- At least 10 pixels per crop class (enforced by `wapor_extract_crop_classes(min_pixels = 10)`)
- Integer values (no floating point)
- Spatial overlap with the AOI where AETI data exists

---

### 5.2 Season Raster Preparation

Season rasters define the **start and end of the growing season per pixel** as Julian day-of-year integers.

**Accepted input**: Single-band integer GeoTIFF. Values are Julian days (1–365 or 1–366). For seasons crossing the year boundary (e.g., Oct–May), `end` values < `start` values are handled by the `ref_year` parameter.

**Option A: Uniform season (same dates everywhere)**
```r
library(terra)

template <- terra::rast("crop_mask.tif")  # Use crop mask as geometry template

# Convert dates to Julian days
start_julian <- as.integer(format(as.Date("2023-10-15"), "%j"))  # = 288
end_julian   <- as.integer(format(as.Date("2024-05-15"), "%j"))  # = 136 (next year)

# Create constant rasters
season_start <- template
terra::values(season_start) <- start_julian
terra::NAflag(season_start) <- 0  # Set 0 as NoData

season_end <- template
terra::values(season_end) <- end_julian

terra::writeRaster(season_start, "season_start.tif", overwrite = TRUE)
terra::writeRaster(season_end,   "season_end.tif",   overwrite = TRUE)
```

**Option B: Plot-specific dates from CSV + vector file**
```r
# CSV format: id, season_name, start_date, end_date, crop_class (optional)
# Vector file: polygons with matching ID column

wapor_vector_to_season_rasters(
  vector_path   = "plots.shp",
  csv_path      = "plot_seasons.csv",
  template_r    = terra::rast("crop_mask.tif"),
  id_col        = "plot_id",
  season_col    = "season_name",
  start_col     = "start_date",   # Format: "YYYY-MM-DD"
  end_col       = "end_date",
  crop_col      = "crop_class",   # Optional integer column
  ref_year      = 1970,           # Julian day reference year
  output_folder = "seasonal_masks"
)
# Writes: season_start.tif, season_end.tif, crop_mask.tif (if crop_col provided)
```

**Option C: From phenology maps (e.g., MODIS MCD12Q2, ASAP)**
```r
# MODIS MCD12Q2 stores "Greenup" and "Maturity" as days since 1970-01-01
modis <- terra::rast("MCD12Q2.A2023001.006.tif")
greenup  <- modis[[1]]  # Layer 1 = Greenup date
maturity <- modis[[4]]  # Layer 4 = Maturity date (proxy for harvest)

# Convert to Julian days of the crop year
ref_date    <- as.Date("1970-01-01")
season_year <- 2023

greenup_julian  <- greenup  - as.integer(as.Date(paste0(season_year, "-01-01")) - ref_date) + 1
maturity_julian <- maturity - as.integer(as.Date(paste0(season_year, "-01-01")) - ref_date) + 1

terra::writeRaster(greenup_julian,  "season_start.tif", overwrite = TRUE)
terra::writeRaster(maturity_julian, "season_end.tif",   overwrite = TRUE)
```

---

### 5.3 Crop Parameters Preparation

Crop parameters follow FAO-56 standards. Each crop class in the mask needs these values:

| Parameter | Description | Typical range | Example (Sorghum) |
|-----------|-------------|---------------|-------------------|
| `kc_ini`  | Kc initial stage | 0.3–0.5 | 0.35 |
| `kc_mid`  | Kc mid season | 0.9–1.2 | 1.05 |
| `kc_end`  | Kc end season | 0.4–0.9 | 0.55 |
| `l_ini`   | Days in initial stage | 15–30 | 20 |
| `l_dev`   | Days in development stage | 25–50 | 35 |
| `l_mid`   | Days in mid season | 40–80 | 40 |
| `l_late`  | Days in late season | 20–40 | 30 |
| `hi`      | Harvest Index (0–1) | 0.3–0.55 | 0.40 |
| `mc`      | Moisture Content (%) | 12–75 | 12 |
| `fc`      | Fractional Cover at peak | 0.7–0.95 | 0.85 |
| `aot`     | Aboveground/Total biomass ratio | 0.5–0.9 | 0.75 |

```r
# Use FAO defaults (available for sorghum, winter_wheat, sugarbeet)
wapor_list_crops()  # List available defaults
defaults <- wapor_crop_defaults("sorghum")
# Returns named list with all parameters above

# Build the crop_params data.frame (one row per class)
crop_params <- wapor_build_crop_assignments(
  class_values = c(1, 2, 3),
  crop_defaults = list(
    "1" = wapor_crop_defaults("sorghum"),
    "2" = wapor_crop_defaults("winter_wheat"),
    "3" = list(  # Custom crop
      kc_ini = 0.40, kc_mid = 1.15, kc_end = 0.70,
      l_ini = 25,  l_dev = 35,   l_mid = 50,  l_late = 30,
      hi = 0.45, mc = 14, fc = 0.90, aot = 0.80
    )
  )
)

# Validate before use
wapor_validate_crop_params(crop_params)  # Raises informative error if invalid
```

---

### 5.4 AOI (Area of Interest) Formats

The `region` parameter in all download functions accepts:

```r
# 1. Bounding box vector (most common)
region <- c(xmin = 36.0, ymin = 8.0, xmax = 38.5, ymax = 10.5)  # WGS84 decimal degrees

# 2. Named L3 region code (string)
region <- "AWA"  # Awash, Ethiopia — use wapor_l3_regions_to_df() to find codes

# 3. sf polygon object
region <- sf::st_read("my_aoi.shp")   # Any CRS; auto-reprojected to WGS84

# 4. File path to vector file
region <- "my_aoi.shp"  # Package reads with sf::st_read()

# Parse and inspect AOI info
region_info <- wapor_parse_region(region)
# Returns: list(type, bbox, crs, l3_code)

# Auto-detect which L3 region(s) overlap with your AOI
wapor_guess_region(variable = "L3-AETI-D", region_info = region_info, period = c("2023-10-01", "2024-05-31"))
```

---

## 6. Parameter & Configuration Reference

### 6.1 Analysis Config Object (Complete)

```r
config <- list(
  # Required
  ref_year    = 2023,              # Integer: year containing season START date
  period      = c("2023-10-01", "2024-05-31"),  # or list for multi-season

  # Data variables (at least aeti_var required)
  aeti_var    = "L2-AETI-D",       # Actual ET variable
  ret_var     = "L1-RET-D",        # RET only at L1 — always L1 regardless of AETI level
  precip_var  = "L1-PCP-D",        # PCP only at L1 — always L1 regardless of AETI level
  npp_var     = "L2-NPP-D",        # NPP (required for yield/CWP)

  # Crop configuration
  crop_params = crop_params,        # data.frame from wapor_build_crop_assignments()

  # Selected indicators (vector of strings)
  indicators  = c("agg_aeti", "agg_ret", "etc", "adequacy_etc",
                  "adequacy_p95", "peff", "green_blue_water", "cwp_bwp"),

  # Data source
  data_source = "api",             # "api" (stream) or "local" (pre-downloaded)
  l3_code     = NULL,              # Optional: force L3 region (e.g., "AWA")

  # Kc curve customization (optional overrides)
  kc_aggregation = "dekadal_mean"  # How to aggregate daily Kc to dekads
)
```

### 6.2 FAO-56 Crop Defaults (Built-in)

```r
# Available defaults
wapor_list_crops()
# [1] "winter_wheat"  "sorghum"  "sugarbeet"

# Sorghum parameters
wapor_crop_defaults("sorghum")
# $kc_ini [1] 0.35
# $kc_mid [1] 1.05
# $kc_end [1] 0.55
# $l_ini  [1] 20
# $l_dev  [1] 35
# $l_mid  [1] 40
# $l_late [1] 30
# $hi     [1] 0.40
# $mc     [1] 12
# $fc     [1] 0.85
# $aot    [1] 0.75

# Winter Wheat parameters
wapor_crop_defaults("winter_wheat")
# Kc_ini=0.40, Kc_mid=1.15, Kc_end=0.25, stages=25/140/40/30, HI=0.40
```

### 6.3 Temporal Unit Conversions

```r
# Available conversions
wapor_temporal_codes()
# Returns list of supported temporal codes: D (dekad), M (month), A (annual), E (daily)

# Convert time-series data.frame between units
ts_monthly <- wapor_convert_units(ts_dekadal, unit_conversion = "dekad_to_month")
ts_annual  <- wapor_convert_units(ts_monthly,  unit_conversion = "month_to_year")

# Convert raster units
raster_mm_month <- wapor_convert_raster(
  raster          = my_raster,
  unit_conversion = "dekad_to_month",
  variable        = "L2-AETI-D",
  tres            = "D"
)
```

---

## 7. Output Schemas

### wapor_ts() output

```
data.frame columns:
  date       : character "YYYY-MM-DD" (dekad start date)
  mean       : numeric   Mean value across polygon pixels (mm/dekad or original unit)
  min        : numeric   Minimum pixel value
  max        : numeric   Maximum pixel value
  sum        : numeric   Sum across pixels (for area calculations)
  stdev      : numeric   Standard deviation
  count      : integer   Number of valid pixels
  identifier : character Polygon identifier (from identifier= parameter)
```

### wapor_analysis_pipeline() output

```
List with elements:
  $rasters   : named list of terra::SpatRaster
               Names: "agg_aeti", "agg_ret", "etc", "adequacy_etc",
                      "adequacy_p95", "peff", "green_water", "blue_water",
                      "cwp", "bwp"
  $summary   : data.frame
               Columns: crop_class, indicator, mean, median, sd, min, max,
                        q25, q75, n_pixels, area_ha
  $metadata  : list(config, run_time, n_dekads_used, crs, bbox)
```

### wapor_compare_seasons() output

```
data.frame columns:
  season     : character Season label (from input names)
  crop_class : integer   Crop class value (or "overall")
  indicator  : character Indicator name
  mean       : numeric   Zonal mean for this class/season
  change_abs : numeric   Absolute change vs. first season
  change_pct : numeric   % change vs. first season
```

---

## 8. Common Patterns & Gotchas

### 8.1 Spatial Mismatch Between Inputs

All rasters passed to the analysis pipeline (crop_mask, season_start, season_end) must be harmonized to the same geometry (CRS, resolution, extent) as the AETI raster. The pipeline handles this internally, but if you pre-process rasters manually:

```r
# Harmonize to AETI geometry (required if pre-processing manually)
aeti_template <- terra::rast("aeti_dekad.tif")
crop_mask_h   <- wapor_harmonize_raster(crop_mask,    aeti_template, method = "near")
season_start_h<- wapor_harmonize_raster(season_start, aeti_template, method = "near")
season_end_h  <- wapor_harmonize_raster(season_end,   aeti_template, method = "near")

# Verify geometry match
wapor_compare_geom(crop_mask_h, aeti_template)  # Must return TRUE
```

### 8.2 Cross-Year Seasons

For seasons that span two calendar years (e.g., Oct 2023 – May 2024), always set:
- `ref_year = 2023` (the year containing the start date)
- `season_end` Julian days that are numerically LESS than `season_start` values — the package handles wrap-around automatically via `wapor_continuous_julian()`

### 8.3 L1 vs L2 vs L3 Variable Selection

- **Always prefer L2 or L3 for AETI and component variables** — higher resolution than L1 (100m at L2, 20m at L3, vs 300m at L1)
- **RET and PCP are L1-only** — always use `"L1-RET-D"` and `"L1-PCP-D"` regardless of which level you use for AETI and NPP. Passing `"L2-RET-D"` or `"L3-PCP-D"` will cause an API error.
- **L3 requires a specific region code** — use `wapor_guess_region()` to auto-detect or pass `l3_code` explicitly in config
- **Typical mixed-level config** (most common for L3 field analysis):
  ```r
  aeti_var   = "L3-AETI-D"   # 20m field resolution
  npp_var    = "L3-NPP-D"    # 20m
  ret_var    = "L1-RET-D"    # L1-only, ~11 km (ERA5-based)
  precip_var = "L1-PCP-D"    # L1-only, ~5 km (CHIRPS)
  ```

### 8.4 Memory Management for Large Areas / Long Periods

```r
# For multi-year downloads, increase batch_size or enable batching
wapor_map(
  region     = large_region,
  variable   = "L1-AETI-D",
  period     = c("2018-01-01", "2024-12-31"),  # 7 years = ~250 dekads
  folder     = "data/",
  batching   = TRUE,
  batch_size = 12L,   # Process 12 dekads at a time (~4 months)
  parallel   = TRUE
)

# Pre-plan batches to estimate download size
plan <- wapor_plan_time_slices("2018-01-01", "2024-12-31", "L1-AETI-D", batch_size = 12L)
nrow(plan)  # Number of batches
```

### 8.5 API Access & Rate Limits

```r
# No API key required for WaPOR public data
# But if API calls fail repeatedly:

# 1. Configure GDAL (helps with SSL and vsicurl issues)
wapor_configure_gdal(verbose = TRUE)

# 2. Windows users: fix PROJ collision
wapor_fix_proj()

# 3. Check all dependencies
wapor_preflight_check()

# 4. Clear memoized API cache if stale
library(memoise)
memoise::forget(wapor_generate_urls)

# 5. Test a single URL
urls <- wapor_generate_urls("L1-AETI-D", period = c("2023-11-01", "2023-11-10"))
terra::rast(urls[1])  # Should load without error
```

### 8.6 Season Duration Constraints

The `wapor_season_ldev()` function computes the development stage length from total duration minus fixed stages. The development stage MUST be positive:

```
l_dev_actual = total_season_days - l_ini - l_mid - l_late

REQUIRED: total_season_days > (l_ini + l_mid + l_late)
```

If seasons are shorter than expected (< 90 days), use shorter `l_ini`, `l_mid`, `l_late` values, or subset the crop mask to exclude pixels with too-short seasons.

### 8.7 Effective Precipitation (Peff) Notes

The USDA SCS formula for monthly Peff is applied per calendar month. For sub-monthly seasons, the function pro-rates monthly values to the fraction of the month within the season. Provide `start_date`, `end_date` when calling `wapor_calc_peff()` for accurate pro-rating.

---

## 9. Minimal Working Examples

### Example 1: Download 1 year of AETI for Ethiopia highlands

```r
library(Rwapor)
wapor_configure_gdal()

wapor_map(
  region   = c(37.5, 8.5, 39.0, 10.0),
  variable = "L1-AETI-D",
  period   = c("2023-01-01", "2023-12-31"),
  folder   = "data/eth_aeti_2023",
  separate_files = TRUE, parallel = TRUE
)
```

### Example 2: Time-series for irrigation districts

```r
library(Rwapor)
library(sf)

districts <- st_read("irrigation_districts.shp")

ts <- wapor_ts(
  region     = districts,
  variable   = "L2-AETI-D",
  period     = c("2023-01-01", "2023-12-31"),
  identifier = "district_name"
)
write.csv(ts, "aeti_timeseries_2023.csv", row.names = FALSE)
```

### Example 3: End-to-end seasonal CWP analysis for Awash, Ethiopia

```r
library(Rwapor)
wapor_configure_gdal()

# Use L3 AWA region
crop_mask    <- wapor_load_crop_mask("awa_crop_mask.tif")
season_start <- wapor_load_season_raster("awa_season_start.tif")  # Julian days
season_end   <- wapor_load_season_raster("awa_season_end.tif")

classes    <- wapor_extract_crop_classes(crop_mask)
crop_parms <- wapor_build_crop_assignments(
  class_values  = classes$class_value,
  crop_defaults = lapply(setNames(rep("sorghum", nrow(classes)), classes$class_value),
                         wapor_crop_defaults)
)

results <- wapor_analysis_pipeline(
  config = list(
    ref_year    = 2023,
    period      = c("2023-09-01", "2024-04-30"),
    aeti_var    = "L3-AETI-D",
    ret_var     = "L1-RET-D",   # RET is L1-only even when AETI is L3
    precip_var  = "L1-PCP-D",  # PCP is L1-only even when AETI is L3
    npp_var     = "L3-NPP-D",
    crop_params = crop_parms,
    indicators  = c("agg_aeti", "etc", "adequacy_etc", "cwp_bwp"),
    data_source = "api",
    l3_code     = "AWA"
  ),
  region       = "AWA",
  crop_mask    = crop_mask,
  season_start = season_start,
  season_end   = season_end,
  save_outputs = TRUE,
  output_folder = "results/AWA_2023_24"
)

print(results$summary)
```

---

## 10. Suggested Improvements for Agentic Use

These capabilities are planned or recommended to improve agent-driven workflows:

1. **`wapor_capabilities()`**: Returns a structured list of all supported indicators, data sources, and workflow types — lets agents self-discover capabilities without reading this file.

2. **`wapor_suggest_workflow(goal, data_available)`**: Takes a plain-text goal and available inputs, returns a recommended workflow config — an LLM-friendly entry point.

3. **`wapor_validate_prerequisites(config)`**: Pre-flight check that tests API connectivity, validates that all required variables exist for the chosen period, and returns a ready-to-run report before any download starts.

4. **JSON output mode**: All summary functions should optionally return JSON (`as_json = TRUE`) for easier ingestion by agent orchestration frameworks.

5. **Structured error objects**: Errors should return machine-readable codes alongside human messages so agents can route to the correct recovery action.

## 11. Repository Navigation for Agents

When working in this repository, use these path conventions to reduce context noise and avoid mixing production/runtime code with development artifacts:

- Package/runtime code: `R/`, `inst/`, `man/`, `tests/testthat/`, `vignettes/`
- Shared workflow memory/state: `agent-workflow/`
- Reusable development scripts and diagnostics: `dev-tools/scripts/`
- Archived development outputs and historical notes: `dev-archive/`

Agents should prefer package/runtime paths for feature and bug work, and only traverse `dev-archive/` when historical context is explicitly needed.

---

*This file is maintained as part of the Rwapor package. Report issues at https://github.com/almutaz9000/Rwapor/issues*
