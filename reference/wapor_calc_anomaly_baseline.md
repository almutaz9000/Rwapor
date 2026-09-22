# Calculate Anomaly Relative to a Baseline Climatology

Calculate Anomaly Relative to a Baseline Climatology

## Usage

``` r
wapor_calc_anomaly_baseline(current, baseline_mean, baseline_sd = NULL)
```

## Arguments

- current:

  SpatRaster. Current observation raster.

- baseline_mean:

  SpatRaster. Historical baseline mean raster.

- baseline_sd:

  SpatRaster. Optional historical baseline standard deviation.

## Value

If baseline_sd is provided, returns Z-score anomaly raster. Otherwise,
returns absolute difference (current - baseline_mean).

## Examples

``` r
curr <- terra::rast(nrows=5, ncols=5, vals=450)
base_m <- terra::rast(nrows=5, ncols=5, vals=400)
diff_r <- wapor_calc_anomaly_baseline(curr, base_m)
```
