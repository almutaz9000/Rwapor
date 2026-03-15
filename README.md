# Rwapor

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Rwapor** is an R package designed to download and process [WaPOR](https://wapor.apps.fao.org/) (Water Productivity through Open access of Remotely sensed derived data) and [AgERA5](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators) data. It provides a robust, parallelized workflow to download raster data, extract time series for regions or polygons, and calculate zonal statistics with high accuracy.

It serves as an R alternative to the Python `wapordl` library, leveraging the power of `terra`, `sf`, and `exactextractr`.

## Features

- **Universal Data Access**: Download any WaPOR or AgERA5 variable.
    - **Dynamic Metadata**: Automatically fetches metadata for variables not hardcoded in the package.
    - **Batching & Parallelism**: Optional batching of URLs and parallel processing of chunks for massive time series without memory crashes.
- **Improved Windows Support**: Automatic detection and correction of `PROJ_LIB` conflicts (e.g., from PostGIS or ArcGIS).
- **Accurate Zonal Statistics**: Uses `exactextractr` to calculate weighted statistics for polygons, ensuring accuracy even for small fields that don't cover full pixels.
- **Interactive UI**: Built-in Shiny Dashboard (`run_dashboard()`) for visual AOI selection and code generation.
- **Unit Conversion**: Built-in support for converting units (e.g., `mm/dekad` to `mm/day`) on the fly.
- **Efficient**: Caches API responses using `memoise` to minimize network traffic.

## Available Data

`Rwapor` provides access to a wide range of geospatial datasets from both WaPOR and AgERA5. For a complete list of variables, resolutions, scale factors, and units, please refer to the **Data Catalog** documentation:

```r
# View the data catalog in your browser
vignette("data-catalog", package = "Rwapor")
```

The catalog includes:
- **WaPOR (v3)**: Level 1 (Global), Level 2 (National), and Level 3 (Sub-national) variables including AETI, NPP, and Precipitation.
- **AgERA5**: Global agro-meteorological indicators like Reference ET, Temperature, and Wind Speed.

## Installation

You can install the development version of Rwapor from [GitHub](https://github.com/almutaz9000/Rwapor) with:

```r
# install.packages("devtools")
devtools::install_github("almutaz9000/Rwapor")
```

### Dependencies
If you encounter issues, ensure you have the necessary system dependecies (especially for `sf` and `terra`) and R packages installed:

```r
install.packages(c("httr2", "jsonlite", "terra", "sf", "dplyr", "purrr", "lubridate", "stringr", "exactextractr", "memoise", "furrr", "progressr", "future"))
```

## Usage

### 1. Setup
```r
library(Rwapor)
library(future)

# Enable parallel processing for downloads
plan(multisession)
```

### 2. Download a Map
Download a raster map for a specific region and period. The package efficiently streams and subsets data using GDAL's virtual file system (`/vsicurl/`) without downloading the entire global raster.

```r
region <- c(35.75, 33.70, 35.82, 33.75) # Bounding box: xmin, ymin, xmax, ymax
variable <- "L1-AETI-D" # Actual Evapotranspiration (Dekadal)
period <- c("2021-01-01", "2021-01-10")
folder <- "output_maps"

# 1. Download as a single multi-band raster (default)
# By default for Dekadal variables, this converts mm/day -> mm/dekad
map_path <- wapor_map(region, variable, period, folder)

# 2. Download multiple variables at once
# Creates folders: output_maps/L1-AETI-D and output_maps/L1-NPP-D
vars <- c("L1-AETI-D", "L1-NPP-D")
paths <- wapor_map(region, vars, period, folder)

# 3. Download as separate files per time step
files <- wapor_map(region, variable, period, folder, separate_files = TRUE)

# 4. Download raw daily rates (mm/day) without conversion to dekadal
map_day <- wapor_map(region, variable, period, folder, unit_conversion = "day")

r <- terra::rast(map_path)
plot(r)
```

### 3. Extract Time Series (Zonal Stats)
Extract time series for polygons defined in a GeoJSON or Shapefile.

```r
# Supports robust weighted stats for small polygons
df <- wapor_ts("path/to/polygons.geojson", "L1-AETI-D", period, 
               identifier="id_column", 
               unit_conversion = "day")  # Convert mm/dekad -> mm/day

head(df)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Issues

If you encounter a bug, please report it at: https://github.com/almutaz9000/Rwapor/issues

## License

MIT
