# Compute ETc-Based Adequacy

Adequacy_ETc = Seasonal_AETI / Seasonal_ETc

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
