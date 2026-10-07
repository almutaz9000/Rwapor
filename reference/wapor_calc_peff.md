# USDA-SCS effective precipitation from monthly rasters

CROPWAT simplification (Smith 1992): Peff = P (125 - 0.2 P) / 125 for P
\<= 250 mm/month, else 125 + 0.1 P. Applied to each monthly raster, then
summed to a seasonal total.

## Usage

``` r
wapor_calc_peff(monthly_rasters)
```

## Source

Smith (1992) CROPWAT.

## Arguments

- monthly_rasters:

  Named list of monthly precipitation SpatRasters (mm).

## Value

List with `monthly` (Peff rasters) and `seasonal` (sum of monthly Peff).

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_calc_peff(list(`2023-01` = p_jan, `2023-02` = p_feb))
} # }
```
