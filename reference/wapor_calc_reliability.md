# Temporal reliability of relative ET

Population (default) or sample CV over time of AETI/ETc per pixel, or
per zone through
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).
Monthly relative ET is the intended input; dekadal relative ET is noisy.
No default class scheme (Molden and Gates 1990 bands are secondary and
unverified for ET).

## Usage

``` r
wapor_calc_reliability(
  ratio_stack,
  zones = NULL,
  id = NULL,
  sd_type = "population"
)
```

## Source

Bastiaanssen and Bos (1999).

## Arguments

- ratio_stack:

  SpatRaster stack of AETI_t / ETc_t, or the output of
  [`wapor_relative_et_stack()`](https://almutaz9000.github.io/Rwapor/reference/wapor_relative_et_stack.md).

- zones:

  Optional polygons for a zonal series.

- id:

  Zone id column.

- sd_type:

  `"population"` or `"sample"`.

## Value

A SpatRaster of CV (pixel mode) or a data frame (zone mode).
