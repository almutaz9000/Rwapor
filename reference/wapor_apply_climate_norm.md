# Apply a climate normalisation factor

Normalises water consumption depths or water productivity indicators to
remove the confounding effect of spatial climate variability
(evaporative demand).

## Usage

``` r
wapor_apply_climate_norm(x, f_norm, type = c("depth", "productivity"))
```

## Arguments

- x:

  Numeric or SpatRaster.

- f_norm:

  Factor from
  [`wapor_calc_climate_norm()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_climate_norm.md).

- type:

  `"depth"` or `"productivity"`.

## Value

The same type as `x` (or a raster if `x` is a raster).

## Details

Mathematical Derivation: With climate factor \\f\_{norm} =
\overline{RET} / RET\\:

- **Depth indicators (AETI, ETc in mm):** Multiplied by \\f\_{norm}\\.
  \$\$Depth\_{norm} = Depth \times \frac{\overline{RET}}{RET}\$\$ Areas
  with higher evaporative demand (\\RET \> \overline{RET}\\, so
  \\f\_{norm} \< 1\\) have their consumed depth scaled downward to
  represent consumption under regional average demand.

- **Productivity indicators (CWP, BWP in kg/m3):** Divided by
  \\f\_{norm}\\. Since \\WP = Yield / Depth\\, normalising depth in the
  denominator yields: \$\$WP\_{norm} = \frac{Yield}{Depth\_{norm}} =
  \frac{Yield}{Depth \times f\_{norm}} = \frac{WP}{f\_{norm}} = WP
  \times \frac{RET}{\overline{RET}}\$\$ Under harsh, high-evaporative
  climates, plants inevitably consume more water per kg biomass
  produced, depressing unadjusted WP. Dividing by \\f\_{norm}\\
  compensates for this climatic penalty, enabling fair comparison of
  agricultural performance across diverse agro-climatic zones.

## References

Chukalla, A. D., Krol, M. S., & Hoekstra, A. Y. (2022). Climate
normalisation of crop water productivity and irrigation performance
indicators. Agricultural Water Management, 260, 107297.
