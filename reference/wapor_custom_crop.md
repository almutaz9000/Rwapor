# Customize Crop Parameters from FAO Defaults

Copies an existing FAO default crop profile and allows selectively
overriding specific crop factors (Kc values, stage lengths, HI, MC,
etc.) for a specific class code.

## Usage

``` r
wapor_custom_crop(
  base_crop,
  class_value = 1L,
  crop_name = NULL,
  kc_ini = NULL,
  kc_mid = NULL,
  kc_end = NULL,
  l_ini_days = NULL,
  l_mid_days = NULL,
  l_late_days = NULL,
  max_height_m = NULL,
  HI = NULL,
  MC = NULL,
  fc = NULL,
  AOT = NULL,
  region = NULL,
  notes = NULL
)
```

## Arguments

- base_crop:

  Character. Name of the base FAO crop (e.g. "Winter Wheat", "Maize",
  "Potato").

- class_value:

  Integer. Target class value in the crop mask (default: 1L).

- crop_name:

  Character. Optional custom name (defaults to base_crop name).

- kc_ini, kc_mid, kc_end:

  Numeric. Optional Kc overrides.

- l_ini_days, l_mid_days, l_late_days:

  Integer. Optional stage length overrides.

- max_height_m, HI, MC, fc, AOT:

  Numeric. Optional production parameter overrides.

- region, notes:

  Character. Optional metadata overrides.

## Value

A single-row data.frame formatted for `crop_params`.

## Examples

``` r
custom_wheat <- wapor_custom_crop(
  base_crop = "Winter Wheat",
  class_value = 2L,
  crop_name = "High-Yield Irrigated Wheat",
  kc_mid = 1.25,
  HI = 0.52
)
```
