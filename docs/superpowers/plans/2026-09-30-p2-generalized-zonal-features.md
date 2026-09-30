# P2 implementation plan (v2): zonal statistics, configurable classes and irrigation performance indicators

| | |
|---|---|
| **Status** | v2, 2026-09-30. Design approved by the user; science reviewed by a domain expert agent (geospatial analysis, WaPOR, irrigation performance assessment, agronomy, agrometeorology). Ready for implementation, one work package at a time. |
| **Target release** | Rwapor **1.0.6** (unreleased; ships together with the P0 correctness gates). If 1.0.6 is released before P2 is finished, use **1.0.7**. Current dev version: `1.0.5.9000`. |
| **Written by** | Claude (planner). **Implementers**: any model (Codex, Antigravity, Claude, ...). |
| **Board tasks** | WP1 + WP2: `ti-10` (+ `ti-16`); WP3: `ti-09`, `ti-13`; WP4: `ti-11`; WP5: `ti-12`, `ti-14`, `ti-15`; WP6: new task `p2-peff` (`agent-workflow/agents-board.json`). |
| **Scientific review** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (cited below as "Review §x"). Every default in this plan follows it. |
| **Design background** | `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`, section "P2". |

### What changed from v1

v1 was derived from one training notebook. v2 is general: the training (citrus in the North Jordan Valley,
winter wheat in Jendouba) is only one example that showed which features were missing. Main changes:

- Defaults come from the published literature, with correct sources (adequacy: Karimi et al. 2019 as
  applied by Chukalla et al. 2022; equity: Bastiaanssen et al. 1996; spots: the IHE Delft/FAO WaPOR
  protocol). Heuristics are labelled as such.
- Uniformity classes are per irrigation method (one standard each), not one ordinal scale.
- WP2 separates the crop share of a zone from data coverage, computes volumes only from depths, uses one
  standard deviation definition and a weighted quantile that equals R's type 7 for equal weights.
- Resolution-independent parameters (hectares and cell fractions, not pixel counts), so the same call
  works at L1 (300 m), L2 (100 m) and L3 (20 m).
- New indicators: relative water deficit, productivity targets and gaps, temporal reliability,
  Christiansen CU, low-quarter DU, Gini, net irrigation requirement, Kc climate adjustment.
- Perennial crops: evergreen and deciduous types, dormant Kc, verified FAO-56 rows, FAO-56 stage names.
- New WP6: effective rainfall method choice and rainfed classes.
- The training becomes an optional local example check, never a standard.

---

## 0. How to use this plan (every implementer)

1. Start every session with `agent-workflow/START-HERE.md` (preflight, board, session brief).
2. Implement **one work package (WP) per run**: WP1 -> WP2 -> WP3; WP4, WP5 and WP6 are independent
   and can run in any order after WP1.
3. Claim the board task first:
   `.\agent-workflow\scripts\board_claim.ps1 -Id <task-id> -Model <your-model> -Status active -Notes "plan: docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md WP<n>"`
4. Edit **only** the files in the WP's file table. If another file must change, stop and report.
5. Run the WP's validation commands; report each result line; tick every done criterion with evidence.
6. Do not commit or push unless the user asks. Branch: `version-1.0.6` (exists; update it from the
   default branch first). CI runs on `version-*` branches.
7. If something in this plan is wrong or impossible, stop and report (`STATUS: blocked`, file and line).
   Never replace an UNVERIFIED value with a guess.

### Principles (apply to every WP)

- **General, not case-specific.** Any crop, region, scale (field to country), WaPOR level, season
  (including seasons crossing 1 January), irrigated or rainfed. Nothing may assume the training's crops,
  regions, resolution or dates.
- **Literature defaults, configurable everything.** Every threshold is a documented default with its
  source, changeable by argument or `options()`. Values marked UNVERIFIED in the review must not become
  defaults or golden test values.
- **Resolution-independent parameters.** Minimum sizes in hectares and cell fractions, never raw pixel
  counts.
- **Transparent results.** Every classified or derived result carries the parameters that produced it.
- **Known-answer rule.** `tests/testthat/test-known-answer.R` must keep passing unchanged: no WP changes
  existing analysis numbers by default. Changing existing defaults (e.g. the crop table corrections in
  decision D5) is a separate, announced change with regenerated golden values.

### Project conventions

- R: `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` (Windows);
  `devtools::document()`, `devtools::test(filter = ...)`; `devtools::check()` at the end of a WP that
  changes exports.
- Style: base pipe `|>`, `pkg::fun()`, no `library()` in `R/`, `stop(..., call. = FALSE)`, roxygen2 with
  `@export`, `@param`, `@return`, `@examples` (`\dontrun{}` for slow or network examples), lintr/styler
  clean.
- No new hard dependencies (Imports: terra, sf, exactextractr, ...). `ggplot2` is in Suggests: guard
  plot code with `requireNamespace()`.
- Progress messages via `.wapor_inform()`; problems via `warning()` / `stop()`.
- Units: depths mm; rates mm/day; areas m2 / ha; volumes m3 (1 mm over 1 ha = 10 m3). Never planar area
  math on longitude/latitude.
- Tests compare with independent calculations (base R, hand values from Review §5), never with the
  function's own output.
- Update `NEWS.md` (section `# Rwapor 1.0.6 (development)`, at the top) and the board/`task-status.md`
  entry at the end of each WP.
- If a local full test run fails with "No space left on device", rerun the failing files individually
  and report it (CI is the reference).

---

## 1. Objectives

| # | Objective | Measurable success |
|---|---|---|
| O1 | One general zonal engine for any polygons at any scale | `wapor_zonal_stats()` returns correct weighted statistics, volumes, crop share, coverage and class shares from field to country; tests against independent values (Review §5, tests 11 to 15) |
| O2 | Every classification configurable and correctly sourced | One `wapor_classify()`; schemes with literature sources; no hard-coded thresholds; parameters travel with results |
| O3 | Irrigation performance assessment for any units | Adequacy, uniformity (1 - CV, CU, DU_lq) per irrigation method, equity, reliability, relative water deficit, climate normalization |
| O4 | Productivity targets, gaps and bright/dark spots for pixels or zones | Protocol definitions (P95 targets, both LP and WP), shares per zone and AOI |
| O5 | Perennial crops handled correctly | Verified FAO-56 rows, evergreen/deciduous types, dormant Kc, optional FAO-56 Eq. 62/65 climate adjustment |
| O6 | Effective rainfall and green/blue water that fit any climate and water source | Peff method choice; rainfed classes get no blue water |
| O7 | Remove common traps | Masks that reproject and return fractions (usable as weights), guarded plots, offline URL lists |

**Non-goals (later releases)**: download cache (ti-06), parallel remote opening (ti-07), supply-based
indicators with delivery data (Review §3.7), yield response to water Ky (§3.8), full multi-season and
double-cropping engine support (§3.9; only a `season` column is reserved now), full USDA-SCS NEH 623 Peff,
dekadal Peff, soil-water-balance green/blue split, normalized biomass WP (needs dekadal T/ET0 wiring),
`wapor_ts()`/monitoring refactor onto the zonal engine.

---

## 2. Architecture

```
            user rasters / wapor_run_seasonal_analysis() result
                                |
   +----------------------------+-----------------------------+
   |                                                          |
 wapor_classify()   (WP1)                           wapor_zonal_stats()   (WP2)
  schemes + breaks/labels/method/reference            any zones, nested ids, weights (fraction masks)
  direction, min_n, metadata                          mean, median, quantiles, sd, cv, cu, du_lq, gini,
                                                      theil, min, max, count, n_eff, area_ha,
                                                      mask_fraction, coverage, sum_volume, class_share
   |                                                          |
   +-----------------------------+----------------------------+
                                 |
  WP3 indicators: adequacy classes, uniformity (per method), equity, reliability, RWD,
      productivity targets/gaps, spots, climate normalization, NIR / deficit
  WP4 perennial crops + wapor_adjust_kc_climate()     WP5 masks (fractions), plots, offline URLs
  WP6 effective rainfall methods + rainfed classes (seasonal-analysis engine)
```

New files: `R/classify.R` (WP1), `R/zonal_stats.R` (WP2), `R/performance_indicators.R` (WP3),
`R/kc_adjust.R` (WP4), `R/mask_helpers.R` (WP5). WP6 edits existing files.

---

## 3. WP1: configurable classification engine (`ti-10` part 1)

**Objective**: one classifier for every classification, with literature defaults, user breaks,
fixed or percentile methods, reference groups, class direction and attached metadata.
**Effort**: small to medium. **Depends on**: nothing.

### Files

| File | Change |
|---|---|
| `R/classify.R` | new: `wapor_classify()`, `wapor_class_defaults()`, `wapor_class_info()`, internal helpers |
| `tests/testthat/test-classify.R` | new |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | NEWS entry; `devtools::document()` |

### Default schemes (`wapor_class_defaults()`)

Each scheme: `list(breaks, labels, method, right, direction, units, source, note)`.

| scheme | method | breaks | labels | direction | source |
|---|---|---|---|---|---|
| `adequacy` | fixed | `c(0.68, 0.80, 1.00)` | poor, acceptable, good, above ETc | higher_better (up to 1) | Karimi et al. (2019) Remote Sens. 11, 705; as applied in Chukalla et al. (2022) HESS 26, 2759-2778 (Sect. 2.3.2). Note: "above ETc" is a package class, not published; it usually signals a Kc or data issue, not over-consumption. |
| `equity` | fixed | `c(0.10, 0.25)` (CV as a fraction) | good, fair, poor | lower_better | Bastiaanssen et al. (1996); Karimi et al. (2019); quoted in Chukalla et al. (2022) |
| `uniformity_surface` | fixed | `0.65` | below standard, meets standard | higher_better | Pitts et al. (1996), quoted in Chukalla et al. (2022); standard written for applied water |
| `uniformity_sprinkler` | fixed | `0.75` | below standard, meets standard | higher_better | same |
| `uniformity_pivot` | fixed | `0.75` | below standard, meets standard | higher_better | same |
| `uniformity_drip` | fixed | `0.85` | below standard, meets standard | higher_better | same |
| `spots` | quantile | `c(0.05, 0.95)` | dark, normal, bright | higher_better | Chukalla et al. (2020) WaPOR productivity protocol (Zenodo 10.5281/zenodo.4641360; WAPORWP Module 5): targets at P95, bright = at or above target. "dark" (at or below P5) is a package convention. |

No default scheme for relative water deficit or beneficial fraction (no published class limits; Review
§2 WP1). Molden & Gates (1990) adequacy and dependability bands are **not** shipped in 1.0.6 (their exact
bands are UNVERIFIED; decision D11).

Project-wide overrides: `options(Rwapor.class_breaks = list(<scheme> = list(breaks = ..., labels = ...)))`
merged field by field over the defaults.

### API

```r
wapor_classify(x, breaks = NULL, labels = NULL, method = c("fixed", "quantile"),
               reference = NULL, id = NULL, scheme = NULL, right = TRUE, min_n = 30)
wapor_class_defaults(scheme = NULL)
wapor_class_info(x)
```

- `x`: SpatRaster (one or more layers) or numeric vector.
- `scheme`: default scheme name; `breaks`, `labels`, `method` left `NULL` come from it (after
  `options(Rwapor.class_breaks)`). Without `scheme`, `breaks` is required and `method = "fixed"`.
- `method = "fixed"`: intervals with `right = TRUE`: `(-Inf, b1]`, `(b[k-1], b[k]]`, `(b_n, Inf)`;
  `right = FALSE`: `[b[k-1], b[k])`. Adequacy with `right = TRUE`: poor <= 0.68 < acceptable <= 0.80 <
  good <= 1.00 < above ETc.
- `method = "quantile"`: `breaks` are probabilities in (0, 1); thresholds =
  `stats::quantile(type = 7)` of the non-NA values within each reference group
  (`reference = NULL`: all values; a SpatRaster of group codes, resampled with `"near"` if needed; or
  polygons + `id`, rasterized to the grid of `x`). Groups with fewer than `min_n` values get NA
  thresholds and NA classes, with one warning listing them (`min_n = 30` matches the existing
  `wapor_calc_p95_aeti()` default).
- Returns an integer categorical SpatRaster (codes `1..length(breaks) + 1`,
  `terra::levels(r) <- data.frame(value, class)`) or a factor for numeric input.
- Attribute `"wapor_classes"` (also written with `terra::metags()` so it survives GeoTIFF):
  `list(scheme, method, breaks, labels, right, direction, thresholds, source)`; `thresholds` is a
  data.frame (`group`, `t1..tn`).
- Validation errors: non-numeric, non-finite, unsorted or duplicate breaks; `length(labels) !=
  length(breaks) + 1`; quantile breaks outside (0, 1); `id` missing for polygon references; unknown scheme
  (message lists the available ones).

### Tests (`test-classify.R`; expected values from Review §5)

1. Adequacy tie rule: `c(0.68, 0.80, 1.00, 1.0001)` -> poor, acceptable, good, above ETc.
2. `right = FALSE` moves the boundary values up one class.
3. Custom breaks on a 4 x 4 SpatRaster (values 1..16, breaks `c(4, 8, 12)`): codes `rep(1:4, each = 4)`;
   `terra::levels()` holds the labels; `wapor_class_info()` returns breaks, source and direction.
4. Quantile, one group, values 1..100, `c(0.05, 0.95)`: thresholds 5.95 and 95.05 (type 7); counts
   5 / 90 / 5.
5. Quantile per group (values 1..100 and 101..200): thresholds per group; 5 / 90 / 5 per group; same result
   with a group raster and with two polygons + `id`.
6. `min_n`: a group of 20 values gets NA classes and a warning.
7. Uniformity per method: 0.70 is "meets standard" with `uniformity_surface`, "below standard" with
   `uniformity_sprinkler`.
8. Option override: `Rwapor.class_breaks = list(adequacy = list(breaks = c(0.6, 0.8, 1)))` makes 0.65
   acceptable; labels stay the defaults.
9. Validation errors (each case above) and the unknown-scheme message.
10. Metadata survives a GeoTIFF round trip (`wapor_class_info()` after `writeRaster()` / `rast()`).

### Validation

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] 10 test groups pass; known-answer unchanged
- [ ] Class thresholds exist only in `wapor_class_defaults()`; every scheme has a `source`
- [ ] `?wapor_classify` documents the interval rule, `min_n`, `direction`, and the defaults table with sources

---

## 4. WP2: `wapor_zonal_stats()`, the general zonal engine (`ti-10` part 2, `ti-16`)

**Objective**: weighted statistics, volumes, crop share, data coverage and class shares for any polygons
(nested levels) on any WaPOR raster or analysis result, correct at every WaPOR resolution.
**Effort**: medium. **Depends on**: WP1.

### Files

| File | Change |
|---|---|
| `R/zonal_stats.R` | new: `wapor_zonal_stats()`, `wapor_zonal_wide()`, internal statistics helpers (`.wapor_wmean`, `.wapor_wsd`, `.wapor_wquantile`, `.wapor_cu`, `.wapor_du_lq`, `.wapor_wgini`, `.wapor_wtheil`) |
| `tests/testthat/test-zonal-stats.R` | new (synthetic) |
| `tests/testthat/test-zonal-known-answer.R` | new (existing known-answer fixture) |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | as usual |

### API

```r
wapor_zonal_stats(
  x, zones, id,
  stats = c("mean", "area_ha", "mask_fraction", "coverage"),
  probs = c(0.1, 0.9),
  mask = NULL, weights = NULL,
  dissolve = TRUE, aoi = TRUE,
  classes = NULL, breaks = NULL, labels = NULL, method = NULL, scheme = NULL,
  min_coverage = 0.5, min_cell_fraction = 0, min_mask_area_ha = 0,
  sd_type = c("population", "sample"),
  days = NULL, season = NULL,
  normalize_id = TRUE, layers = NULL,
  format = c("long", "wide", "sf")
)
wapor_zonal_wide(z)
```

**Arguments** (differences from a plain zonal mean are the point of this engine):

- `x`: SpatRaster (layer names = variables or time steps) or a `wapor_run_seasonal_analysis()` result
  (`layers` selects outputs; default: present among `seasonal_aeti`, `seasonal_t`, `seasonal_ret`,
  `seasonal_pcp`, `seasonal_peff`, `etc` (combined from `etc_by_class`), `adequacy_etc`, `adequacy_p95`,
  `beneficial_fraction`, `green_water`, `blue_water`, `seasonal_biomass_t`, `yield_raster`; internal
  `.wapor_result_layers()`; elements `list(raster = ...)` use `$raster`).
- `zones`: sf, SpatVector or vector file path. `id`: one or more columns; several = nested levels from
  coarse to fine; each level is extracted from its own dissolved geometry (never by averaging children).
- `mask`: optional binary mask (cells where `mask` is NA do not count). `weights`: optional fractional
  weight raster in [0, 1] (e.g. the crop fraction from `wapor_harmonize_mask()`, WP5); cell weight =
  covered area x fraction. Use `weights` rather than a hard mask at L1/L2, where most pixels are mixed
  (Review §3.10).
- `stats`: `"mean"`, `"median"`, `"quantiles"` (`probs`), `"sd"`, `"cv"`, `"cu"`, `"du_lq"`, `"gini"`,
  `"theil"`, `"min"`, `"max"`, `"count"`, `"n_eff"`, `"area_ha"`, `"mask_fraction"`, `"coverage"`,
  `"sum_volume"`, `"class_share"`.
- `min_cell_fraction`: drop cells whose covered fraction of the cell is below this (removes mixed edge
  pixels from spread statistics; default 0).
- `min_coverage`: applies to `coverage` only (valid share of the **masked** area); zones below it get NA
  statistics (except the area terms, `count`, `n_eff`), with one warning naming the first 5 zones.
- `min_mask_area_ha`: zones whose masked (crop) area is smaller get NA statistics (default 0).
- `sd_type`: population (default, as the IHE Delft WaPOR protocol) or sample.
- `days`: per-layer day counts (numeric vector or data.frame with `layer`, `days`) used to turn rate
  layers (mm/day) into depths for `sum_volume`.
- `season`: optional season id (character) written to the output `season` column (reserved for
  multi-season support; default NA, or taken from the analysis result when available).
- `classes`/`breaks`/`labels`/`method`/`scheme`: for `class_share` (already classified integer layers, or
  classify on the fly with WP1).
- `format`: long (default), wide (`wapor_zonal_wide()`), or sf (finest level plus AOI, wide columns).

**Output (long)**: data.frame of class `c("wapor_zonal", "data.frame")`: `level`, `zone_id`,
`zone_key` (`toupper(trimws(id))`), parent id columns, `season`, `variable`, `period`, `stat`, `class`,
`value`, `unit`. Class shares: `stat = "class_area_ha"` and `"class_pct"` per class, every class listed
(zero included), plus a `"no data"` class area row. Attributes: `"wapor_classes"`, `"wapor_zonal_call"`
(stats, mask/weights used, thresholds, sd_type, area method).

### Algorithm (normative)

1. Normalize inputs; `sf::st_make_valid()`; drop empty geometries (warning); check `id` columns (error
   lists available columns).
2. Dissolve per level (group by the id combination, `sf::st_union()` per group; no dplyr).
3. Transform zones to `terra::crs(x)`.
4. Extract with `exactextractr::exact_extract(x_stack, zones, coverage_area = TRUE,
   max_cells_in_memory = <.wapor_memory_budget_bytes() / 8>, progress = FALSE)` where `x_stack` includes
   the value layers, the mask indicator and the weight raster; zones in batches of 500. `coverage_area` is
   the covered area of each cell in m2 (geodesic for geographic rasters).
5. Per zone: `a` = `coverage_area`; `frac` = covered fraction of the cell (`coverage_fraction`); drop
   cells with `frac < min_cell_fraction`; `m` = mask indicator (1 inside, 0 outside); `f` = weight
   fraction (1 without `weights`); weight `w = a * m * f`; `ok = !is.na(v) & w > 0`.
   - Areas: `zone_area_ha` from the geometry, equal-area: for projected CRSs `sf::st_area()`; for
     geographic CRSs `sf::st_area()` with `sf::sf_use_s2(FALSE)` (ellipsoidal geodesic via lwgeom),
     restored on exit (fixes the s2 "degenerate edge" failure, ti-16). `mask_area_ha = sum(a * m * f) /
     1e4`; `valid_area_ha = sum(w[ok]) / 1e4`.
   - `mask_fraction = mask_area_ha / zone_area_ha`; `coverage = valid_area_ha / mask_area_ha` (clamp
     [0, 1]).
   - `mean = sum(w v) / sum(w)` over `ok`.
   - `sd` population: `sqrt(sum(w (v - mean)^2) / sum(w))`; sample: multiply the variance by
     `V1^2 / (V1^2 - V2)` with `V1 = sum(w)`, `V2 = sum(w^2)` (reduces to n/(n-1) for equal weights).
   - `cv = sd / mean` (NA if mean is 0).
   - Weighted quantile that reduces to `type = 7` for equal weights: sort by `v`; positions
     `pos_i = (cumsum(w)_i - w_i) / (sum(w) - w_n)`; linear interpolation of `v` at `p` on `pos`
     (Review §2 WP2, issue 2.3). Test the equal-weight case against `quantile(type = 7)`.
   - `cu = 1 - sum(w |v - mean|) / (mean * sum(w))` (Christiansen 1942).
   - `du_lq` = weighted mean of the lowest 25% of the weight distribution / `mean` (Merriam & Keller
     1978): take the cells in increasing `v` until their cumulative weight reaches 25% of `sum(w)`
     (split the boundary cell's weight).
   - `gini`: weighted Gini `sum_i sum_j w_i w_j |v_i - v_j| / (2 * sum(w)^2 * mean)` (compute with the
     sorted-cumulative formula, O(n log n)).
   - `theil = sum(w (v/mean) ln(v/mean)) / sum(w)` over `v > 0`.
   - `min`, `max`, `count` (number of `ok` cells), `n_eff = sum(frac[ok])`.
   - `sum_volume` (m3) = `sum(depth / 1000 * w)`; `depth = v` for depth units (`mm`, `mm/season`,
     `mm/month`, `mm/year`, or `mm/dekad` for a dekad total); for rate units (`mm/day`) `depth = v *
     days[layer]`, and without `days` the volume row is skipped with one warning per layer. Also
     `sum_volume_mcm` (million m3).
   - `class_share`: `class_area_ha = sum(w[ok & v == k]) / 1e4`; `class_pct = 100 * sum(w[ok & v == k])
     / sum(w[ok])`; plus `no data` area = `(mask_area_ha - valid_area_ha)`.
6. Apply `min_coverage` and `min_mask_area_ha`; warn once.
7. Warn once per call when zones have `n_eff < 9` for spread statistics (sd, cv, cu, du_lq, gini, theil,
   quantiles): "fewer than about 3 x 3 whole cells: spread statistics are unreliable at this resolution"
   (heuristic, Review §2 issue 2.6).
8. Assemble the long table; AOI row set over `sf::st_union()` of all zones when `aoi = TRUE`.

Performance (optional, allowed): exactextractr's built-in summary operations may be used for `mean`,
`count` and `frac` when they give identical results; custom statistics use the R path above. Verify
equality in a test before using them.

### Tests (`test-zonal-stats.R`, synthetic; EPSG:32636 10 x 10 grid of 20 m cells at x = 700000,
y = 3600000, values `1:100` row-wise, unit `"mm"`)

1. Aligned halves: mean = plain mean of the covered cells; count 50; area 2 ha; coverage 1; mask_fraction 1.
2. Half a cell: count 1, weight 200 m2, area 0.02 ha, mean = that cell's value, `n_eff` 0.5.
3. Partial cells: one full cell (a = 10) and half of another (b = 20): mean = 13.333.
4. `min_cell_fraction = 0.6` drops the half cell of test 3: mean = 10.
5. Crop share vs coverage (Review test 11): zone of 100 cells, mask keeps 20, 5 of those NA:
   `mask_fraction` 0.20, `coverage` 0.75, statistics not NA at `min_coverage = 0.5`.
6. Fraction weights (Review test 15): two equal cells, values 500 (fraction 1.0) and 300 (fraction 0.25):
   mean 460.
7. Volumes: depth layer 100 mm over 2 ha = 2000 m3; rate layer 2.0 mm/day over 1 ha with `days = 8` =
   160 m3; rate layer without `days`: no volume row, one warning. Dekad day counts: February 2023 third
   dekad 8 days, February 2024 third dekad 9, January third dekad 11 (independent check via
   `lubridate::days_in_month()` or base date arithmetic).
8. Nested levels: `scheme` (2) and `farm` (4) with one smaller quadrant: parent mean = mean over the
   parent's cells (not the mean of child means); when children partition the parent, parent volume = sum
   of child volumes (1e-9 relative).
9. Dissolve: two polygons with the same id -> one zone, count = sum.
10. AOI over overlapping polygons: AOI area = union area.
11. Coverage threshold: 60% of a zone's cells NA with `min_coverage = 0.5` -> coverage 0.4, mean NA,
    warning; with 0.3 the mean of valid cells.
12. Spread statistics on 1..100 with equal weights (Review test 8): `1 - cv` (population) 0.42840, `cu`
    0.504950, `du_lq` 0.257426, `gini` 0.33; `theil` of `c(1, 2, 3, 4)` 0.106440; `sd_type = "sample"`
    equals `sd()`.
13. Weighted quantile with equal weights equals `quantile(x, p, type = 7)` for random x and p in
    {0.05, 0.5, 0.95}.
14. Class share: classes from `breaks = c(25, 50, 75)`; shares by independent counting; sum 100; zero
    classes listed; "no data" area row.
15. Geographic raster (EPSG:4326, 0.01 degree cells near 32 N): `area_ha` equals `terra::expanse()` of the
    polygon within 0.1%; per-cell weights match `terra::cellSize(unit = "m")` within 0.1%.
16. `n_eff < 9` warning for a zone of 4 cells when `stats` includes `sd`.
17. Formats (`wide`, `sf`) and `normalize_id` (`" f01 "` and `"F01"` share a `zone_key`).
18. Errors: missing id column (message lists columns); no overlap (coverage 0, warning); `class_share`
    on a non-integer layer without `breaks`/`scheme` (error explains how to classify).

### Tests (`test-zonal-known-answer.R`, real data)

Use `tests/testthat/fixtures/known-answer/citrus` (unstack as in `test-known-answer.R`; copy the small
helpers). Run the citrus analysis exactly as in `test-known-answer.R` (memory mode). Zones: four 10 x 10
pixel quadrants with `scheme` (north/south) and `block` (q1..q4) in the fixture CRS.

1. Quadrant means of every layer = plain means of the 100 cells (independent index arithmetic), 1e-9.
2. AOI mean `seasonal_aeti` = 446.3228 and `etc` = 1050.9293 (golden.csv), 1e-6.
3. AOI `sum_volume` of `seasonal_aeti` = 446.3228 / 1000 * 160000 m3 (16 ha), 1e-6 relative.
4. Class share of `adequacy_etc` with `scheme = "adequacy"`: sums to 100; equals independent pixel counts.

### Validation

```powershell
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] 18 synthetic and 4 fixture test groups pass; known-answer unchanged
- [ ] Crop share and coverage reported separately; volumes only from depths or with `days`
- [ ] One sd definition (population default) and a weighted quantile equal to type 7 for equal weights
- [ ] `?wapor_zonal_stats` documents every formula, units, the class-share denominator, and the
      resolution caveats (n_eff, mixed pixels, fraction weights)

---

## 5. WP3: irrigation performance indicators, productivity gaps and spots (`ti-09`, `ti-13`)

**Objective**: the core WaPOR irrigation performance indicators for any units, built on WP1/WP2, with
literature definitions and configurable classes. **Effort**: medium. **Depends on**: WP1, WP2.

### Files

| File | Change |
|---|---|
| `R/performance_indicators.R` | new: functions below |
| `R/analysis_indicators.R` | `@export` and full roxygen for `wapor_calc_cv()` (~line 883), `wapor_calc_peff()` (~858), `wapor_calc_theil()` (~917); no behaviour change |
| `tests/testthat/test-performance-indicators.R` | new |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | as usual |

### API and definitions

| Function | Definition | Source |
|---|---|---|
| `wapor_classify_adequacy(adequacy, breaks = NULL, labels = NULL, right = TRUE)` | `wapor_classify(scheme = "adequacy")` | Karimi et al. (2019); Chukalla et al. (2022) |
| `wapor_calc_rwd(aeti, etx = NULL, etx_method = c("etc", "percentile"), p = 0.95, reference = NULL, id = NULL)` | RWD = 1 - AETI / ETx; ETx = ETc raster, or the percentile `p` of AETI within each reference group (the IHE Delft protocol uses ETp or P99; package adequacy uses P95). Not clamped in stored data. Also returns deficit depth `ETx - AETI` (mm). | Bastiaanssen & Bos (1999); Chukalla et al. (2020) WAPORWP Module 3 |
| `wapor_calc_uniformity(aeti, units, id = NULL, mask = NULL, weights = NULL, irrigation_method = c("unknown", "surface", "sprinkler", "pivot", "drip"), measures = c("uniformity_cv", "cu", "du_lq"), min_area_ha = 1, min_cell_fraction = 0.5, sd_type = "population")` | Per unit: `uniformity_cv = 1 - CV` (Chukalla proxy), Christiansen CU, low-quarter DU (WP2 statistics). Classes from `uniformity_<method>` (one standard per method) applied to `uniformity_cv`; `"unknown"`: values only, no classes. Units with valid area below `min_area_ha` are NA. Docs state that the standards are for applied water and 1 - CV of ET overstates irrigation uniformity (DU_lq is the closer comparison). | Chukalla et al. (2022); Pitts et al. (1996); Christiansen (1942); Merriam & Keller (1978) |
| `wapor_calc_equity(aeti, units, id = NULL, mask = NULL, weights = NULL, unit_weights = c("none", "area"), min_area_ha = 1, sd_type = "population")` | CV of the unit means (unweighted by default, as the literature; `"area"` optional). Class from scheme `equity`. | Bastiaanssen et al. (1996); Chukalla et al. (2022) |
| `wapor_calc_reliability(ratio_stack, zones = NULL, id = NULL, sd_type = "population")` | Temporal CV of relative ET per pixel (or per zone via WP2): input is a stack of monthly AETI_t / ETc_t (the engine's `monthly_aeti` and `monthly_etc`; helper `wapor_relative_et_stack(result)` builds it). Monthly by default (dekadal relative ET is noisy). No default class scheme. | Bastiaanssen & Bos (1999) |
| `wapor_calc_climate_norm(ret, zones = NULL, id = NULL, weights = c("area", "none"), mask = NULL)` | f_norm = mean(RET) / RET per pixel; the mean is area-weighted over the masked area (Chukalla weights by field size and growing length; season length weighting is the caller's choice via per-season inputs). | Chukalla et al. (2022) Eq. 3 |
| `wapor_apply_climate_norm(x, f_norm, type = c("depth", "productivity"))` | depth indicators multiplied by f_norm; productivity divided by f_norm. Docs: this application rule follows from WP being inversely related to evaporative demand (UNVERIFIED as a published convention; say so). | Review §2 WP3 issue 3.6 |
| `wapor_calc_productivity_gap(x, p = 0.95, reference = NULL, id = NULL, zones = NULL, zone_id = NULL)` | target = P`p` of `x` within the reference group; gap = max(0, target - x); production gap = sum(gap x area) via WP2 (units from `x`, e.g. t/ha -> t). | Chukalla et al. (2020) protocol (WAPORWP Module 5) |
| `wapor_classify_spots(lp, wp, breaks = NULL, labels = NULL, reference = NULL, id = NULL, zones = NULL, zone_id = NULL, min_cell_fraction = 0.5)` | Protocol pair: land productivity `lp` (biomass or yield) and water productivity `wp`. bright = `lp >= P_high` AND `wp >= P_high`; dark = `lp <= P_low` AND `wp <= P_low` (package convention); else normal. Built with explicit `>=`/`<=` comparisons (a value equal to a threshold is bright/dark). Zone mode (`zones`) classifies zone means (recommended for management use). Warns when `reference = NULL` and the AOI has more than one crop class. | Chukalla et al. (2020) |
| `wapor_calc_nir(etc_monthly, peff_monthly)` | Net irrigation requirement NIR = sum over months of max(0, ETc_m - Peff_m) (mm); volume via WP2. | Allen et al. (1998); Smith (1992) CROPWAT |

Block units: `units` may be a single number (block size in metres; projected CRS required, else an error
suggesting polygons or `terra::project()`): blocks are generated with `sf::st_make_grid()` and evaluated
with the WP2 engine (one code path, one sd definition). Docs: blocks are a fallback when field
boundaries are missing and measure landscape heterogeneity, not field uniformity.

### Tests (`test-performance-indicators.R`; independent values from Review §5)

1. Adequacy classes on the known-answer wheat fixture's `adequacy_etc`: counts = independent
   `table(cut(values, c(-Inf, 0.68, 0.8, 1, Inf)))`.
2. RWD: AETI 400, ETc 500 -> 0.20; percentile ETx on 1..100 with `p = 0.99` -> ETx 99.01.
3. Uniformity: a unit with values 1..100 -> `uniformity_cv` 0.42840, `cu` 0.504950, `du_lq` 0.257426;
   `irrigation_method = "surface"` with 1 - CV = 0.70 -> meets standard; `"sprinkler"` -> below;
   `"unknown"` -> no class column values.
4. `min_area_ha`: a 0.5 ha unit is NA at the default 1 ha.
5. Equity: unit means c(10, 12, 14): population CV 0.13608, sample 0.16667, class "fair" both.
6. Reliability: a pixel with monthly ratios c(1, 1, 1) -> 0; c(0.5, 1.0, 1.5) -> population CV 0.40825.
7. Climate norm: RET constant -> 1; RET c(2, 4) on equal areas -> c(1.5, 0.75); apply: depth 100 x 1.5 =
   150; productivity 1.2 / 1.5 = 0.8.
8. Productivity gap: yields 1..100 -> target 95.05; gap at 90 = 5.05, at 100 = 0; production gap over 1 ha
   cells = 4469.75.
9. Spots: lp = wp = 1..100 -> 5 bright (96..100), 5 dark (1..5); wp reversed -> 0 bright, 0 dark; a value
   equal to a user-fixed threshold is bright.
10. Spots per reference group (two groups) -> 5 + 5 bright per group; zone mode returns one class per zone;
    `class_share` of the spot raster sums to 100 per zone.
11. NIR: ETc c(100, 80), Peff c(30, 90) -> 70 mm.
12. `wapor_calc_cv()`, `wapor_calc_peff()`, `wapor_calc_theil()` are exported and documented.

### Optional local example check (never a standard; skip without training data, skip on CI)

With the training notebook data present, run the package functions on the wheat case and print the
results next to the notebook's (adequacy classes, block uniformity/equity, f_norm). Differences are
expected where the package uses literature defaults (population sd, `min_area_ha`); report them, do not
tune the package to match.

### Validation

```powershell
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'performance-indicators')"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] 12 test groups pass; known-answer unchanged
- [ ] Every class threshold from `wapor_class_defaults()` or user arguments; every function's help cites
      its source and formula and states known caveats (proxy uniformity, rainfed/deficit adequacy)

---

## 6. WP4: perennial crops and Kc climate adjustment (`ti-11`)

**Objective**: correct FAO-56 data for tree and vine crops, evergreen and deciduous behaviour, and an
optional climate adjustment of tabulated Kc. **Effort**: medium. **Depends on**: nothing.

### Files

| File | Change |
|---|---|
| `R/crop_defaults.R` | new columns and verified rows in `FAO_CROP_DEFAULTS`; `crop_type`, `kc_dormant`, `start_month`, `stage_names` in `wapor_create_crop_params()` / `wapor_custom_crop()`; `fc` documentation; corrected `notes` of existing rows (values unchanged, decision D5) |
| `R/kc_adjust.R` | new: `wapor_adjust_kc_climate()` |
| the file that builds daily Kc for the season (`wapor_build_kc()` in `R/analysis.R`, and the kernel profile code in `R/processing_kernel.R`; locate with grep) | dormant Kc outside the stages for deciduous crops |
| the file where `yield_npp` / `cwp_bwp` are computed (grep) | skip the NPP yield chain for perennial classes |
| `tests/testthat/test-perennial.R` | new |
| `NEWS.md`, `man/*.Rd` | as usual |

### Steps

1. New columns in `FAO_CROP_DEFAULTS` (grep all usages first; existing tests must pass):
   `crop_type` (`"annual"`, `"perennial_evergreen"`, `"perennial_deciduous"`; `"annual"` for the 12
   existing rows), `kc_dormant` (NA except deciduous), `start_month` (FAO-56 Table 11 start month, NA
   where not given), `stage_names` (NA = FAO-56 names initial / development / mid-season / late season).
2. New rows, **all values VERIFIED from FAO-56 Tables 11 and 12 in the review** (Review §2 WP4):

   | crop_name | kc_ini | kc_mid | kc_end | h (m) | stages ini/dev/mid/late | start_month | crop_type |
   |---|---|---|---|---|---|---|---|
   | Citrus, no ground cover, 70% canopy | 0.70 | 0.65 | 0.70 | 4 | 60/90/120/95 | 1 | perennial_evergreen |
   | Citrus, no ground cover, 50% canopy | 0.65 | 0.60 | 0.65 | 3 | 60/90/120/95 | 1 | perennial_evergreen |
   | Citrus, no ground cover, 20% canopy | 0.50 | 0.45 | 0.55 | 2 | 60/90/120/95 | 1 | perennial_evergreen |
   | Citrus, active ground cover, 70% canopy | 0.75 | 0.70 | 0.75 | 4 | 60/90/120/95 | 1 | perennial_evergreen |
   | Citrus, active ground cover, 50% canopy | 0.80 | 0.80 | 0.80 | 3 | 60/90/120/95 | 1 | perennial_evergreen |
   | Citrus, active ground cover, 20% canopy | 0.85 | 0.85 | 0.85 | 2 | 60/90/120/95 | 1 | perennial_evergreen |
   | Olives (40 to 60% ground cover) | 0.65 | 0.70 | 0.70 | 4 (3 to 5) | 30/90/60/90 | 3 | perennial_evergreen |
   | Grapes, table or raisin | 0.30 | 0.85 | 0.45 | 2 | 20/40/120/60 | 4 | perennial_deciduous |
   | Grapes, wine | 0.30 | 0.70 | 0.45 | 1.75 (1.5 to 2) | 30/60/40/80 | 4 | perennial_deciduous |
   | Pistachios, no ground cover | 0.40 | 1.10 | 0.45 | 4 (3 to 5) | 20/60/30/40 | 2 | perennial_deciduous |
   | Apples, cherries, pears (no ground cover, killing frost) | 0.45 | 0.95 | 0.70 | 4 | 20/70/120/60 | 3 | perennial_deciduous |
   | Stone fruit (no ground cover, killing frost) | 0.45 | 0.90 | 0.65 | 3 | 20/70/120/60 | 3 | perennial_deciduous |

   `region` = the Table 11 region (Mediterranean or low latitudes as in the review table); `notes` cite
   "FAO-56 Table 12 (Kc, h), Table 11 (stages, start)" and the relevant footnotes (citrus: +0.1 to 0.2 in
   humid/subhumid climates, footnotes 21 and 22; olives: 40 to 60% cover, footnote 24; deciduous:
   footnote 18). Deciduous `kc_dormant = 0.20` (footnote 18: bare dry soil or dead cover; document that
   0.50 to 0.80 applies with active ground cover). `HI`, `MC`, `AOT` = NA for perennial rows; `fc = 1.0`.
   **Not added** (UNVERIFIED in the review): date palm (no Table 11 row found), avocado (stages not
   checked), banana (two-year crop; later with multi-season support).
3. `wapor_create_crop_params()` / `wapor_custom_crop()`: new arguments `crop_type`, `kc_dormant`,
   `start_month`, `stage_names`, stored in the params (defaults from the base crop, else `"annual"`/NA).
4. Kc curve: for `perennial_deciduous`, days of the season outside the four stages get `kc_dormant`;
   evergreen and annual crops unchanged (known-answer ETc unchanged). Seasons crossing 1 January must
   work (test with a January to December citrus year and an October to September water year).
5. Yield chain: for perennial classes, skip `yield_npp` and `cwp_bwp` with one warning ("NPP-based yield
   uses field-crop factors; skipped for perennial class <k>; supply measured yields (decision D1)").
6. `wapor_adjust_kc_climate(kc_mid, kc_end, u2, rh_min, h)` (exported, pure numeric): FAO-56 Eq. 62
   `Kc_mid = Kc_mid_tab + (0.04 (u2 - 2) - 0.004 (rh_min - 45)) (h / 3)^0.3`, and Eq. 65 for `kc_end` only
   when `kc_end_tab > 0.45`. Clamp inputs to the validity range (1 <= u2 <= 6 m/s, 20 <= rh_min <= 80 %,
   0.1 < h < 10 m) with a warning. **Re-read the constants on the FAO-56 page
   (https://www.fao.org/4/x0490e/x0490e0b.htm) before coding** and cite the equation numbers. Not applied
   automatically in 1.0.6 (decision D10).
7. `@param fc`: "Light use efficiency correction factor: crop LUE / WaPOR generic LUE; about 1 for C3 crops,
   above 1 for C4 crops (e.g. 1.6 for sugarcane in Chukalla et al. 2022)." Same text in
   `R/analysis_indicators.R`.
8. Existing rows (decision D5): correct only the `notes` column now (Winter Wheat: Kc_ini 0.40 is the
   FAO-56 frozen-soil value, non-frozen is 0.7; Sorghum: Table 12 grain sorghum Kc_ini is 0.2; Sugarcane:
   stage lengths do not match a single Table 11 row; Alfalfa: one cutting cycle). Values unchanged.

### Tests (`test-perennial.R`)

1. All new rows present with exactly the values in the table above; `crop_type`, `start_month` correct
   (citrus start 1).
2. `wapor_custom_crop(base_crop = "Citrus, no ground cover, 70% canopy")` carries crop_type and stages;
   stage names default to the FAO-56 names.
3. The known-answer citrus configuration with this profile gives golden ETc 1050.9293 (1e-6).
4. Deciduous dormant Kc: a 365-day year with stages 20/70/120/60 and `kc_dormant = 0.20`: the 95 remaining
   days have Kc 0.20; the annual mean Kc equals the hand-computed piecewise-linear mean.
5. Year-crossing seasons (January to December; October to September) build a Kc curve of the right length.
6. Perennial class with `yield_npp` requested: no yield raster, one warning; wheat known-answer yield
   5.0362 unchanged.
7. Eq. 62: citrus 0.65, u2 3, RHmin 30, h 4 -> 0.75901; wheat 1.15, u2 4, RHmin 25, h 1 -> 1.26508;
   Eq. 65 not applied for kc_end 0.30; out-of-range inputs clamped with a warning.
8. Existing crop-default tests pass unchanged; existing values unchanged.

### Done criteria

- [ ] Tests pass; known-answer unchanged; every new row cites FAO-56; no UNVERIFIED crop added

---

## 7. WP5: mask helpers, plots, offline URL lists (`ti-12`, `ti-14`, `ti-15`)

**Objective**: masks that work on any grid and return fractions usable as weights; safe plots; offline
URL lists. **Effort**: small. **Depends on**: nothing (WP2 uses the fraction output).

### Files

| File | Change |
|---|---|
| `R/mask_helpers.R` | new: `wapor_rasterize_mask()`, `wapor_harmonize_mask()` |
| `R/viz.R` | remove `aes_string()` (lines ~27, ~89); `requireNamespace("ggplot2")` guard; calendar/stage Kc plot |
| the file where `wapor_generate_urls()` caches API responses (grep `Rwapor.cache_ttl`) | stale-cache fallback when offline |
| `tests/testthat/test-mask-helpers.R`, `test-viz-basic.R`, `test-offline-urls.R` | new |

### Steps

1. `wapor_rasterize_mask(polygons, template, field = NULL, value = 1L, touches = FALSE, fraction = FALSE)`:
   reproject polygons to the template CRS automatically; rasterize (`field` or constant `value`,
   background NA), layer name `"crop_mask"`. With `fraction = TRUE`, return the covered fraction per cell
   (from `exactextractr::coverage_fraction()`), usable as `weights` in WP2. Area check: mask area vs
   polygon area (as WP2); tolerance depends on polygon size in cells (warn outside 0.9 to 1.1 only for
   polygons of at least 25 cells); attribute `"area_ratio"`.
2. `wapor_harmonize_mask(crop_map, template, class, min_fraction = 0.5, value = NULL, return_fraction = TRUE)`:
   per class, binary (1 = class, 0 otherwise including NA) -> `terra::project(method = "average")` to the
   template grid = fraction; binary mask where fraction >= `min_fraction` (heuristic majority rule,
   documented); several classes -> largest fraction wins; returns `list(mask, fraction)` when
   `return_fraction = TRUE` (the fraction is the recommended WP2 weight at L1/L2).
3. `R/viz.R`: guard with `requireNamespace("ggplot2", quietly = TRUE)` (clear error if missing);
   replace `aes_string()` with `aes()` on bare names plus `utils::globalVariables(c("x", "y", "value",
   "day", "kc"))` (rlang is not imported); keep `geom_raster()` for regular grids (fast; `geom_tile()` only
   for irregular grids); full data via `terra::as.data.frame(r, xy = TRUE)`.
   `wapor_plot_kc_curve(kc_daily, save = NULL, dpi = 300, start_date = NULL, stage_days = NULL,
   stage_names = NULL)`: date axis with `start_date`; shaded stages with FAO-56 names by default; dormant
   periods shown; seasons crossing 1 January; old calls unchanged.
4. Offline URL lists: when the live request fails and a cached response exists (even beyond the TTL), use
   it with one message "No connection to the WaPOR server; using the URL list cached on <date>."; without
   a cache keep the current error; never use a stale cache when the server answers.

### Tests

1. Lon/lat polygons on a UTM template: non-empty mask, area ratio within 0.9 to 1.1; direct
   `terra::rasterize()` without reprojection gives an empty mask (documents the trap).
2. `fraction = TRUE`: a polygon covering half of a cell gives 0.5 in that cell.
3. Harmonize: a 10 m map on a 20 m template, class in 3 of 4 sub-cells: fraction 0.75, kept at 0.5,
   dropped at 0.8; two classes: largest fraction wins.
4. Plots: no warnings (`expect_no_warning()`), full-resolution data (1e6 rows for 1000 x 1000); clear
   error when ggplot2 is not available (mock `requireNamespace`).
5. Offline: mocked failing HTTP after a cached call -> cached URLs + message; no cache -> previous error;
   working server -> fresh request.

### Done criteria

- [ ] Tests pass; no `aes_string` in `R/`; known-answer unchanged

---

## 8. WP6: effective rainfall methods and rainfed classes (new task `p2-peff`)

**Objective**: effective rainfall and the green/blue split that suit any climate and water source,
without changing current results by default. **Effort**: small to medium. **Depends on**: nothing.

### Files

| File | Change |
|---|---|
| `R/indicators_math.R` / `R/analysis_indicators.R` (where `wapor_math_peff_usda` and `wapor_calc_peff` live) | `peff_method` argument and new methods |
| the engine/registry code computing monthly Peff and green/blue (`R/analysis_engine.R`, `R/analysis_registry.R`; grep `monthly_green_water`) | pass `config$peff_method`, `config$peff_fraction`; rainfed classes |
| `R/crop_defaults.R` | `water_source` (`"irrigated"` default, `"rainfed"`) in crop params |
| `tests/testthat/test-peff-methods.R` | new |
| `NEWS.md`, `man/*.Rd` | as usual |

### Steps

1. `wapor_calc_peff(monthly_rasters, method = c("usda_cropwat", "fao_aglw", "fixed", "none"),
   fraction = NULL)`:
   - `usda_cropwat` (default, current behaviour): P <= 250: P (125 - 0.2 P) / 125; else 125 + 0.1 P
     (Smith 1992, CROPWAT). Documented as the CROPWAT simplification, not the full USDA-SCS NEH 623 method.
   - `fao_aglw` (dependable rain): P <= 70: max(0, 0.6 P - 10); else 0.8 P - 24 (Smith 1992 CROPWAT; the
     primary document is UNVERIFIED in the review: cite as "FAO/AGLW formula as implemented in CROPWAT").
   - `fixed`: `fraction * P`; `fraction` required (no default; error otherwise).
   - `none`: Peff = P.
   Monthly totals only (document: formulas are calibrated on monthly totals; partial start/end months
   slightly overestimate; a dekadal split gives more blue water).
2. Seasonal analysis config: `peff_method` (default `"usda_cropwat"`) and `peff_fraction`; recorded in the
   result metadata and exports.
3. Crop params `water_source`: for `"rainfed"` classes, blue water = 0, green = AETI, and the difference
   `AETI - Peff` (positive part) is returned as `unexplained_water` ("stored soil water or other sources")
   instead of blue water. Irrigated classes unchanged.
4. Help pages state: green/blue from min(AETI, Peff) ignores soil water stored before the season (winter
   rain used by Mediterranean crops and trees is booked as blue water for irrigated classes); WaPOR
   precipitation is much coarser than L3 AETI, so field-scale green/blue variation comes from AETI.

### Tests (independent values, Review §5 tests 16 to 18)

1. `usda_cropwat`: P 100 -> 84.0; 250 -> 150.0; 300 -> 155.0.
2. `fao_aglw`: P 10 -> 0; 50 -> 20; 70 -> 32; 100 -> 56.
3. `fixed` with 0.7: P 100 -> 70; `fixed` without `fraction` -> error. `none`: P 100 -> 100.
4. Rainfed class: AETI 300, Peff 200 -> green 300, blue 0, unexplained 100.
5. Default run: known-answer tests unchanged (all 236 golden values).
6. A run with `peff_method = "fao_aglw"` changes `seasonal_peff` and green/blue exactly as recomputed
   independently from the fixture's monthly precipitation.

### Done criteria

- [ ] Tests pass; known-answer unchanged with defaults; method and fraction recorded in results

---

## 9. Release and documentation (after WP1 to WP6)

1. `DESCRIPTION`: `Version: 1.0.6`; rename the NEWS section to `# Rwapor 1.0.6` and summarise.
2. Vignette `vignettes/zonal-statistics-and-performance.Rmd`, evaluated offline on a copy of the
   known-answer citrus fixture in `inst/extdata/example-citrus/`: zonal statistics at two levels, crop
   share vs coverage, volumes, class shares of adequacy and spots per zone and AOI, custom breaks,
   uniformity per irrigation method, equity, productivity gaps. The example is neutral: it demonstrates
   the functions, it does not set standards.
3. `devtools::check()` 0 errors / 0 warnings; CI green on `version-1.0.6`; live release checks pass.
4. Separate task: update the training notebook to use the package functions (differences caused by the
   literature defaults are documented in the notebook, not removed).

---

## 10. Decisions

### Decided (user, 2026-09-30)

- Zones of any scale; class shares per zone and AOI; every class break and percentile configurable.
- `wapor_zonal_stats()` never downloads; `coverage` reports missing data.
- Release 1.0.6 (1.0.7 if 1.0.6 is released first).
- Generalize: literature defaults; the training is an example only.

### Defaults adopted from the expert review (change any by telling the planner)

| # | Topic | Adopted in this plan |
|---|---|---|
| A1 | SD definition | population, area-weighted; `sd_type = "sample"` optional |
| A2 | Uniformity | headline `1 - CV` (Chukalla proxy) with CU and DU_lq also returned; classes only with a known `irrigation_method` |
| A3 | Spots | protocol bright rule (both LP and WP at or above P95); dark = both at or below P5 as a documented package convention |
| A4 | Fraction masks | accepted as `weights` in WP2 (recommended at L1/L2) |
| A5 | Peff default | `usda_cropwat` unchanged (known answers stable); `fao_aglw`, `fixed`, `none` as options |
| A6 | Rainfed classes | `water_source = "rainfed"` gives blue = 0 and an `unexplained_water` diagnostic |
| A7 | Adequacy label above 1 | "above ETc" |

### Open (need the user before the affected step)

| # | Decision | Affects | Default until decided |
|---|---|---|---|
| D1 | Measured (survey) yields as input (table per zone or raster) so CWP works for perennials and any crop | WP4 step 5 | NPP yield chain skipped for perennials with a warning |
| D2 | Download cache location (project folder vs R user cache dir) | P3 (ti-06) | not needed here |
| D5 | Correct the existing crop-table values (Winter Wheat Kc_ini 0.4 -> 0.7 non-frozen, Sorghum 0.3 -> 0.2, Sugarcane stages); this changes golden values | WP4 step 8 | notes corrected, values unchanged |
| D6 | RWD separate from the existing `adequacy_etc` / `adequacy_p95`, or reuse them | WP3 | separate function, reusing ETc and P95 inputs |
| D10 | Apply the Kc climate adjustment automatically from AgERA5 wind and humidity, or keep it a manual helper | WP4 step 6 | manual helper only |
| D11 | Confirm the Molden & Gates (1990) bands from the original paper before shipping them as alternative schemes | WP1 | not shipped |
| D12 | Confirm WaPOR v3 specifics (native resolution of PCP and RET, generic LUE, NBWP definition) from the v3 methodology document | docs | documented as UNVERIFIED |

---

## 11. Handoff notes per model

- **Codex** (`agent-workflow/scripts/codex_task.ps1`): one WP per run:
  `codex_task.ps1 -Plan docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md` with the
  instruction "Implement WP<n> only". Codex reads `AGENTS.override.md` and `.agents/skills/`
  (`rwapor-plan-executor`, `rwapor-r-dev`).
- **Antigravity / Gemini / others**: read `agent-workflow/START-HERE.md`, this plan and the review; implement
  one WP; report as STATUS / FILES / VALIDATION (result line per command) / DONE CRITERIA (with evidence) /
  DEVIATIONS / QUESTIONS.
- **Reviewer (Claude or the user)**: per WP, check `git diff --stat` against the file table, rerun the
  validation commands, confirm tests use independent expected values, `test-known-answer.R` unchanged and
  passing, and no UNVERIFIED value became a default.

## 12. References

Full citations with evidence labels are in the review, section 7
(`docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md`). Key sources: Allen et al. (1998) FAO-56;
Chukalla et al. (2022) HESS 26, 2759-2778; Chukalla et al. (2020) WaPOR productivity protocol (Zenodo
10.5281/zenodo.4641360); Karimi et al. (2019) Remote Sens. 11, 705; Bastiaanssen et al. (1996);
Bastiaanssen & Bos (1999); Pitts et al. (1996); Christiansen (1942); Merriam & Keller (1978); Smith (1992)
FAO-46 CROPWAT.
