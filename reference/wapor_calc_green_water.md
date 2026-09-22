# Compute Green Water Consumption

Green water = min(AETI, Peff) — the portion of actual evapotranspiration
sourced from effective precipitation (rainfall stored in the soil).

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

## Examples

``` r
wapor_calc_green_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 200 mm green water
#> [1] 200
```
