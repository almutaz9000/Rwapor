# Compute Seasonal AETI with Season Mask

Applies dekadal season weights to AETI rasters and optionally summarizes
by crop class.

## Usage

``` r
wapor_calc_seasonal_aeti(
  aeti_dekad,
  season_weights,
  crop_mask = NULL,
  layer_multipliers = NULL,
  incremental = FALSE
)
```

## Arguments

- aeti_dekad:

  SpatRaster. Dekadal AETI layers.

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

  SpatRaster of seasonal AETI per pixel

- by_class:

  data.frame of mean seasonal AETI per crop class (if crop_mask
  provided)
