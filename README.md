# Rwapor: Satellite Data Ingestion & Water Productivity Analysis in R

<!-- badges: start -->
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
[![R-CMD-check](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml/badge.svg?branch=version-0.9.9)](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

**Rwapor** is a high-performance R package for streaming, analyzing, and visualizing satellite data from [**FAO WaPOR v3**](https://www.fao.org/in-action/remote-sensing-for-water-productivity/en/) (Water Productivity Open-access portal) and [**ECMWF AgERA5**](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators) agro-meteorological indicators.

It provides both a complete **programmatic R API** and an **interactive Shiny dashboard** with full offline DuckDB analytics, out-of-core tiled raster processing, agronomic crop modeling (FAO-56), and spatial water stress anomaly detection.

---

## Key Features

* 🚀 **Cloud-Optimized Streaming**: Direct window reading of Cloud-Optimized GeoTIFFs (COGs) via GDAL `/vsicurl/` with automatic HTTP range-request chunking and persistent 24h disk caching.
* 🌾 **FAO-56 Crop Water Modeling**: Automated calculation of Crop Evapotranspiration ($ET_c$), Water Adequacy, Transpiration Fraction ($T/AETI$), Green and Blue Water partitioning, and NPP-based crop yields ($CWP$ / $BWP$).
* 🛠️ **Custom Crop Parameters**: Full flexibility to define custom crop coefficients ($K_c$) and growth stages or selectively override FAO default profiles.
* 🌐 **Latitude-Aware Area Weighting**: Exact ellipsoidal pixel area calculation (`wapor_pixel_area_ha()`) ensuring latitude-unbiased class and AOI statistics on geographic (`EPSG:4326`) grids.
* 🧩 **Extensible Step Registry**: Modular indicator architecture allowing custom calculation steps to be registered and executed seamlessly.
* 🖥️ **Interactive Shiny Dashboard**: Point-and-click UI with interactive Leaflet map drawing, automatic Level 3 region detection, multi-season batch execution, and split-screen swipe map visualization.
* 📦 **Out-of-Core Tiled Engine**: Windowed raster engine (`wapor_run_seasonal_analysis_tiled()`) to process large regional or continental extents without memory overflow.
* ⚡ **High-Throughput Vector Extraction**: Fast polygon zonal statistics powered by `exactextractr` and embedded `DuckDB` storage for multi-year farm monitoring.

---

## Installation

### Prerequisites

Rwapor utilizes modern R geospatial libraries (`terra`, `sf`, `exactextractr`).

* **Windows / macOS**: Binary packages include all GDAL and PROJ requirements automatically.
* **Linux (Ubuntu/Debian)**: Install GDAL, PROJ, and GEOS system libraries:
  ```bash
  sudo apt-get update
  sudo apt-get install -y libgdal-dev libproj-dev libgeos-dev libudunits2-dev
  ```

### Install Required CRAN Packages

```r
install.packages(c(
  # Geospatial & API Core
  "terra", "sf", "httr2", "jsonlite", "dplyr", "purrr", "remotes",
  "lubridate", "exactextractr", "memoise", "future", "future.apply",
  
  # Interactive Dashboard & Database
  "shiny", "bslib", "leaflet", "leaflet.extras", "leaflet.extras2",
  "shinyFiles", "shinyvalidate", "shinyjs", "shinyAce", "DT", 
  "shinycssloaders", "promises", "duckdb", "DBI",
  
  # Visualization & Data
  "ggplot2", "tidyterra", "patchwork", "ggspatial", "viridisLite", 
  "RColorBrewer", "arrow"
))
```

### Install Rwapor

```r
# install.packages("remotes")
remotes::install_github("almutaz9000/Rwapor")
```

---

## Quick Start: Launch the Interactive Dashboard

Launch the full interactive point-and-click GUI directly from R:

```r
library(Rwapor)

# Launch Shiny application
run_wapor()

# Or specify a custom default working directory for downloaded data
run_wapor(data_folder = "C:/WaPOR_Projects")
```

### Dashboard Modules:

1. **📥 Download & Spatial Extraction**:
   - Draw custom AOI polygons or rectangles interactively on Leaflet maps.
   - Upload Shapefiles, GeoJSON, KML, or raster templates.
   - **Smart L3 Region Auto-Detection**: Intersects your AOI with all sub-national WaPOR Level 3 regions and selects overlapping schemes automatically.
   - Stream and download any of the 100+ WaPOR / AgERA5 variables across custom date ranges.

2. **🌾 Seasonal Analysis & Crop Productivity**:
   - Configure single-season or multi-year batch runs with automatic calendar detection.
   - Choose from 12 standard FAO-56 crop profiles or customize parameters interactively.
   - Compute seasonal $AETI$, $ET_c$, Water Adequacy, Crop Water Productivity ($CWP$), and Biomass Water Productivity ($BWP$).
   - Export structured GeoTIFFs, dekadal stacks, and CSV summaries in a single click.

3. **📈 Seasonal Comparison**:
   - Compare multi-year performance across seasons.
   - Assess spatial uniformity and inequality using Coefficient of Variation ($CV$) and Theil Index.
   - Interactive boxplots, violin plots, and bar summaries.

4. **🛰️ High-Throughput Field Monitoring**:
   - Ingest plot boundaries and attribute tables into embedded DuckDB.
   - Fast SQL filtering and temporal anomaly detection ($Z$-score water stress).

5. **🗺️ Split-Screen Map Visualizer**:
   - Side-by-side interactive swipe slider comparing rasters (e.g. $AETI$ vs. $ET_c$ or year-over-year changes).

---

## Programmatic Workflows & Code Examples

### 1. Extract Time Series for Agricultural Fields

Download satellite data and extract polygon zonal statistics in parallel:

```r
library(Rwapor)
library(future)

# Enable parallel background workers
plan(multisession, workers = 4)

# Define vector file (Shapefile, GeoJSON, or GeoPackage)
fields_path <- "farm_parcels.geojson"

# Extract dekadal actual evapotranspiration (Level 2, ~100m)
ts_data <- wapor_ts(
  region          = fields_path,
  variable        = "L2-AETI-D",
  period          = c("2023-01-01", "2023-12-31"),
  identifier      = "plot_id",
  unit_conversion = "unit_conversion" # Converts daily rates (mm/day) to dekadal totals (mm)
)

head(ts_data)
# Write results to CSV
write.csv(ts_data, "aeti_timeseries.csv", row.names = FALSE)
```

---

### 2. Custom Crop Factors & Details

Define custom crop coefficients without relying strictly on FAO defaults:

```r
library(Rwapor)

# Option A: Build a completely custom crop from scratch
custom_crop <- wapor_create_crop_params(
  class_value  = 1L,
  crop_name    = "Local High-Yield Durum Wheat",
  kc_ini       = 0.35,
  kc_mid       = 1.25,
  kc_end       = 0.30,
  l_ini_days   = 25L,
  l_mid_days   = 50L,
  l_late_days  = 30L,
  HI           = 0.50, # Harvest Index
  MC           = 0.12  # Moisture Content
)

# Option B: Override specific factors from an FAO profile
custom_maize <- wapor_custom_crop(
  base_crop   = "Maize",
  class_value = 2L,
  crop_name   = "Irrigated Hybrid Maize",
  kc_mid      = 1.30,
  HI          = 0.55
)

# Option C: Combine into a multi-class crop parameters table
crop_params <- wapor_combine_crop_params(custom_crop, custom_maize)
```

---

### 3. Run End-to-End Seasonal Analysis

```r
library(Rwapor)

config <- list(
  period        = c("2023-10-01", "2024-05-31"),
  ref_year      = 1970,
  aeti_var      = "L2-AETI-D",
  ret_var       = "L1-RET-D",
  precip_var    = "L1-PCP-D",
  npp_var       = "L2-NPP-D",
  t_var         = "L2-T-D",
  data_source   = "local",
  folder        = "wapor_data",
  area_weighted = TRUE, # Exact latitude-aware pixel weighting
  indicators    = c("agg_aeti", "agg_t", "etc", "adequacy_etc", "peff", "cwp_bwp", "beneficial_fraction")
)

# Crop classification mask
rasters <- list(crop_mask = terra::rast("crop_mask.tif"))

# Run seasonal analysis engine
results <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = crop_params,
  rasters     = rasters
)

# Export all seasonal rasters, monthly aggregations, and CSV summaries
wapor_export_analysis_outputs(
  results      = results,
  folder       = "outputs/Winter_2023",
  indicators   = config$indicators,
  season_label = "Winter_2023"
)
```

---

### 4. Spatial Anomaly & Water Stress Hotspots

Identify spatial water stress using temporal $Z$-scores and statistical classification:

```r
library(Rwapor)
library(terra)

# Multi-year seasonal AETI stack
aeti_stack <- c(rast("aeti_2021.tif"), rast("aeti_2022.tif"), rast("aeti_2023.tif"))

# Compute pixel-wise temporal Z-score
z_score <- wapor_calc_zscore(aeti_stack)

# Classify 2023 season into deficit / normal / surplus hotspots (+/- 1.96 = 95% CI)
hotspots_2023 <- wapor_calc_spatial_hotspots(z_score[[3]], low = -1.96, high = 1.96)

# Plot classified deficit/surplus map
plot(hotspots_2023, col = c("#d7191c", "#fdae61", "#ffffbf", "#a6d96a", "#1a9641"))
```

---

## Supported Agricultural & Water Indicators

| Indicator | Code | Description | Formula / Method |
|-----------|------|-------------|------------------|
| **Seasonal AETI** | `agg_aeti` | Total seasonal actual evapotranspiration | $\sum (AETI_i \times w_i \times \text{mult}_i)$ (mm) |
| **Seasonal RET** | `agg_ret` | Total seasonal reference evapotranspiration | $\sum (RET_i \times w_i \times \text{mult}_i)$ (mm) |
| **Crop ET** | `etc` | Potential crop evapotranspiration | $ET_c = RET \times K_c(\text{stage})$ |
| **Water Adequacy** | `adequacy_etc` | Evapotranspiration deficit ratio | $\text{Adequacy} = AETI / ET_c$ |
| **Upper Adequacy** | `adequacy_p95` | Adequacy relative to 95th percentile target | $\text{Adequacy}_{95} = AETI / P_{95}(AETI)$ |
| **Beneficial Fraction** | `beneficial_fraction` | Ratio of transpiration to total AETI | $BF = \text{Seasonal } T / \text{Seasonal } AETI$ |
| **Effective Precipitation** | `peff` | Usable rainfall for crop consumption | USDA Soil Conservation Service monthly method |
| **Green / Blue Water** | `green_water`, `blue_water` | Partitioning of water consumption | Green: $\min(AETI, P_{\text{eff}})$, Blue: $\max(0, AETI - P_{\text{eff}})$ |
| **Biomass Water Productivity** | `cwp_bwp` | Biomass produced per unit of water consumed | $BWP = \text{AGBP } (\text{kg/ha}) / (AETI \times 10)$ ($\text{kg/m}^3$) |
| **Crop Water Productivity** | `cwp_bwp` | Crop yield produced per unit of water consumed | $CWP = \text{Yield } (\text{kg/ha}) / (AETI \times 10)$ ($\text{kg/m}^3$) |
| **Spatial Uniformity** | `cv_aeti`, `theil_aeti` | Spatial variation & inequality across field/scheme | Coefficient of Variation ($CV$) & Theil Disparity Index |

---

## Data Catalog Overview

| Level | Spatial Resolution | Coverage | Key Variables |
|---|---|---|---|
| **Level 1** | ~250 m | Global | `L1-AETI-D`, `L1-E-D`, `L1-I-D`, `L1-NPP-D`, `L1-PCP-D`, `L1-RET-D`, `L1-T-D` |
| **Level 2** | ~100 m | Africa & Near East | `L2-AETI-D`, `L2-E-D`, `L2-I-D`, `L2-NPP-D`, `L2-T-D`, `L2-GBWP-A`, `L2-NBWP-A` |
| **Level 3** | ~20 m | 30+ Irrigation Schemes | `L3-AETI-D`, `L3-E-D`, `L3-I-D`, `L3-NPP-D`, `L3-T-D` (e.g. Awash, Bekaa, Gezira, Nile) |
| **AgERA5** | 0.1° (~10 km) | Global | `AGERA5-ET0-E`, `AGERA5-TMIN-E`, `AGERA5-TMAX-E`, `AGERA5-PRECIP-E` |

Explore available variables inside R:
```r
?WAPOR3_VARS   # WaPOR v3 metadata table
?AGERA5_VARS   # AgERA5 variables metadata table
?L3_REGIONS    # Sub-national Level 3 regions
```

---

## Documentation & Vignettes

* **[Getting Started Vignette](https://almutaz9000.github.io/Rwapor/articles/getting-started.html)**: Comprehensive introductory tutorial.
* **[Shiny Dashboard Guide](https://almutaz9000.github.io/Rwapor/articles/shiny-dashboard.html)**: Step-by-step walkthrough of all dashboard features.
* **[Advanced Analysis & Monitoring](https://almutaz9000.github.io/Rwapor/articles/advanced-analysis.html)**: Tiled processing, DuckDB integration, and custom math extensions.
* **[Data Catalog](https://almutaz9000.github.io/Rwapor/articles/data-catalog.html)**: Complete variable definitions, scale factors, and units.

---

## Citation

If you use `Rwapor` in academic publications or operational water accounting projects, please cite:

```bibtex
@software{rwapor2024,
  title  = {{Rwapor}: An {R} Package for Downloading and Analyzing {FAO WaPOR} Data},
  author = {Mohammed, Almutaz},
  year   = {2024},
  url    = {https://github.com/almutaz9000/Rwapor},
  note   = {R package version 0.9.9}
}
```

---

## License

MIT License © 2024 Almutaz Mohammed / Food and Agriculture Organization of the United Nations.
