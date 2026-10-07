# Classification schemes and defaults

Classification schemes and defaults

## Usage

``` r
wapor_class_defaults(scheme = NULL)
```

## Arguments

- scheme:

  Optional scheme name.

## Value

`wapor_class_defaults()` returns a scheme list, or all schemes.

## Examples

``` r
wapor_class_defaults("adequacy")
#> $breaks
#> [1] 0.68 0.80 1.00
#> 
#> $labels
#> [1] "poor"       "acceptable" "good"       "above ETc" 
#> 
#> $method
#> [1] "fixed"
#> 
#> $right
#> [1] TRUE
#> 
#> $direction
#> [1] "higher_better"
#> 
#> $units
#> [1] "ratio"
#> 
#> $source
#> [1] "Karimi et al. (2019) Remote Sens. 11, 705; as applied in Chukalla et al. (2022) HESS 26, 2759-2778 (Sect. 2.3.2)"
#> 
#> $note
#> [1] "above ETc is a package class, not published; check Kc and data, not a performance class"
#> 
```
