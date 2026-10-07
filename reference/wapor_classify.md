# Classify numeric values or a raster using fixed or quantile thresholds

Fixed intervals use `(-Inf, b1]`, `(b1, b2]`, ..., `(bn, Inf)` when
`right = TRUE`; with `right = FALSE`, boundary values move to the upper
interval. Quantile thresholds use type-7 quantiles within reference
groups. Groups below `min_n` (default 30) are returned as `NA` and
reported in one warning. Defaults are literature schemes; `direction`
records whether higher or lower values are better and does not reverse
the interval order.

## Usage

``` r
wapor_classify(
  x,
  breaks = NULL,
  labels = NULL,
  method = c("fixed", "quantile"),
  reference = NULL,
  id = NULL,
  scheme = NULL,
  right = TRUE,
  min_n = 30
)
```

## Arguments

- x:

  Numeric vector or a terra SpatRaster.

- breaks:

  Break values, or probabilities for `method = "quantile"`.

- labels:

  Class labels, one more than `breaks`.

- method:

  Classification method, `"fixed"` or `"quantile"`.

- reference:

  Optional grouping vector, SpatRaster, or polygon data.

- id:

  Polygon attribute used for reference groups.

- scheme:

  Optional default scheme.

- right:

  Logical interval closure.

- min_n:

  Minimum observations per quantile group.

## Value

An integer categorical SpatRaster or factor.

## Details

Scheme defaults from
[`wapor_class_defaults()`](https://almutaz9000.github.io/Rwapor/reference/wapor_class_defaults.md)
(every scheme has a `source`):

|  |  |  |  |  |  |
|----|----|----|----|----|----|
| scheme | method | breaks | labels | direction | source |
| adequacy | fixed | 0.68, 0.80, 1.00 | poor, acceptable, good, above ETc | higher_better | Karimi et al. (2019); Chukalla et al. (2022) |
| equity | fixed | 0.10, 0.25 | good, fair, poor | lower_better | Bastiaanssen et al. (1996); Karimi et al. (2019) |
| uniformity_surface | fixed | 0.65 | below standard, meets standard | higher_better | Pitts et al. (1996) |
| uniformity_sprinkler | fixed | 0.75 | below standard, meets standard | higher_better | Pitts et al. (1996) |
| uniformity_pivot | fixed | 0.75 | below standard, meets standard | higher_better | Pitts et al. (1996) |
| uniformity_drip | fixed | 0.85 | below standard, meets standard | higher_better | Pitts et al. (1996) |
| spots | quantile | 0.05, 0.95 | dark, normal, bright | higher_better | Chukalla et al. (2020) WAPORWP Module 5 |

Class 4 of adequacy is labelled "above ETc". It is a package class, not
a published over-irrigation class. Uniformity schemes are per irrigation
method, not one ordinal scale. Project overrides:
`options(Rwapor.class_breaks)`.

## Examples

``` r
wapor_classify(c(0.68, 0.8, 1, 1.01), scheme = "adequacy")
#> [1] poor       acceptable good       above ETc 
#> attr(,"wapor_classes")
#> attr(,"wapor_classes")$scheme
#> [1] adequacy
#> 
#> attr(,"wapor_classes")$method
#> [1] fixed
#> 
#> attr(,"wapor_classes")$breaks
#> [1] 0.68 0.80 1.00
#> 
#> attr(,"wapor_classes")$labels
#> [1] poor       acceptable good       above ETc 
#> 
#> attr(,"wapor_classes")$right
#> [1] TRUE
#> 
#> attr(,"wapor_classes")$direction
#> [1] higher_better
#> 
#> attr(,"wapor_classes")$thresholds
#>   group   t1  t2 t3
#> 1   all 0.68 0.8  1
#> 
#> attr(,"wapor_classes")$source
#> [1] Karimi et al. (2019) Remote Sens. 11, 705; as applied in Chukalla et al. (2022) HESS 26, 2759-2778 (Sect. 2.3.2)
#> 
#> Levels: poor acceptable good above ETc
```
