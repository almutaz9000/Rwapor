# Compute Seasonal Standard Deviation (Variability)

Applies dekadal season weights to compute weighted standard deviation of
rasters, and optionally summarizes by crop class.

## Usage

``` r
wapor_calc_seasonal_std(
  x,
  season_weights,
  crop_mask = NULL,
  layer_multipliers = NULL,
  incremental = FALSE
)
```

## Arguments

- x:

  SpatRaster. Dekadal layers of any variable.

- season_weights:

  SpatRaster. Dekadal season weights (0-1).

- crop_mask:

  SpatRaster. Optional crop mask for per-class summaries.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers.

- incremental:

  Logical. If TRUE, performs aggregation layer-by-layer to save memory.

## Value

A list with:

- raster:

  SpatRaster of seasonal weighted standard deviation per pixel

- by_class:

  data.frame of mean seasonal standard deviation per crop class (if
  crop_mask provided)
