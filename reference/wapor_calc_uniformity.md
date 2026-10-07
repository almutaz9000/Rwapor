# Irrigation uniformity within units

Per unit: `uniformity_cv = 1 - CV` (Chukalla proxy), Christiansen CU,
and low-quarter DU. Classes come from `uniformity_<method>` and are
applied to `uniformity_cv`. With `irrigation_method = "unknown"` only
values are returned. Units smaller than `min_area_ha` are NA.

## Usage

``` r
wapor_calc_uniformity(
  aeti,
  units,
  id = NULL,
  mask = NULL,
  weights = NULL,
  irrigation_method = c("unknown", "surface", "sprinkler", "pivot", "drip"),
  measures = c("uniformity_cv", "cu", "du_lq"),
  min_area_ha = 1,
  min_cell_fraction = 0.5,
  sd_type = "population"
)
```

## Source

Chukalla et al. (2022); Pitts et al. (1996); Christiansen (1942);
Merriam and Keller (1978).

## Arguments

- aeti:

  SpatRaster of AETI (or another ET layer).

- units:

  `sf` polygons, SpatVector, file path, or a single number: block size
  in metres (projected CRS required).

- id:

  Polygon id column. Default: first attribute, or `block_id`.

- mask, weights:

  Passed to
  [`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md).

- irrigation_method:

  One of `unknown`, `surface`, `sprinkler`, `pivot`, `drip`.

- measures:

  Statistics to return.

- min_area_ha:

  Units below this valid area (ha) get NA (default 1; heuristic).

- min_cell_fraction:

  Passed to the zonal engine (default 0.5; heuristic).

- sd_type:

  `"population"` (default) or `"sample"`.

## Value

A data frame, one row per unit.

## Details

The method standards are for applied water. 1 - CV of ET overstates
irrigation uniformity; DU_lq is the closer comparison. Blocks generated
from a numeric size measure landscape heterogeneity, not field
uniformity.
