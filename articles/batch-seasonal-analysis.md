# Batch Seasonal Analysis, Smart-Linking, and Multi-Crop Modeling

## Introduction

Agricultural water management rarely deals with a single isolated
season. Water accounting studies, irrigation scheme audits, and yield
forecasting projects typically require analyzing **multiple consecutive
years**, **rotational cropping seasons** (e.g., Winter Wheat followed by
Summer Maize), and **spatially variable planting/harvesting dates**
across thousands of fields.

The **Rwapor** package provides a high-throughput **Batch Seasonal
Analysis Engine** with **Smart-Linking**, allowing users to execute
multi-year, multi-crop analyses seamlessly through both programmatic R
scripts and the interactive Shiny Web GIS dashboard
([`run_wapor()`](https://almutaz9000.github.io/Rwapor/reference/run_wapor.md)).

------------------------------------------------------------------------

## 1. Batch Architecture & Smart-Linking Mechanics

When running in batch mode, `Rwapor` executes an automated extraction
loop over a list of named seasons. Rather than requiring users to
manually crop, resample, and pass individual rasters for every season,
the engine activates **Smart-Linking**:

    Project Directory
    ├── seasonal_masks/
    │   ├── Winter_2021_mask.tif    <── Automatically matched for "Winter_2021"
    │   ├── Winter_2021_start.tif
    │   ├── Winter_2021_end.tif
    │   ├── Summer_2022_mask.tif    <── Automatically matched for "Summer_2022"
    │   ├── Summer_2022_start.tif
    │   └── Summer_2022_end.tif
    └── ...

### Supported Raster Naming Conventions

For each season label (e.g. `Winter_2021`), the engine automatically
looks inside the project root directory and the `seasonal_masks/`
subfolder. Both **suffix** and **prefix** naming conventions are
supported:

| Layer Type | Suffix Convention (Default) | Prefix Convention (Alternative) | Value Description |
|:---|:---|:---|:---|
| **Crop Mask** | `<Label>_mask.tif` | `mask_<Label>.tif` | Integer crop class codes (`1` = Wheat, `2` = Maize; `0` or `NA` = non-crop). |
| **Season Start (SOS)** | `<Label>_start.tif` or `<Label>_sos.tif` | `start_<Label>.tif` or `sos_<Label>.tif` | Pixel-wise planting Day of Year (DOY $`1`$–$`366`$) or continuous Julian days. |
| **Season End (EOS)** | `<Label>_end.tif` or `<Label>_eos.tif` | `end_<Label>.tif` or `eos_<Label>.tif` | Pixel-wise harvesting Day of Year (DOY $`1`$–$`366`$) or continuous Julian days. |

> \[!NOTE\] **Cross-Year Seasons**: In temperate and Mediterranean
> climates, winter crops are often planted in October/November (e.g. DOY
> 305) and harvested in April/May of the following calendar year
> (e.g. DOY 120). Rwapor automatically detects whenever
> $`\text{EOS} < \text{SOS}`$ pixel-wise and shifts the continuous
> Julian day reference by $`365`$ (or $`366`$ in leap years). You do not
> need to manually normalize cross-year dates.

------------------------------------------------------------------------

## 2. Case 1: Pure Date-Driven Multi-Year Monitoring

For regional or basin-scale analyses where cropping calendars are
relatively uniform or where satellite phenology rasters are not
available, you can run batch mode with fixed date windows.

### Step-by-Step Script

``` r

library(Rwapor)

# 1. Define multi-season schedule as a named list of date pairs (YYYY-MM-DD)
seasons <- list(
  "Winter_2021" = c("2020-11-01", "2021-05-31"),
  "Winter_2022" = c("2021-11-01", "2022-05-31"),
  "Winter_2023" = c("2022-11-01", "2023-05-31")
)

# 2. Configure analysis settings
config <- list(
  period      = seasons,      # Pass the named list to activate batch mode
  aeti_var    = "L2-AETI-D",
  ret_var     = "L1-RET-D",
  precip_var  = "L1-PCP-D",
  npp_var     = "L2-NPP-D",
  t_var       = "L2-T-D",
  data_source = "local",
  folder      = "wapor_data", # Directory containing downloaded dekadal rasters
  indicators  = c("agg_aeti", "agg_ret", "etc", "adequacy_etc", "agg_pcp", "cwp_bwp")
)

# 3. Define crop parameters (applied to all AOI pixels in single-crop mode)
crop_wheat <- wapor_custom_crop(
  base_crop   = "Winter Wheat",
  class_value = 1L,
  kc_mid      = 1.15,
  HI          = 0.45
)

# 4. Execute batch run
batch_results <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = crop_wheat,
  rasters     = list() # No masks: entire area treated as class 1
)

# 5. Access results per season
names(batch_results)
# [1] "Winter_2021" "Winter_2022" "Winter_2023"

# Example: Inspect Winter 2022 AETI raster and summary metrics
w22_aeti <- batch_results$Winter_2022$seasonal_aeti$raster
w22_etc  <- batch_results$Winter_2022$seasonal_etc
print(batch_results$Winter_2022$cwp)
```

------------------------------------------------------------------------

## 3. Case 2: Multi-Crop Batch Analysis with Auto-Linked Season Rasters

In complex irrigation schemes, different crops grow simultaneously
across distinct parcels with different crop coefficients ($`K_c`$),
stage lengths, and planting schedules.

### File Organization

Place your season-specific rasters in your project folder’s
`seasonal_masks/` subfolder:

``` text
my_project/
  seasonal_masks/
    Season_2021_mask.tif     # Multi-class: 1 = Wheat, 2 = Sugarbeet, 3 = Alfalfa
    Season_2021_start.tif    # Pixel-wise SOS (DOY)
    Season_2021_end.tif      # Pixel-wise EOS (DOY)
    Season_2022_mask.tif
    Season_2022_start.tif
    Season_2022_end.tif
```

### Multi-Crop Parameter Table Setup

``` r

library(Rwapor)

# Define parameters for each crop class matching the mask integer values
wheat_params <- wapor_custom_crop(
  base_crop   = "Winter Wheat",
  class_value = 1L,
  crop_name   = "Durum Wheat",
  kc_mid      = 1.20,
  HI          = 0.48
)

sugarbeet_params <- wapor_custom_crop(
  base_crop   = "Sugarbeet",
  class_value = 2L,
  crop_name   = "Sugar Beet",
  kc_mid      = 1.20,
  HI          = 0.80
)

alfalfa_params <- wapor_custom_crop(
  base_crop   = "Alfalfa",
  class_value = 3L,
  crop_name   = "Alfalfa Hay",
  kc_mid      = 1.20,
  HI          = 0.90
)

# Combine into a single validated crop_params table
multi_crop_params <- wapor_combine_crop_params(
  wheat_params,
  sugarbeet_params,
  alfalfa_params
)
```

### Running Batch Analysis with Auto-Linking

``` r

config <- list(
  period      = list(
    "Season_2021" = c("2020-10-01", "2021-06-30"),
    "Season_2022" = c("2021-10-01", "2022-06-30")
  ),
  aeti_var    = "L2-AETI-D",
  ret_var     = "L1-RET-D",
  precip_var  = "L1-PCP-D",
  npp_var     = "L2-NPP-D",
  data_source = "local",
  folder      = "my_project",
  output_dir  = "my_project/analysis_outputs",
  indicators  = c("agg_aeti", "etc", "adequacy_etc", "agg_pcp", "cwp_bwp")
)

# The engine discovers Season_2021_* and Season_2022_* rasters in seasonal_masks/
results <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = multi_crop_params,
  rasters     = list() # Smart-linking automatically resolves rasters per season
)

# Export all outputs into structured per-season directories
wapor_export_analysis_outputs(
  results      = results,
  folder       = "my_project/analysis_outputs",
  indicators   = config$indicators,
  include_seasonal_tables = TRUE
)
```

### Resulting Output Structure

``` text
my_project/analysis_outputs/
├── Season_2021/
│   ├── seasonal_rasters/
│   │   ├── Season_2021_seasonal_aeti.tif
│   │   ├── Season_2021_seasonal_ret.tif
│   │   ├── Season_2021_seasonal_etc.tif
│   │   ├── Season_2021_adequacy_etc.tif
│   │   └── Season_2021_etc_class_1.tif
│   └── seasonal_tables/
│       └── Season_2021_summary_metrics.csv
└── Season_2022/
    ├── seasonal_rasters/
    └── seasonal_tables/
```

------------------------------------------------------------------------

## 4. Case 3: Generating Season Rasters from Field Boundaries & Planting Tables

If you have vector boundaries of agricultural parcels and a spreadsheet
of planting/harvesting dates from farmer surveys or farm management
software, `Rwapor` can automatically build all the required GeoTIFF
masks.

### Required Input Format

1.  **Vector File** (`parcels.geojson` or `parcels.shp`): Contains
    polygon boundaries for each field, with an ID column
    (e.g. `field_id`).
2.  **CSV Table** (`crop_calendar.csv`): Contains recorded dates and
    crop types per field:

| id    | season_name | start_date | end_date   | crop_type |
|:------|:------------|:-----------|:-----------|:----------|
| P-101 | Winter_2022 | 2021-11-05 | 2022-05-20 | Wheat     |
| P-102 | Winter_2022 | 2021-11-12 | 2022-05-28 | Wheat     |
| P-103 | Winter_2022 | 2021-10-25 | 2022-06-10 | Sugarbeet |
| P-101 | Summer_2022 | 2022-06-15 | 2022-09-30 | Maize     |
| P-102 | Summer_2022 | 2022-06-20 | 2022-10-05 | Maize     |

### Generating Rasters Programmatically

``` r

library(Rwapor)

# Load a template raster (e.g., an existing AETI or RET layer for grid alignment)
template_raster <- terra::rast("my_project/L2-AETI-D/WAPOR-3.L2-AETI-D.2022-01-01.tif")

# Generate all seasonal start, end, and crop mask rasters
mask_registry <- wapor_vector_to_season_rasters(
  vector_path   = "parcels.geojson",
  csv_path      = "crop_calendar.csv",
  template_r    = template_raster,
  vector_id_col = "field_id",
  csv_id_col    = "id",
  season_col    = "season_name",
  start_col     = "start_date",
  end_col       = "end_date",
  crop_col      = "crop_type",
  output_folder = "my_project/seasonal_masks"
)

print(mask_registry)
#        season                         start_raster                           end_raster                           crop_mask
# 1 Winter_2022 .../seasonal_masks/Winter_2022_start.tif .../seasonal_masks/Winter_2022_end.tif .../seasonal_masks/Winter_2022_mask.tif
# 2 Summer_2022 .../seasonal_masks/Summer_2022_start.tif .../seasonal_masks/Summer_2022_end.tif .../seasonal_masks/Summer_2022_mask.tif
```

Once generated, these files are immediately recognized by
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
in batch mode!

------------------------------------------------------------------------

## 5. Case 4: Interactive Batch Analysis in the Shiny Dashboard

You can execute the entire batch workflow without writing a line of code
using the **Rwapor Shiny Dashboard**.

1.  **Launch the App**:

    ``` r

    Rwapor::run_wapor()
    ```

2.  **Navigate to the Analysis Tab**:

    - In the sidebar, select your project folder.

3.  **Step 1: Enable Batch Mode**:

    - Check the **Batch Mode** checkbox.

    - Click the **`[?] Batch Guide`** link at any time to review syntax
      and file conventions.

    - Enter your seasons in the text area (one per line, format:
      `Label, Start, End`):

      ``` text
      Winter_2021, 2020-11-01, 2021-05-31
      Summer_2022, 2022-06-01, 2022-09-30
      Winter_2022, 2021-11-01, 2022-05-31
      ```

    - *Tip*: If you already downloaded seasonal data in the Download
      tab, click **`Detect`** to auto-scan your folder and fill the
      table automatically, or **`Copy DL`** to import the periods
      defined during download.

4.  **Step 2: Masking & Timing**:

    - If you have field boundary polygons and a date CSV, check
      **`Generate from Vector & CSV`**, upload your files, map your
      columns, and click **`Update Masks`**.

5.  **Step 3: Crop Specs**:

    - Review and customize FAO-56 crop parameters ($`K_c`$, Stage
      lengths, Harvest Index) for each detected class.

6.  **Step 4: Indicator Selection**:

    - Use the grouped checklist or click **`[Core]`** or **`[All]`** to
      select your target indicators.

7.  **Run & Review**:

    - Click **`Run Analysis`**. The progress bar tracks execution across
      all seasons.
    - View results in the **Seasonal Indicators** unified table and
      switch to the **Visualisation** tab to explore spatial rasters.
