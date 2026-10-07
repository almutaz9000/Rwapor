# Bring a Classified Map onto a Template Grid as a Mask and a Fraction

For a crop or land cover map at any resolution, gives the fraction of
each template cell that belongs to the requested class or classes, and a
mask of the cells where that fraction reaches `min_fraction`.

## Usage

``` r
wapor_harmonize_mask(
  crop_map,
  template,
  class,
  min_fraction = 0.5,
  value = NULL,
  return_fraction = TRUE
)
```

## Arguments

- crop_map:

  Classified `SpatRaster` (class codes).

- template:

  `SpatRaster` whose grid the result gets.

- class:

  Class code or codes to keep.

- min_fraction:

  Smallest fraction of a template cell that must belong to the class for
  the cell to enter the mask. Default `0.5`, a majority rule (a
  heuristic, not a published threshold; choose it for your map).

- value:

  Value of mask cells. Default `NULL`: `1` for one class, the code of
  the winning class for several.

- return_fraction:

  Logical. Return the fraction as well. Default `TRUE`.

## Value

With `return_fraction = TRUE` a list with `mask` (layer `crop_mask`,
`NA` outside) and `fraction` (layer `fraction`, 0 to 1); otherwise the
mask.

## Details

Each class is turned into a 0/1 raster (cells of another class and cells
without data are 0) and averaged onto the template grid. With several
classes the class with the largest fraction wins the cell, ties go to
the first class given, and `fraction` holds the winner's fraction.

The fraction is the recommended `weights` input of
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md)
at Level 1 and Level 2.

## See also

[`wapor_rasterize_mask()`](https://almutaz9000.github.io/Rwapor/reference/wapor_rasterize_mask.md),
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).

## Examples

``` r
map <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                   crs = "EPSG:32636", vals = c(1, 1, 1, 2))
cell <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                    crs = "EPSG:32636")
terra::values(wapor_harmonize_mask(map, cell, class = 1)$fraction)
#>      fraction
#> [1,]     0.75
```
