# Per-pixel area in hectares

For geographic (lon/lat) grids, area varies with latitude. Uses
[`terra::area()`](https://rspatial.github.io/terra/reference/expanse.html)
when available (correct spherical-area computation) and falls back to
the lon/lat approximation `111320 m/deg * cos(lat)` only when
[`terra::area()`](https://rspatial.github.io/terra/reference/expanse.html)
is unavailable. For projected grids a constant cell area is used.

## Usage

``` r
wapor_pixel_area_ha(x)
```

## Arguments

- x:

  SpatRaster. Template whose geometry defines the area raster.

## Value

A SpatRaster of per-pixel area in hectares.
