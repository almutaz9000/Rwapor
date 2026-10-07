# Classify irrigation adequacy (AETI / ETc)

Wrapper for
[`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md)
with scheme `"adequacy"`. Formula: class of the ratio AETI/ETc. Default
breaks 0.68, 0.80, 1.00 (poor / acceptable / good / above ETc). Class 4
is a package extension, not a published over-irrigation class; for
deficit irrigation, rainfed crops and salinity, a "poor" class can be
intended management.

## Usage

``` r
wapor_classify_adequacy(adequacy, breaks = NULL, labels = NULL, right = TRUE)
```

## Source

Karimi et al. (2019); Chukalla et al. (2022).

## Arguments

- adequacy:

  Numeric vector or SpatRaster of AETI/ETc.

- breaks, labels, right:

  Passed to
  [`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md).

## Value

A factor or categorical SpatRaster.

## Examples

``` r
wapor_classify_adequacy(c(0.68, 0.8, 1, 1.01))
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
