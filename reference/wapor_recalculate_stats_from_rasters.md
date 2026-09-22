# Recalculate Statistics from Saved Rasters

Queries all saved raster blobs for a farm from DuckDB and recalculates
zonal statistics using a new percentile threshold. Updates the
farm_timeseries table.

## Usage

``` r
wapor_recalculate_stats_from_rasters(con, farm_id, polygon, threshold_pct = 5)
```

## Arguments

- con:

  DuckDB connection

- farm_id:

  Farm identifier

- polygon:

  sf object with farm boundary

- threshold_pct:

  New threshold percentile (0-50)

## Value

data.frame with updated statistics
