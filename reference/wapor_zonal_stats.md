# Zonal Statistics for Any Polygons on Any WaPOR Raster

Area-weighted statistics, volumes, crop share, data coverage and class
shares for polygons at one or several nested levels (for example scheme
and farm), on a raster or on the result of
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md).

## Usage

``` r
wapor_zonal_stats(
  x,
  zones,
  id,
  stats = c("mean", "area_ha", "mask_fraction", "coverage"),
  probs = c(0.1, 0.9),
  mask = NULL,
  weights = NULL,
  dissolve = TRUE,
  aoi = TRUE,
  classes = NULL,
  breaks = NULL,
  labels = NULL,
  method = NULL,
  scheme = NULL,
  min_coverage = 0.5,
  min_cell_fraction = 0,
  min_mask_area_ha = 0,
  sd_type = c("population", "sample"),
  days = NULL,
  season = NULL,
  normalize_id = TRUE,
  layers = NULL,
  format = c("long", "wide", "sf")
)
```

## Arguments

- x:

  A `SpatRaster` (one layer per variable or time step), or the result of
  [`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md).
  For a result the default layers are those present among
  `seasonal_aeti`, `seasonal_t`, `seasonal_ret`, `seasonal_pcp`,
  `seasonal_peff`, `etc`, `adequacy_etc`, `adequacy_p95`,
  `beneficial_fraction`, `green_water`, `blue_water`,
  `seasonal_biomass_t` and `yield_raster`; seasonal totals carry the
  unit mm.

- zones:

  Polygons: `sf`, `SpatVector` or a vector file path.

- id:

  One or more column names of `zones`, from coarse to fine. Several
  columns give nested levels; each level is computed from its own
  dissolved geometry, never by averaging the finer zones.

- stats:

  Statistics to return: `"mean"`, `"median"`, `"quantiles"` (at
  `probs`), `"sd"`, `"cv"`, `"cu"`, `"du_lq"`, `"gini"`, `"theil"`,
  `"min"`, `"max"`, `"count"`, `"n_eff"`, `"area_ha"`,
  `"mask_fraction"`, `"coverage"`, `"sum_volume"`, `"class_share"`. See
  Details.

- probs:

  Probabilities for `"quantiles"`.

- mask:

  Optional raster; cells where it is 0 or `NA` do not count.

- weights:

  Optional raster of fractions between 0 and 1, for example the crop
  fraction from
  [`wapor_harmonize_mask()`](https://almutaz9000.github.io/Rwapor/reference/wapor_harmonize_mask.md).
  Prefer it to a hard mask at Level 1 and Level 2, where most pixels are
  mixed.

- dissolve:

  Merge polygons that share the same id values. Default `TRUE`.

- aoi:

  Add one row set for the union of all zones (level 0, id `"AOI"`).

- classes:

  Optional classified raster (integer codes, optionally with category
  labels). With `"class_share"` its classes are reported instead of
  classes of `x`.

- breaks, labels, method, scheme:

  Classify the values of `x` for `"class_share"` with
  [`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md).

- min_coverage:

  Zones with a smaller valid share of their masked area get `NA`
  statistics (areas, `count` and `n_eff` are still reported).

- min_cell_fraction:

  Drop cells of which a smaller fraction is covered by the zone (removes
  mixed edge pixels from spread statistics).

- min_mask_area_ha:

  Zones with a smaller masked area get `NA` statistics.

- sd_type:

  `"population"` (default, as in the IHE Delft WaPOR protocol) or
  `"sample"`.

- days:

  Days per layer, to turn rates (mm/day) into depths for `"sum_volume"`:
  a numeric vector in layer order, or a data frame with columns `layer`
  and `days`.

- season:

  Optional season label written to the `season` column.

- normalize_id:

  Build `zone_key` as upper case without surrounding blanks, so that
  `" f01 "` and `"F01"` match. Default `TRUE`.

- layers:

  Layers of `x` to use (names or indices; output names for an analysis
  result).

- format:

  `"long"` (default), `"wide"` (see
  [`wapor_zonal_wide()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_wide.md))
  or `"sf"` (the wide table of the finest level and the AOI, with
  geometry).

## Value

For `format = "long"` a data frame of class `wapor_zonal` with one row
per zone, layer and statistic: `level` (0 = AOI, 1 = first id column,
...), `zone_id`, `zone_key`, the id columns, `season`, `variable`,
`period`, `stat`, `class`, `value`, `unit`. Attribute
`"wapor_zonal_call"` records the settings; `"wapor_classes"` the classes
of `"class_share"`.

## Details

Each cell counts with the weight `w = a * m * f`: `a` is the area of the
cell covered by the zone in m2 (from exactextractr; for lon/lat rasters
the covered fraction times the cell's area on the WGS84 ellipsoid), `m`
the mask (1 inside), `f` the weight fraction. Cells with data and
`w > 0` are the valid cells.

- `area_ha`: area of the zone geometry (lon/lat zones are measured in an
  equal-area projection). `mask_fraction` = masked area / zone area (the
  crop share). `coverage` = valid area / masked area (the data share).
  The two are different questions and are reported separately.

- `mean` = `sum(w v) / sum(w)`; `median` and `quantiles` are weighted
  and equal `quantile(type = 7)` for equal weights.

- `sd`: population `sqrt(sum(w (v - mean)^2) / sum(w))`; the sample form
  multiplies the variance by `V1^2 / (V1^2 - V2)` with `V1 = sum(w)`,
  `V2 = sum(w^2)`. `cv` = `sd / mean`.

- `cu` = `1 - sum(w |v - mean|) / (mean sum(w))` (Christiansen, 1942).
  `du_lq` = mean of the lowest quarter of the weight / mean (Merriam and
  Keller, 1978). `gini` and `theil` (over `v > 0`) are weighted.

- `count` = number of valid cells; `n_eff` = sum of their covered
  fractions.

- `sum_volume` (m3, and `sum_volume_mcm` in million m3) =
  `sum(depth / 1000 * w)`. Depth units (`mm`, `mm/season`, `mm/month`,
  `mm/year`, `mm/dekad`) are used as they are; rates (`mm/day`) need
  `days`. Layers with another or no unit give no volume, with a warning.

- `class_share`: `class_area_ha` per class and `class_pct` = class area
  / valid area \* 100 (the denominator is the area with data, so the
  shares sum to 100), plus the area without data as class `"no data"`.
  Every class is listed, also with zero area, when the classes are known
  (labels, a scheme, or a categorical raster).

Resolution: a warning is given when a zone holds fewer than about 3 x 3
whole cells (`n_eff < 9`) and spread statistics are requested; they are
not reliable there (heuristic). At 100 m and 300 m most cells along
field borders are mixed: use `weights`, or `min_cell_fraction`.

Layers are read in groups sized to `options(Rwapor.memory_budget_mb)`.

## See also

[`wapor_zonal_wide()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_wide.md),
[`wapor_classify()`](https://almutaz9000.github.io/Rwapor/reference/wapor_classify.md),
[`wapor_harmonize_mask()`](https://almutaz9000.github.io/Rwapor/reference/wapor_harmonize_mask.md).

## Examples

``` r
r <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200,
                 ymin = 3600000, ymax = 3600200, crs = "EPSG:32636", vals = 1:100)
names(r) <- "aeti"
terra::units(r) <- "mm"
half <- sf::st_sf(farm = "west", geometry = sf::st_as_sfc(sf::st_bbox(
  c(xmin = 700000, ymin = 3600000, xmax = 700100, ymax = 3600200), crs = 32636)))
wapor_zonal_stats(r, half, id = "farm", stats = c("mean", "area_ha", "sum_volume"), aoi = FALSE)
#>   level zone_id zone_key farm season variable period           stat class
#> 1     1    west     WEST west   <NA>     aeti   <NA>        area_ha  <NA>
#> 2     1    west     WEST west   <NA>     aeti   <NA>           mean  <NA>
#> 3     1    west     WEST west   <NA>     aeti   <NA>     sum_volume  <NA>
#> 4     1    west     WEST west   <NA>     aeti   <NA> sum_volume_mcm  <NA>
#>     value unit
#> 1 2.0e+00   ha
#> 2 4.8e+01   mm
#> 3 9.6e+02   m3
#> 4 9.6e-04  Mm3
```
