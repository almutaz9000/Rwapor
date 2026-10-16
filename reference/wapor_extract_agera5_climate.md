# Extract Daily Climate Time Series from AgERA5 via Rwapor

Queries AgERA5 climate rasters for a specified Area of Interest (AOI)
and date range using
[`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
to obtain daily wind speed (\\u_2\\) and minimum relative humidity
(\\RH\_{min}\\).

## Usage

``` r
wapor_extract_agera5_climate(
  aoi,
  period,
  method_rh = c("hourly_rh", "tmin_tmax")
)
```

## Arguments

- aoi:

  Region spatial object (sf polygon, numeric bounding box
  `c(xmin, ymin, xmax, ymax)`, or path to vector file).

- period:

  Character vector of date range: `c("YYYY-MM-DD", "YYYY-MM-DD")`.

- method_rh:

  Method to derive minimum relative humidity:

  - `"hourly_rh"` (default): Uses midday/afternoon AgERA5 relative
    humidity (`AGERA5-RH12-E` and `AGERA5-RH15-E`, converted to
    percentage 0-100%).

  - `"tmin_tmax"`: Approximates RHmin from daily minimum and maximum
    temperatures (`AGERA5-TMIN-E` and `AGERA5-TMAX-E`) using the Tetens
    vapor pressure formulation.

## Value

A data.frame with daily records:

- date:

  Date object

- u2:

  Wind speed at 2 m (m/s)

- rh_min:

  Minimum relative humidity (%)

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- c(35.5, 31.8, 35.7, 32.2) # Jordan Valley bbox
clim <- wapor_extract_agera5_climate(aoi, period = c("2023-01-01", "2023-03-31"))
head(clim)
} # }
```
