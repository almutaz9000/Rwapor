# Rwapor

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Rwapor** is an R package designed to download and process [WaPOR](https://wapor.apps.fao.org/) (Water Productivity through Open access of Remotely sensed derived data) and [AgERA5](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators) data. It provides a robust, parallelized workflow to download raster data, extract time series for regions or polygons, and calculate zonal statistics with high accuracy.

It serves as an R alternative to the Python `wapordl` library, leveraging the power of `terra`, `sf`, and `exactextractr`.

## Features

- **Universal Data Access**: Download any WaPOR or AgERA5 variable.
    - **Dynamic Metadata**: Automatically fetches metadata for variables not hardcoded in the package.
    - **Parallel Downloads**: Optionally download files concurrently to a local cache for speed and robustness (`download_locally = TRUE`).
- **Accurate Zonal Statistics**: Uses `exactextractr` to calculate weighted statistics for polygons, ensuring accuracy even for small fields that don't cover full pixels.
- **Unit Conversion**: Built-in support for converting units (e.g., `mm/dekad` to `mm/day`) on the fly.
- **Efficient**: Caches API responses using `memoise` to minimize network traffic.

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
# Filename: bb_WAPOR-3.L1-AETI-D.2021-01-01_2021-01-10.tif
map_path <- wapor_map(region, variable, period, folder)

# 2. Download as separate files per time step
# Filenames: bb_WAPOR-3.L1-AETI-D.2021-01-01.tif, ...
files <- wapor_map(region, variable, period, folder, separate_files = TRUE)

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
