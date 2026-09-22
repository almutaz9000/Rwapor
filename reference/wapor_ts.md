# Extract Time Series with Zonal Statistics

Downloads WaPOR or AgERA5 raster data and extracts time series of zonal
statistics (mean, min, max) for specified polygons or regions.

## Usage

``` r
wapor_ts(
  region,
  variable,
  period,
  identifier = NULL,
  unit_conversion = NULL,
  seasonal = FALSE,
  download_locally = FALSE,
  parallel = FALSE,
  batching = TRUE,
  batch_size = 12L,
  l3_region = NULL,
  l3_mode = c("select", "mosaic_all"),
  partial = FALSE,
  on_batch_done = NULL,
  fun = NULL
)
```

## Arguments

- region:

  Region definition. One of:

  - Path to a vector file (shapefile, GeoJSON, GeoPackage) containing
    polygons

  - L3 region code (3 uppercase letters, e.g., "AWA")

  - Numeric bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84

- variable:

  Character. Variable name following WaPOR/AgERA5 naming convention
  (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").

- period:

  Character vector or list. Date range as `c(start_date, end_date)` in
  "YYYY-MM-DD" format. Can also be a named or unnamed list of such
  vectors for multiple seasons.

- identifier:

  Character. Optional column name in vector file to identify polygons in
  output. If NULL, numeric IDs are used.

- unit_conversion:

  Character. Public unit-conversion mode. One of: `"unit_conversion"` or
  `"none"`. Default is `NULL`, which dynamically matches the variable
  behavior:

  - Dekadal daily-rate products are returned as dekadal totals

  - Monthly products remain monthly totals

  - `"none"` preserves raw API values without temporal conversion

- seasonal:

  Logical. If `TRUE`, calculates a single seasonal aggregate (sum/mean)
  for each polygon over the entire period. Default is `FALSE`.

- download_locally:

  Logical. Deprecated and ignored. Data are streamed with `/vsicurl/`.
  Kept for backward compatibility.

- parallel:

  Logical. If `TRUE`, attempts to use `future.apply` for parallel
  processing within or across batches. Default is `FALSE`.

- batching:

  Logical. If `TRUE` (default), processes data in chunks of
  `batch_size`. If `FALSE`, loads all layers at once.

- batch_size:

  Integer. Number of remote raster layers loaded and processed per
  batch. Lower values reduce peak memory usage for long time series.
  Default is `12L` (~4 months of dekadal data).

- l3_region:

  Character. Optional L3 region code to use when `variable` is an L3
  product and `region` is a spatial AOI. This keeps polygon/bbox
  extraction against the supplied AOI while constraining source rasters
  to the selected L3 mosaic.

- l3_mode:

  L3 coverage policy. `"select"` requires one selected region for a
  multi-L3 AOI; `"mosaic_all"` extracts every intersecting L3 source.

- partial:

  Logical. If `TRUE`, incomplete temporal coverage is allowed and
  recorded. Default `FALSE` fails the request.

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

A data.frame with columns:

- `mean`, `min`, `max`: Zonal statistics for each polygon/time step

- `start_date`, `end_date`: Date range for each time step

- `number_of_days`: Number of days in the time step

- `ID` or custom identifier: Polygon identifier

- `layer_index`: Index of the raster layer

The data.frame also has attributes:

- `units`: The unit of measurement (possibly converted)

- `long_name`: Full variable name

- `original_units`: Original units before conversion (if converted)

## Details

The function uses
[`exactextractr::exact_extract()`](https://isciences.gitlab.io/exactextractr/reference/exact_extract.html)
for accurate zonal statistics that properly handle partial pixel
coverage at polygon boundaries.

## Examples

``` r
if (FALSE) { # \dontrun{
# Extract time series for a bounding box
# For dekadal variables, defaults to mm/dekad behavior
df <- wapor_ts(
  region = c(35.0, 33.0, 36.0, 34.0),
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-03-31")
)

# Preserve raw API values without temporal conversion
df <- wapor_ts(
  region = "fields.geojson",
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-12-31"),
  identifier = "field_name",
  unit_conversion = "none"
)

# Parallel extraction for memory efficiency
library(future)
plan(multisession)
df <- wapor_ts(
  region = c(35.0, 33.0, 36.0, 34.0),
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-12-31"),
  parallel = TRUE,
  batching = TRUE,
  batch_size = 3
)

# Check units
attr(df, "units")
attr(df, "long_name")
} # }
```
