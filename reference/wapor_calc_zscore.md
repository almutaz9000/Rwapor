# Calculate Temporal Z-Score Anomaly Stack

Computes pixel-wise standard normalized anomalies (Z-scores) across a
multi-layer SpatRaster time series: Z = (X - Mean) / SD.

## Usage

``` r
wapor_calc_zscore(stack)
```

## Arguments

- stack:

  SpatRaster. Multi-layer raster stack (e.g. multi-year seasonal AETI).

## Value

A SpatRaster of Z-scores with the same number of layers as input.

## Examples

``` r
r1 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=400, sd=50))
r2 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=350, sd=50))
r3 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=450, sd=50))
s <- c(r1, r2, r3)
z <- wapor_calc_zscore(s)
```
