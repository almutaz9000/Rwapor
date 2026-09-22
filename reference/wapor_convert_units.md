# Convert DataFrame Values Between Temporal Units

Converts statistical values (mean, min, max, median) in a data frame
from one temporal unit to another. Commonly used to convert dekadal
values to monthly or annual totals.

## Usage

``` r
wapor_convert_units(df, unit_conversion)
```

## Arguments

- df:

  A data.frame containing columns to convert. Must have:

  - At least one of: `mean`, `min`, `max`, `median`

  - `start_date`: Date string for calculating conversion factors

  - `number_of_days`: Number of days in the source period

  Must also have a `units` attribute specifying the source unit (e.g.,
  "mm/day", "mm/dekad").

- unit_conversion:

  Character. Target temporal unit. One of:

  - "none": No conversion (returns input unchanged)

  - "day": Convert to daily rate

  - "dekad": Convert to 10-day total

  - "month": Convert to monthly total

  - "year": Convert to annual total

## Value

The input data.frame with converted values. The following attributes are
updated:

- `units`: New unit string (e.g., "mm/month")

- `original_units`: Original unit string before conversion

## Details

Conversion factors:

- day -\> dekad: multiply by number_of_days

- day -\> month: multiply by days in month

- day -\> year: multiply by 365

- dekad -\> month: multiply by 3

- month -\> year: multiply by 12

## Examples

``` r
# Create sample data
df <- data.frame(
  mean = c(2.5, 3.0, 2.8),
  min = c(1.0, 1.5, 1.2),
  max = c(4.0, 4.5, 4.2),
  start_date = c("2023-01-01", "2023-01-11", "2023-01-21"),
  number_of_days = c(10, 10, 11)
)
attr(df, "units") <- "mm/day"

# Convert to monthly totals
df_monthly <- wapor_convert_units(df, "month")
attr(df_monthly, "units")
#> [1] "mm/month"
# [1] "mm/month"
```
