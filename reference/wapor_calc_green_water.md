# Compute Green Water Consumption

Green water = min(AETI, Peff) — the portion of actual evapotranspiration
sourced from effective precipitation (rainfall stored in the root-zone
soil).

## Usage

``` r
wapor_calc_green_water(aeti_seasonal, peff_seasonal)
```

## Arguments

- aeti_seasonal:

  SpatRaster or numeric. Seasonal AETI (mm).

- peff_seasonal:

  SpatRaster or numeric. Seasonal effective precipitation (mm).

## Value

SpatRaster or numeric. Green water consumption (mm).

## References

Falkenmark, M., & Rockström, J. (2004). Balancing water for humans and
nature: The new approach in ecohydrology. Earthscan, London.

Chukalla, A. D., Krol, M. S., & Hoekstra, A. Y. (2015). Green and blue
water footprint reduction in irrigated agriculture: effect of irrigation
techniques, irrigation strategies and mulching. Hydrology and Earth
System Sciences, 19(12), 4877-4891.

## Examples

``` r
wapor_calc_green_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 200 mm green water
#> [1] 200
```
