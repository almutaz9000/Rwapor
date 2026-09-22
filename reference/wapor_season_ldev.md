# Compute Development Stage Length Raster

Derives l_dev dynamically: l_dev = total_days - (l_ini + l_mid +
l_late).

## Usage

``` r
wapor_season_ldev(total_days_raster, l_ini_days, l_mid_days, l_late_days)
```

## Arguments

- total_days_raster:

  SpatRaster. Total season days per pixel.

- l_ini_days:

  Integer. Length of initial stage.

- l_mid_days:

  Integer. Length of mid-season stage.

- l_late_days:

  Integer. Length of late-season stage.

## Value

A SpatRaster of development stage days per pixel.
