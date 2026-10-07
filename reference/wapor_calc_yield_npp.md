# Calculate Crop Yield from NPP

Implementation of the FAO WaPOR yield estimation formula based on Net
Primary Production (NPP): \$\$AGBM = \left(AOT \times f_c \times
\frac{NPP \times 22.222}{1 - MC}\right) / 1000\$\$ \$\$CropYield = HI
\times AGBM\$\$

## Usage

``` r
wapor_calc_yield_npp(npp_gc_m2, mc, fc, aot, hi)
```

## Arguments

- npp_gc_m2:

  Numeric or SpatRaster. Seasonal sum of NPP in gC/m2.

- mc:

  Numeric. Moisture content (0-1).

- fc:

  Numeric. Light use efficiency correction factor.

- aot:

  Numeric. Above ground over total biomass production ratio.

- hi:

  Numeric. Harvest index.

## Value

Numeric or SpatRaster. Crop yield in t/ha.

## Details

where:

- `NPP * 22.222` converts gC/m2 to dry matter production (kgDM/ha).

- `1 / (1 - MC)` adjusts dry matter to fresh storage moisture content.

- `AOT` is the above-ground over total biomass ratio (e.g. 0.8).

- `fc` is the light use efficiency / crop-specific correction factor
  (typically 1.0).

- `1000` converts kg/ha to t/ha.

- `HI` is the Harvest Index (ratio of economic yield to above-ground
  biomass).

## References

Steduto, P., Hsiao, T. C., Fereres, E., & Raes, D. (2012). Crop yield
response to water. FAO Irrigation and Drainage Paper 66. Food and
Agriculture Organization of the United Nations, Rome.

Bastiaanssen, W. G. M., & Steduto, P. (2012). The water productivity
score (WPS) for irrigated crops: Concept and application. Agricultural
Water Management, 108, 119-132.
