# Guess L3 Region from Spatial Intersection

Guess L3 Region from Spatial Intersection

## Usage

``` r
wapor_guess_region(variable, reg_info, period)
```

## Arguments

- variable:

  Character. The WaPOR variable name (e.g., L3-AETI-D)

- reg_info:

  List from wapor_parse_region()

- period:

  Date period vector

## Value

Character vector of intersecting L3 regions, or NULL
