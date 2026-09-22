# Group a vector of variable codes by shared native grid

Splits a character vector of variable codes into named groups where all
members share the same resolution key (and therefore the same native
pixel grid). Only groups with more than one variable benefit from
batched extraction; single-variable groups are left as-is.

## Usage

``` r
wapor_group_by_res(variables)
```

## Arguments

- variables:

  Character vector of variable codes.

## Value

A named list of character vectors, one element per unique resolution
key. Names are the resolution keys.

## Examples

``` r
wapor_group_by_res(c("L1-AETI-D", "L1-NPP-D", "L1-PCP-D", "L2-AETI-D"))
#> $L1_300m
#> [1] "L1-AETI-D" "L1-NPP-D" 
#> 
#> $L1_5000m
#> [1] "L1-PCP-D"
#> 
#> $L2_100m
#> [1] "L2-AETI-D"
#> 
# $L1_300m   -> c("L1-AETI-D", "L1-NPP-D")
# $L1_5000m  -> "L1-PCP-D"
# $L2_100m   -> "L2-AETI-D"
```
