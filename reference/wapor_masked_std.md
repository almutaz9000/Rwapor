# Apply Season-Masked Weighted Standard Deviation

Computes weighted standard deviation of a raster time series using
per-dekad season weights.

## Usage

``` r
wapor_masked_std(x, weights, layer_multipliers = NULL, incremental = FALSE)
```

## Arguments

- x:

  SpatRaster. Multi-layer raster.

- weights:

  SpatRaster. Season weights (0-1), same number of layers as x.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers.

- incremental:

  Logical. If TRUE, performs aggregation layer-by-layer to save memory.
  Default FALSE.

## Value

A single-layer SpatRaster of weighted standard deviations.
