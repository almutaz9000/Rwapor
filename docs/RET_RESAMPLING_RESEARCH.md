# RET resampling default: research findings and recommendation

**Scope:** source-backed research only, triggered by `IMPROVEMENTS_PLAN.md:122`
("`R/analysis_engine.R:160-166` defaults RET resampling to nearest while PCP is
bilinear... Compare documented intent and test both methods on synthetic
gradients and native product grids before changing defaults."). No repository
code was edited for this research pass.

## 1. What the code actually does (verified in this checkout)

- `R/analysis_engine.R:160-167` sets the per-layer resampling defaults:
  ```r
  resampling_method <- utils::modifyList(
    list(
      aeti = "near", crop_mask = "near", ret = "near",
      pcp = "bilinear", npp = "near", t = "near",
      season_start = "near", season_end = "near"
    ),
    as.list(config$resampling_method %||% list())
  )
  ```
  `ret` defaults to `"near"`, `pcp` to `"bilinear"`. Both are the only two
  *meteorological, coarse-native-grid, continuous* inputs in this list; every
  other `"near"` entry (`aeti`, `crop_mask`, `npp`, `t`, `season_start`,
  `season_end`) is either categorical/mask-like or already matches the
  analysis grid in the common case.
- `R/analysis_engine.R:37-45` (function doc) states the design intent
  explicitly: *"With the default nearest-neighbour resampling every output
  value is a raw server value or a sum of raw values."* This is a real,
  legitimate design goal (traceability to the exact server-reported number),
  but the same docstring does not explain why `pcp`, which is equally a
  coarse server-reported continuous meteorological grid, is exempted from
  that goal by defaulting to `"bilinear"`.
- `vignettes/global-tiled.Rmd:72-82` ("Accuracy" section) repeats the same
  framing for users and gives the override: `config$resampling_method <-
  list(ret = "bilinear", pcp = "bilinear")`.

### Git history of the asymmetry

- Commit `0edffaa`'s ancestor history shows `ret` and `pcp` both started as
  `"near"` (`git log -S'ret = "near"'` on `R/analysis_engine.R`).
- Commit `9017edc` ("feat: implement provenance validation M1-M4, publication
  map helpers, and memory benchmarks") changed only `pcp` from `"near"` to
  `"bilinear"`, bundled into a large, otherwise-unrelated commit (provenance
  framework, viz helpers, benchmarks). The commit message gives no scientific
  rationale for singling out `pcp`, and `ret` was left untouched. **The
  nearest/bilinear split between `ret` and `pcp` is not documented or
  justified anywhere in the repository** (commit messages, NEWS.md, roxygen
  docs, or vignettes) — it is an artifact of an incremental edit, not a
  recorded design decision.

## 2. Internal consistency: how the rest of the codebase treats continuous vs. categorical rasters

The package already has a clear, repeated convention elsewhere: **nearest for
categorical/mask data, bilinear (or `"average"` for sub-pixel fractions) for
continuous physical fields**, exactly matching GIS best practice (§3):

| Location | Data | Method used | Role |
|---|---|---|---|
| `R/analysis_indicators.R:962-963,971` (`wapor_calc_et_rain`) | precipitation (mm, continuous) | `resample_method = "bilinear"` default | explicit doc: *"appropriate for the continuous PCP flux"* |
| `R/analysis_indicators.R:1009-1010,1018` (`wapor_calc_rainfall_surplus`) | precipitation (mm, continuous) | `resample_method = "bilinear"` default | same rationale |
| `R/performance_indicators.R:48-54` (`.wapor_pi_align`) | generic continuous raster alignment | `terra::resample(y, x, method = "bilinear")` | unconditional for any misaligned pair |
| `R/zonal_stats.R:326-333` | `mask` (categorical) vs `weights` (continuous) | `near` for mask, `bilinear` for weights | explicit split by data type in the same function |
| `R/mask_helpers.R:112-118` | crop-class fraction (continuous 0–1) | `"average"` (continuous-preserving) | fraction, not a hard class label |
| `R/classify.R:64-68` | classification reference raster (categorical) | `terra::resample(..., method = "near")` | correctly categorical |
| `R/wapor_monitoring.R:671-676` | reprojected raster values (continuous) | `terra::project(..., method = "bilinear")` | |
| `R/wapor_monitoring.R:1191-1197` | seasonal mask (categorical) | `terra::resample(..., method = "near")` | correctly categorical |

RET (`mm/day`, scale `0.1`, a smoothly varying climate field — see §3) is
squarely in the "continuous physical field" column, the same column PCP is
already in. The current `ret = "near"` default is the **only** coarse
continuous meteorological input in the engine that does not follow this
established in-repo convention.

## 3. Raster-GIS guidance and its limits

Common raster-GIS guidance distinguishes nearest-neighbour (which preserves source cell values) from bilinear interpolation (which produces a weighted smooth surface); the GDAL/Esri/USDA references below discuss quality and use cases. This is not by itself a complete scientific rule for coarse meteorological fields: the right choice depends on whether the intended quantity is a source-cell value carried to finer cells or an interpolated estimate at finer cell centers.

- **GDAL** (`gdalwarp`/`gdal raster reproject` docs): nearest neighbour is
  described as giving the *"worst interpolation quality"* among the
  available resamplers; bilinear/cubic/cubicspline weight by Cartesian
  distance to produce smoothly varying output appropriate for continuous
  surfaces. (<https://gdal.org/en/stable/programs/gdalwarp.html>)
- **Esri** (ArcGIS/ArcGIS Pro "Cell size and resampling in analysis" and the
  Esri knowledge-base article "What is the difference between Nearest
  Neighbor, Bilinear Interpolation and Cubic Convolution?"): *"Nearest
  Neighbor is best used for categorical data... Bilinear Interpolation...
  should be used for continuous data like elevation and raw slope values...
  not recommended for categorical data."*
  (<https://support.esri.com/en-us/knowledge-base/what-is-the-difference-between-nearest-neighbor-bilinea-000005606>,
  <https://pro.arcgis.com/en/pro-app/3.1/help/analysis/spatial-analyst/performing-analysis/cell-size-and-resampling-in-analysis.htm>)
- **USDA-NRCS "Raster Mastery" (Issue 2, Jan 2020)**: gives a direct lookup
  table — Discrete/Categorical → Nearest Neighbor; Continuous (e.g. DEM,
  imagery) → Bilinear or Cubic Convolution — and states in bold: *"Never
  select the Nearest Neighbor method for continuous data. It will introduce
  artifacts... inherited by all subsequent derivatives."*
  (<https://www.nrcs.usda.gov/sites/default/files/2023-01/rastermastery-issue2.pdf>)

None of these sources is WaPOR-specific, but they are the standard
cartographic justification already invoked verbatim inside this repository
for PCP (`R/analysis_indicators.R:962-963`). RET is not categorical: it is a
continuous meteorological depth (mm/day) derived from a Penman-Monteith-type
model over a smooth spatial field (see §4), so the same justification applies
with at least equal force.

## 4. What is actually true about the native RET grid (WaPOR v3)

- `inst/metadata/wapor_L1.json:3-18` records `L1-RET-D`: `spatial_resolution:
  "30km"`, `spatial_resolution_m: 30000`.
- `vignettes/data-catalog.Rmd:23-26,35` documents the same figure ("30 km
  reference ET... per `inst/metadata/wapor_L1.json`") and is internally
  consistent with the JSON.
- **FAO's own WaPOR v3 data catalogue entries** confirm this independently:
  "Reference Evapotranspiration (Global – Daily – ~30 km) – WaPOR v3" and
  "(Global – Monthly – ~30 km) – WaPOR v3"
  (<https://data.apps.fao.org/catalog/dataset/6f487301-9731-4317-b620-faeccc976443>,
  <https://data.apps.fao.org/catalog/dataset/5f52e47e-1a14-4a07-864f-421ba53f83e2>),
  and additionally reveal the native grid is **not square**: width
  resolution `0.3125°`, height resolution `0.25°` (721 rows × 1152 columns
  globally). WaPOR v3 RET is produced from the **GEOS-5** reanalysis at ~30
  km via the FAO-56 Penman-Monteith equation (confirmed by an FAO
  application note citing GEOS-5 at 30 km resolution with <1-day latency for
  WaPOR ET₀: Tran et al. 2025, *Hydrological Sciences Journal*,
  <https://doi.org/10.1080/02626667.2025.2600682>), not AgERA5.
- **Documentation defect found in passing (not the subject of this
  question, but material to it):** `vignettes/global-tiled.Rmd:76-78` says
  *"AgERA5-based reference ET at about 9 km is summed on its own grid..."* —
  this contradicts both the repo's own metadata (`30 km`, GEOS-5-derived) and
  the FAO catalogue (`30 km`, non-square `0.3125°×0.25°`). This should be
  corrected to match `data-catalog.Rmd` and `inst/metadata/wapor_L1.json`
  (e.g. "GEOS-5-based reference ET at about 30 km"), independent of whatever
  is decided about the resampling default, because it currently
  understates the true up-sampling ratio to users by roughly 3×.
- Practical implication for the resampling question: RET's native cell
  (~30 km, non-square) is **6× coarser linearly than PCP's 5 km native
  grid**, and the up-sampling ratio to a typical analysis grid (300 m / 100 m
  / 20 m) is correspondingly larger (≈100×, ≈300×, ≈1500× linear). Blocky
  "stair-step" artifacts from nearest-neighbour resampling of a continuous
  field — the exact failure mode the external sources in §3 warn about — are
  *more* visible/consequential for RET than for PCP, not less, because the
  source cells are larger relative to the output grid.

## 5. WaPOR-specific methodological precedent and remaining gap

An important qualification to the earlier search result: Chukalla et al. (2022), a peer-reviewed WaPOR irrigation-performance study, explicitly resampled WaPOR's 5 km PCP and 20 km RET to 100 m using nearest-neighbour (Methods §2.2; DOI 10.5194/hess-26-2759-2022). This is directly relevant precedent for nearest-neighbour on continuous WaPOR meteorological inputs, although it documents a method used rather than proving it is more accurate than bilinear. The WaPOR-specific method search is therefore not a total negative result: there is precedent for nearest, but no comparative accuracy study establishing nearest versus bilinear as superior for the Rwapor use case.

Blatchford et al. (2020) describe bilinear resampling of weather data in the WaPOR production workflow; that is evidence that interpolation is also used in WaPOR-related processing, but it is not the same operation as a downstream user resampling the published L1 RET product. Neither paper establishes which choice best meets Rwapor's contract. The exact v3 L1 RET processing decision remains use-case dependent; do not claim FAO prescribes one specific downstream method.

## 6. What the existing tests actually check (and what they don't)

- `tests/testthat/test-processing.R:264-305` ("Accuracy: agreement with
  v1.0.0 and coverage (decisions A-C)") — `v100_seasonal_sum()` plus the test
  around line 292-305 verifies that the *new* engine's `"memory"` mode
  numerically reproduces the *old* v1.0.0 formula
  (`terra::resample(..., method = method)` then `wapor_masked_sum`) for
  **both** `"near"` (default) and `"bilinear"` (via
  `cfg$resampling_method <- list(ret = "bilinear")`) on the **same test
  fixture**. This is a **regression/consistency test** (new code matches old
  code's arithmetic for whichever method is requested) — it does **not**
  test which method is scientifically more appropriate, and it does not use
  a synthetic gradient or the real ~30 km × non-square native RET grid. It
  would pass identically whether the *default* were `"near"` or
  `"bilinear"`, so it provides no evidence either way for the default
  question.
- `tests/testthat/test-processing.R:246-262` ("agree on a projected analysis
  grid") and the surrounding `memory`/`stream`/`tiled` parity tests check
  cross-mode consistency, not resampling-method suitability.
- `tests/testthat/test-analysis.R:173-230` tests `wapor_harmonize_raster()`
  generically (overlap validation, multi-layer stacks) with synthetic grids,
  but not specifically for RET or for a >100× up-sampling ratio.
- **No existing test measures interpolation error/bias on a synthetic
  smooth gradient**, and **no existing test uses the real non-square ~30 km
  RET grid shape** (`0.3125° × 0.25°`) to check for anisotropic artifacts.
  This matches the gap the improvement plan already flagged (`IMPROVEMENTS_PLAN.md:132`,
  "Resampling methodology slice").

## 7. Recommendation

**Verdict: do not change the current RET default based on interpolation theory alone.** `ret = "near"` is not a demonstrated scientific optimum, but it is a defensible reproducibility/traceability choice: the engine documentation explicitly values retaining raw server values, and a peer-reviewed WaPOR v2.1 irrigation-performance workflow explicitly resampled both 5 km PCP and 20 km RET to 100 m using nearest-neighbour. This is direct precedent for nearest on continuous WaPOR meteorological layers, contrary to the earlier claim that the methodology angle had no relevant literature precedent. Bilinear is a reasonable configurable alternative for a smooth-field interpolation objective, but a synthetic plane test can only verify interpolation behavior against its constructed surface; it cannot establish which estimator better represents actual RET between coarse grid cells.

A bounded way forward:

1. Keep nearest as the default for now; do not label it a bug or silently switch user outputs.
2. Keep and clarify the per-variable overrides so users can choose interpolation when their analysis objective warrants it.
3. Treat synthetic-gradient comparisons as an explanatory numerical demonstration, not as evidence of meteorological truth. If deciding to change defaults later, compare against higher-resolution/reference meteorological data or a scientifically validated downscaling approach, and quantify impacts on seasonal outputs.
4. Document the existing rationale (raw WaPOR value traceability) and explain that PCP's bilinear default is a separate explicit configuration choice, rather than implying a universal continuous-vs-categorical rule.
5. Independently correct the verified source-description error in `global-tiled.Rmd` (completed in this checkout): the package metadata identifies L1 RET as 30 km; it is not AgERA5 at 9 km.

This is a methodology decision with user-output implications; current evidence supports preserving behavior until a comparison against relevant reference data justifies a change.

## 8. Possible validation work (not a default-selection test)

The synthetic cases below can make interpolation behavior measurable and catch implementation mistakes, but they **cannot establish which method best estimates true RET at unobserved locations**. Use them as explanatory/implementation tests only; a default change requires comparison to an appropriate independent reference or validated downscaling method.

1. **Synthetic smooth-gradient test (quantifies the §3 "blocky artifact"
   claim numerically).**
   Build a small synthetic "RET-like" source raster with a known smooth
   analytic field (e.g. `value = a + b*x + c*y`, a linear ramp, or a smooth
   sinusoid) at a coarse resolution analogous to ~30 km, and a fine analysis
   grid at a ratio similar to real use (e.g. 100–300×). Resample with both
   `"near"` and `"bilinear"`, then:
   - Compare each against the *known analytic value* at each fine-grid cell
     center (ground truth, not the old-vs-new regression check in
     `test-processing.R`). Assert bilinear's RMSE/MAE against the analytic
     truth is strictly lower than nearest's for a smooth field — this is the
     direct, falsifiable version of the §3 claim.
   - Assert nearest output is piecewise-constant in blocks matching the
     coarse grid (e.g. `length(unique(values_in_one_coarse_cell))` collapses
     to 1 for `"near"` but varies continuously for `"bilinear"`), giving a
     concrete, numeric artifact signature rather than a visual one.
2. **Real non-square native-grid regression test.**
   Construct a fixture raster with the *actual* WaPOR v3 L1-RET grid shape
   (`0.3125°` × `0.25°` cells, confirmed in §4) rather than a square
   approximation, resample onto representative L2 (100 m) and L3 (20 m)
   analysis grids, and assert the resampled output is free of row/column
   banding artifacts distinguishable from genuine spatial RET variation
   (e.g. check that `near` produces axis-aligned step discontinuities at
   multiples of the native cell size that `bilinear` does not).
3. **End-to-end seasonal-indicator sensitivity test.**
   Using the existing `processing_fixture()` helper already in
   `tests/testthat/helper-*.R` / `test-processing.R`, run
   `wapor_run_seasonal_analysis()` once with `ret` default (`"near"`) and
   once with `resampling_method = list(ret = "bilinear")`, and report (not
   just assert) the magnitude of change in `agg_ret`, `etc`, and
   `adequacy_etc` pixel-wise and as an AOI mean, so reviewers can see the
   practical impact before deciding (this generalizes the comparison already
   partially present at `test-processing.R:292-305`, but compares the two
   *methods* against each other and against ground truth, not each method
   against its own v1.0.0 replica).
4. **Documentation/metadata consistency check (cheap, catches regressions
   like the §4 "9 km" defect).**
   A test or lint step asserting the RET native-resolution figure quoted in
   `vignettes/global-tiled.Rmd` matches `inst/metadata/wapor_L1.json`'s
   `spatial_resolution_m` for `L1-RET-D`/`-E`, so vignette prose cannot drift
   from the metadata file again without failing CI.

## 9. Residual uncertainty / limitations of this research

- This was a documentation/code/web research pass; no R execution was
  performed to actually run the proposed tests (no code changes were
  authorized for this subtask). The RMSE/artifact magnitudes in §8 are
  expected, not measured.
- The `un-fao/wapor-et-look` GitHub wiki and FAO WaPOR quality-note PDFs
  (the most likely primary sources for an explicit FAO resampling
  recommendation) could not be fetched by the extraction backend available
  in this environment; only search-result snippets were available. Someone
  with working PDF/wiki access should check those directly before treating
  §5's negative result as final.
- "Needs more evidence" and "needs a code change" are not mutually
  exclusive here: the recommendation is to gather the specific evidence in
  §8 (which is cheap and fast to produce) and then act on it, rather than
  either leaving `"near"` unexamined or flipping the default without proof.

## Sources consulted

- Repository (this checkout, branch `docs/critical-review-improvement-plan`):
  `IMPROVEMENTS_PLAN.md:119-135`; `R/analysis_engine.R:37-45,160-170`;
  `R/analysis_indicators.R:949-972,996-1018`; `R/performance_indicators.R:48-54`;
  `R/zonal_stats.R:326-333`; `R/mask_helpers.R:112-118`; `R/classify.R:64-68`;
  `R/wapor_monitoring.R:671-676,1191-1197`; `inst/metadata/wapor_L1.json:1-18`;
  `vignettes/data-catalog.Rmd:21-26,32-36`; `vignettes/global-tiled.Rmd:72-82`;
  `tests/testthat/test-processing.R:225-305`; `tests/testthat/test-analysis.R:173-230`;
  `NEWS.md:129-147`; git history for `R/analysis_engine.R` (commits `9017edc`,
  and the earlier commit introducing `ret = "near"`/`pcp = "near"`).
- Blatchford et al. (2020), *Influence of Spatial Resolution on Remote Sensing-Based Irrigation Performance Assessment Using WaPOR Data*, Remote Sensing 12(18), 2949. The article's §2.2.2 states weather data were resampled to 250 m using bilinear interpolation; this is relevant counter-evidence to treating nearest as a universal continuous-data rule. <https://www.mdpi.com/2072-4292/12/18/2949>
- Chukalla et al. (2022), *A framework for irrigation performance assessment using WaPOR data: the case of a sugarcane estate in Mozambique*, Hydrology and Earth System Sciences 26, 2759–2778. The methods state 5 km precipitation and 20 km RET were resampled to 100 m using nearest-neighbour. <https://hess.copernicus.org/articles/26/2759/2022/>
- GDAL documentation: <https://gdal.org/en/stable/programs/gdalwarp.html>,
  <https://gdal.org/en/latest/programs/gdal_raster_reproject.html>.
- Esri: <https://support.esri.com/en-us/knowledge-base/what-is-the-difference-between-nearest-neighbor-bilinea-000005606>,
  <https://pro.arcgis.com/en/pro-app/3.1/help/analysis/spatial-analyst/performing-analysis/cell-size-and-resampling-in-analysis.htm>.
- USDA NRCS, "Raster Mastery" Issue 2 (Jan 2020):
  <https://www.nrcs.usda.gov/sites/default/files/2023-01/rastermastery-issue2.pdf>.
- FAO WaPOR v3 data catalogue: L1-RET-D/-M dataset pages,
  <https://data.apps.fao.org/catalog/dataset/6f487301-9731-4317-b620-faeccc976443>,
  <https://data.apps.fao.org/catalog/dataset/5f52e47e-1a14-4a07-864f-421ba53f83e2>;
  FAO GEE access page listing `L1-RET-D`/`L1-RET-E` collections,
  <https://www.fao.org/in-action/remote-sensing-for-water-productivity/wapor-data-access/en>.
- Tran, B.N., Dehati, S., Seyoum, S., van der Kwast, J., Jewitt, G.,
  Uijlenhoet, R. and Mul, M. (2025). "Evaluating reanalysis datasets as
  meteorological input for estimating reference evapotranspiration in Africa
  and Southwest Asia," *Hydrological Sciences Journal* (preproduction),
  confirming WaPOR's use of GEOS-5 at 30 km with FAO-56 Penman-Monteith for
  RET. <https://doi.org/10.1080/02626667.2025.2600682>
  (summary via FAO applications catalogue page).
- `un-fao/wapor-et-look` GitHub wiki (methodology document index only;
  page content not retrievable with the extraction backend available here —
  see §9): <https://github.com/un-fao/wapor-et-look/wiki>.
