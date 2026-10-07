# Relative water deficit

RWD = 1 - AETI / ETx, with ETx = ETc (`etx_method = "etc"`) or the
type-7 percentile `p` of AETI within each reference group
(`"percentile"`). The IHE Delft protocol uses ETp or P99; package
adequacy uses P95. Values are not clamped. Also returns the deficit
depth ETx - AETI (mm).

## Usage

``` r
wapor_calc_rwd(
  aeti,
  etx = NULL,
  etx_method = c("etc", "percentile"),
  p = 0.95,
  reference = NULL,
  id = NULL
)
```

## Source

Bastiaanssen and Bos (1999); Chukalla et al. (2020) WAPORWP Module 3.

## Arguments

- aeti:

  Actual evapotranspiration (mm), numeric or SpatRaster.

- etx:

  Optional ETc (or other demand) raster or numeric. Required when
  `etx_method = "etc"`.

- etx_method:

  `"etc"` or `"percentile"`.

- p:

  Percentile of AETI when `etx_method = "percentile"` (default 0.95).

- reference, id:

  Grouping for the percentile, as in
  [`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md).

## Value

A list with `rwd`, `deficit_mm` and `etx`.
