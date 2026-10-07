# Compute Crop Water Productivity

CWP = Yield / AETI, with unit conversion to kg/m3. AETI in mm is
equivalent to m3/(10 ha) or 1 mm = 10 m3/ha. CWP measures the physical
mass of harvested economic crop yield produced per cubic meter of total
evapotranspired water.

## Usage

``` r
wapor_calc_cwp(yield_value, aeti_mm, yield_unit = "kg/ha")
```

## Arguments

- yield_value:

  Numeric. Yield (scalar or raster).

- aeti_mm:

  Numeric. Seasonal AETI in mm (scalar or raster).

- yield_unit:

  Character. Unit of yield: "kg/ha" (default) or "t/ha".

## Value

Numeric or SpatRaster. CWP in kg/m3.

## References

Molden, D. (1997). Accounting for water use and productivity. SWIM
Paper 1. International Irrigation Management Institute (IIMI), Colombo,
Sri Lanka.

Bastiaanssen, W. G. M., & Steduto, P. (2012). The water productivity
score (WPS) for irrigated crops: Concept and application. Agricultural
Water Management, 108, 119-132.

## Examples

``` r
wapor_calc_cwp(5000, 400)  # 5000 kg/ha, 400 mm -> kg/m3
#> [1] 1.25
```
