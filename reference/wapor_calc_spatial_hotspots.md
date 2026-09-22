# Classify Spatial Hotspots from Z-Score Anomaly

Identifies severe deficit / surplus hotspots based on statistical
significance thresholds (e.g., +/- 1.96 corresponding to 95% confidence
interval).

## Usage

``` r
wapor_calc_spatial_hotspots(zscore_layer, low = -1.96, high = 1.96)
```

## Arguments

- zscore_layer:

  SpatRaster. Single-layer raster of Z-scores.

- low:

  Numeric. Lower threshold for severe deficit (default: -1.96).

- high:

  Numeric. Upper threshold for severe surplus (default: 1.96).

## Value

A SpatRaster with classified values:

- -2: Severe Deficit (Z \< low)

- -1: Moderate Deficit (low \<= Z \< -1.0)

- 0: Normal (-1.0 \<= Z \<= 1.0)

- 1: Moderate Surplus (1.0 \< Z \<= high)

- 2: Severe Surplus (Z \> high)

## Examples

``` r
z <- terra::rast(nrows=5, ncols=5, vals=seq(-2.5, 2.5, length.out=25))
h <- wapor_calc_spatial_hotspots(z)
```
