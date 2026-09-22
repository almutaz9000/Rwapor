# Compute Blue Water Consumption

Blue water = max(0, AETI - Peff) — the portion of actual
evapotranspiration sourced from irrigation (surface water or
groundwater).

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

## Examples

``` r
wapor_calc_blue_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 150 mm blue water
#> [1] 150
```
