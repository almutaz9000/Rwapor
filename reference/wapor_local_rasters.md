# Get Local Raster Paths for a Variable and Date Range

Returns file paths for locally available rasters matching a variable and
date range. For dekadal/monthly data, includes any time step that
overlaps with the analysis period (not just those starting within it).

## Usage

``` r
wapor_local_rasters(folder, variable, start_date, end_date)
```

## Arguments

- folder:

  Character. Path to the download folder.

- variable:

  Character. Variable code (e.g., "L1-AETI-D").

- start_date:

  Character or Date. Start of date range.

- end_date:

  Character or Date. End of date range.

## Value

Character vector of full file paths, sorted by date.
