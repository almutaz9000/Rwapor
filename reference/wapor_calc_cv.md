# Spatial coefficient of variation

Spatial coefficient of variation

## Usage

``` r
wapor_calc_cv(r, crop_mask = NULL)
```

## Arguments

- r:

  SpatRaster (typically seasonal AETI).

- crop_mask:

  Optional SpatRaster mask / class raster.

## Value

List with `overall` CV and optional `by_class` table.
