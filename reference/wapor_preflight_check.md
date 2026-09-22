# Pre-Flight Analysis Validation

Comprehensive validation before running analysis. Returns detailed
diagnostic information.

## Usage

``` r
wapor_preflight_check(
  config,
  data_source = "api",
  folder = NULL,
  crop_mask = NULL,
  season_start = NULL,
  season_end = NULL
)
```

## Arguments

- config:

  List. Analysis configuration.

- data_source:

  Character. "api" or "local".

- folder:

  Character. Local data folder (for local mode).

- crop_mask:

  SpatRaster or path.

- season_start:

  SpatRaster or path.

- season_end:

  SpatRaster or path.

## Value

A list with validation results and recommendations.
