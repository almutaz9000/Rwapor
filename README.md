# Rwapor

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/almutaz9000/Rwapor/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

**Rwapor** is an R package for downloading and processing data from [**FAO WaPOR**](https://www.fao.org/in-action/remote-sensing-for-water-productivity/en/) — the FAO portal for Water Productivity through Open access of Remotely sensed derived data — and [**AgERA5**](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators) climate data.

It provides a robust, parallelized workflow to download raster data, extract time series for regions or polygons, and calculate zonal statistics with high accuracy. **Rwapor** serves as an R alternative to the Python [`wapordl`](https://github.com/bertcoerver/wapordl) library, leveraging the power of [`terra`](https://rspatial.org/terra/), [`sf`](https://r-spatial.github.io/sf/), and [`exactextractr`](https://isciences.gitlab.io/exactextractr/).

---

## About WaPOR

[**WaPOR**](https://wapor.apps.fao.org/) is FAO's open-access portal that provides remote sensing data on water and biomass productivity across Africa and the Near East. The database covers a wide range of variables at multiple spatial resolutions (continental, national, and sub-national level) and temporal resolutions (dekadal, monthly, annual).

- 🌐 **WaPOR Portal**: <https://wapor.apps.fao.org/>
- 📖 **FAO WaPOR Overview**: <https://www.fao.org/in-action/remote-sensing-for-water-productivity/en/>
- 📊 **WaPOR Data Catalog**: <https://wapor.apps.fao.org/catalog/WAPOR_2/1>
- 📄 **WaPOR Documentation**: <https://www.fao.org/3/ca9564en/CA9564EN.pdf>

---

## Features

| Feature | Description |
|---|---|
| 🌍 **Universal Data Access** | Download any WaPOR or AgERA5 variable by name |
| 🔄 **Dynamic Metadata** | Automatically fetches metadata for all variables via the WaPOR API |
| ⚡ **Batching & Parallelism** | Parallel processing of large time series without memory crashes |
| 📐 **Accurate Zonal Statistics** | Pixel-weighted statistics via `exactextractr` for small or irregular polygons |
| 🖥️ **Interactive Dashboard** | Built-in Shiny app (`run_dashboard()`) for visual AOI selection and code generation |
| 🔁 **Unit Conversion** | Built-in support for converting units (e.g., `mm/dekad` → `mm/day`) on the fly |
| 💾 **Efficient Caching** | API responses are cached with `memoise` to minimize network traffic |

---

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

## Usage

### 1. Setup

```r
library(Rwapor)
library(future)

# Enable parallel processing for downloads
plan(multisession)
```

### 2. Download a Raster Map

Download a raster map for a specific region and time period. The package efficiently streams and subsets data using GDAL's virtual file system (`/vsicurl/`) — no need to download the entire global raster.

```r
region   <- c(35.75, 33.70, 35.82, 33.75)  # xmin, ymin, xmax, ymax
variable <- "L1-AETI-D"                     # Actual Evapotranspiration (Dekadal)
period   <- c("2021-01-01", "2021-01-10")
folder   <- "output_maps"

# Download as a single multi-band raster (default)
# Dekadal variables are automatically converted: mm/day -> mm/dekad
map_path <- wapor_map(region, variable, period, folder)

# Download multiple variables at once
vars  <- c("L1-AETI-D", "L1-NPP-D")
paths <- wapor_map(region, vars, period, folder)

# Download as separate files per time step
files <- wapor_map(region, variable, period, folder, separate_files = TRUE)

# Download raw daily rates (mm/day) without unit conversion
map_day <- wapor_map(region, variable, period, folder, unit_conversion = "day")

r <- terra::rast(map_path)
plot(r)
```

### 3. Extract Time Series (Zonal Statistics)

Extract time series for polygons defined in a GeoJSON or Shapefile, using pixel-weighted statistics for high accuracy on small fields.

```r
df <- wapor_ts(
  "path/to/polygons.geojson",
  "L1-AETI-D",
  period,
  identifier     = "id_column",
  unit_conversion = "day"    # Convert mm/dekad -> mm/day
)

head(df)
```

---

## Contributing

Contributions are welcome! Please feel free to open a [Pull Request](https://github.com/almutaz9000/Rwapor/pulls) or report issues on the [issue tracker](https://github.com/almutaz9000/Rwapor/issues).

## License

[MIT](LICENSE)
