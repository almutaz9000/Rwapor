# Compute Beneficial Fraction

Beneficial Fraction = Transpiration (T) / Actual Evapotranspiration
(AETI)

## Usage

``` r
wapor_calc_beneficial_fraction(t_seasonal, aeti_seasonal)
```

## Arguments

- t_seasonal:

  SpatRaster or numeric. Seasonal Transpiration (mm).

- aeti_seasonal:

  SpatRaster or numeric. Seasonal AETI (mm).

## Value

SpatRaster or numeric of beneficial fraction (0-1).
