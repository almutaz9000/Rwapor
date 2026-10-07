# One Row per Zone and Variable from a Long Zonal Table

One Row per Zone and Variable from a Long Zonal Table

## Usage

``` r
wapor_zonal_wide(z)
```

## Arguments

- z:

  A long table returned by
  [`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).

## Value

A data frame with `level`, `zone_id`, `zone_key`, the id columns,
`season` and `variable`, and one column per statistic. Class rows become
columns named `<stat>.<class>` (for example `class_pct.good`).
