# Adjust Crop Parameters Table using AgERA5 Climate Data

Automatically computes growth stage windows for each crop class and
updates `kc_mid` and `kc_end` in a crop parameters data frame using
stage-specific mean climate parameters from AgERA5.

## Usage

``` r
wapor_adjust_crop_params_agera5(
  crop_params,
  aoi = NULL,
  season_start,
  season_end,
  climate_df = NULL,
  method_rh = c("hourly_rh", "tmin_tmax")
)
```

## Arguments

- crop_params:

  data.frame of crop parameters. Must contain columns: `kc_ini`,
  `kc_mid`, `kc_end`, `l_ini_days`, `l_mid_days`, `l_late_days`. May
  also contain `class_value`, `class_name`, `max_height_m` (or
  `height_m`).

- aoi:

  Region spatial object (sf polygon, bbox, or file path). Required if
  `climate_df` is not provided.

- season_start:

  Date or character `"YYYY-MM-DD"`. Season start date.

- season_end:

  Date or character `"YYYY-MM-DD"`. Season end date.

- climate_df:

  Optional data.frame of pre-extracted climate records with columns
  `date`, `u2`, and `rh_min` (as returned by
  [`wapor_extract_agera5_climate()`](https://almutaz9000.github.io/Rwapor/reference/wapor_extract_agera5_climate.md)).
  If provided, `aoi` is not queried.

- method_rh:

  Method for relative humidity: `"hourly_rh"` or `"tmin_tmax"`.

## Value

An updated `crop_params` data.frame with:

- kc_mid:

  Updated climatically adjusted Kc_mid

- kc_end:

  Updated climatically adjusted Kc_end

- kc_mid_tab:

  Preserved original tabulated Kc_mid

- kc_end_tab:

  Preserved original tabulated Kc_end

- u2_mid:

  Mean wind speed during mid-season (m/s)

- rh_min_mid:

  Mean minimum RH during mid-season (%)

- u2_late:

  Mean wind speed during late-season (m/s)

- rh_min_late:

  Mean minimum RH during late-season (%)

## Examples

``` r
# Prepare synthetic climate data
dates <- seq.Date(as.Date("2023-01-01"), as.Date("2023-04-30"), by = "day")
clim <- data.frame(
  date = dates,
  u2 = 3.5, # breezy
  rh_min = 28 # dry
)

crop_df <- data.frame(
  class_value = 1,
  class_name = "Wheat",
  kc_ini = 0.40,
  kc_mid = 1.15,
  kc_end = 0.30,
  l_ini_days = 30L,
  l_mid_days = 40L,
  l_late_days = 30L,
  max_height_m = 1.0
)

adj_crop_df <- wapor_adjust_crop_params_agera5(
  crop_params = crop_df,
  season_start = "2023-01-01",
  season_end = "2023-04-30",
  climate_df = clim
)
adj_crop_df
#>   class_value class_name kc_ini kc_mid kc_end l_ini_days l_mid_days l_late_days
#> 1           1      Wheat    0.4  1.242    0.3         30         40          30
#>   max_height_m kc_mid_tab kc_end_tab u2_mid rh_min_mid u2_late rh_min_late
#> 1            1       1.15        0.3    3.5         28     3.5          28
```
