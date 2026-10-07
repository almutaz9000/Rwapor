# Spatial coefficient of variation

CV = sd / mean over finite cells (optionally masked). By-class values
use
[`terra::zonal()`](https://rspatial.github.io/terra/reference/zonal.html)
means and sds. This is the existing package helper; the zonal engine in
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md)
is the area-weighted definition used by irrigation uniformity.

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

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_calc_cv(aeti, crop_mask)
} # }
```
