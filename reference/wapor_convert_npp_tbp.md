# Convert NPP to Total Biomass Production (TBP)

Converts seasonal Net Primary Production (NPP, gC/m2) to Total Biomass
Production (TBP, kgDM/ha) using the standard carbon fraction conversion
factor 22.222.

## Usage

``` r
wapor_convert_npp_tbp(npp_gc_m2)
```

## Arguments

- npp_gc_m2:

  Numeric or SpatRaster. Seasonal sum of NPP in gC/m2.

## Value

Numeric or SpatRaster. TBP in kgDM/ha.

## Details

Derivation: 1 gC/m2 = 10 kgC/ha. Assuming an average carbon fraction of
dry plant biomass of 0.45 (45% carbon), TBP (kgDM/ha) = NPP \* 10 / 0.45
= NPP \* 22.2222.

## References

FAO. (2020). WaPOR Database Methodology: Version 2 Release. Food and
Agriculture Organization of the United Nations, Rome.

Running, S. W., Nemani, R. R., Heinsch, F. A., Zhao, M., Reeves, M., &
Hashimoto, H. (2004). A continuous satellite-derived measure of global
terrestrial primary production. BioScience, 54(6), 547-560.
