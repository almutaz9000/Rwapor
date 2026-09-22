# Build Dekadal Season Weights and Days

For each dekad in a given date range, computes:

1.  A per-pixel fractional weight (0-1) representing the portion of the
    dekad falling inside the pixel's growing season.

2.  A per-pixel count of absolute days (0-11) falling inside the season.

## Usage

``` r
wapor_build_season_weights(
  start_date,
  end_date,
  start_raster,
  end_raster,
  reference_year
)
```

## Arguments

- start_date:

  Date or character. Start of the analysis date range.

- end_date:

  Date or character. End of the analysis date range.

- start_raster:

  SpatRaster. Pixel-wise season start Julian days.

- end_raster:

  SpatRaster. Pixel-wise season end Julian days.

- reference_year:

  Integer. The season reference year.

## Value

A list with components:

- weights:

  SpatRaster with one layer per dekad (fraction 0-1)

- days:

  SpatRaster with one layer per dekad (absolute days)

- dekad_table:

  data.frame of dekad periods
