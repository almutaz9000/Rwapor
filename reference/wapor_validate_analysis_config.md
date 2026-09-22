# Validate Analysis Configuration

Checks analysis configuration for common errors before running the
pipeline.

## Usage

``` r
wapor_validate_analysis_config(
  config,
  crop_mask = NULL,
  season_start = NULL,
  season_end = NULL
)
```

## Arguments

- config:

  List. Analysis configuration (see wapor_run_seasonal_analysis).

- crop_mask:

  SpatRaster or NULL. Crop mask raster.

- season_start:

  SpatRaster or NULL. Season start raster.

- season_end:

  SpatRaster or NULL. Season end raster.

## Value

A list with `valid` (logical) and `errors` (character vector).
