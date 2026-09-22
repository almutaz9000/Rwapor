# Validate Data Coverage for Analysis Period

Checks if local data covers the requested analysis period.

## Usage

``` r
wapor_validate_data_coverage(folder, variables, period, l3_code = NULL)
```

## Arguments

- folder:

  Character. Path to local data folder.

- variables:

  Character vector. Variable names to check.

- period:

  Character vector c(start_date, end_date).

- l3_code:

  Character. L3 region code (optional).

## Value

A list with `complete` (logical) and `missing` (list of missing dates
per variable).
