# Interactive Web GIS & Agricultural Analytics with the Rwapor Shiny Dashboard

## Introduction

The **Rwapor** package includes a full-featured, reactive Shiny Web GIS
dashboard designed for point-and-click satellite data retrieval, FAO-56
crop water productivity modeling, seasonal comparisons, and
high-throughput farm monitoring.

------------------------------------------------------------------------

## 1. Launching the Dashboard

Launch the dashboard directly from your R console:

``` r

library(Rwapor)

# Launch default dashboard
run_wapor()

# Or specify a custom data directory
run_wapor(data_folder = "C:/WaPOR_Projects")
```

The application automatically opens in your default web browser.

------------------------------------------------------------------------

## 2. Dashboard Architecture & Modules

    ┌────────────────────────────────────────────────────────────────────────┐
    │                        Rwapor Shiny Dashboard                          │
    ├──────────────┬──────────────┬──────────────────────────┬───────────────┤
    │ 📥 Download  │ 🌾 Seasonal  │ 📊 Visualisation         │ 🛰️ Field     │
    │  & Extraction│   Analysis   │  & Time Series Analysis  │   Monitoring  │
    └──────────────┴──────────────┴──────────────────────────┴───────────────┘

------------------------------------------------------------------------

## 3. Module Walkthroughs

### 📥 3.1 Download & Spatial Extraction Tab

1.  **Project Folder**: Select or browse for your project workspace. All
    downloaded rasters and metadata are organized hierarchically by
    variable and period.
2.  **Interactive Area of Interest (AOI)**:
    - **Draw on Map**: Draw rectangles or arbitrary polygons directly on
      the Leaflet map.
    - **Upload Spatial File**: Ingest Shapefiles (`.shp` in `.zip`),
      GeoJSON, KML, GeoPackage (`.gpkg`), or GeoTIFF templates.
    - **Smart L3 Region Auto-Detection**: When Level 3 variables are
      selected, the app intersects your AOI geometry with all 30+
      sub-national WaPOR Level 3 irrigation schemes in Africa and the
      Near East, filtering and auto-selecting the appropriate scheme.
3.  **Variable Selection & Date Ranges**:
    - Choose from 100+ WaPOR v3 and AgERA5 variables across Level 1
      (~300m), Level 2 (~100m), and Level 3 (~20m).
    - Set custom start and end dates.
4.  **Execution**:
    - Stream raster data directly into local GeoTIFFs or extract polygon
      zonal time series in parallel.

------------------------------------------------------------------------

### 🌾 3.2 Seasonal Analysis & Crop Water Productivity Hub

The Seasonal Analysis module provides a structured 4-step wizard for
configuring, parameterizing, and computing agricultural water
performance metrics:

1.  **Step 1: Seasonal Calendar & Batch Mode**:
    - **Single Season vs. Batch Mode**: Toggle between single-season
      dates or a multi-season schedule (`Label, Start, End`).
    - **Smart Folder Detection (`Detect`)**: Auto-scans downloaded
      dekadal rasters in your project directory to deduce available time
      ranges.
    - **Download Sync (`Copy DL`)**: Instantly imports the temporal
      periods configured in the Download tab.
    - **Interactive Batch Guide (`[?] Batch Guide`)**: Built-in modal
      explaining batch syntax, directory layouts, and auto-linking
      naming conventions.
2.  **Step 2: Spatial Masks & Timing**:
    - **Crop Masking**: Support for single-crop AOIs or multi-crop
      categorical masks (`1` = Wheat, `2` = Maize, etc.).
    - **Phenological Timing (SOS/EOS)**: Supply pixel-wise Day of Year
      (DOY) planting and harvesting rasters. Cross-year seasons
      ($`\text{EOS} < \text{SOS}`$) are automatically shifted by 365/366
      days.
    - **Custom Vector & CSV Generation**: Collapsible panel to build all
      required seasonal rasters from parcel polygons (`.geojson`/`.shp`)
      and survey planting spreadsheets (`.csv`) via
      [`wapor_vector_to_season_rasters()`](https://almutaz9000.github.io/Rwapor/reference/wapor_vector_to_season_rasters.md).
    - **Latitude-Aware Area Weighting**: Exact ellipsoidal pixel surface
      area weighting (`cos(lat)`) for distortion-free volumetric
      aggregations.
3.  **Step 3: Crop Parameterization**:
    - **FAO-56 Presets**: Choose from 12 pre-configured crops (Winter
      Wheat, Sorghum, Sugarbeet, Maize, Rice, Cotton, Potato, Soybean,
      Sunflower, Barley, Alfalfa, Sugarcane).
    - **Multi-Crop Table Editor**: Customize crop coefficients
      ($`K_{c,\text{ini}}, K_{c,\text{mid}}, K_{c,\text{end}}`$), stage
      lengths, Harvest Index ($`HI`$), and Moisture Content ($`MC`$) per
      crop class.
4.  **Step 4: Thematic Indicator Selection**: Indicators are organized
    into four logical thematic fieldsets with quick-select controls
    (**`[Core]`**, **`[All]`**, **`[Clear]`**):
    - **Evapotranspiration & Consumptive Use**: Seasonal $`AETI`$,
      Reference $`RET`$, Transpiration $`T`$, and Crop
      Evapotranspiration ($`ET_c`$, including class-level rasters).
    - **Agricultural Water Adequacy**: Water Adequacy vs. RET
      ($`AETI/RET`$), Adequacy vs. ETc ($`AETI/ET_c`$), and Relative
      Water Deficit ($`1 - AETI/ET_c`$).
    - **Water Accounting & Precipitation**: Seasonal Precipitation
      ($`PCP`$), Effective Precipitation ($`P_{eff}`$ via USDA SCS or
      FAO methods), and Net Irrigation Requirement
      ($`NIR = \max(0, ET_c - P_{eff})`$).
    - **Biomass Productivity & Uniformity**: Seasonal $`NPP`$, Crop
      Water Productivity ($`CWP`$), Biomass Water Productivity
      ($`BWP`$), Beneficial Transpiration Fraction ($`T/AETI`$), and
      Uniformity ($`CV`$, Theil Disparity Index).
    - **Dynamic L3 Coverage Policy**: Conditionally rendered only when
      sub-national Level 3 datasets are selected.
5.  **Execution & Export**:
    - Real-time progress bar tracking multi-season execution.
    - Unified summary metrics table and one-click export of GeoTIFF
      rasters and CSV tables.

> \[!TIP\] For advanced scripting and multi-crop batch workflows, see
> the dedicated **[Batch Seasonal Analysis
> Tutorial](https://almutaz9000.github.io/Rwapor/articles/batch-seasonal-analysis.md)**.

------------------------------------------------------------------------

### 📊 3.3 Visualisation & Time Series Hub

The unified Visualisation tab combines spatial raster exploration,
side-by-side comparison, and field-level time series diagnostics:

- **Single Map Visualizer**: Interactive Leaflet map with real-time
  cursor hover values, coordinate readouts, and perceptually uniform
  color palettes (Viridis, Turbo, Spectral, Plasma).
- **Dual Map Split-Screen Swipe Slider**: Compare two rasters
  side-by-side (e.g. $`AETI`$ vs. $`ET_c`$, or 2021 vs. 2022) with a
  draggable swipe bar to pinpoint localized water stress hotspots.
- **Zonal Time Series & Phenology**: Extract and plot multi-field time
  series trajectories, compute running means, and decompose seasonal
  cycles using interactive Plotly graphics.
- **Seasonal Comparison & Anomaly Distribution**: Multi-year violin and
  box plots comparing water productivity across cropping seasons and
  field parcels.

------------------------------------------------------------------------

### 🛰️ 3.4 High-Throughput Field Monitoring (DuckDB)

- **Parcels Ingestion**: Import agricultural field polygons and crop
  rotation records.
- **Embedded DuckDB Engine**: Synchronize WaPOR satellite data with a
  local embedded analytical database.
- **Field Diagnostics**: Run interactive SQL queries, temporal water
  stress anomaly checks, and border pixel filtering to ensure pure crop
  canopy signals.
