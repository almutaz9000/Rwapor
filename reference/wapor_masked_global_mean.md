# Compute masked global mean

When `area` is a SpatRaster of per-pixel hectares, the mean is
area-weighted so geographic grids are not biased toward polar pixels.
Without `area` the result is a plain pixel-count mean (previous
behaviour).

## Usage

``` r
wapor_masked_global_mean(r, mask_rast = NULL, area = NULL)
```

## Arguments

- r:

  SpatRaster.

- mask_rast:

  SpatRaster. Optional mask.

- area:

  SpatRaster. Optional per-pixel area in hectares.

## Value

Numeric mean.
