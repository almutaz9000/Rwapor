# Compute Monthly Weighted Standard Deviation Raster Series

Aggregates a dekadal raster stack into per-month standard deviations
using season weights and optional per-layer multipliers.

## Usage

``` r
wapor_calc_monthly_weighted_std_rasters(
  x,
  season_weights,
  dekad_table,
  layer_multipliers = NULL,
  incremental = FALSE,
  summary_mask = NULL,
  summary_value_name = "std_mm"
)
```

## Arguments

- x:

  SpatRaster. Multi-layer raster stack.

- season_weights:

  SpatRaster. Per-layer season weights.

- dekad_table:

  data.frame. Must include either `dekad_start` or `dekad_key`.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers.

- incremental:

  Logical. If TRUE, performs aggregation layer-by-layer.

- summary_mask:

  Optional SpatRaster mask for mean summaries.

- summary_value_name:

  Character. Name of the summary column to create.

## Value

A list with `rasters` and `summary` entries.
