# Compute P95-Based Adequacy

Adequacy_P95 = Seasonal_AETI / P95(Seasonal_AETI within crop class)

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
