# Equity of ET between units

CV of the unit means (unweighted by default, as in the literature).
Optional area weighting. Class from scheme `equity` (good / fair /
poor).

## Usage

``` r
wapor_calc_equity(
  aeti,
  units,
  id = NULL,
  mask = NULL,
  weights = NULL,
  unit_weights = c("none", "area"),
  min_area_ha = 1,
  sd_type = "population"
)
```

## Source

Bastiaanssen et al. (1996); Chukalla et al. (2022).

## Arguments

- aeti:

  SpatRaster.

- units:

  Polygons or a block size in metres (see
  [`wapor_calc_uniformity()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_uniformity.md)).

- id, mask, weights, min_area_ha, sd_type:

  As in
  [`wapor_calc_uniformity()`](https://almutaz9000.github.io/Rwapor/reference/wapor_calc_uniformity.md).

- unit_weights:

  `"none"` (default) or `"area"`.

## Value

A list with `cv`, `class`, `unit_means` and settings.
