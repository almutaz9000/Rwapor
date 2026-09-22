# Compute Total Season Days Raster

For each pixel, computes total_days = end_jd - start_jd + 1. When
`reference_year` is supplied, cross-year seasons are handled
automatically: pixels where `end_raster < start_raster` (e.g. a
Nov-to-May season stored as raw day-of-year values) have the
reference-year length added to `end_raster` before the subtraction.

## Usage

``` r
wapor_season_days(start_raster, end_raster, reference_year = NULL)
```

## Arguments

- start_raster:

  SpatRaster. Pixel-wise season start Julian days.

- end_raster:

  SpatRaster. Pixel-wise season end Julian days.

- reference_year:

  Integer or NULL. When supplied, corrects cross-year seasons where
  `end_raster` DOY \< `start_raster` DOY.

## Value

A SpatRaster of total season days per pixel.
