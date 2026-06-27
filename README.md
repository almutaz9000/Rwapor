# Rwapor

<!-- badges: start -->
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
[![R-CMD-check](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

**Rwapor** is an R package for downloading and analyzing [**FAO WaPOR**](https://www.fao.org/in-action/remote-sensing-for-water-productivity/en/) satellite data and [**AgERA5**](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators) climate data for water productivity analysis.

> **Quick Start**: Jump to [Installation](#installation) → [Shiny Dashboard](#-option-1-interactive-shiny-dashboard-recommended) to get started in minutes!

---

## About WaPOR

[**WaPOR**](https://wapor.apps.fao.org/) is FAO's open-access portal providing remote sensing data on water productivity, evapotranspiration, and biomass across Africa and the Near East at multiple spatial resolutions (250m to 30m) and temporal frequencies (dekadal, monthly, annual).

**Key Resources**:
- 🌐 [WaPOR Portal](https://wapor.apps.fao.org/)
- 📖 [Technical Documentation](https://www.fao.org/3/ca9564en/CA9564EN.pdf)
- 📊 [Data Catalog](https://wapor.apps.fao.org/catalog/WAPOR_2/1)

---

## What Can You Do?

✅ **Download satellite imagery** (AETI, NPP, Precipitation) for any region  
✅ **Extract time-series** for crop fields and administrative boundaries  
✅ **Run seasonal crop analysis** with crop masks and growing season dates  
✅ **Calculate water productivity indicators** (CWP, NBWP, ETc, Adequacy, Transpiration)  
✅ **Use the interactive Shiny dashboard** for point-and-click workflows

## 🚀 Recent Highlights: High-Precision Batch Analysis

The latest version introduces powerful tools for large-scale agricultural research:

*   🔄 **Batch Multi-Year Analysis**: Process 10+ years of crop seasons in a single run with automated season detection and historical anchor support.
*   📍 **Plot-Level Precision**: Define unique planting/harvest dates for every single farm plot using a Vector file and CSV lookup table.

## 🛠️ One-Time Setup

You only need to perform these steps once on your computer (or when updating the package).

### Step 1: Install Required Dependencies

Rwapor requires several geospatial and web-interface libraries. Run this code in R to ensure all dashboard features work correctly:

```r
# Install all core and dashboard dependencies
install.packages(c(
  # Core Geospatial & API
  "terra", "sf", "httr2", "jsonlite", "dplyr", "purrr", "remotes",
  "lubridate", "exactextractr", "memoise", "future", "future.apply",
  
  # Dashboard UI & Logic
  "shiny", "bslib", "leaflet", "leaflet.extras", "leaflet.extras2",
  "shinyFiles", "shinyvalidate", "shinyjs", "shinyAce", "DT", 
  "shinycssloaders", "promises", "duckdb", "DBI",
  
  # Visualization & Data
  "ggplot2", "tidyterra", "patchwork", "ggspatial", "viridisLite", 
  "RColorBrewer", "arrow"
))
```

> **Note for Windows Users**: `sf` and `terra` usually come with everything they need. Linux/Mac users may need to install system libraries like `libgdal-dev` and `libproj-dev` first.

### Step 2: Install Rwapor

Install the latest version directly from GitHub:

```r
# install.packages("remotes")
remotes::install_github("almutaz9000/Rwapor")
```

---

## 🚀 Everyday Usage

Whenever you start RStudio and want to work with WaPOR data, just run:

```r
library(Rwapor)

# Option A: Launch the point-and-click dashboard
run_wapor()

# Option B: Use R commands for analysis
# results <- wapor_run_seasonal_analysis(...) followed by
# wapor_export_analysis_outputs(results, folder = "analysis_output")
```

---

## 🎯 Seasonal Analysis Scenarios

Choose the analysis workflow that matches your data availability. Rwapor scales from simple regional studies to high-precision farm monitoring.

### 🟢 Level 1: Starter (Regional Analysis)
**Data Availability**: Minimum (AOI + Single Season dates).  
**Scenario**: "I want to analyze how a single crop (e.g. Sugarbeet) performed across my entire project area this year."  
**How-to**: 
- Uncheck "Upload a crop mask" in the dashboard.
- The app treats the whole AOI as one crop class.
- Perfect for quick regional assessments or single-field studies.

### 🟡 Level 2: Standard (Regional Monitoring)
**Data Availability**: AOI + Multi-Year Season List.  
**Scenario**: "I want to compare Wheat productivity across the last 5 years for this entire district."  
**How-to**: 
- Use **Batch Mode** in the "Season Definition" section.
- Provide a text list of labels and dates (Start, End).
- The app loops through each year, applying your crop profile to the whole area.

### 🔴 Level 3: Advanced (High-Precision Monitoring)
**Data Availability**: Maximum (Plot Boundaries + CSV with IDs, Dates, and Crops).  
**Scenario**: "Every farm plot has a different planting date and different crops. I need precise results for each plot and season."  
**How-to**: 
- Use the **Custom Timing** section.
- Upload your GeoJSON boundaries and a CSV attribute table.
- Specify your **Grouping Column (Season)** to "unstack" rotations.
- The app generates unique, pixel-perfect timing and crop masks for every plot.

---

## Getting Started

You have **two options** to use Rwapor:

1. **Interactive Shiny Dashboard** *(recommended for beginners)*
2. **R Scripts** *(for automation and advanced workflows)*

---

## 🖥️ Option 1: Interactive Shiny Dashboard (Recommended)

The **easiest way** to use Rwapor is through the built-in Shiny dashboard — no coding required!

### Launch the Dashboard

```r
library(Rwapor)

# Launch dashboard
run_wapor()

# Or specify where to save downloaded data
run_wapor(data_folder = "C:/WaPOR_Data")
```

### What You Can Do in the Dashboard

**📍 Download Tab**:
- **Define Area of Interest** (AOI) - draw on map, upload vector, or upload raster
- **Smart L3 Region Detection** - automatically identifies overlapping L3 regions
  - Auto-filters L3 regions to show only those intersecting your AOI
  - Auto-selects when exactly one region overlaps
  - Shows status messages for guidance
  - See [L3 Auto-Detection Guide](.github/L3-AUTO-DETECTION.md) for details
- Upload your own polygons (Shapefile, GeoJSON, KML, GeoPackage)
- Select variables (AETI, NPP, Precipitation, etc.)
- Choose date range and download data
- Extract time-series statistics for each polygon

**📊 Analysis Tab**:
- Choose **project folder** (local rasters source) and a separate **output folder**
- Upload crop mask raster
- Upload season start/end rasters (Julian day of year)
- Configure crop parameters (Kc coefficients, growth stages)
- Or select from FAO-56 crop defaults (Wheat, Maize, Rice, etc.)
- Run single-season or batch analysis with `Detect from Folder` season parsing
- Calculate seasonal indicators:
  - Seasonal AETI and RET
  - Effective precipitation (`peff`, normalized internally to `agg_peff`)
  - Crop evapotranspiration (ETc)
  - Water adequacy ratios
  - Crop/Biomass water productivity
  - NPP-based yield estimates
- Export structured outputs (seasonal rasters, optional dekadal rasters, monthly CSV summaries)

---

## 💻 Option 2: R Scripts

For automation and custom workflows, use the programmatic interface.

### Example 1: Download Time-Series for Crop Fields

Download AETI (evapotranspiration) data for specific crop fields and extract statistics:

```r
library(Rwapor)
library(future)

# Enable parallel processing for faster downloads
plan(multisession, workers = 4)

# Define your polygons (crop fields)
crop_fields <- "path/to/crop_fields.geojson"  # or .shp, .kml

# Download time-series for 2023 growing season
df <- wapor_ts(
  region          = crop_fields,
  variable        = "L2-AETI-D",           # Dekadal AETI (Level 2, ~100m)
  period          = c("2023-04-01", "2023-11-30"),
  identifier      = "field_id",            # Column in your data with unique IDs
  unit_conversion = "dekad"                # Keep as mm/dekad
)

# View results
head(df)
#   field_id   start_date  end_date    mean  min   max
#   <chr>      <date>      <date>      <dbl> <dbl> <dbl>
# 1 Field_001  2023-04-01  2023-04-10  2.5   1.1   4.2
# 2 Field_001  2023-04-11  2023-04-20  3.1   1.5   5.0
# ...

# Save to CSV
write.csv(df, "aeti_timeseries.csv", row.names = FALSE)
```

### Example 2: Download Raster Maps

Download raster data for a bounding box:

```r
# Define your region (bbox: xmin, ymin, xmax, ymax)
region <- c(35.0, 8.0, 36.0, 9.0)  # Example: part of Ethiopia

# Download AETI for one month
map_path <- wapor_map(
  region   = region,
  variable = "L2-AETI-D",
  period   = c("2023-06-01", "2023-06-30"),
  folder   = "output_rasters"
)

# Load and visualize
library(terra)
r <- rast(map_path)
plot(r[[1]], main = "AETI - 2023-06-01")

### Example 3: Seasonal Analysis + Structured Export

Run multi-season analysis from local data and export all outputs in one step:

```r
library(Rwapor)

periods <- list(
  Winter_2019 = c("2018-10-12", "2019-05-31"),
  Winter_2021 = c("2020-11-07", "2021-04-25")
)

config <- list(
  period = periods,
  ref_year = 1970,
  aeti_var = "L1-AETI-D",
  ret_var = "L1-RET-D",
  precip_var = "L1-PCP-D",
  npp_var = "L1-NPP-D",
  t_var = "L1-T-D",
  data_source = "local",
  folder = "multi_season_results",
  indicators = c("agg_aeti", "peff", "etc", "beneficial_fraction", "yield_npp")
)

crop_params <- wapor_crop_defaults("Winter Wheat")
rasters <- list(crop_mask = terra::rast("wheat_mask.tif"))

results <- wapor_run_seasonal_analysis(
  config = config,
  crop_params = crop_params,
  rasters = rasters
)

wapor_export_analysis_outputs(
  results = results,
  folder = "analysis_outputs",
  indicators = config$indicators,
  season_label = NULL
)
```

---

## 🚀 Advanced Workflows

For complex analysis, multi-year monitoring, and seasonal productivity modeling, please refer to the dedicated guides:

*   📖 **[Advanced Analysis & Monitoring](vignettes/advanced-analysis.Rmd)**: DuckDB integration, resampling mixed resolutions, and percentile filtering.
*   📖 **[Seasonal Analysis Guide](vignettes/advanced-analysis.Rmd#1-seasonal-crop-water-productivity-analysis)**: Full step-by-step for CWP, BWP, and Yield.
*   📖 **[Data Catalog](vignettes/data-catalog.Rmd)**: Detailed list of all 100+ available variables.

---

## 📚 Learn More

### Available Data

To see all available WaPOR and AgERA5 variables:

```r
# View complete data catalog
vignette("data-catalog", package = "Rwapor")

# Or explore in R
?WAPOR3_VARS   # WaPOR v3 variables
?AGERA5_VARS   # AgERA5 climate variables
?L3_REGIONS    # Level 3 sub-national regions
```

### Detailed Documentation

For advanced features, see:

- **[Getting Started Vignette](vignettes/getting-started.Rmd)**: Comprehensive tutorial
- **[Data Catalog](vignettes/data-catalog.Rmd)**: All available variables and resolutions
- **[Shiny Dashboard Guide](vignettes/shiny-dashboard.Rmd)**: Dashboard usage and features
- **Function References**: Type `?function_name` in R (e.g., `?wapor_ts`)

### Repository Structure (Production vs Development)

The repository is organized to keep package runtime code easy to navigate:

- Production package paths: `R/`, `inst/`, `man/`, `tests/testthat/`, `vignettes/`
- Agent workflow state: `agent-workflow/`
- Reusable developer scripts: `dev-tools/scripts/`
- Archived development artifacts: `dev-archive/2026-05-production-cleanup/`

For details, see `docs/REPOSITORY_STRUCTURE.md`.

### Key Functions

| Function | Purpose |
|----------|---------|
| `run_wapor()` | Launch interactive Shiny dashboard |
| `wapor_ts()` | Download time-series for polygons |
| `wapor_map()` | Download raster maps for a region |
| `wapor_build_season_weights()` | Build pixel-wise dekadal season weights |
| `wapor_calc_seasonal_aeti()` | Calculate seasonal actual ET |
| `wapor_calc_seasonal_etc()` | Calculate seasonal crop water requirement |
| `wapor_calc_bwp()` | Calculate biomass water productivity |
| `wapor_calc_cwp()` | Calculate crop water productivity |
| `wapor_crop_defaults()` | Get FAO-56 crop parameters |
| `wapor_harmonize_raster()` | Reproject/resample raster to a target grid |

---

## 🤖 AI Agent Workflow

This repository utilizes a structured workflow for AI-assisted development (Claude, Codex, Gemini, etc.). If you are an AI assistant or a developer using one, please start with:

👉 **[agent-workflow/START-HERE.md](agent-workflow/START-HERE.md)**

This directory contains the canonical task state, issue logs, and session coordination protocols.

---

## 🤝 Contributing

Contributions are welcome! Please:
- Report bugs via [GitHub Issues](https://github.com/almutaz9000/Rwapor/issues)
- Submit improvements via [Pull Requests](https://github.com/almutaz9000/Rwapor/pulls)

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 📧 Citation

If you use Rwapor in your research, please cite:

```
FAO WaPOR Database: https://wapor.apps.fao.org/
Rwapor R Package: https://github.com/almutaz9000/Rwapor
```
