# Productivity target and gap

Target = type-7 percentile `p` of `x` within the reference group
(default P95). Gap = max(0, target - x). Production gap = sum(gap x
area), so t/ha becomes tonnes when cell areas are in hectares.

## Usage

``` r
wapor_calc_productivity_gap(
  x,
  p = 0.95,
  reference = NULL,
  id = NULL,
  zones = NULL,
  zone_id = NULL
)
```

## Source

Chukalla et al. (2020) WAPORWP Module 5.

## Arguments

- x:

  Numeric or SpatRaster (for example yield or biomass).

- p:

  Percentile (default 0.95).

- reference, id:

  Grouping as in
  [`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md).

- zones, zone_id:

  Optional polygons to summarise production gap per zone.

## Value

A list with `gap`, `target` and `production_gap`.
