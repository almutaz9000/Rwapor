# FAO Crop Default Parameters

A data.frame containing default crop coefficients and growth stage
lengths for common crops, sourced from FAO Irrigation and Drainage Paper
56.

## Usage

``` r
FAO_CROP_DEFAULTS
```

## Format

A data.frame with columns:

- crop_name:

  Character. Name of the crop

- region:

  Character. Reference region for the growth parameters

- kc_ini:

  Numeric. Crop coefficient during initial stage

- kc_mid:

  Numeric. Crop coefficient during mid-season stage

- kc_end:

  Numeric. Crop coefficient during late/end stage

- l_ini_days:

  Integer. Length of initial growth stage in days

- l_mid_days:

  Integer. Length of mid-season stage in days

- l_late_days:

  Integer. Length of late-season stage in days

- max_height_m:

  Numeric. Maximum crop height in meters

- notes:

  Character. Additional notes

## Details

Note that l_dev (development stage) is not stored here. It is derived
dynamically as: l_dev = total_season_days - (l_ini + l_mid + l_late).
Total season length comes from the user-supplied season start/end
rasters.
