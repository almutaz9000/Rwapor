# Compute Seasonal ETc Incrementally

Avoids building a full multi-layer ETc stack by accumulating RET \*
season_weight \* kc layer-by-layer. This is significantly more
memory-efficient for long seasons.

## Usage

``` r
wapor_calc_seasonal_etc(
  ret_dekad,
  season_weights,
  kc_dekad,
  layer_multipliers = NULL
)
```

## Arguments

- ret_dekad:

  SpatRaster. Dekadal RET layers.

- season_weights:

  SpatRaster. Dekadal season weights (0-1).

- kc_dekad:

  Numeric vector. Dekadal Kc values.

- layer_multipliers:

  Optional numeric vector of per-layer multipliers.

## Value

A single-layer SpatRaster of seasonal ETc (weighted sum).
