# Compute Net Biomass Water Productivity (NBWP)

Net Biomass Water Productivity (NBWP) = Biomass (kg/ha) / Transpiration
(mm) \* 10. Measures the biomass produced per unit of water beneficially
consumed through crop transpiration alone, isolating beneficial water
consumption from non-beneficial evaporation and canopy interception
losses.

## Usage

``` r
wapor_calc_nbwp(
  biomass_value,
  t_mm,
  biomass_unit = "kg/ha",
  provenance = NULL,
  compatibility_mode = c("warn", "strict")
)
```

## Arguments

- biomass_value:

  Numeric or SpatRaster. Seasonal biomass (kg/ha or t/ha).

- t_mm:

  Numeric or SpatRaster. Seasonal Transpiration (mm).

- biomass_unit:

  Character. Unit: "kg/ha" (default) or "t/ha".

- provenance:

  Optional named provenance records for `biomass` and `transpiration`.

- compatibility_mode:

  Missing-metadata policy: `"warn"` or `"strict"`. Known
  incompatibilities always stop the calculation.

## Value

Numeric or SpatRaster. NBWP in kg/m3.

## References

Molden, D., Oweis, T., Steduto, P., Bindraban, P., Hanjra, M. A., &
Kijne, J. (2010). Improving agricultural water productivity: Between
optimism and realism. Agricultural Water Management, 97(4), 528-535.

## Examples

``` r
wapor_calc_nbwp(12000, 300) # 12000 kg/ha biomass, 300 mm T -> 4.0 kg/m3
#> [1] 4
```
