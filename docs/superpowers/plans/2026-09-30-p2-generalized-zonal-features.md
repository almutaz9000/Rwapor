# P2 implementation plan: generalized zonal statistics, configurable classes and training-derived features

| | |
|---|---|
| **Status** | Approved design (user, 2026-09-30). Ready for implementation, work package by work package. |
| **Written by** | Claude (planner). **Implementers**: any model (Codex, Antigravity, Claude, ...). |
| **Target release** | Rwapor **1.1.0** (new exported functions = minor version). Current dev version: `1.0.5.9000`. |
| **Board tasks** | WP1 + WP2: `ti-10` (+ `ti-16`); WP3: `ti-09`, `ti-13`; WP4: `ti-11`; WP5: `ti-12`, `ti-14`, `ti-15` (`agent-workflow/agents-board.json`). |
| **Design source** | `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`, section "P2", block "REVISED 2026-09-30". |
| **Evidence source** | `training/water-productivity-training.qmd` (the 2026 WaPOR training notebook): every feature here replaces a helper the notebook had to write by hand. |

---

## 0. How to use this plan (read first, every implementer)

1. Start every session with `agent-workflow/START-HERE.md` (preflight, board, session brief).
2. Implement **one work package (WP) per run**, in the order WP1 -> WP2 -> WP3 -> WP4 -> WP5.
   WP2 needs WP1; WP3 needs WP1 and WP2. WP4 and WP5 are independent of each other.
3. Claim the WP's board task before editing:
   `.\agent-workflow\scripts\board_claim.ps1 -Id <task-id> -Model <your-model> -Status active -Notes "plan: docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md WP<n>"`
4. Edit **only** the files listed in the WP's file table. If another file must change, stop and report.
5. Run the WP's validation commands and report each result line. Tick every done criterion with evidence.
6. Do not commit or push unless the user asks. Work on branch `version-1.1.0` (create it from the default
   branch if it does not exist; CI runs on `version-*` branches).
7. When a detail in this plan is wrong or impossible, stop and report instead of guessing
   (`STATUS: blocked`, with the file and line).

### Project conventions (apply to every WP)

- R: `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` (Windows). Use
  `devtools::document()`, `devtools::test(filter = ...)`; `devtools::check()` only at the end of a WP
  that changes exports.
- Code style: base pipe `|>`, `pkg::fun()` calls (no `library()` in `R/`), `stop(..., call. = FALSE)`,
  roxygen2 with `@export`, `@param`, `@return`, `@examples` (wrap slow or network examples in
  `\dontrun{}`), lintr/styler clean (CI job "lintr and styler").
- No new hard dependencies. Allowed: packages already in `DESCRIPTION` Imports (terra, sf, exactextractr,
  ggplot2, ...). Suggests only with `requireNamespace()` guards.
- Messages: progress via the internal `.wapor_inform()` (honours `options(Rwapor.verbose)`);
  problems via `warning()` / `stop()`.
- **Known-answer rule**: `tests/testthat/test-known-answer.R` must keep passing unchanged. No WP in this
  plan changes existing analysis numbers; if a golden value moves, you have introduced a bug.
- Units: WaPOR depths are mm (seasonal totals) or mm/day, mm/dekad (per time step); areas m2/ha;
  volumes m3 (1 mm over 1 m2 = 0.001 m3). Never measure areas on longitude/latitude with planar math.
- Disk: the development machine may be low on disk space; if a local full test run shows
  "No space left on device", rerun the failing files individually and report it (CI is the reference).
- Update `NEWS.md` (section `# Rwapor 1.1.0 (development)`, create it above 1.0.6 if missing) and the
  board/`task-status.md` entry at the end of each WP.

---

## 1. Objectives

| # | Objective | Measurable success |
|---|---|---|
| O1 | One general zonal engine for any polygons at any scale (field, farm, scheme, district, basin, country, AOI) | `wapor_zonal_stats()` returns correct area-weighted statistics, volumes, coverage and class shares for zones from a 20 m farm to a country at 300 m; tests compare with independent calculations |
| O2 | Every classification is user-configurable | No hard-coded class threshold anywhere; one shared `wapor_classify()`; published values only as documented defaults; the thresholds used travel with every result |
| O3 | Irrigation performance assessment (Chukalla et al., 2022) for any units | Adequacy classes, uniformity within units, equity between units, climate normalization; reproduce the training notebook's wheat results |
| O4 | Bright/dark spot analysis for pixels or zones, with shares per zone and AOI | `wapor_classify_spots()` + `class_share`; percentiles within a chosen reference group |
| O5 | Tree (perennial) crops handled correctly | Citrus profiles (FAO-56), `crop_type`, stage names; the grain yield chain is not applied to trees by default |
| O6 | Remove common traps found in the training | Masks that reproject automatically, full-resolution plots without deprecated ggplot2 calls, URL lists usable offline |

**Non-goals (this plan)**: download cache `wapor_download()` (ti-06) and parallel remote opening (ti-07)
are P3; refactoring `wapor_ts()` and monitoring to use the new engine is P3; no Shiny dashboard changes;
no change to the seasonal-analysis math.

---

## 2. Architecture

```
                 user rasters / wapor_run_seasonal_analysis() result
                                   |
       +---------------------------+----------------------------+
       |                                                        |
 wapor_classify()  (WP1)                              wapor_zonal_stats()  (WP2)
   breaks / labels / method = fixed|quantile            zones: any polygons, nested ids
   reference = AOI | zones | group raster               stats: mean, median, quantiles, sd, cv,
   defaults: wapor_class_defaults()                     min, max, count, area_ha, coverage,
   overrides: options(Rwapor.class_breaks)              sum_volume, class_share
       |                                                        |
       +-----------------------+--------------------------------+
                               |
            WP3 indicators: wapor_classify_adequacy(), wapor_calc_uniformity(),
            wapor_calc_equity(), wapor_climate_norm(), wapor_classify_spots(),
            exported wapor_calc_cv(), wapor_calc_peff()
                               |
            WP4 crops: perennial profiles, crop_type, stage_names      WP5 helpers: masks, plots, offline URLs
```

New files: `R/classify.R` (WP1), `R/zonal_stats.R` (WP2), `R/performance_indicators.R` (WP3),
`R/mask_helpers.R` (WP5). Tests in matching `tests/testthat/test-*.R` files.

---

## 3. WP1: configurable classification engine (`ti-10` part 1)

**Objective**: one classifier used by every classification in the package, with user-defined breaks,
labels, fixed or percentile method, and reference groups; published thresholds only as defaults.

**Effort**: small to medium. **Depends on**: nothing.

### Files

| File | Change |
|---|---|
| `R/classify.R` | new: `wapor_classify()`, `wapor_class_defaults()`, `wapor_class_info()`, internal helpers |
| `tests/testthat/test-classify.R` | new |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | NEWS entry; regenerated by `devtools::document()` |

### API

```r
wapor_class_defaults(scheme = NULL)
```
Returns a named list of schemes (or one scheme when `scheme` is given). Each scheme is
`list(breaks, labels, method, right, units, source)`. Values:

| scheme | method | breaks | labels | source |
|---|---|---|---|---|
| `adequacy` | fixed | `c(0.68, 0.8, 1)` | poor, acceptable, good, above demand | Chukalla et al. (2022), HESS 26, 2759-2778, Table A1 |
| `equity` | fixed | `c(0.10, 0.25)` (CV as a fraction) | good, fair, poor | Chukalla et al. (2022) |
| `uniformity` | fixed | `c(0.65, 0.75, 0.85)` (1 - CV) | below 65%, 65 to 75%, 75 to 85%, 85% and above | irrigation-method standards used in the training: furrow 65%, sprinkler 75%, drip 85% |
| `spots` | quantile | `c(0.05, 0.95)` | dark, normal, bright | WaPOR bright/dark spot practice (training notebook) |

Project-wide overrides: `options(Rwapor.class_breaks = list(adequacy = list(breaks = ..., labels = ...)))`
are merged over these defaults (only the given fields replace the default fields).

```r
wapor_classify(x, breaks = NULL, labels = NULL, method = c("fixed", "quantile"),
               reference = NULL, id = NULL, scheme = NULL, right = TRUE)
```

- `x`: SpatRaster (one or more layers) or numeric vector.
- `scheme`: name of a default scheme; any of `breaks`, `labels`, `method` left `NULL` is taken from it
  (after applying `options(Rwapor.class_breaks)`). Without `scheme`, `breaks` is required and
  `method` defaults to `"fixed"`.
- `method = "fixed"`: `breaks` are values. Intervals with `right = TRUE`:
  class 1 = `(-Inf, b1]`, class k = `(b[k-1], b[k]]`, last class = `(b_n, Inf)`.
  With `right = FALSE`: `[b[k-1], b[k])`. (Adequacy default with `right = TRUE` gives
  poor <= 0.68 < acceptable <= 0.8 < good <= 1 < above demand, exactly the training notebook.)
- `method = "quantile"`: `breaks` are probabilities in (0, 1). Thresholds are quantiles
  (`stats::quantile(type = 7)`) of the non-NA values of `x` within each reference group:
  - `reference = NULL`: one group, all non-NA cells (or values) of `x`;
  - `reference` = SpatRaster of group codes (same grid as `x`, else resampled with `"near"`): one set of
    thresholds per group code;
  - `reference` = polygons (sf / SpatVector / path) + `id` column: groups are the polygons
    (rasterized to the grid of `x` with `terra::rasterize(..., field = id)`; cells outside all polygons
    get NA).
  Then classify with the fixed rule above using the group's thresholds.
- Returns, for a SpatRaster, an integer SpatRaster (codes `1..(length(breaks) + 1)`, NA stays NA) that is
  categorical: `terra::levels(r) <- data.frame(value = codes, class = labels)`; for a numeric vector, a
  factor with `levels = labels`.
- The result carries attribute `"wapor_classes"` (for SpatRaster also stored with `terra::metags()` so it
  survives `writeRaster()` in GeoTIFF metadata):
  `list(scheme, method, breaks, labels, right, thresholds)` where `thresholds` is a data.frame with
  columns `group` (NA for one group) and `t1..tn` (actual values used).
- Validation (each an error with a clear message): `breaks` numeric, finite, strictly increasing and
  unique; `length(labels) == length(breaks) + 1` (when `labels` is `NULL` use `"class_1"`, ...);
  quantile breaks strictly between 0 and 1; `reference` group raster must overlap `x`; `id` required
  when `reference` is polygons; unknown `scheme` name lists the available ones.
- Edge cases: a group with fewer than `length(breaks) + 1` non-NA values gets NA thresholds and its cells
  NA, with one warning listing such groups; ties at a threshold follow `right`.

Also export `wapor_class_info(x)`: returns the `"wapor_classes"` list of a classified result
(reads the attribute, or the metadata tags of a raster read from file).

### Tests (`test-classify.R`)

1. Fixed, numeric: `wapor_classify(c(0.5, 0.68, 0.7, 0.8, 0.9, 1, 1.2), scheme = "adequacy")` gives
   `poor, poor, acceptable, acceptable, good, good, above demand`.
2. `right = FALSE` moves the boundary values: 0.68 -> acceptable, 0.8 -> good, 1 -> above demand.
3. Custom breaks and labels on a SpatRaster (4 x 4, values 1..16, breaks `c(4, 8, 12)`): codes
   `rep(1:4, each = 4)` in cell order; `terra::levels()` holds the labels; `wapor_class_info()` returns
   the breaks.
4. Quantile, one group: values 1..100, `breaks = c(0.05, 0.95)`: thresholds equal
   `quantile(1:100, c(0.05, 0.95), type = 7)`; counts per class 5 / 90 / 5.
5. Quantile per group: two groups of values 1..100 and 101..200; each group gets its own thresholds
   (group 2 thresholds = group 1 + 100) and counts 5 / 90 / 5 per group. Same result with a group raster
   and with two polygons + `id`.
6. Option override (`old <- options(...); on.exit(options(old))`): set
   `Rwapor.class_breaks = list(adequacy = list(breaks = c(0.6, 0.8, 1)))`; 0.65 becomes acceptable;
   labels still the defaults.
7. Validation errors: unsorted, duplicated, non-finite breaks; wrong number of labels; quantile break
   1.0; unknown scheme (message lists `adequacy`, `equity`, `uniformity`, `spots`).
8. Metadata survives a GeoTIFF round trip: write the classified raster, read it back,
   `wapor_class_info()` returns the same breaks and labels.

### Validation

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] All 8 test groups pass; known-answer tests unchanged and passing
- [ ] Class thresholds appear only inside `wapor_class_defaults()` (code review; no literal
      0.68 / 0.95 class thresholds elsewhere in `R/`)
- [ ] `?wapor_classify` documents every argument, the interval rule, and the defaults table with sources

---

## 4. WP2: `wapor_zonal_stats()`, the general zonal engine (`ti-10` part 2, `ti-16`)

**Objective**: area-weighted statistics, water volumes, data coverage and class shares for any polygons
(nested levels possible) on any WaPOR raster or analysis result.

**Effort**: medium. **Depends on**: WP1.

### Files

| File | Change |
|---|---|
| `R/zonal_stats.R` | new: `wapor_zonal_stats()`, `wapor_zonal_wide()`, internal helpers |
| `tests/testthat/test-zonal-stats.R` | new (synthetic grids) |
| `tests/testthat/test-zonal-known-answer.R` | new (uses the existing known-answer fixture) |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | as usual |

### API

```r
wapor_zonal_stats(
  x, zones, id,
  stats = c("mean", "area_ha", "coverage"),
  probs = c(0.1, 0.9),
  mask = NULL,
  dissolve = TRUE,
  aoi = TRUE,
  classes = NULL, breaks = NULL, labels = NULL, method = NULL, scheme = NULL,
  min_coverage = 0.5,
  normalize_id = TRUE,
  layers = NULL,
  format = c("long", "wide", "sf")
)
wapor_zonal_wide(z)   # long result -> one row per zone, one column per variable_stat[_class]
```

**Arguments**

- `x`: a SpatRaster (each layer = one variable or one time step; layer names are used as `variable`), or a
  `wapor_run_seasonal_analysis()` result. For a result, `layers` selects outputs by name; the default
  set is those present among `seasonal_aeti`, `seasonal_t`, `seasonal_ret`, `seasonal_pcp`,
  `seasonal_peff`, `etc` (from `etc_by_class`, combined), `adequacy_etc`, `adequacy_p95`,
  `beneficial_fraction`, `green_water`, `blue_water`, `seasonal_biomass_t`, `yield_raster`.
  Internal helper `.wapor_result_layers(result, layers)` returns a named multi-layer SpatRaster
  (list elements that are `list(raster = ...)` use `$raster`).
- `zones`: sf, SpatVector, or a vector file path (read with `sf::st_read(quiet = TRUE)`).
- `id`: one or more column names. Several = nested levels, from coarse to fine, e.g.
  `c("governorate", "scheme", "farm")`: statistics are computed for each level
  (level 1 zones = polygons dissolved by `governorate`; level 2 = dissolved by `governorate` + `scheme`;
  ...). Each level is extracted from its own dissolved geometry (never by averaging child results, which
  would be wrong for medians, percentiles and overlapping polygons).
- `stats`: any of `"mean"`, `"median"`, `"quantiles"` (uses `probs`), `"sd"`, `"cv"`, `"min"`, `"max"`,
  `"count"`, `"area_ha"`, `"coverage"`, `"sum_volume"`, `"class_share"`.
- `mask`: optional SpatRaster (e.g. a crop mask); only cells where `mask` is not NA count. Resampled to
  `x` with `"near"` when grids differ.
- `dissolve`: merge polygons that share the same id (multi-part farms, districts).
- `aoi`: also return one row set for the whole area of interest (`level = "AOI"`, `zone_id = "AOI"`),
  extracted over `sf::st_union()` of all zones, so overlapping polygons are not counted twice.
- `classes`, `breaks`, `labels`, `method`, `scheme`: for `"class_share"`. Either `x` layers are already
  classified (integer codes; labels from `terra::levels()` or `classes`, a named character vector
  `c("1" = "bright", ...)`), or `breaks`/`method`/`scheme` classify on the fly with `wapor_classify()`
  (WP1) before extraction; the class info is attached to the output.
- `min_coverage`: zones whose `coverage` is below this get NA statistics (the `coverage` row itself is
  kept) and one warning naming the first 5 such zones.
- `normalize_id`: add a `zone_key` column = `toupper(trimws(as.character(id)))` for joins; the original
  `zone_id` is kept unchanged.
- `format`: `"long"` (default) tidy table; `"wide"` = `wapor_zonal_wide()`; `"sf"` = the zones of the
  finest level (plus the AOI when `aoi = TRUE`) with wide columns attached.

**Output (long)**: data.frame of class `c("wapor_zonal", "data.frame")` with columns
`level`, `zone_id`, `zone_key`, one column per coarser id level (parent ids), `variable`, `period`,
`stat`, `class`, `value`, `unit`.
- `period`: parsed from the layer name when it looks like a date (`YYYY-MM` or `YYYY-MM-DD`), else NA.
- `stat` for quantiles: `"p10"`, `"p90"` (from `probs`).
- `class`: NA except for `class_share` rows, which come in pairs per class: `stat = "class_area_ha"` and
  `stat = "class_pct"`; every class appears for every zone (zero rows included) so tables are complete.
- `unit`: the raster unit (`terra::units()`) for value statistics; `"ha"`, `"fraction"`, `"m3"`,
  `"%"` as appropriate.
- Attributes: `"wapor_classes"` (when class shares were computed), `"wapor_zonal_call"`
  (stats, mask used, min_coverage, CRS of the areas).

### Algorithm (normative)

1. Normalize inputs: `x` -> SpatRaster; `zones` -> sf, `sf::st_make_valid()`, drop empty geometries
   (warn with count); check every `id` column exists (error lists available columns).
2. Build the zone sets per level (`dissolve`: group by the id combination and `sf::st_union()` the
   geometries per group, keeping the id columns; no dplyr dependency).
3. Reproject each zone set to `terra::crs(x)` with `sf::st_transform()`.
4. Apply `mask`: `x <- terra::mask(x, mask_on_x_grid)`.
5. For `"class_share"` with on-the-fly classification: `x_cls <- wapor_classify(x, ...)`.
6. Extract with `exactextractr::exact_extract(x, zones, include_cell = FALSE, coverage_area = TRUE,
   max_cells_in_memory = <from the processing planner memory budget, .wapor_memory_budget_bytes() / 8>,
   progress = FALSE)`: per zone a data.frame of cell values plus `coverage_area` (the covered area of each
   cell in m2; exactextractr computes it geodesically for geographic rasters, which satisfies the
   "never planar lon/lat" rule). Process zones in batches of 500 to bound memory for many zones.
7. Per zone and layer, with `v` = values, `w` = `coverage_area` (m2), `ok = !is.na(v)`:
   - `mean` = `sum(v[ok] * w[ok]) / sum(w[ok])`
   - `sd` = `sqrt(sum(w[ok] * (v[ok] - mean)^2) / sum(w[ok]))` (area-weighted population sd; document it)
   - `cv` = `sd / mean` (NA when mean is 0)
   - `median`, quantiles: area-weighted quantile: sort by `v`, cumulative weight share
     `c = cumsum(w) / sum(w)`, value at the first `c >= p` (document the definition)
   - `min`, `max` over `ok` cells with `w > 0`
   - `count` = number of `ok` cells with `w > 0`
   - `area_ha` = zone area in ha from the geometry, measured in an equal-area projection:
     `sf::st_area(sf::st_transform(zone, laea))` with `laea = "+proj=laea +lat_0=<zone centroid lat>
     +lon_0=<zone centroid lon> +datum=WGS84"`, computed with `sf::sf_use_s2(FALSE)` restored on exit
     (fixes the training's s2 "degenerate edge" failure, ti-16)
   - `coverage` = `sum(w[ok]) / zone_area_m2`, clamped to `[0, 1]`
   - `sum_volume` = `sum(v[ok] / 1000 * w[ok])` in m3; only for layers whose unit starts with `"mm"`
     (else the row is skipped with one warning per layer); also report `stat = "sum_volume_mcm"`
     (million m3)
   - `class_share`: for each class code `k`: `class_area_ha = sum(w[ok & v == k]) / 1e4`;
     `class_pct = 100 * sum(w[ok & v == k]) / sum(w[ok])`
8. Zones with `coverage < min_coverage`: set all statistics except `coverage`, `area_ha` and `count` to
   NA; one warning.
9. Assemble the long table; add the AOI row set when `aoi = TRUE`; attach attributes.

### Tests (`test-zonal-stats.R`, synthetic, fast, offline)

Use a projected 10 x 10 grid (EPSG:32636, 20 m cells, origin at x = 700000, y = 3600000), values
`1:100` row-wise, unit `"mm"`.

1. **Aligned zones**: two polygons covering the left 5 columns and the right 5 columns exactly. `mean`
   equals the plain mean of the covered cells (independently computed from the value vector); `count` =
   50; `area_ha` = 50 x 400 / 1e4 = 2 ha; `coverage` = 1.
2. **Fractional cell**: a polygon covering exactly half of one cell -> `count` 1, weight 200 m2,
   `area_ha` 0.02, `coverage` 1, `mean` = that cell's value.
3. **Weighted mean with partial cells**: polygon covering one full cell (value a) and half of a second
   (value b): `mean = (a * 400 + b * 200) / 600`.
4. **Volume**: `sum_volume` = `sum(values_mm / 1000 * 400)` m3 for the left zone; equals
   `mean * area_m2 / 1000`; `sum_volume_mcm` = that / 1e6. A layer with unit `"-"` produces no volume
   row and a warning.
5. **Nested levels**: 4 polygons (quadrants) with columns `scheme` (left/right) and `farm` (q1..q4),
   one quadrant made smaller: level `scheme` has 2 zones, level `farm` 4; the `scheme` mean equals the
   mean over its cells (not the mean of the two quadrant means).
6. **Dissolve**: two separate polygons with the same `farm` id give one zone whose `count` is the sum.
7. **AOI and overlap**: two overlapping polygons; the AOI `area_ha` equals the union area, not the sum.
8. **Mask**: mask keeping only even values: `count` halves; `mean` is the mean of the even values.
9. **Coverage / NA**: set 60% of one zone's cells to NA with `min_coverage = 0.5`: coverage 0.4, mean
   NA, a warning; with `min_coverage = 0.3` the mean is the mean of the valid cells.
10. **Class share**: classify `1:100` with `breaks = c(25, 50, 75)` (4 classes): left zone shares
    computed independently by counting; shares sum to 100 per zone; every class has a row even when 0.
11. **Class share on the fly with quantiles and labels**: `scheme = "spots"` gives 3 labelled classes;
    the `wapor_classes` attribute holds the thresholds.
12. **Geographic raster**: test 1 on an EPSG:4326 grid of 0.01 degree cells near 32 N: `area_ha` equals
    `terra::expanse()` of the polygon in ha within 0.1%; per-cell weights match
    `terra::cellSize(unit = "m")` within 0.1%.
13. **Formats**: `"wide"` has one row per zone and columns such as `<layer>_mean`; `"sf"` returns an sf
    with those columns; `normalize_id` makes `" f01 "` and `"F01"` the same `zone_key`.
14. **Errors**: missing id column (message lists columns); zones not overlapping `x` (coverage 0,
    warning); `class_share` on a non-integer layer without `breaks`/`scheme` (error explaining how to
    classify).

### Tests (`test-zonal-known-answer.R`, real data)

Use `tests/testthat/fixtures/known-answer/citrus` (see its README; unstack as in `test-known-answer.R`:
copy the small helpers, do not source that file). Run the citrus seasonal analysis exactly as in
`test-known-answer.R` (memory mode). Build zones on the fixture grid: 4 quadrant polygons (10 x 10 pixels
each) with columns `scheme` (`"north"`, `"south"`) and `block` (`q1`..`q4`), in the fixture's CRS.

1. `wapor_zonal_stats(result, zones, id = "block", stats = c("mean", "count", "area_ha"))`: for every
   layer, the quadrant means equal plain `mean()` of the corresponding 100 cells (independent path via
   `terra::values()` and index arithmetic) within 1e-9; area 4 ha each (100 x 400 m2).
2. AOI mean of `seasonal_aeti` equals the golden mean in `golden.csv` (446.3228, within 1e-6).
3. AOI mean of `etc` equals 1050.9293 (golden) within 1e-6.
4. `sum_volume` of `seasonal_aeti` for the AOI = `446.3228 / 1000 * 160000` m3 (16 ha) within 1e-6
   relative.
5. Class share of `adequacy_etc` with `scheme = "adequacy"`: shares sum to 100 per block and AOI, and
   equal independent pixel counts per class (all pixels are full cells).

### Optional local acceptance (not in CI; skip when the training data are absent)

`tests/testthat/test-zonal-training-acceptance.R` with `skip_on_ci()` and a skip when
`training/wapor_data` does not exist: dissolve `training/data/citrus/Citrus_farms_final.geojson` by
`Name`, run `wapor_zonal_stats()` on the notebook's citrus indicator stack and compare farm means with the
notebook's `terra::extract(..., fun = mean, weights = TRUE)` result: relative difference below 0.5% for
every farm (terra's weights are approximate, exactextractr's are exact). Do not commit training data.

### Validation

```powershell
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] All synthetic (14) and fixture (5) tests pass; known-answer unchanged
- [ ] Areas never computed with planar math on lon/lat (test 12 passes; code review of area helpers)
- [ ] A 300 m country-size example documented as `\dontrun{}`; exactextractr `max_cells_in_memory` set
      from the planner
- [ ] `?wapor_zonal_stats` documents every statistic formula, the weighted sd/quantile definitions,
      units, and the class-share denominator

---

## 5. WP3: irrigation performance indicators and bright/dark spots (`ti-09`, `ti-13`)

**Objective**: the Chukalla et al. (2022) indicators for any units, and spot analysis for pixels or
zones, all built on WP1 and WP2 and all classes configurable.

**Effort**: medium. **Depends on**: WP1, WP2.

### Files

| File | Change |
|---|---|
| `R/performance_indicators.R` | new: functions below |
| `R/analysis_indicators.R` | add `@export` and full roxygen to `wapor_calc_cv()` (line ~883) and `wapor_calc_peff()` (line ~858); no behaviour change |
| `tests/testthat/test-performance-indicators.R` | new |
| `NEWS.md`, `NAMESPACE`, `man/*.Rd` | as usual |

### API

```r
wapor_classify_adequacy(adequacy, breaks = NULL, labels = NULL, right = TRUE)
# = wapor_classify(adequacy, breaks, labels, method = "fixed", scheme = "adequacy", right = right)

wapor_calc_uniformity(aeti, units, id = NULL, mask = NULL, min_pixels = 100,
                      breaks = NULL, labels = NULL)
wapor_calc_equity(aeti, units, id = NULL, mask = NULL, min_pixels = 100,
                  breaks = NULL, labels = NULL)
wapor_climate_norm(ret, mask = NULL)
wapor_classify_spots(cwp, yield = NULL, breaks = NULL, labels = NULL,
                     method = NULL, reference = NULL, id = NULL, zones = NULL, zone_id = NULL)
```

- `units`: either polygons (sf/SpatVector/path, with `id`) or a single number = block size in metres
  (regular grid). For blocks, the raster must be projected (error otherwise, suggesting polygons or
  `terra::project()`); `fact = round(units / terra::res(aeti)[1])`, must be >= 2.
- **Uniformity** per unit = `1 - sd / mean` of AETI inside the unit; units with fewer than `min_pixels`
  valid pixels excluded (NA).
  - Blocks: computed exactly as the training notebook (`training/water-productivity-training.qmd`, chunk
    `wheat-performance-uniformity`): `terra::aggregate(aeti, fact, fun = "mean")`, `fun = "sd"`, and
    pixel counts; uniformity raster painted on the block grid.
  - Polygons: from `wapor_zonal_stats(stats = c("mean", "sd", "count"))` (area-weighted sd; document the
    difference from the block path's sample sd).
  - Returns `list(raster = <block raster or NULL>, table = data.frame(unit, n_pixels, mean, sd,
    uniformity, class), summary = list(mean, min, n_units), classes = <wapor_classes>)`, with `class`
    from `wapor_classify(scheme = "uniformity")` (overridable by `breaks`/`labels`).
- **Equity** = CV of the unit means = `sd(unit_means) / mean(unit_means)` (sample sd, as in the notebook),
  over units with at least `min_pixels` valid pixels; class from `wapor_classify(scheme = "equity")`.
  Returns `list(cv, class, n_units, table, classes)`.
- **Climate normalization** `f_norm = mean(RET over the masked area) / RET` per pixel, masked (notebook
  chunk computing `f_norm`).
- **Spots**:
  - Pixel mode (`zones = NULL`): thresholds via `wapor_classify(method = "quantile", scheme = "spots")`
    on `cwp` (and on `yield` when given), per `reference` group. Class: bright when `cwp >= high`
    threshold and (`yield` is NULL or `yield >= high`); dark when `cwp <= low` and (`yield` NULL or
    `yield <= low`); otherwise normal. With more than two breaks, the first and last thresholds define
    dark and bright; document it.
  - Zone mode (`zones` + `zone_id` given): classify the zone means from
    `wapor_zonal_stats(stats = "mean")` instead of pixels; returns a table.
  - Result carries `wapor_classes`. Shares per zone/AOI: pass the spot raster to
    `wapor_zonal_stats(stats = "class_share")`.

### Tests (`test-performance-indicators.R`)

1. Adequacy classes on the known-answer wheat fixture's `adequacy_etc`: counts per class equal
   `table(cut(values, c(-Inf, 0.68, 0.8, 1, Inf), right = TRUE))` computed independently.
2. Custom adequacy breaks change the counts accordingly.
3. Uniformity, blocks, synthetic projected 100 x 100 grid of 20 m pixels, `units = 400` (fact 20):
   25 blocks; for each block `1 - sd/mean` equals the value computed with base R on the block's cells
   (sample sd); `min_pixels = 500` makes all blocks NA (400 cells each) with a warning.
4. Uniformity, polygons: 2 polygons; values equal `1 - sd_w/mean_w` from `wapor_zonal_stats()`.
5. Equity: unit means `c(10, 12, 14)` -> `sd(c(10, 12, 14)) / 12` = 0.1667 -> class `"fair"` by
   default; with `breaks = c(0.2, 0.3)` -> `"good"`.
6. Climate normalization: RET constant -> all 1; RET `c(2, 4)` -> `c(1.5, 0.75)`.
7. Spots, pixel mode: cwp and yield both 1..100 -> 5 bright, 5 dark, 90 normal; with yield reversed
   (100..1) -> no bright and no dark pixel.
8. Spots with a reference group raster (two groups) -> 5 + 5 per group.
9. Spots zone mode returns one class per zone; `class_share` of the spot raster per zone sums to 100.
10. `wapor_calc_cv()` and `wapor_calc_peff()` are exported and documented (in `getNamespaceExports()`;
    examples run).

### Optional local acceptance (skip without training data, not on CI)

Reproduce the training notebook's wheat results (JEN, 2023/24, full cereal mask) with the package
functions: adequacy classes poor 73.6%, acceptable 24.6%, good 1.8%, above demand 0.0%; 1 km blocks:
1015 blocks used, mean uniformity 89.1%, minimum 77%, equity CV 9.6% -> good; `f_norm` range 0.98 to
1.19. Tolerance: percentages +-0.1 point, counts exact.

### Validation

```powershell
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'performance-indicators')"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'known-answer')"
```

### Done criteria

- [ ] 10 test groups pass; known-answer unchanged
- [ ] Every class threshold comes from `wapor_class_defaults()` or user arguments
- [ ] Each function's help cites Chukalla et al. (2022) and states its formula

---

## 6. WP4: perennial (tree) crop support (`ti-11`)

**Objective**: tree crops get correct FAO-56 profiles and are protected from the field-crop yield chain.

**Effort**: medium. **Depends on**: nothing (can run in parallel with WP1 to WP3).

### Files

| File | Change |
|---|---|
| `R/crop_defaults.R` | new columns and rows in `FAO_CROP_DEFAULTS`; `crop_type` and `stage_names` in `wapor_create_crop_params()` / `wapor_custom_crop()`; fix the `fc` documentation (line ~143) |
| the file where `yield_npp` / `cwp_bwp` are computed (`R/analysis_engine.R` or `R/analysis_registry.R`; locate with grep) | skip the yield chain for perennials, with one warning |
| `tests/testthat/test-perennial.R` | new (existing crop-default tests stay unchanged) |
| `NEWS.md`, `man/*.Rd` | as usual |

### Steps

1. Add to `FAO_CROP_DEFAULTS` the columns `crop_type` (`"annual"` for all 12 existing rows) and
   `stage_names` (character, `"|"`-separated, `NA` for existing rows). Do not change existing columns or
   values (grep usages of `FAO_CROP_DEFAULTS` first; existing tests must pass).
2. Add perennial rows. **Citrus values are verified** (FAO-56 Table 12, used in the training):

   | crop_name | kc_ini | kc_mid | kc_end | max_height_m |
   |---|---|---|---|---|
   | Citrus, no ground cover, 70% canopy | 0.70 | 0.65 | 0.70 | 4.0 |
   | Citrus, no ground cover, 50% canopy | 0.65 | 0.60 | 0.65 | 3.0 |
   | Citrus, no ground cover, 20% canopy | 0.50 | 0.45 | 0.55 | 2.0 |
   | Citrus, active ground cover, 70% canopy | 0.75 | 0.70 | 0.75 | 4.0 |
   | Citrus, active ground cover, 50% canopy | 0.80 | 0.80 | 0.80 | 3.0 |
   | Citrus, active ground cover, 20% canopy | 0.85 | 0.85 | 0.85 | 2.0 |

   The first and fourth rows are the values the training used and cited; before committing, the
   implementer re-checks all six rows against FAO-56 Table 12 (Allen et al., 1998) and reports any
   difference instead of guessing. Stage lengths for citrus (FAO-56 Table 11, Mediterranean, start
   March): `l_ini_days = 60`, `l_mid_days = 120`, `l_late_days = 95` (development = remainder of the
   365-day year = 90). `stage_names = "Flowering and new growth|Fruit set and early growth|Fruit
   development|Maturation and harvest"`. `region = "Mediterranean"`, `crop_type = "perennial"`, `notes`
   citing "FAO-56 Table 12 (Kc), Table 11 (stages)". For perennial rows set `HI`, `MC`, `AOT` to `NA`
   and `fc = 1.0`. **Olive, grape and date palm**: add only after transcribing their Kc values and stage
   lengths from FAO-56 Tables 11 and 12 with the table row cited in `notes`; if the values cannot be
   verified from the source, do not add these rows and report it (decision D3; never invent numbers).
3. `wapor_create_crop_params()` and `wapor_custom_crop()`: new arguments `crop_type = c("annual",
   "perennial")` (default: from the base crop, else `"annual"`) and `stage_names = NULL`; stored in the
   returned params.
4. Seasonal analysis: when a class's `crop_type` is `"perennial"` and the indicators include
   `yield_npp` or `cwp_bwp`, skip those two for that class and warn once:
   "Yield and CWP/BWP from NPP are for field crops; skipped for perennial class <k>. Supply measured
   yields instead." (Decision D1 may later add a yield input.) Other indicators are unchanged.
5. Fix `@param fc` in `R/crop_defaults.R` to: "Light use efficiency correction factor (fc); 1 for C3
   crops such as wheat (WaPOR methodology)." (matches `R/analysis_indicators.R:661`).

### Tests

1. `wapor_list_crops()` includes the citrus rows; values match the table above exactly.
2. `wapor_custom_crop(base_crop = "Citrus, no ground cover, 70% canopy", class_value = 1L)` returns
   `crop_type = "perennial"`, the stage names, and the Kc values.
3. The known-answer citrus configuration run with the new citrus profile (kc 0.70/0.65/0.70, stages
   60/120/95) gives the golden ETc 1050.9293 within 1e-6.
4. A perennial class with `yield_npp` requested: no `yield_raster`, one warning; an annual class
   unchanged (wheat known-answer yield 5.0362).
5. Existing crop-default tests pass unchanged.

### Done criteria

- [ ] Tests pass; known-answer unchanged; every new crop row cites its FAO-56 table
- [ ] `fc` documented identically in both places

---

## 7. WP5: mask helpers, plots, offline URL lists (`ti-12`, `ti-14`, `ti-15`)

**Objective**: remove three traps met in the training.

**Effort**: small. **Depends on**: nothing.

### Files

| File | Change |
|---|---|
| `R/mask_helpers.R` | new: `wapor_rasterize_mask()`, `wapor_harmonize_mask()` |
| `R/viz.R` | remove `aes_string()` (lines ~27 and ~89); full-resolution maps; calendar Kc axis |
| the file where `wapor_generate_urls()` fetches and caches API responses (`R/api_client.R` / `R/metadata.R`; locate with grep) | stale-cache fallback when offline |
| `tests/testthat/test-mask-helpers.R`, `tests/testthat/test-viz-basic.R`, `tests/testthat/test-offline-urls.R` | new |

### Steps

1. `wapor_rasterize_mask(polygons, template, field = NULL, value = 1L, touches = FALSE)`: reads polygons
   (sf/SpatVector/path), reprojects them to `terra::crs(template)` automatically, rasterizes (`field`
   column or constant `value`, background NA), names the layer `"crop_mask"`. Area check: ratio of mask
   area (`terra::expanse()` of non-NA cells) to polygon area (equal-area, as in WP2); warn when outside
   0.9 to 1.1; return the ratio as attribute `"area_ratio"`.
2. `wapor_harmonize_mask(crop_map, template, class, min_fraction = 0.5, value = NULL)`: for each value in
   `class`: binary (1 where `crop_map == class`, 0 elsewhere including NA), fraction on the template grid
   with `terra::project(binary, template, method = "average")`; keep cells with fraction >=
   `min_fraction`; with several classes a cell takes the class with the largest fraction; output codes =
   `value` (default = `class`). For one class this is exactly the notebook method (chunk
   `wheat-isolate-mask`).
3. `R/viz.R`: replace `ggplot2::aes_string("x", "y", fill = "value")` with
   `ggplot2::aes(x = .data$x, y = .data$y, fill = .data$value)` (`.data` via `@importFrom rlang .data`
   only if rlang is already imported; otherwise use `utils::globalVariables(c("x", "y", "value", ...))`
   and bare names); same for the Kc plot; use `ggplot2::geom_tile()` if `geom_raster()` warns about
   uneven intervals; convert with `terra::as.data.frame(r, xy = TRUE)` (no down-sampling).
   `wapor_plot_kc_curve(kc_daily, save = NULL, dpi = 300, start_date = NULL, stage_days = NULL,
   stage_names = NULL)`: with `start_date`, the x axis shows dates; with `stage_days` + `stage_names`,
   stages are shaded and labelled. Old calls produce the same plot as before.
4. Offline URL lists: read how `wapor_generate_urls()` caches API responses (`options(Rwapor.cache_ttl)`).
   When the live request fails and a cached response exists (even if older than the TTL), use it with
   one message: "No connection to the WaPOR server; using the URL list cached on <date>." Without a
   cache, keep the current error. Never use a stale cache when the server answers.

### Tests

1. Rasterize lon/lat polygons onto a UTM template: non-empty mask, area ratio within 0.9 to 1.1; the same
   polygons rasterized directly with `terra::rasterize()` (no reprojection) give an empty mask
   (documents the trap).
2. Harmonize: a 10 m map with a 20 m template, class present in 3 of 4 sub-cells -> kept at
   `min_fraction = 0.5`, dropped at 0.8; with two classes the larger fraction wins.
3. Plots: `wapor_plot_map()` and `wapor_plot_kc_curve()` produce no warnings (`expect_no_warning()`);
   the plotted data of a 1000 x 1000 raster has 1e6 rows.
4. Offline: mock the HTTP layer to fail after one successful cached call: URLs returned from the cache
   with the message; without a cache: the previous error; with a working server: a fresh request.

### Done criteria

- [ ] Tests pass; no `aes_string` left in `R/`; known-answer unchanged

---

## 8. Release and documentation (after WP1 to WP5)

1. `DESCRIPTION`: `Version: 1.1.0`; NEWS section `# Rwapor 1.1.0` summarising the new functions.
2. New vignette `vignettes/zonal-statistics.Rmd`, evaluated on a copy of the known-answer citrus fixture
   in `inst/extdata/example-citrus/` so it runs offline: zonal statistics at two levels, volumes, class
   shares of adequacy and spots per zone and AOI, custom breaks, uniformity/equity with blocks.
3. `devtools::check()` 0 errors / 0 warnings; CI green on `version-1.1.0`; live release checks pass
   (`inst/bench/live_release_checks.R`).
4. Separate task: update the training notebook to call the package functions instead of its helpers
   (acceptance: identical checkpoint values).

---

## 9. Open decisions (need the user before the affected step)

| # | Decision | Affects | Default if not decided |
|---|---|---|---|
| D1 | Allow measured (survey) yields as input (table per zone or raster) so CWP works for perennial crops? | WP4 step 4 | Yield chain skipped for perennials with a warning |
| D2 | Download cache location for `wapor_download()` (project folder vs R user cache dir) | P3 (ti-06), not this plan | not needed here |
| D3 | Add olive, grape and date palm profiles in WP4 or later | WP4 step 2 | Only when the implementer can cite verified FAO-56 values; otherwise later |

Decided on 2026-09-30: zones of any scale; class shares per zone and AOI; every class break or percentile
user-configurable; `wapor_zonal_stats()` never downloads (coverage reports missing data).

---

## 10. Handoff notes per model

- **Codex** (`agent-workflow/scripts/codex_task.ps1`): one WP per run:
  `codex_task.ps1 -Plan docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md` with the
  instruction "Implement WP<n> only". Codex reads `AGENTS.override.md` and `.agents/skills/`
  (`rwapor-plan-executor`, `rwapor-r-dev`).
- **Antigravity / Gemini / others**: read `agent-workflow/START-HERE.md` and this file; implement one WP;
  report as: STATUS / FILES / VALIDATION (result line per command) / DONE CRITERIA (with evidence) /
  DEVIATIONS / QUESTIONS.
- **Reviewer (Claude or the user)**: per WP, check `git diff --stat` against the WP file table, rerun the
  validation commands, confirm tests compare against independent calculations (never against the
  function's own output), and that `test-known-answer.R` is unchanged and passing.
