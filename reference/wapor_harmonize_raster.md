# Harmonize a Raster to a Template Grid

Reprojects and resamples a source raster to match the CRS, extent,
resolution, and alignment of a template raster. Handles cases where
input is larger than template by cropping first, and validates spatial
overlap before resampling.

## Usage

``` r
wapor_harmonize_raster(x, template, method = "near")
```

## Arguments

- x:

  SpatRaster. The raster to harmonize.

- template:

  SpatRaster. The target geometry (CRS, extent, resolution).

- method:

  Character. Resampling method. Default is "near" (nearest-neighbor),
  which is required for categorical data like crop masks and integer
  season dates. Use "bilinear" for continuous data.

## Value

A SpatRaster aligned to the template.
