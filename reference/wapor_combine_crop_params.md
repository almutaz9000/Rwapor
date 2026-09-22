# Combine Multiple Crop Parameter Definitions

Merges multiple single-crop parameter data.frames into a consolidated
multi-class `crop_params` data.frame, validating for duplicate class
values.

## Usage

``` r
wapor_combine_crop_params(...)
```

## Arguments

- ...:

  Multiple data.frames created by
  [`wapor_create_crop_params()`](https://almutaz9000.github.io/Rwapor/reference/wapor_create_crop_params.md)
  or
  [`wapor_custom_crop()`](https://almutaz9000.github.io/Rwapor/reference/wapor_custom_crop.md).

## Value

Combined, validated `crop_params` data.frame.

## Examples

``` r
c1 <- wapor_custom_crop("Winter Wheat", class_value = 1L)
c2 <- wapor_custom_crop("Maize", class_value = 2L)
params <- wapor_combine_crop_params(c1, c2)
```
