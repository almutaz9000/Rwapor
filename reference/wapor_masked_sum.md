# Apply Season-Masked Sum

Computes weighted sum of a raster time series using per-dekad season
weights.

## Usage

``` r
wapor_masked_sum(x, weights, layer_multipliers = NULL, incremental = FALSE)
```

## Arguments

- x:

  SpatRaster. Multi-layer raster (e.g., dekadal AETI or RET).

- weights:

  SpatRaster. Season weights (0-1), same number of layers as x.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers. Use this for rate
  variables stored per day where a weighted sum must be multiplied by
  the full slice length.

- incremental:

  Logical. If TRUE, performs aggregation layer-by-layer to save memory.
  Recommended for very long seasons or low RAM. Default FALSE.

## Value

A single-layer SpatRaster of weighted sums.
