# Rwapor: Satellite Data Ingestion & Water Productivity Analysis in R

**Rwapor** is a high-performance R package for streaming, analyzing, and
visualizing satellite data from [**FAO WaPOR
v3**](https://www.fao.org/in-action/remote-sensing-for-water-productivity/en/)
(Water Productivity Open-access portal) and [**ECMWF
AgERA5**](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators)
agro-meteorological indicators.

It provides both a complete **programmatic R API** and an **interactive
Shiny dashboard** with DuckDB analytics, tiled raster processing,
agronomic crop modeling (FAO-56), and spatial water stress anomaly
detection.

No programming experience? The [Installation](#installation) guide below
walks you through everything from scratch, and the [Quick
Start](#quick-start-launch-the-interactive-dashboard) section gets you
to a point-and-click dashboard with no coding at all.

------------------------------------------------------------------------

## Table of Contents

- [Key Features](#key-features)
- [Installation](#installation)
- [Quick Start: Launch the Interactive
  Dashboard](#quick-start-launch-the-interactive-dashboard)
- [Programmatic Workflows & Code
  Examples](#programmatic-workflows--code-examples)
- [Worked Examples by Crop/Use Case](#worked-examples-by-cropuse-case)
  - [Wheat: Single-Season Water
    Productivity](#wheat-single-season-water-productivity)
  - [Wheat: Multi-Season Water
    Productivity](#wheat-multi-season-water-productivity)
- [Supported Agricultural & Water
  Indicators](#supported-agricultural--water-indicators)
- [Data Catalog Overview](#data-catalog-overview)
- [Documentation & Vignettes](#documentation--vignettes)
- [Getting Help](#getting-help)
- [Citation](#citation)
- [License](#license)

------------------------------------------------------------------------

## Key Features

- 🚀 **Cloud-Optimized Streaming**: Direct window reading of
  Cloud-Optimized GeoTIFFs (COGs) via GDAL `/vsicurl/` with automatic
  HTTP range-request chunking and persistent 24h disk caching.
- 🌾 **FAO-56 Crop Water Modeling**: Automated calculation of Crop
  Evapotranspiration ($`ET_c`$), Water Adequacy, Transpiration Fraction
  ($`T/AETI`$), Green and Blue Water partitioning, and NPP-based crop
  yields ($`CWP`$ / $`BWP`$).
- 🛠️ **Custom Crop Parameters**: Full flexibility to define custom crop
  coefficients ($`K_c`$) and growth stages or selectively override FAO
  default profiles.
- 🌐 **Latitude-Aware Area Weighting**: Exact ellipsoidal pixel area
  calculation
  ([`wapor_pixel_area_ha()`](https://almutaz9000.github.io/Rwapor/reference/wapor_pixel_area_ha.md))
  ensuring latitude-unbiased class and AOI statistics on geographic
  (`EPSG:4326`) grids.
- 🧩 **Extensible Step Registry**: Modular indicator architecture
  allowing custom calculation steps to be registered and executed
  seamlessly.
- 🖥️ **Interactive Shiny Dashboard**: Point-and-click UI with
  interactive Leaflet map drawing, automatic Level 3 region detection,
  multi-season batch execution, and split-screen swipe map
  visualization.
- 📦 **Tiled Seasonal Engine**:
  [`wapor_run_seasonal_analysis_tiled()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis_tiled.md)
  windows sources onto square tiles, writes a versioned run manifest,
  and assembles GeoTIFF/COG products with a VRT. Peak memory is bounded
  by tile size, not the full AOI.
- ⚡ **High-Throughput Vector Extraction**: Fast polygon zonal
  statistics powered by `exactextractr` and embedded `DuckDB` storage
  for multi-year farm monitoring.

------------------------------------------------------------------------

## Installation

This guide assumes **no prior R experience**. Follow the steps in order
for your operating system. The whole process takes about 10–15 minutes.

> **Already have R and RStudio installed?** Skip to [Step 3: Install
> Rwapor](#step-3-install-rwapor).

### Step 1: Install R

R is the free statistical programming language Rwapor runs on.

**🪟 Windows**

1.  Go to
    [cran.r-project.org/bin/windows/base](https://cran.r-project.org/bin/windows/base/).
2.  Click the top link (**Download R-x.x.x for Windows**) and run the
    installer.
3.  Accept all the default options.

**🍎 macOS**

1.  Go to
    [cran.r-project.org/bin/macosx](https://cran.r-project.org/bin/macosx/).
2.  Download the `.pkg` installer that matches your Mac: **arm64** for
    Apple Silicon (M1/M2/M3/M4, most Macs sold since late 2020) or the
    Intel build for older machines. If unsure, check **Apple menu →
    About This Mac**.
3.  Open the downloaded `.pkg` file and follow the installer.

**🐧 Linux (Ubuntu/Debian)**

Open a terminal and run:

``` bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends r-base r-base-dev
```

For Fedora/RHEL/CentOS, use `sudo dnf install R` instead.

### Step 2: Install RStudio (strongly recommended)

RStudio is a free, beginner-friendly application for writing and running
R code — you’ll use it for everything below. It works identically on
Windows, macOS, and Linux.

1.  Go to
    [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop/).
2.  Download the installer for your operating system and run it,
    accepting the defaults.
3.  Open **RStudio** (not “R” — RStudio is the application you’ll
    actually use). You should see a window with a text-input pane called
    the **Console**. Every code block below is typed or pasted directly
    into that Console, followed by Enter.

### Step 3: Install Rwapor

Copy each code block below into the RStudio Console, one at a time,
pressing Enter after each. If a popup asks whether to update other
packages, choose **“All”** (or press a then Enter if asked in the
Console).

**3.1 — Install system geospatial libraries (Linux only)**

Rwapor depends on `terra` and `sf`, which need the GDAL, PROJ, and GEOS
geospatial libraries. Windows and macOS CRAN packages already include
these, so **Windows and macOS users can skip straight to 3.2**.

**🐧 Linux (Ubuntu/Debian)**

``` bash
sudo apt-get update
sudo apt-get install -y libgdal-dev libproj-dev libgeos-dev libudunits2-dev libssl-dev libcurl4-openssl-dev
```

(Fedora/RHEL:
`sudo dnf install gdal-devel proj-devel geos-devel udunits2-devel openssl-devel libcurl-devel`)

**3.2 — Install the required R packages**

In the RStudio Console:

``` r

install.packages(c(
  # Geospatial & API Core
  "terra", "sf", "httr2", "jsonlite", "dplyr", "purrr",
  "lubridate", "exactextractr", "memoise", "future", "future.apply", "digest",

  # Interactive Dashboard & Database
  "shiny", "bslib", "leaflet", "leaflet.extras", "leaflet.extras2",
  "shinyFiles", "shinyvalidate", "shinyjs", "shinyAce", "DT",
  "shinycssloaders", "promises", "duckdb", "DBI",

  # Visualization & Data
  "ggplot2", "tidyterra", "patchwork", "ggspatial", "viridisLite",
  "RColorBrewer", "arrow"
))
```

This step downloads and compiles several packages, so it can take a few
minutes the first time — that’s normal.

**3.3 — Install Rwapor from GitHub**

``` r

install.packages("remotes")  # if not already installed
remotes::install_github("almutaz9000/Rwapor", build_vignettes = TRUE)
```

### Step 4: Verify the installation

``` r

library(Rwapor)
wapor_variable_metadata("L1-AETI-D")
```

If this prints a table of variable metadata with no errors, Rwapor is
installed correctly. Jump to [Quick
Start](#quick-start-launch-the-interactive-dashboard) to launch the
point-and-click dashboard.

### Troubleshooting

“package ‘terra’/‘sf’ is not available” or a compilation error

- **Windows**: install
  [Rtools](https://cran.r-project.org/bin/windows/Rtools/) (matching
  your R version) so packages without a ready-made binary can be built
  from source, then retry Step 3.2.
- **macOS**: install Apple’s command-line developer tools by running
  `xcode-select --install` in the **Terminal** app, then retry.
- **Linux**: make sure Step 3.1 completed without errors — a missing
  `-dev`/`-devel` system library is the most common cause.

RStudio can’t find R / asks which R version to use

Restart RStudio after installing R (Step 1) so it detects the new
installation. On Windows/macOS this is automatic; on Linux, confirm with
`R --version` in a terminal that R is on your `PATH`.

Still stuck?

Open a [GitHub issue](https://github.com/almutaz9000/Rwapor/issues) with
your operating system, R version (`R.version.string` in the Console),
and the full error message — see [Getting Help](#getting-help).

------------------------------------------------------------------------

## Quick Start: Launch the Interactive Dashboard

Launch the full interactive point-and-click GUI directly from R:

``` r

library(Rwapor)

# Launch Shiny application
run_wapor()

# Or specify a custom default working directory for downloaded data
run_wapor(data_folder = "C:/WaPOR_Projects")
```

### Dashboard Modules:

1.  **📥 Download & Spatial Extraction**:
    - Draw custom AOI polygons or rectangles interactively on Leaflet
      maps.
    - Upload Shapefiles, GeoJSON, KML, or raster templates.
    - **Smart L3 Region Auto-Detection**: Intersects your AOI with all
      sub-national WaPOR Level 3 regions and selects overlapping schemes
      automatically.
    - Stream and download any of the 100+ WaPOR / AgERA5 variables
      across custom date ranges.
2.  **🌾 Seasonal Analysis & Crop Productivity**:
    - Configure single-season or multi-year batch runs with automatic
      calendar detection.
    - Choose from 12 standard FAO-56 crop profiles or customize
      parameters interactively.
    - Compute seasonal $`AETI`$, $`ET_c`$, Water Adequacy, Crop Water
      Productivity ($`CWP`$), and Biomass Water Productivity ($`BWP`$).
    - Export structured GeoTIFFs, dekadal stacks, and CSV summaries in a
      single click.
3.  **📈 Seasonal Comparison**:
    - Compare multi-year performance across seasons.
    - Assess spatial uniformity and inequality using Coefficient of
      Variation ($`CV`$) and Theil Index.
    - Interactive boxplots, violin plots, and bar summaries.
4.  **🛰️ High-Throughput Field Monitoring**:
    - Ingest plot boundaries and attribute tables into embedded DuckDB.
    - Fast SQL filtering and temporal anomaly detection ($`Z`$-score
      water stress).
5.  **🗺️ Split-Screen Map Visualizer**:
    - Side-by-side interactive swipe slider comparing rasters
      (e.g. $`AETI`$ vs. $`ET_c`$ or year-over-year changes).

------------------------------------------------------------------------

## Programmatic Workflows & Code Examples

### 1. Extract Time Series for Agricultural Fields

Download satellite data and extract polygon zonal statistics in
parallel:

``` r

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

------------------------------------------------------------------------

### 2. Custom Crop Factors & Details

Define custom crop coefficients without relying strictly on FAO
defaults:

``` r

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

------------------------------------------------------------------------

### 3. Run End-to-End Seasonal Analysis

``` r

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

------------------------------------------------------------------------

### 4. Spatial Anomaly & Water Stress Hotspots

Identify spatial water stress using temporal $`Z`$-scores and
statistical classification:

``` r

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

------------------------------------------------------------------------

## Worked Examples by Crop/Use Case

Full, applied case studies live in their own vignettes so this page
stays short — each one builds a crop mask, defines crop coefficients,
and runs the complete indicator chain through to Crop/Biomass Water
Productivity.

### Wheat: Single-Season Water Productivity

Build a wheat-only mask from a crop-type raster, define wheat’s $`K_c`$
profile, and run one season’s start-to-end analysis (AETI → ETc →
Adequacy → CWP/BWP):

``` r

wheat_mask   <- terra::classify(crop_type, rcl = matrix(c(11, 1), ncol = 2), othersNA = TRUE)
wheat_params <- wapor_custom_crop(base_crop = "Winter Wheat", class_value = 1L, crop_name = "Irrigated Winter Wheat")

config$period <- c("2023-10-15", "2024-05-31")  # this season's start/end
wheat_season  <- wapor_run_seasonal_analysis(config, wheat_params, rasters = list(crop_mask = wheat_mask))
```

**Full walkthrough**:
[`vignette("wheat-water-productivity")`](https://almutaz9000.github.io/Rwapor/articles/wheat-water-productivity.md)
— includes building the mask from either a classified raster or a
field-boundary vector, and exporting CWP/BWP rasters and summary tables.

### Wheat: Multi-Season Water Productivity

Same wheat mask and crop parameters, applied across several years by
passing a named list of season start/end pairs instead of one:

``` r

config$period <- list(
  "Wheat_Winter2021" = c("2020-10-15", "2021-05-31"),
  "Wheat_Winter2022" = c("2021-10-15", "2022-05-31"),
  "Wheat_Winter2023" = c("2022-10-15", "2023-05-31")
)
wheat_all_seasons <- wapor_run_seasonal_analysis(config, wheat_params, rasters = list(crop_mask = wheat_mask))
```

**Full walkthrough**:
[`vignette("wheat-water-productivity")`](https://almutaz9000.github.io/Rwapor/articles/wheat-water-productivity.md)
— covers the same multi-season pattern plus year-over-year CWP
comparison.

------------------------------------------------------------------------

## Supported Agricultural & Water Indicators

| Indicator | Code | Description | Formula / Method |
|----|----|----|----|
| **Seasonal AETI** | `agg_aeti` | Total seasonal actual evapotranspiration | $`\sum (AETI_i \times w_i \times \text{mult}_i)`$ (mm) |
| **Seasonal RET** | `agg_ret` | Total seasonal reference evapotranspiration | $`\sum (RET_i \times w_i \times \text{mult}_i)`$ (mm) |
| **Crop ET** | `etc` | Potential crop evapotranspiration | $`ET_c = RET \times K_c(\text{stage})`$ |
| **Water Adequacy** | `adequacy_etc` | Evapotranspiration deficit ratio | $`\text{Adequacy} = AETI / ET_c`$ |
| **Upper Adequacy** | `adequacy_p95` | Adequacy relative to 95th percentile target | $`\text{Adequacy}_{95} = AETI / P_{95}(AETI)`$ |
| **Beneficial Fraction** | `beneficial_fraction` | Ratio of transpiration to total AETI | $`BF = \text{Seasonal } T / \text{Seasonal } AETI`$ |
| **Effective Precipitation** | `peff` | Usable rainfall for crop consumption | USDA Soil Conservation Service monthly method |
| **Green / Blue Water** | `green_water`, `blue_water` | Partitioning of water consumption | Green: $`\min(AETI, P_{\text{eff}})`$, Blue: $`\max(0, AETI - P_{\text{eff}})`$ |
| **Biomass Water Productivity** | `cwp_bwp` | Biomass produced per unit of water consumed | $`BWP = \text{AGBP } (\text{kg/ha}) / (AETI \times 10)`$ ($`\text{kg/m}^3`$) |
| **Crop Water Productivity** | `cwp_bwp` | Crop yield produced per unit of water consumed | $`CWP = \text{Yield } (\text{kg/ha}) / (AETI \times 10)`$ ($`\text{kg/m}^3`$) |
| **Spatial Uniformity** | `cv_aeti`, `theil_aeti` | Spatial variation & inequality across field/scheme | Coefficient of Variation ($`CV`$) & Theil Disparity Index |

------------------------------------------------------------------------

## Data Catalog Overview

| Level | Spatial Resolution | Coverage | Key Variables |
|----|----|----|----|
| **Level 1** | ~300 m | Global | `L1-AETI-D`, `L1-E-D`, `L1-I-D`, `L1-NPP-D`, `L1-T-D` |
| **Level 1** | ~5 km | Global | `L1-PCP-D` |
| **Level 1** | ~30 km | Global | `L1-RET-D` |
| **Level 2** | ~100 m | Africa & Near East | `L2-AETI-D`, `L2-E-D`, `L2-I-D`, `L2-NPP-D`, `L2-T-D`, `L2-GBWP-A`, `L2-NBWP-A` |
| **Level 3** | ~20 m | 30+ Irrigation Schemes | `L3-AETI-D`, `L3-E-D`, `L3-I-D`, `L3-NPP-D`, `L3-T-D` (e.g. Awash, Bekaa, Gezira, Nile) |
| **AgERA5** | 0.1° (~10 km) | Global | `AGERA5-ET0-E`, `AGERA5-TMIN-E`, `AGERA5-TMAX-E`, `AGERA5-PRECIP-E` |

> `L1-PCP-D` (precipitation) and `L1-RET-D` (reference
> evapotranspiration) are auxiliary meteorological inputs sourced from
> coarser gridded/reanalysis products, not the 300 m
> PROBA-V/MODIS-derived imagery used for the other Level 1
> evapotranspiration and productivity variables. Resolutions above are
> the variables’ native source resolution, as recorded in the package’s
> own metadata (`inst/metadata/wapor_L1.json`), and apply across **all**
> temporal resolutions of a variable — dekadal (`-D`), monthly (`-M`),
> and annual (`-A`) products share the same native spatial resolution as
> their `-E`/`-D` counterpart shown here (e.g. `L1-AETI-M` and
> `L1-AETI-A` are still ~300 m, `L1-PCP-M` and `L1-PCP-A` are still ~5
> km).

Explore available variables inside R:

``` r

?WAPOR3_VARS   # WaPOR v3 metadata table
?AGERA5_VARS   # AgERA5 variables metadata table
?L3_REGIONS    # Sub-national Level 3 regions
```

------------------------------------------------------------------------

## Documentation & Vignettes

Browse locally after installation:

``` r

browseVignettes("Rwapor")
# or open a specific one:
vignette("getting-started", package = "Rwapor")
vignette("shiny-dashboard", package = "Rwapor")
vignette("advanced-analysis", package = "Rwapor")
vignette("wheat-water-productivity", package = "Rwapor")
vignette("data-catalog", package = "Rwapor")
```

If the [pkgdown site](https://almutaz9000.github.io/Rwapor/) is
published for this repository, the same vignettes are also available
online:

- **[Getting
  Started](https://almutaz9000.github.io/Rwapor/articles/getting-started.html)**:
  Comprehensive introductory tutorial.
- **[Shiny Dashboard
  Guide](https://almutaz9000.github.io/Rwapor/articles/shiny-dashboard.html)**:
  Step-by-step walkthrough of all dashboard features.
- **[Advanced Analysis &
  Monitoring](https://almutaz9000.github.io/Rwapor/articles/advanced-analysis.html)**:
  Tiled processing, DuckDB integration, and custom math extensions.
- **[Wheat Water Productivity (Worked
  Example)](https://almutaz9000.github.io/Rwapor/articles/wheat-water-productivity.html)**:
  Wheat mask + single-season and multi-season indicator chains through
  to CWP/BWP.
- **[Data
  Catalog](https://almutaz9000.github.io/Rwapor/articles/data-catalog.html)**:
  Complete variable definitions, scale factors, and units.

------------------------------------------------------------------------

## Getting Help

- **Bug reports & feature requests**: [open a GitHub
  issue](https://github.com/almutaz9000/Rwapor/issues).
- **Usage questions**: check the [vignettes](#documentation--vignettes)
  first — most workflows are covered end-to-end with runnable examples.
- **Function-level help**: every exported function has built-in
  documentation,
  e.g. [`?wapor_ts`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
  or
  [`?run_wapor`](https://almutaz9000.github.io/Rwapor/reference/run_wapor.md)
  from the R console.

------------------------------------------------------------------------

## Citation

If you use `Rwapor` in academic publications or operational water
accounting projects, please cite:

``` bibtex
@software{Rwapor,
  title  = {{Rwapor}: An {R} Package for Downloading and Analyzing {FAO WaPOR} Data},
  author = {Mohammed, Almutaz},
  year   = {2024},
  url    = {https://github.com/almutaz9000/Rwapor},
  note   = {R package version 1.0.0}
}
```

------------------------------------------------------------------------

## License

MIT License © 2024 Almutaz Mohammed / Food and Agriculture Organization
of the United Nations.
