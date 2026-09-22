# Build Kc Curves by Crop Class

Generates daily Kc curves for each crop class, optionally grouped by
unique season duration patterns.

## Usage

``` r
wapor_build_kc_by_class(crop_assignment, total_days)
```

## Arguments

- crop_assignment:

  data.frame with crop parameters per class. Must include columns:
  class_value, kc_ini, kc_mid, kc_end, l_ini_days, l_mid_days,
  l_late_days.

- total_days:

  Integer or named integer vector of total season days per class. If a
  single value, applied to all classes.

## Value

A named list of numeric vectors (daily Kc values), one per class.
