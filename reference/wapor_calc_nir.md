# Net irrigation requirement

NIR = sum over months of max(0, ETc_m - Peff_m) (mm). Compute monthly,
then sum, as for green/blue water. Volume via
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).

## Usage

``` r
wapor_calc_nir(etc_monthly, peff_monthly)
```

## Source

Allen et al. (1998); Smith (1992) CROPWAT.

## Arguments

- etc_monthly:

  Monthly ETc, numeric vector, SpatRaster stack, or list of rasters.

- peff_monthly:

  Monthly effective rainfall, same shape as `etc_monthly`.

## Value

Numeric or SpatRaster (mm).
