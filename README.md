# Rwapor

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
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
✅ **Calculate water productivity indicators** (CWP, BWP, ETc, Adequacy)  
✅ **Use the interactive Shiny dashboard** for point-and-click workflows

## Installation

Install the development version from [GitHub](https://github.com/almutaz9000/Rwapor):

```r
# install.packages("devtools")
devtools::install_github("almutaz9000/Rwapor")
```

### Dependencies

If you encounter issues, ensure the required R packages are installed:

```r
install.packages(c(
  "httr2", "jsonlite", "terra", "sf", "dplyr", "purrr",
  "lubridate", "stringr", "exactextractr", "memoise",
  "furrr", "progressr", "future"
))
```

> **Note**: `sf` and `terra` require system-level geospatial libraries (GDAL, PROJ, GEOS). See the [`sf` installation guide](https://r-spatial.github.io/sf/#installing) for platform-specific instructions.

---

## Installation

### Step 1: Install Required Dependencies

Rwapor requires geospatial libraries. Install them first:

```r
install.packages(c(
  "terra", "sf", "httr2", "jsonlite", "dplyr", 
  "lubridate", "exactextractr", "shiny", "future"
))
```

> **Note**: `sf` and `terra` require system libraries (GDAL, PROJ, GEOS). See the [sf installation guide](https://r-spatial.github.io/sf/#installing) if you encounter issues.

### Step 2: Install Rwapor

```r
# Install from GitHub
# install.packages("devtools")
devtools::install_github("almutaz9000/Rwapor")
```

### Step 3: Load the Package

```r
library(Rwapor)
```

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
- Upload crop mask raster
- Upload season start/end rasters (Julian day of year)
- Configure crop parameters (Kc coefficients, growth stages)
- Or select from FAO-56 crop defaults (Wheat, Maize, Rice, etc.)
- Calculate seasonal indicators:
  - Seasonal AETI and RET
  - Crop evapotranspiration (ETc)
  - Water adequacy ratios
  - Crop/Biomass water productivity
  - NPP-based yield estimates
- Export results as rasters and CSV tables

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
  unit_conversion = "dekad",               # Keep as mm/dekad
  fun             = c("mean", "sum")       # Calculate mean and sum per polygon
)

# View results
head(df)
#   field_id       date    mean  sum
#   <chr>          <date>  <dbl> <dbl>
# 1 Field_001  2023-04-01  2.5   250
# 2 Field_001  2023-04-11  3.1   310
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
```

### Example 3: Seasonal Crop Water Productivity Analysis

Run a complete seasonal analysis for a specific crop:

```r
library(Rwapor)
library(terra)

# ===== STEP 1: Prepare Input Data =====

# Load your crop mask (1 = crop, 0 or NA = non-crop)
crop_mask <- rast("path/to/wheat_mask_2023.tif")

# Load season start/end rasters (Julian day of year, e.g., 91 = April 1)
season_start <- rast("path/to/planting_date.tif")    # DOY when planting occurred
season_end   <- rast("path/to/harvest_date.tif")     # DOY when harvest occurred

# ===== STEP 2: Download Required WaPOR Data =====

# Get bounding box from your crop mask
bbox <- as.vector(ext(crop_mask))

# Download AETI (Actual ET), RET (Reference ET), NPP (Productivity)
vars <- c("L2-AETI-D", "L2-RET-D", "L2-NPP-D")
wapor_map(bbox, vars, c("2023-01-01", "2023-12-31"), folder = "wapor_data")

# Download AgERA5 precipitation
wapor_map(bbox, "AgERA5-PCP-D", c("2023-01-01", "2023-12-31"), folder = "wapor_data")

# ===== STEP 3: Load Data as Raster Stacks =====

aeti_stack <- rast("wapor_data/L2-AETI-D.tif")   # 36 layers (dekads)
ret_stack  <- rast("wapor_data/L2-RET-D.tif")
npp_stack  <- rast("wapor_data/L2-NPP-D.tif")
pcp_stack  <- rast("wapor_data/AgERA5-PCP-D.tif")

# ===== STEP 4: Harmonize Inputs to Same Resolution/Extent =====

# Use AETI as the template
crop_mask_h    <- rwapor_harmonize_crop_mask(crop_mask, aeti_stack[[1]])
season_start_h <- rwapor_harmonize_to_template(season_start, aeti_stack[[1]])
season_end_h   <- rwapor_harmonize_to_template(season_end, aeti_stack[[1]])

# ===== STEP 5: Build Season Weights =====

# Create weights that account for pixel-specific growing seasons
weights <- rwapor_build_season_weights_dekad(
  start_date     = "2023-01-01",
  end_date       = "2023-12-31",
  season_start_r = season_start_h,
  season_end_r   = season_end_h,
  reference_year = 2023
)

# ===== STEP 6: Calculate Seasonal AETI and RET =====

seasonal_aeti <- rwapor_calc_seasonal_aeti_masked(
  aeti_stack, weights$weights, crop_mask_h
)

seasonal_ret <- rwapor_calc_seasonal_ret_masked(
  ret_stack, weights$weights, crop_mask_h
)

# ===== STEP 7: Calculate Crop Water Requirement (ETc) =====

# Get FAO-56 default parameters for your crop
crop_params <- rwapor_get_crop_defaults("Winter Wheat")

# Build daily Kc curve
kc_curve <- rwapor_build_daily_kc(
  Lini = crop_params$Lini,
  Ldev = crop_params$Ldev,
  Lmid = crop_params$Lmid,
  Llate = crop_params$Llate,
  Kcini = crop_params$Kcini,
  Kcmid = crop_params$Kcmid,
  Kcend = crop_params$Kcend
)

# Calculate seasonal ETc
seasonal_etc <- rwapor_calc_seasonal_etc_incremental(
  ret_stack, kc_curve, weights$weights, crop_mask_h, "2023-01-01"
)

# ===== STEP 8: Calculate Water Productivity =====

# Aggregate NPP to seasonal total
seasonal_npp <- rwapor_apply_masked_sum(npp_stack, weights$weights, crop_mask_h)

# Biomass Water Productivity (kg/m³)
bwp <- rwapor_calc_bwp(seasonal_npp, seasonal_aeti)

# Crop Water Productivity with yield estimation (kg/m³)
cwp <- rwapor_calc_cwp(
  seasonal_npp, seasonal_aeti,
  harvest_index = crop_params$HI,
  dry_matter    = crop_params$dm
)

# ===== STEP 9: Calculate Adequacy =====

adequacy <- rwapor_calc_adequacy_etc(seasonal_aeti, seasonal_etc)

# ===== STEP 10: Export Results =====

writeRaster(seasonal_aeti, "output/seasonal_aeti_2023.tif", overwrite = TRUE)
writeRaster(seasonal_etc,  "output/seasonal_etc_2023.tif",  overwrite = TRUE)
writeRaster(bwp,           "output/bwp_2023.tif",           overwrite = TRUE)
writeRaster(cwp,           "output/cwp_2023.tif",           overwrite = TRUE)
writeRaster(adequacy,      "output/adequacy_2023.tif",      overwrite = TRUE)

# Extract statistics for each crop field
fields <- vect("path/to/crop_fields.geojson")
stats <- extract(c(seasonal_aeti, seasonal_etc, bwp, cwp, adequacy), 
                 fields, fun = "mean", na.rm = TRUE)
write.csv(stats, "output/field_statistics.csv", row.names = FALSE)

print("✅ Seasonal analysis complete!")
```

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
- **Function References**: Type `?function_name` in R (e.g., `?wapor_ts`)

### Key Functions

| Function | Purpose |
|----------|---------|
| `run_wapor()` | Launch interactive Shiny dashboard |
| `wapor_ts()` | Download time-series for polygons |
| `wapor_map()` | Download raster maps for a region |
| `rwapor_calc_seasonal_aeti_masked()` | Calculate seasonal ET |
| `rwapor_calc_etc_dekad()` | Calculate crop water requirement |
| `rwapor_calc_bwp()` | Calculate biomass water productivity |
| `rwapor_calc_cwp()` | Calculate crop water productivity |
| `rwapor_get_crop_defaults()` | Get FAO-56 crop parameters |

---

## 🤝 Contributing

Contributions are welcome! Please:
- Report bugs via [GitHub Issues](https://github.com/almutaz9000/Rwapor/issues)
- Submit improvements via [Pull Requests](https://github.com/almutaz9000/Rwapor/pulls)
- Follow the [CLAUDE.md](CLAUDE.md) development guidelines

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
