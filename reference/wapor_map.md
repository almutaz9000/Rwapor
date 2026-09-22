# Download and Save a Raster Map

Downloads WaPOR or AgERA5 raster data for a specified region and time
period, optionally crops/masks to the region boundary, and saves as a
GeoTIFF file.

## Usage

``` r
wapor_map(
  region,
  variable,
  period,
  folder,
  filename = NULL,
  separate_files = FALSE,
  unit_conversion = NULL,
  seasonal = FALSE,
  mask = FALSE,
  parallel = FALSE,
  batching = TRUE,
  batch_size = 12L,
  l3_region = NULL,
  l3_mode = c("select", "mosaic_all"),
  partial = FALSE,
  cog = FALSE,
  on_batch_done = NULL,
  fun = NULL
)
```

## Arguments

- region:

  Region definition. One of:

  - Path to a vector file (shapefile, GeoJSON, GeoPackage)

  - L3 region code (3 uppercase letters, e.g., "AWA")

  - Numeric bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84

- variable:

  Character. Variable name following WaPOR/AgERA5 naming convention
  (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").

- period:

  Character vector or list. Date range as `c(start_date, end_date)` in
  "YYYY-MM-DD" format. Can also be a named or unnamed list of such
  vectors for multiple seasons.

- folder:

  Character. Output directory path. Will be created if needed.

- filename:

  Character. Optional output filename. If NULL, a default name is
  generated based on region and variable.

- separate_files:

  Logical. If `TRUE`, writes each time step as a separate GeoTIFF file
  instead of a multi-band stack. In seasonal mode, this saves
  seasonal-plan component rasters into
  `<folder>/<variable>_seasonal/components/`. Default is `FALSE`.

- unit_conversion:

  Character. Public unit-conversion mode. One of: `"unit_conversion"` or
  `"none"`. Default is `NULL`, which dynamically matches the variable
  behavior:

  - Dekadal daily-rate products are saved as dekadal totals

  - Monthly products remain monthly totals

  - `"none"` preserves raw API values without temporal conversion

- seasonal:

  Logical. If `TRUE`, downloads and aggregates data for the entire
  period into a single seasonal raster (sum/mean). Default is `FALSE`.

- mask:

  Logical. If `TRUE` and `region` is a vector file or polygon, the
  output raster is masked to the polygon boundary (pixels outside set to
  NA). If `FALSE` (default), only a rectangular crop to the bounding box
  is applied. Ignored for bounding box and L3 code regions.

- parallel:

  Logical. If `TRUE`, attempts to use `future.apply` for parallel
  processing. Default is `FALSE`.

- batching:

  Logical. If `TRUE` (default), processes data in chunks of
  `batch_size`. If `FALSE`, loads all layers at once.

- batch_size:

  Integer. Number of remote files loaded per chunk in non-seasonal mode.
  Lower values reduce memory pressure for long periods. Default is
  `12L`.

- l3_region:

  Optional L3 code to use for an L3 variable and spatial AOI.

- l3_mode:

  L3 coverage policy: `"select"` requires one selected L3 code when
  several regions intersect; `"mosaic_all"` writes source assets and a
  coverage-bearing mosaic for every intersecting L3 region.

- partial:

  Logical. If `TRUE`, incomplete temporal coverage is allowed and
  recorded. Default `FALSE` fails the request.

- cog:

  Logical. Write GeoTIFF outputs with
  [`wapor_write_cog()`](https://almutaz9000.github.io/Rwapor/reference/wapor_write_cog.md).
  Default `FALSE`.

- on_batch_done:

  Optional function called after each processed batch with
  `(batch_index, batch_count)`. Callback errors are ignored.

- fun:

  Optional seasonal summary function. `NULL` (default) preserves
  variable-aware weighted aggregation. Explicit `"sum"` remains weighted
  for accumulative products and is rejected for state/rate products;
  `"mean"`, `"std"`, `"min"`, `"max"`, and `"median"` use each
  overlapping source layer once without scaling partial layers.

## Value

Character path to the output GeoTIFF file, or in seasonal mode with
`separate_files = TRUE`, a list with `seasonal_aggregate` and
`seasonal_components`.

## Details

The function performs the following steps:

1.  Generates download URLs for the specified variable and period

2.  Streams raster data using GDAL virtual file system (/vsicurl/)

3.  Crops to bounding box or masks to vector geometry

4.  Applies temporal-resolution conversion when requested

5.  Writes output as a multi-band GeoTIFF (one band per time step) or
    separate files

## Examples

``` r
if (FALSE) { # \dontrun{
# Download dekadal ET for a bounding box (defaults to mm/dekad)
output_file <- wapor_map(
  region = c(35.0, 33.0, 36.0, 34.0),
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-01-31"),
  folder = "output"
)

# Preserve raw API values without temporal conversion
output_file <- wapor_map(
  region = c(35.0, 33.0, 36.0, 34.0),
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-01-31"),
  folder = "output",
  unit_conversion = "none"
)

# Download with parallel batching for long periods
library(future)
plan(multisession)
output_file <- wapor_map(
  region = c(35.0, 33.0, 36.0, 34.0),
  variable = "L1-AETI-D",
  period = c("2020-01-01", "2023-12-31"),
  folder = "output",
  parallel = TRUE,
  batch_size = 12
)
} # }
```
