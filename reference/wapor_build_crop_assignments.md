# Build Crop Assignment Table

Creates a data.frame for each crop class extracted from the mask,
pre-populated with NA parameters that can be filled by crop defaults or
user input.

## Usage

``` r
wapor_build_crop_assignments(class_values, crop_defaults = NULL)
```

## Arguments

- class_values:

  Integer vector of unique crop class values.

- crop_defaults:

  Optional named list keyed by class value (as a character string, e.g.
  `"1"`). Each element is either a single-row data.frame in the same
  format as
  [`wapor_crop_defaults()`](https://almutaz9000.github.io/Rwapor/reference/wapor_crop_defaults.md)'s
  return value, or a plain named list using the same column names
  (`kc_ini`, `kc_mid`, `kc_end`, `l_ini_days`, `l_mid_days`,
  `l_late_days`, `max_height_m`, `HI`, `MC`, `fc`, `AOT`, and optionally
  `crop_name`/`crop_label`). Class values without a matching entry are
  left as `NA` for manual entry.

## Value

A data.frame with one row per class, columns for all crop parameters.

## Examples

``` r
wapor_build_crop_assignments(
  class_values = c(1L, 2L),
  crop_defaults = list(
    "1" = wapor_crop_defaults("sorghum"),
    "2" = list(kc_ini = 0.4, kc_mid = 1.15, kc_end = 0.7,
               l_ini_days = 25L, l_mid_days = 50L, l_late_days = 30L,
               HI = 0.45, MC = 0.14, fc = 0.90, AOT = 0.80,
               crop_label = "Custom crop")
  )
)
#>   class_value  crop_label kc_ini kc_mid kc_end l_ini_days l_mid_days
#> 1           1     Sorghum    0.3   1.05   0.55         20         40
#> 2           2 Custom crop    0.4   1.15   0.70         25         50
#>   l_late_days max_height_m   MC  fc AOT   HI
#> 1          30          1.5 0.11 1.0 0.8 0.40
#> 2          30           NA 0.14 0.9 0.8 0.45
```
