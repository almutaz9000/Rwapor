# Compute weighted mean over specific classes

Prefers `area_ha` when present on `class_stats` so geographic summaries
are latitude-unbiased. Falls back to `pixel_count` when area is
unavailable.

## Usage

``` r
wapor_weighted_class_mean(
  summary_tbl,
  class_stats,
  value_col,
  area_weighted = TRUE
)
```

## Arguments

- summary_tbl:

  data.frame with class_value and the value to average.

- class_stats:

  data.frame with class_value and pixel_count and/or area_ha.

- value_col:

  Character. Column name in summary_tbl to average.

- area_weighted:

  Logical. If TRUE (default), prefers `area_ha` when present on
  `class_stats` for latitude-unbiased means. If FALSE, uses
  `pixel_count`.

## Value

Numeric weighted mean.
