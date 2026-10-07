# Rasterize Polygons to a Mask on a Template Grid

Turns polygons (for example crop fields) into a mask on the grid of a
WaPOR raster. The polygons are reprojected to the template's CRS first:
rasterizing lon/lat polygons directly on a UTM grid (WaPOR Level 3)
gives an empty mask.

## Usage

``` r
wapor_rasterize_mask(
  polygons,
  template,
  field = NULL,
  value = 1L,
  touches = FALSE,
  fraction = FALSE
)
```

## Arguments

- polygons:

  `sf`, `SpatVector`, or a vector file path.

- template:

  `SpatRaster` whose grid the mask gets.

- field:

  Optional polygon attribute to write into the mask instead of `value`.

- value:

  Value of mask cells when `field` is `NULL`. Default `1`.

- touches:

  Logical. Include every cell a polygon touches, not only cells whose
  centre is inside. Ignored with `fraction = TRUE`.

- fraction:

  Logical. Return the fraction of each cell covered by the polygons (0
  to 1; overlapping or adjacent polygons are merged first) instead of a
  binary mask. Use it as `weights` in
  [`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md),
  especially at 100 m and 300 m, where most cells along field borders
  are mixed.

## Value

A `SpatRaster` named `crop_mask` (cells outside are `NA` for a binary
mask, `0` for a fraction). Attribute `"area_ratio"` is the mask area
divided by the polygon area.

## Details

Area check: a warning is given when the mask area differs from the
polygon area by more than 10% and the polygons cover at least 25 cells.
For smaller polygons a centre-based mask is too coarse for the check to
mean anything; use `fraction = TRUE` there.

## See also

[`wapor_harmonize_mask()`](https://almutaz9000.github.io/Rwapor/reference/wapor_harmonize_mask.md),
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).

## Examples

``` r
template <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200,
                        ymin = 3600000, ymax = 3600200, crs = "EPSG:32636")
field <- sf::st_sf(id = 1, geometry = sf::st_as_sfc(sf::st_bbox(
  c(xmin = 700030, ymin = 3600030, xmax = 700130, ymax = 3600130), crs = 32636)))
m <- wapor_rasterize_mask(field, template, fraction = TRUE)
attr(m, "area_ratio")
#> [1] 1
```
