# Calculate Crop Yield from NPP

Implementation of the provided yield formula based on NPP: AGBM = (aot
\* fc \* (NPP \* 22.222 / (1 - MC))) / 1000 CropYield = HI \* AGBM

## Usage

``` r
wapor_calc_yield_npp(npp_gc_m2, mc, fc, aot, hi)
```

## Arguments

- npp_gc_m2:

  Numeric. Seasonal sum of NPP in gC/m2.

- mc:

  Numeric. Moisture content (0-1).

- fc:

  Numeric. Light use efficiency correction factor.

- aot:

  Numeric. Above ground over total biomass production ratio.

- hi:

  Numeric. Harvest index.

## Value

Numeric. Crop yield in t/ha.
