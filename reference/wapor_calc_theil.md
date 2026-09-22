# Spatial Theil T inequality index

Theil's T = mean( (x / xbar) \* log(x / xbar) ) for positive finite
values.

## Usage

``` r
wapor_calc_theil(r, crop_mask = NULL)
```

## Arguments

- r:

  SpatRaster.

- crop_mask:

  Optional SpatRaster mask / class raster.

## Value

List with `overall` Theil T and optional `by_class` table.
