# Retrieve classification metadata

Retrieve classification metadata

## Usage

``` r
wapor_class_info(x)
```

## Arguments

- x:

  A classified factor or SpatRaster.

## Value

The `wapor_classes` metadata list, or `NULL`.

## Examples

``` r
wapor_class_info(wapor_classify(1:3, breaks = 2:3))
#> $scheme
#> NULL
#> 
#> $method
#> [1] "fixed"
#> 
#> $breaks
#> [1] 2 3
#> 
#> $labels
#> [1] "1" "2" "3"
#> 
#> $right
#> [1] TRUE
#> 
#> $direction
#> [1] "none"
#> 
#> $thresholds
#>   group t1 t2
#> 1   all  2  3
#> 
#> $source
#> NULL
#> 
```
