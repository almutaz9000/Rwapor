# Run the monitoring update loop for a set of farms

Run the monitoring update loop for a set of farms

## Usage

``` r
wapor_run_monitoring(
  con,
  farms_sf,
  variables,
  period,
  save_rasters = TRUE,
  l3_region = NULL,
  log_fn = message
)
```

## Arguments

- con:

  DuckDB connection.

- farms_sf:

  sf object containing farm polygons with a `farm_id` column.

- variables:

  Vector of WaPOR variable codes to monitor.

- period:

  Date range c(start, end).

- save_rasters:

  Logical; if TRUE, saves clipped raster blobs to the database.

- l3_region:

  Optional L3 region code for L3 variables.

- log_fn:

  Optional function for logging messages (e.g. `message` or a custom
  function).

## Value

A list with statistics about the run.
