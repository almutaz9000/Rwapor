# Compute P95-Based Adequacy

Adequacy_P95 = Seasonal_AETI / P95(Seasonal_AETI within crop class).
Measures the relative water consumption compared to the top 5%
performing water-consuming areas of the same crop under local
conditions.

## Usage

``` r
wapor_calc_adequacy_p95(aeti_seasonal, crop_mask, p95_table)
```

## Arguments

- aeti_seasonal:

  SpatRaster. Seasonal AETI raster.

- crop_mask:

  SpatRaster. Crop mask.

- p95_table:

  data.frame. Output from wapor_calc_p95_aeti().

## Value

A SpatRaster of P95-based adequacy.

## References

Bastiaanssen, W. G., & Bos, M. G. (1999). Irrigation performance
indicators based on satellite remote sensing. Irrigation and Drainage
Systems, 13(1), 3-36.

Karimi, P., Bastiaanssen, W. G., & Molden, D. (2019). Water accounting
plus (WA+) - a water accounting procedure for complex river basins based
on satellite measurements. Hydrology and Earth System Sciences, 17(7),
2459-2472.
