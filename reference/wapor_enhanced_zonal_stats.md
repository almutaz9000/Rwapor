# Calculate Enhanced Zonal Statistics

Extracts pixel values within a polygon and applies a percentile-based
threshold filter to remove noise or edge pixels.

## Usage

``` r
wapor_enhanced_zonal_stats(raster, polygon, threshold_percentile = 0)
```

## Arguments

- raster:

  terra SpatRaster object

- polygon:

  sf object with farm boundaries

- threshold_percentile:

  Numeric (0-50). Percentile threshold to filter low values.

## Value

data.frame with mean, min, max, std, and pixel counts.
