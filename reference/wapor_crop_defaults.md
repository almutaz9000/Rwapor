# Get Crop Default Parameters

Retrieves the default crop parameters for a named crop from the FAO
defaults dataset.

## Usage

``` r
wapor_crop_defaults(crop_name)
```

## Arguments

- crop_name:

  Character. Name of the crop (case-insensitive partial match).

## Value

A single-row data.frame with crop parameters, or NULL if not found.

## Examples

``` r
wapor_crop_defaults("Winter Wheat")
#>      crop_name        region kc_ini kc_mid kc_end l_ini_days l_mid_days
#> 1 Winter Wheat Mediterranean    0.4   1.15    0.3         30         40
#>   l_late_days max_height_m   HI   MC fc AOT                             notes
#> 1          30            1 0.45 0.12  1 0.8 FAO-56 Table 12, non-frozen soils
```
