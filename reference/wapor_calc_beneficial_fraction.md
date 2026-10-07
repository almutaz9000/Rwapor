# Compute Beneficial Fraction

Beneficial Fraction = Transpiration (T) / Actual Evapotranspiration
(AETI). Quantifies the proportion of consumed water that directly
supports plant growth and productive biomass development, as opposed to
non-beneficial soil evaporation and canopy interception losses.

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

## References

Perry, C. (2007). Efficient irrigation; inefficient communication;
flawed recommendations. Irrigation and Drainage, 56(4), 367-378.

Molden, D., Oweis, T., Steduto, P., Bindraban, P., Hanjra, M. A., &
Kijne, J. (2010). Improving agricultural water productivity: Between
optimism and realism. Agricultural Water Management, 97(4), 528-535.
