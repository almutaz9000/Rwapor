# Aggregate Daily Kc to Dekadal Mean Kc

Takes a daily Kc vector and a dekad table, computes the mean Kc for each
dekad period.

## Usage

``` r
wapor_aggregate_kc(kc_daily, dekad_table, season_start)
```

## Arguments

- kc_daily:

  Numeric vector of daily Kc values.

- dekad_table:

  data.frame with columns dekad_start, dekad_end, n_days.

- season_start:

  Date. The first day of the season.

## Value

Numeric vector of mean Kc per dekad.
