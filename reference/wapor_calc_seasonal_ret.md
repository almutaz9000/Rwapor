# Compute Seasonal RET with Season Mask

Applies dekadal season weights to RET rasters and optionally summarizes
by crop class.

## Usage

``` r
wapor_calc_seasonal_ret(
  ret_dekad,
  season_weights,
  crop_mask = NULL,
  layer_multipliers = NULL,
  incremental = FALSE
)
```

## Arguments

- ret_dekad:

  SpatRaster. Dekadal RET layers.

- season_weights:

  SpatRaster. Dekadal season weights (0-1).

- crop_mask:

  SpatRaster. Optional crop mask for per-class summaries.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers.

- incremental:

  Logical. If TRUE, performs aggregation layer-by-layer to save memory.

## Value

A list with raster and by_class components (same as AETI version).
