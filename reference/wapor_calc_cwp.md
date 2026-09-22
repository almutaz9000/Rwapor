# Compute Crop Water Productivity

CWP = Yield / AETI, with unit conversion to kg/m3. AETI in mm is
equivalent to l/m2; 1 mm = 10 m3/ha.

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

## Examples

``` r
wapor_calc_cwp(5000, 400)  # 5000 kg/ha, 400 mm -> kg/m3
#> [1] 1.25
```
