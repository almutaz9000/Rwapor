# Save clipped WaPOR raster blobs to a monitoring database

Save clipped WaPOR raster blobs to a monitoring database

## Usage

``` r
wapor_save_raster_blobs(
  con,
  farms_sf,
  variable,
  period,
  log_fn = message,
  l3_region = NULL
)
```

## Arguments

- con:

  DuckDB connection.

- farms_sf:

  sf object with farm polygons.

- variable:

  WaPOR variable code.

- period:

  Date range c(start, end).

- log_fn:

  Function for logging.

- l3_region:

  Optional L3 region code.

## Value

NULL (invisibly).
