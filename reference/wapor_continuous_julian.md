# Convert a Date to Continuous Julian Index

Converts a date into a continuous Julian day index relative to a
reference year. Dates in the reference year map to 1..365/366. Dates in
the following year map to 366/367..730/731.

## Usage

``` r
wapor_continuous_julian(date, reference_year)
```

## Arguments

- date:

  Date or character in "YYYY-MM-DD" format.

- reference_year:

  Integer. The season reference year.

## Value

Integer. Continuous Julian day index.

## Examples

``` r
wapor_continuous_julian("2023-03-15", 2023)
#> [1] 74
wapor_continuous_julian("2024-01-15", 2023)  # cross-year
#> [1] 380
```
