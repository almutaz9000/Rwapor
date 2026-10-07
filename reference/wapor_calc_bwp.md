# Compute Biomass Water Productivity

BWP = Biomass / AETI, with unit conversion to kg/m3. AETI in mm is
converted to m3/ha (1 mm = 10 m3/ha). BWP reflects total dry matter or
above-ground biomass produced per cubic meter of water evaporated and
transpired.

## Usage

``` r
wapor_calc_bwp(biomass_value, aeti_mm, biomass_unit = "kg/ha")
```

## Arguments

- biomass_value:

  Numeric. Biomass (scalar or raster).

- aeti_mm:

  Numeric. Seasonal AETI in mm (scalar or raster).

- biomass_unit:

  Character. Unit: "kg/ha" (default) or "t/ha".

## Value

Numeric or SpatRaster. BWP in kg/m3.

## References

Bastiaanssen, W. G. M., & Steduto, P. (2012). The water productivity
score (WPS) for irrigated crops: Concept and application. Agricultural
Water Management, 108, 119-132.

## Examples

``` r
wapor_calc_bwp(12000, 400)  # 12000 kg/ha biomass, 400 mm -> kg/m3
#> [1] 3
```
