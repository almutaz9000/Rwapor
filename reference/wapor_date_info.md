# Extract Date Information from URL

Parses WaPOR or AgERA5 raster filenames to extract date information
including start date, end date, and period duration.

## Usage

``` r
wapor_date_info(url, tres)
```

## Arguments

- url:

  Character. Resource URL or filename containing date information.

- tres:

  Character. Temporal resolution code:

  - "D" = Dekadal (10-day periods)

  - "M" = Monthly

  - "A" = Annual

  - "E" = Daily

## Value

A list with components:

- `start_date`: Character date string in "YYYY-MM-DD" format

- `end_date`: Character date string in "YYYY-MM-DD" format

- `number_of_days`: Integer number of days in the period

## Examples

``` r
# Parse dekadal data URL (WaPOR format: WAPOR-3.L1-AETI-D.YYYY-MM-DX.tif)
date_info <- wapor_date_info(
  "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif",
  tres = "D"
)
date_info$start_date
#> [1] "2023-01-01"
# [1] "2023-01-01"
date_info$number_of_days
#> [1] 10
# [1] 10

# Parse monthly data URL (WaPOR format: WAPOR-3.L1-AETI-M.YYYY-MM.tif)
date_info <- wapor_date_info(
  "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-M/WAPOR-3.L1-AETI-M.2023-06.tif",
  tres = "M"
)
date_info$start_date
#> [1] "2023-06-01"
# [1] "2023-06-01"
```
