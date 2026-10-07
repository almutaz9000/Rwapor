# Compute ETc-Based Adequacy

Adequacy_ETc = Seasonal_AETI / Seasonal_ETc. Measures whether water
consumption meets crop water requirements. Values near 1.0 represent
full satisfaction, values below 1.0 indicate water deficit or stress,
and values above 1.0 indicate water application in excess of standard
crop demand.

## Usage

``` r
wapor_calc_adequacy_etc(aeti_seasonal, etc_seasonal)
```

## Arguments

- aeti_seasonal:

  SpatRaster or numeric. Seasonal AETI.

- etc_seasonal:

  SpatRaster or numeric. Seasonal ETc.

## Value

SpatRaster or numeric of adequacy ratio.

## References

Molden, D. J., & Gates, T. K. (1990). Performance metrics for evaluation
of irrigation-water-delivery systems. Journal of Irrigation and Drainage
Engineering, 116(6), 804-823.

Karimi, P., Bastiaanssen, W. G., & Molden, D. (2019). Water accounting
plus (WA+) - a water accounting procedure for complex river basins based
on satellite measurements. Hydrology and Earth System Sciences, 17(7),
2459-2472.
