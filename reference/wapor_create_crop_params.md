# Create Custom Crop Parameters for Analysis

Builds a validated `crop_params` data.frame of crop growth and
production parameters for a specific raster class, without relying on
FAO default datasets.

## Usage

``` r
wapor_create_crop_params(
  class_value = 1L,
  crop_name = "Custom Crop",
  kc_ini = 0.35,
  kc_mid = 1.15,
  kc_end = 0.35,
  l_ini_days = 25L,
  l_mid_days = 45L,
  l_late_days = 30L,
  max_height_m = 1,
  HI = 0.45,
  MC = 0.12,
  fc = 1,
  AOT = 0.8,
  region = "Custom",
  notes = "User customized"
)
```

## Arguments

- class_value:

  Integer. Raster class code in the crop mask.

- crop_name:

  Character. Descriptive name of the crop.

- kc_ini:

  Numeric. Initial stage crop coefficient (0.05 - 1.5).

- kc_mid:

  Numeric. Mid-season crop coefficient (0.1 - 2.0).

- kc_end:

  Numeric. Late/end stage crop coefficient (0.05 - 1.5).

- l_ini_days:

  Integer. Length of initial stage in days (\>= 1).

- l_mid_days:

  Integer. Length of mid-season stage in days (\>= 1).

- l_late_days:

  Integer. Length of late stage in days (\>= 1).

- max_height_m:

  Numeric. Maximum crop height in meters (default: 1.0).

- HI:

  Numeric. Harvest Index (0.0 - 1.0, default: 0.45).

- MC:

  Numeric. Moisture Content of harvested crop (0.0 - 1.0, default:
  0.12).

- fc:

  Numeric. Ground cover / light interception factor (default: 1.0).

- AOT:

  Numeric. Aboveground to total biomass ratio (default: 0.8).

- region:

  Character. Geographic or agronomic region description.

- notes:

  Character. User notes or metadata.

## Value

A validated single-row data.frame ready for use in
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md).

## Examples

``` r
cp <- wapor_create_crop_params(
  class_value = 1L,
  crop_name = "Local Durum Wheat",
  kc_ini = 0.35,
  kc_mid = 1.20,
  kc_end = 0.28,
  l_ini_days = 25L,
  l_mid_days = 45L,
  l_late_days = 30L,
  HI = 0.48
)
```
