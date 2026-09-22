# Save clipped WaPOR raster blobs to a monitoring database

Writes each cropped seasonal/dekadal layer both as an in-memory
compressed GeoTIFF blob (backward-compatible, unchanged read path) and
as a file-backed COG under `.wapor_monitoring_raster_store_dir()`,
recorded in the raster_path column together with gdal_version,
terra_version, and band_count provenance. Remote layers for one variable
are opened as a single batched /vsicurl/ stack rather than one GDAL
dataset handle per layer, cutting per-layer header round-trips.

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
