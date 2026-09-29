# Per-pixel area in hectares

For geographic (lon/lat) grids, area varies with latitude and is
computed exactly on the ellipsoid with
[`terra::cellSize()`](https://rspatial.github.io/terra/reference/cellSize.html).
For projected grids a constant cell area (resolution x resolution) is
used. Both are computed block-wise, so large grids are not loaded into
memory.

## Usage

``` r
wapor_pixel_area_ha(x)
```

## Arguments

- x:

  SpatRaster. Template whose geometry defines the area raster.

## Value

A SpatRaster of per-pixel area in hectares.
