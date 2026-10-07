# Bright and dark productivity spots

Protocol pair: land productivity `lp` (biomass or yield) and water
productivity `wp`. bright = lp \>= P_high AND wp \>= P_high; dark = lp
\<= P_low AND wp \<= P_low (package convention); else normal. Built with
explicit `>=` / `<=` (a value equal to a threshold is bright or dark).
Zone mode classifies zone means (recommended for management use).

## Usage

``` r
wapor_classify_spots(
  lp,
  wp,
  breaks = NULL,
  labels = NULL,
  reference = NULL,
  id = NULL,
  zones = NULL,
  zone_id = NULL,
  min_cell_fraction = 0.5
)
```

## Source

Chukalla et al. (2020).

## Arguments

- lp, wp:

  Numeric or SpatRaster.

- breaks:

  Two values: either probabilities in (0, 1) (default 0.05, 0.95) or
  absolute thresholds (when any value is outside (0, 1)).

- labels:

  Unused; classes are dark / normal / bright.

- reference, id:

  Grouping for percentiles.

- zones, zone_id:

  Zone mode: classify means per polygon.

- min_cell_fraction:

  Reserved for pixel-mode edge filtering (heuristic).

## Value

A categorical SpatRaster, a factor, or a zone table.
