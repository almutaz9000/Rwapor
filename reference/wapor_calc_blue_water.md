# Compute Blue Water Consumption

Blue water = max(0, AETI - Peff) — the portion of actual
evapotranspiration sourced from irrigation (surface water withdrawals or
groundwater extraction).

## Usage

``` r
wapor_calc_blue_water(aeti_seasonal, peff_seasonal)
```

## Arguments

- aeti_seasonal:

  SpatRaster or numeric. Seasonal AETI (mm).

- peff_seasonal:

  SpatRaster or numeric. Seasonal effective precipitation (mm).

## Value

SpatRaster or numeric. Blue water consumption (mm).

## References

Falkenmark, M., & Rockström, J. (2004). Balancing water for humans and
nature: The new approach in ecohydrology. Earthscan, London.

Hoekstra, A. Y., Chapagain, A. K., Aldaya, M. M., & Mekonnen, M. M.
(2011). The Water Footprint Assessment Manual: Setting the Global
Standard. Earthscan, London.

## Examples

``` r
wapor_calc_blue_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 150 mm blue water
#> [1] 150
```
