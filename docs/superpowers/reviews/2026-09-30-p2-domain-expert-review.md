# Domain expert review: P2 plan (generalized zonal features)

| | |
|---|---|
| **Plan reviewed** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md` (WP1 to WP5) |
| **Design background** | `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`, section P2, block "REVISED 2026-09-30" |
| **Code read** | `R/analysis_indicators.R`, `R/analysis_registry.R`, `R/analysis_engine.R`, `R/crop_defaults.R`, `R/indicators_math.R`, `R/analysis.R` (`wapor_build_kc`), `R/wapor_ts.R`, `R/viz.R`, `DESCRIPTION`, `NAMESPACE`, training notebook chunks |
| **Reviewer role** | Geospatial analysis, WaPOR v3 methodology, irrigation performance assessment, FAO-56 agrometeorology |
| **Date** | 2026-09-30 |
| **Status of this file** | Advisory. It does not change the plan; the owner decides. |

How to read the evidence labels:

- **VERIFIED**: I checked the primary source during this review (quoted text or table).
- **Secondary**: taken from a paper that cites the primary source; the primary source was not opened.
- **UNVERIFIED**: from memory or unclear sources. Check it before it becomes a default or a test value.

---

## 1. Executive summary

The plan is technically sound as software (one classifier, one zonal engine, independent tests). The science
needs corrections before implementation. Ten changes, most important first:

1. **Separate "masked out" from "no data" in WP2.** With a crop mask, `coverage` = valid area / zone area. A zone that is 30% crop then falls below `min_coverage = 0.5` and all its statistics become NA. Report `mask_fraction` (crop share of the zone) and `coverage` (valid share of the *masked* area) as separate values.
2. **Fix the volume unit rule in WP2.** "Unit starts with `mm`" also accepts `mm/day` and `mm/dekad`, which are rates. Allow volumes only for depths (`mm`, `mm/season`, `mm/month`). Convert rate layers with the dekad day counts (8 to 11 days) first.
3. **Replace the `uniformity` scheme.** 65/75/85% are *per irrigation method* acceptance standards (Pitts et al. 1996, as quoted by Chukalla et al. 2022; VERIFIED). They are not three bands of one scale. Use one threshold chosen by `irrigation_method`. Also offer the low-quarter distribution uniformity (DU_lq), the measure those standards are written for.
4. **Cite the correct sources.** The adequacy breaks 0.68/0.8/1 come from Karimi et al. (2019), quoted by Chukalla et al. (2022, text and Table A1; VERIFIED). The equity breaks 0.10/0.25 come from Bastiaanssen et al. (1996) and Karimi et al. (2019). Name the class above 1 "above ETc". It is a package extension, not a published class.
5. **Use one definition of spread everywhere.** Use the population standard deviation, area-weighted where cells differ in area, and let users choose the sample SD. Make the WP2 weighted quantile reduce to `type = 7` when all weights are equal, so it agrees with WP1 and `wapor_calc_p95_aeti()`.
6. **Give resolution-independent minimum sizes.** `min_pixels = 100` is the training's "4 ha at 20 m". Use `min_area_ha` plus `min_cell_fraction`, which excludes mixed edge pixels. Warn when a unit has fewer than about 9 whole pixels (for example, uniformity inside fields at L1, 300 m).
7. **Add the missing core indicators in WP3.** Add relative water deficit, RWD = 1 - AETI/ETx, where ETx is ETc or a percentile of AETI. Add productivity targets and gaps (P95, as in the IHE Delft WaPOR protocol), temporal reliability (CV over time of relative ET), and area-weighted Gini and Theil. All of these work with the existing stacks.
8. **Correct the perennial crop data in WP4.** The six citrus Kc rows match FAO-56 Table 12 (VERIFIED). The Table 11 citrus start month is **January**, not March. The stage names are training wording and should not be defaults. Add a dormant-season Kc for deciduous trees. Add an optional FAO-56 Eq. 62 climate adjustment of Kc_mid.
9. **Generalize effective rainfall.** Offer `peff_method = c("usda_cropwat", "fao_aglw", "fixed", "none")` with documented monthly validity. Stop assigning blue water to classes flagged as rainfed. Document that the green/blue split depends on the time step and ignores soil water carried over from before the season.
10. **Fix the existing `FAO_CROP_DEFAULTS` rows while WP4 has the table open.** Winter wheat Kc_ini 0.40 is Table 12's *frozen-soil* value but is labelled "non-frozen soils" (non-frozen = 0.7). Sorghum Kc_ini 0.30 (Table 12: 0.2) and the sugarcane stage lengths do not match any single Table 11 row. Changing them moves known answers, so this needs an owner decision.

---

## 2. Findings per work package

### WP1: classification engine (`wapor_classify()`, `wapor_class_defaults()`)

**Correct as designed**

- Interval rule, labels, quantile type 7, reference groups, metadata attached to the result, and project-wide overrides. These are good, general design choices.
- Tests 1 to 8 are independent and correct. Test 4: P5 and P95 of 1..100 (type 7) are 5.95 and 95.05, so the counts are 5/90/5.

**Correctness issues**

| # | Issue | Evidence | Recommended change |
|---|---|---|---|
| 1.1 | Adequacy source cited as "Chukalla et al. 2022, Table A1". The thresholds are in Chukalla's text (Sect. 2.3.2), attributed to Karimi et al. (2019). Table A1 lists the indicators with Karimi (2019) as reference, but no class limits. | VERIFIED, Chukalla et al. 2022, pp. 2763 to 2764 and Table A1 | `source = "Karimi et al. (2019) Remote Sens. 11, 705; as applied in Chukalla et al. (2022) HESS 26, 2759"` |
| 1.2 | Class 4 "above demand" (A > 1) is not a published class. A > 1 usually means the Kc x RET demand is too low (wrong Kc, advection, oasis effect) or AETI is biased. It rarely means true over-consumption, because ET cannot exceed the energy-limited rate. | Chukalla defines only good / acceptable / poor | Label it `"above ETc"` and say in the docs "check Kc and data; not a performance class" |
| 1.3 | The `uniformity` scheme `c(0.65, 0.75, 0.85)` treats three irrigation-method standards as one ordinal scale. In the source, each method has a single acceptance threshold: centre pivot 75%, sprinkler 75%, drip 85%, furrow 65%; "exceeding the standard threshold is considered excellent". A furrow field at 70% *meets* its standard, but this scheme puts it in the second-lowest class. | VERIFIED, Chukalla et al. 2022 p. 2763, citing Pitts et al. (1996) | Replace with the schemes `uniformity_surface` (0.65), `uniformity_sprinkler` (0.75), `uniformity_pivot` (0.75), `uniformity_drip` (0.85), each with two classes `"below standard"` / `"meets standard"`. Choose with `irrigation_method` in WP3. |
| 1.4 | The thresholds compare an ET statistic with standards for *applied water*. Pitts et al. (1996) evaluated the distribution uniformity of application depths (UNVERIFIED whether it was DU low-quarter). ET varies much less than applied water, because root-zone storage and crop buffering smooth it. So 1 - CV of ET overstates irrigation uniformity. Chukalla calls it a "proxy". | Chukalla p. 2763 ("can serve as a proxy for irrigation distribution uniformity") | Say so in the docs. Offer DU_lq and Christiansen CU of ET (Sect. 3.4) so users can compare like with like. |
| 1.5 | `equity` breaks 0.10/0.25 are correct (Bastiaanssen et al. 1996; Karimi et al. 2019; VERIFIED as quoted in Chukalla 2022). Molden & Gates (1990) use the same limits for the spatial CV of *delivery* (Secondary). | Chukalla p. 2763 | Keep. Cite both. State that these are CVs as fractions. |
| 1.6 | The `spots` scheme `c(0.05, 0.95)` is attributed to "the training notebook". The published basis is the IHE Delft / FAO WaPOR protocol. It sets the *target* at the 95th percentile of land productivity and of water productivity, and defines bright spots as fields where both are at or above target. "Dark spots" (at or below P5 in both) is a package convention; that protocol only colours the 0 to 5 percentile band. | VERIFIED: WAPORWP Module 5 notebook (Chukalla et al. 2020 protocol, Zenodo 10.5281/zenodo.4641360) | Source: Chukalla et al. (2020) protocol. Label `dark` as "package convention (symmetric to bright)". |
| 1.7 | Ties: `wapor_classify()` with `right = TRUE` places a value equal to P95 in the *lower* class. WP3 spots use `cwp >= high`, which places it in the upper class. The WAPORWP protocol uses `>=` target for bright. | Plan WP1 vs WP3 | Keep `>=` for bright and `<=` for dark, as in the protocol. Build them with explicit comparisons, not through the `right` rule, and test a value that equals the threshold. |
| 1.8 | Quantile groups may have very few values. The plan accepts any group with at least `length(breaks) + 1` values, but a P95 from 4 values is meaningless. `wapor_calc_p95_aeti()` already uses `min_pixels = 30`. | `R/analysis_indicators.R:285` | Add `min_n = 30` to `wapor_classify()` for `method = "quantile"`, the same default as `wapor_calc_p95_aeti()`. Groups below it get NA and a warning. |
| 1.9 | Class direction is implicit. For adequacy, higher is better; for equity (CV), lower is better. Colour scales, and any "share good" summary, need this. | none | Add `direction = c("higher_better", "lower_better", "none")` to each scheme. |

**Additional schemes worth shipping as documented alternatives, not defaults**

- `adequacy_molden_gates`: breaks 0.80 / 0.90 (poor < 0.80, fair 0.80 to 0.89, good 0.90 to 1.00). These were written for delivered/required water; their use with ET is an analogy (Secondary, UNVERIFIED exact bands).
- `dependability_molden_gates`: temporal CV breaks 0.10 / 0.20 (good / fair / poor) (Secondary, UNVERIFIED exact bands).
- `rwd`: no published class limits. Ship without a default scheme; users supply breaks.
- `beneficial_fraction`: no published class limits for WaPOR. Chukalla et al. (2022) question the accuracy of the WaPOR E/T split. Do not ship thresholds.

### WP2: zonal statistics engine (`wapor_zonal_stats()`)

**Correct as designed**

- Exact cell fractions (exactextractr), dissolve by id, each nested level extracted from its own geometry, the AOI as the union of zones (so overlaps are not counted twice), equal-area measurement of areas, and class shares on the valid area. These are good practice.
- Volume formula: 1 mm over 1 m2 = 0.001 m3 (1 mm over 1 ha = 10 m3). Correct.
- The tests are independent. Test 3 expected value: (a x 400 + b x 200) / 600; for a = 10, b = 20 this is 13.333.

**Correctness issues**

| # | Issue | Why it matters | Recommended change |
|---|---|---|---|
| 2.1 | **Coverage conflates mask and missing data.** Step 8 sets statistics to NA when `sum(w[ok]) / zone_area < min_coverage`, and `ok` excludes masked cells. A district with 20% irrigated area always fails at 0.5. | At scheme, district and country scale, crop masks cover a minority of each zone, so the engine would silently return NA for most zones. | Compute three area terms per zone: `zone_area_ha` (geometry, equal-area), `mask_area_ha` (area of cells inside the mask, weighted by coverage), `valid_area_ha` (mask cells with non-NA data). Report `mask_fraction = mask_area / zone_area` and `coverage = valid_area / mask_area`. Apply `min_coverage` to `coverage` only. Add an optional `min_mask_area_ha` (default 0). |
| 2.2 | **Volume unit check accepts rates.** `startsWith(unit, "mm")` is TRUE for `mm/day` and `mm/dekad`. WaPOR v3 dekadal AETI, T, E and RET are mm/day. Their volume is not a depth x area. | A dekadal mm/day stack would give volumes 8 to 11 times too small. | Accept only depths: `mm`, `mm/season`, `mm/month`, `mm/year`, and `mm/dekad` when the layer is a dekad total. For `mm/day`, require `days` (per-layer day counts; the package already derives them as layer multipliers) or skip with a warning. Always label the period the volume refers to. |
| 2.3 | **Weighted quantile definition.** "Value at the first c >= p" is an inverse-CDF (type 1-like) estimator. For a zone of whole cells it differs from `stats::quantile(type = 7)`, which WP1 and `wapor_calc_p95_aeti()` use. The same data would give two different P95 values. | Inconsistent targets between the classifier, the engine and the existing adequacy_p95. | Use a weighted estimator that equals type 7 when all weights are equal. One example is the weighted Harrell-Davis estimator, but that is heavy. A simpler option: linear interpolation on the cumulative weight positions `(cumsum(w) - w) / (sum(w) - w_last)`, which reduces exactly to type 7 for equal weights (check this in a test). Document the definition and test the equal-weight case against `quantile(type = 7)`. |
| 2.4 | **Population vs sample SD.** The engine uses the weighted population SD. WP3 blocks use "sample sd as the notebook". | Two definitions of uniformity within one package. | Population SD everywhere, which is what the IHE Delft protocol uses (`np.nanstd`; VERIFIED in WAPORWP Module 3). Add `sd_type = c("population", "sample")`. With 100 or more pixels the difference is under 0.5%. |
| 2.5 | **Mixed pixels at field edges.** Edge cells mix crop, bunds, roads and neighbours. Area weighting reduces their influence on the mean, but they inflate SD, CV, minimum, maximum and percentiles. | Uniformity and spot analysis of small fields is biased by edges; at L1 and L2 most field pixels are edge pixels. | Add `min_cell_fraction = 0` (engine default). WP3 uniformity uses 0.5 by default (heuristic, no literature). Report `n_cells` (cells with w > 0) and `n_eff = sum(coverage_fraction)`. |
| 2.6 | **Minimum mapping unit by resolution.** A 300 m L1 pixel is 9 ha, a 100 m L2 pixel 1 ha, a 20 m L3 pixel 0.04 ha. The plan has no rule for when statistics inside a zone mean something. | Users will compute "field uniformity" at L1. | Warn when a zone has `n_eff < 9` (fewer than about a 3 x 3 pixel block; heuristic, UNVERIFIED as a standard). Add `min_cells` to the call attributes. |
| 2.7 | **Area of lon/lat zones.** The LAEA-per-zone approach is correct. For geographic CRSs, `sf::st_area()` with s2 off already computes ellipsoidal geodesic areas through lwgeom, which is exact and needs no projection. | Simpler and exact for country-size zones; no centroid issue for multi-part zones crossing ±180 degrees. | Either approach is fine. Test country-size and antimeridian cases. Keep equal-area projection for planar operations. |
| 2.8 | **Heavy R-side extraction.** Pulling every cell value into R for 500-zone batches is slow at 300 m country scale. | Performance. | Consider exactextractr's built-in summary operations (`"weighted_mean"`, `"stdev"`, `"quantile"`, `"frac"`, `"weighted_frac"`, `"count"`) with `weights = "area"` for geographic rasters. They stream in C++. Verify the exact semantics against the installed exactextractr version (UNVERIFIED details: whether stdev and quantile honour area weights). Keep the R path for the custom statistics (DU_lq, Gini). |
| 2.9 | **Time series per zone (`by = "month"/"dekad"`)** is in the design spec but not in the plan. | Temporal indicators (reliability) and monthly green/blue need it. | Keep layers as time steps (as planned) and add a `period`/`days` table input so rate layers can be summed correctly (see 2.2). |
| 2.10 | **Multi-season results.** No `season` column. | Double cropping and perennial years crossing 1 January. | Add a `season` column (NA when not applicable), filled from the analysis result (season id / start-end). |

**Generalization notes**

- Class shares: use the valid masked area as the denominator (as planned), and also report `class_area_ha` for a "no data" class, so the reported percentages can be traced back.
- Nested aggregation: the plan correctly re-extracts each level. For volumes, also check that parent volume = sum of child volumes when the children partition the parent exactly (a useful invariant test).

### WP3: irrigation performance indicators and spots

**Correct as designed**

- Adequacy = AETI / ETc with ETc = Kc x RET is the Chukalla definition. Their ETp,s is built from **monthly** Kc x RET (VERIFIED, Table A1). The package builds dekadal Kc x RET, which is better and consistent.
- Equity = CV of unit means (Chukalla: "CV of the average ET of each field"; VERIFIED).
- f_norm = mean(RET) / RET_i (VERIFIED, Chukalla Eq. 3). In Chukalla, the mean RET is **weighted by field size and growing length**.

**Correctness and generalization issues**

| # | Issue | Recommended change |
|---|---|---|
| 3.1 | Uniformity classes from a single ordinal scheme (see 1.3). | `wapor_calc_uniformity(..., irrigation_method = c("unknown", "surface", "sprinkler", "pivot", "drip"))`. With `"unknown"`, return the values without classes. Compute and return `uniformity_cv = 1 - CV` (Chukalla), `du_lq` and `cu` (Sect. 3.4). |
| 3.2 | `min_pixels = 100` is the training's 4 ha at 20 m. At L1 it would need 900 ha. | Replace with `min_area_ha` (default 1 ha; heuristic) plus `min_cell_fraction = 0.5`. Warn when n_eff < 9. |
| 3.3 | Block path: `terra::aggregate(fun = "sd")`. The plan asserts it is the sample SD; I could not confirm which SD terra uses in `aggregate` (UNVERIFIED). Blocks also mix fields, crops, canals and villages, so block "uniformity" measures landscape heterogeneity. | Compute block statistics with the WP2 engine on a generated grid of block polygons (`sf::st_make_grid()`), so one code path and one SD definition apply. Document that blocks are a fallback when field boundaries are missing. |
| 3.4 | Equity is unweighted across units. Chukalla uses the unweighted form, but for schemes of very unequal fields an area-weighted CV is also reported in the literature. | `weights = c("none", "area")`, default `"none"` (as in the literature). |
| 3.5 | Equity with a sample SD. With units c(10, 12, 14): sample CV 0.1667, population CV 0.1361. Both give "fair". | Follow 2.4 (population by default, `sd_type` argument). |
| 3.6 | `wapor_climate_norm()` returns the factor only. Users must know how to apply it: for water depths (AETI, adequacy numerator) multiply by f_norm; for water productivity divide by f_norm (UNVERIFIED as a published convention; this follows from WP being inversely related to evaporative demand). Chukalla weights the mean RET by field size and growing length. | Rename to `wapor_calc_climate_norm(ret, zones = NULL, weights = c("area", "none"), mask = NULL)`. Add `wapor_apply_climate_norm(x, f_norm, type = c("depth", "productivity"))`. Also offer the physically based normalized biomass WP (Sect. 3.6). |
| 3.7 | Spots use CWP from NPP-derived yield. Yield and CWP are then both functions of NPP and AETI, so they are strongly correlated and the "both high" rule is partly redundant. Spots from pixels at L3 are sensitive to outliers and mixed pixels. | Default spot inputs: land productivity (biomass or yield) and water productivity (the protocol pair). Zone mode is the recommended default for management use. Apply `min_cell_fraction` in pixel mode. Require a homogeneous reference group (same crop, season and agro-climatic zone). Warn when `reference = NULL` and the AOI spans more than one crop class. |
| 3.8 | "Reproduce the training's wheat results" as an objective (O3). The training is one example and uses a sample SD and 100-pixel blocks. | Keep it as an optional local acceptance check only, with tolerances that allow the population-SD change. Put the defaults in writing as *literature* defaults. |
| 3.9 | Adequacy uses ETc for well-watered, standard conditions. For deficit-irrigated trees (RDI in citrus and olives), rainfed crops and salinity-affected areas, "poor" adequacy can be intended management. | Document it. Offer `adequacy_ref = c("etc", "p95", "p99", "etp_user")`. The package already has `adequacy_p95`. |

### WP4: perennial (tree) crops

**Verified values (FAO-56, Allen et al. 1998, Chapter 6)**

- Table 12, citrus (VERIFIED, all six rows match the plan exactly):

  | Citrus row | Kc_ini | Kc_mid | Kc_end | h (m) |
  |---|---|---|---|---|
  | no ground cover, 70% canopy | 0.70 | 0.65 | 0.70 | 4 |
  | no ground cover, 50% canopy | 0.65 | 0.60 | 0.65 | 3 |
  | no ground cover, 20% canopy | 0.50 | 0.45 | 0.55 | 2 |
  | active ground cover or weeds, 70% | 0.75 | 0.70 | 0.75 | 4 |
  | active ground cover or weeds, 50% | 0.80 | 0.80 | 0.80 | 3 |
  | active ground cover or weeds, 20% | 0.85 | 0.85 | 0.85 | 2 |

- Table 12 header: values are for "non stressed, well-managed crops in subhumid climates (RHmin ≈ 45%, u2 ≈ 2 m/s)" (VERIFIED).
- Footnotes 21 and 22 (VERIFIED): for humid and subhumid climates, where citrus has less stomatal control, Kc_ini, Kc_mid and Kc_end "can be increased by 0.1 - 0.2" (Rogers et al. 1983). The no-cover values follow from Eq. 98 with Kc_min = 0.15 and Kc_full = 0.75 / 0.70 / 0.75.
- Table 11, citrus (VERIFIED): Init 60, Dev 90, Mid 120, Late 95, total 365, start **Jan**, Mediterranean. The plan says "start March": **wrong**.
- Other perennial rows verified from Table 12 and Table 11 (this answers decision D3; these can be added):

  | Crop (Table 12 row) | Kc_ini | Kc_mid | Kc_end | h (m) | Table 11 stages (Init/Dev/Mid/Late, start, region) |
  |---|---|---|---|---|---|
  | Olives (40 to 60% ground cover) | 0.65 | 0.70 | 0.70 | 3 to 5 | 30/90/60/90, March, Mediterranean |
  | Grapes, table or raisin | 0.30 | 0.85 | 0.45 | 2 | 20/40/120/60, April, low latitudes (also 20/50/75/60 Calif.; 20/50/90/20 high lat.) |
  | Grapes, wine | 0.30 | 0.70 | 0.45 | 1.5 to 2 | 30/60/40/80, April, mid latitudes (wine) |
  | Date palms | 0.90 | 0.95 | 0.95 | 8 | not found in Table 11 during this review (UNVERIFIED; do not invent) |
  | Pistachios, no ground cover | 0.40 | 1.10 | 0.45 | 3 to 5 | 20/60/30/40, Feb, Mediterranean |
  | Apples, cherries, pears (no cover, killing frost) | 0.45 | 0.95 | 0.70 | 4 | deciduous orchard 20/70/120/60, March, low latitudes |
  | Stone fruit (no cover, killing frost) | 0.45 | 0.90 | 0.65 | 3 | deciduous orchard (as above) |
  | Avocado, no ground cover | 0.60 | 0.85 | 0.75 | 3 | not checked |
  | Banana, 1st year / 2nd year | 0.50/1.00 | 1.10/1.20 | 1.00/1.10 | 3/4 | 120/90/120/60 Mar; 120/60/180/5 Feb, Mediterranean |

  Footnote 18 (VERIFIED): the deciduous Kc_end is the value before leaf drop. After leaf drop, Kc ≈ 0.20 over bare dry soil or dead cover, and 0.50 to 0.80 with actively growing ground cover. Footnote 24: olive values are for 40 to 60% ground cover; use Eq. 98 for immature stands.

**Issues and recommendations**

| # | Issue | Recommended change |
|---|---|---|
| 4.1 | Citrus start month given as March. | Table 11 says January. Store `start_month` as a column (`1` for citrus) and never hard-code it in the analysis; the user's season rasters decide. |
| 4.2 | `stage_names` for citrus ("Flowering and new growth", ...) come from the training, not FAO-56. FAO-56 uses the same four stages (initial, crop development, mid-season, late season) for all crops, including trees. | Default `stage_names = NA` in the table. The plot and output fall back to the FAO-56 names. Users may supply phenological labels. |
| 4.3 | No off-season value for deciduous trees and vines. A 365-day analysis of apples or grapes needs a dormant Kc (footnote 18). | Add `kc_dormant` (NA for evergreen and annual crops) and `crop_type = c("annual", "perennial_evergreen", "perennial_deciduous")`. Outside the Table 11 stages, Kc = `kc_dormant` for deciduous crops. |
| 4.4 | No climate adjustment. FAO-56 Eq. 62: Kc_mid = Kc_mid(Tab) + [0.04 (u2 - 2) - 0.004 (RHmin - 45)] (h/3)^0.3, valid for 1 ≤ u2 ≤ 6 m/s, 20 ≤ RHmin ≤ 80%, 0.1 < h < 10 m. Eq. 65 applies the same to Kc_end only when Kc_end(Tab) > 0.45 (validity and the 0.45 rule VERIFIED; the equation is well known, and its constants should be re-read from the FAO-56 page before coding). The North Jordan Valley (arid) and Jendouba (subhumid) differ in RHmin, so tabulated values are not transferable without it. | Add `wapor_adjust_kc_climate(kc_mid, kc_end, u2, rh_min, h)`, exported and pure numeric. Optional input from AgERA5, which the package already downloads. Clamp inputs to the validity range with a warning. For citrus, also document the footnote 21/22 humid-climate increase. Priority 1.0.6: small and fully testable. |
| 4.5 | Canopy-cover dependence. Table 12 citrus rows are discrete (20/50/70%). Allen & Pereira (2009) and FAO-56 Eq. 98 give Kc from the fraction of ground cover and height. | Later (1.1.x): `wapor_kc_from_cover(fc_eff, h, kc_min, kc_full)`. Point users to Rallo et al. (2021) for updated tree Kc values. |
| 4.6 | Yield chain skipped for perennials (good). The HI/AOT/MC chain for trees is not established in WaPOR methodology. | Keep the skip. Add `yield_input` (a table or raster of measured yield) as decision D1 recommends. That makes CWP possible for trees and for any crop with survey yields. |
| 4.7 | `fc` documentation fix (good). Chukalla used fc = 1.6 for sugarcane (C4), computed as crop LUE / generic WaPOR LUE (VERIFIED, Chukalla Table 2 and text). The WaPOR v3 generic LUE may differ from the v2 value Chukalla used (UNVERIFIED). | Document fc as "crop LUE / WaPOR generic LUE; about 1 for C3 crops; above 1 for C4 crops (e.g. 1.6 for sugarcane in Chukalla et al. 2022)". Do not ship C4 defaults without a v3 source. |
| 4.8 | Existing rows (outside the plan scope, found while verifying): **Winter Wheat** Kc_ini 0.40 with note "non-frozen soils". Table 12 gives 0.4 for frozen soils and **0.7** for non-frozen soils (VERIFIED). **Sorghum** Kc_ini 0.30 (Table 12 grain sorghum 0.2). **Sugarcane** stages 35/180/60 do not match any Table 11 row (virgin low latitudes 35/60/190/120; ratoon tropics 30/50/180/60). **Alfalfa** is one cutting cycle (10/20/20/10), so it cannot be used with a whole-season mask without cutting cycles. Also, Table 12 Kc_ini is a typical value only; FAO-56 computes Kc_ini from wetting interval and depth (Figs. 29 and 30). | Owner decision (these move known answers). At minimum correct the `notes` column now. Change values in a separate, announced change with updated golden values. |
| 4.9 | Evergreen perennials need a "season" = crop or hydrological year, possibly crossing 1 January. | Check that `wapor_build_season_profile_table()` handles start day > end day. Add a test with a Jan to Dec citrus year and an Oct to Sep water year. |

### WP5: masks, plots, offline URLs

The science is sound. Remarks:

- `wapor_harmonize_mask()`: fraction-based resampling with `method = "average"` on a 0/1 raster is correct. The 0.5 default is a reasonable majority rule but has no literature basis; call it a heuristic. **Return the fraction raster too.** A fraction mask is the right weight for zonal statistics at L1 and L2, where most pixels are mixed. Pass it as `weights` to WP2, instead of a hard binary mask (priority 1.0.6: small change, large benefit at coarse levels).
- `wapor_rasterize_mask()`: area ratio check 0.9 to 1.1 is fine as a warning. For small polygons at L1 the ratio is always far off; make the tolerance depend on the polygon area in pixels.
- `viz.R`: `ggplot2` is only in Suggests (`DESCRIPTION`), so the plot functions need a `requireNamespace()` guard. `rlang` is not imported, so use `utils::globalVariables()`. Plotting 1e6 rows with `geom_raster` is fine; `geom_tile` is much slower. Use `geom_tile` only for irregular grids.
- Kc plot: allow dormant periods and year-crossing seasons (from WP4).

---

## 3. Recommended additions (beyond the plan)

Priorities: **1.0.6** = small, pure functions on existing outputs, independently testable. **Later** = needs new inputs, engine changes or more scientific decisions.

### 3.1 Relative water deficit and alternative demand references (1.0.6)

- RWD = 1 - AETI / ETx, where ETx = ETc (Kc x RET) or a percentile of AETI within a homogeneous group. The IHE Delft protocol uses ETp or the **99th** percentile of AETI (VERIFIED, WAPORWP Module 3). The package's `adequacy_p95` uses P95. Make the percentile an argument (`p = 0.95`) and document both choices. Unitless; clamp at [0, 1] only for display, never in stored data.
- Seasonal water deficit depth: ETc - AETI (mm), and volume (m3) through WP2.
- Net irrigation requirement: NIR = max(0, ETc - Peff) (FAO-56 / CROPWAT concept; Smith 1992), in mm and m3. Compute it monthly and then sum, like green/blue.
- Sources: Bastiaanssen & Bos (1999); Chukalla et al. (2020, 2022); Allen et al. (1998).

### 3.2 Productivity targets, gaps and bright spots (1.0.6)

- Target = P95 of land productivity (biomass or yield) and P95 of WP within a reference group. Bright spot = LP ≥ target_LP **and** WP ≥ target_WP. Gap = max(0, target - value). Production gap = sum of LP gap x area (VERIFIED definitions: WAPORWP Module 5; Chukalla et al. 2020 protocol).
- The literature does not agree on the percentile. The yield gap literature commonly uses the 90th or 95th percentile of farmer yields as "attainable" (Lobell et al. 2009; van Ittersum et al. 2013; exact recommendations UNVERIFIED). Default 0.95 (protocol); configurable.
- Functions: `wapor_calc_productivity_gap(x, p = 0.95, reference = NULL)` returning target, gap raster or table, and production gap (t) through WP2.

### 3.3 Temporal indicators (1.0.6 for the function; engine wiring later)

- Reliability (temporal CV of relative ET per pixel or zone): CV over the season's dekads or months of AETI_t / ETc_t (Bastiaanssen & Bos 1999). Molden & Gates (1990) "dependability" is the temporal CV of delivered/required water, with good ≤ 0.10, fair 0.11 to 0.20, poor > 0.20 (Secondary; UNVERIFIED exact bands).
- Needs the monthly AETI and monthly ETc rasters, which the engine already builds (`monthly_aeti`, `monthly_etc`).
- Use monthly by default: dekadal relative ET is noisy (cloud gap-filling in AETI).

### 3.4 Uniformity and inequality measures (1.0.6)

Area-weighted (w = covered cell area) versions of:

| Measure | Formula | Notes and source |
|---|---|---|
| Uniformity (Chukalla) | 1 - CV, CV = σ_w / μ_w | Ascough & Kiker (2002), Chukalla et al. (2022) |
| Christiansen CU | 1 - Σ w\|x - μ\| / (μ Σ w) | Christiansen (1942) |
| Low-quarter DU | mean of the lowest 25% (by weight) / μ | Merriam & Keller (1978); the measure behind irrigation-system standards |
| Gini | weighted Gini of x | Standard inequality index |
| Theil T | Σ w (x/μ) ln(x/μ) / Σ w | Already in the package (`wapor_calc_theil`); expose the weighted version |

For normally distributed values, CU ≈ 1 - 0.798 CV and DU_lq ≈ 1 - 1.27 CV (Warrick 1983; coefficients from memory, UNVERIFIED). For example, CV = 0.20 gives 1 - CV = 0.80 but DU_lq ≈ 0.75. This is why comparing 1 - CV with DU standards is optimistic. Add `"cu"`, `"du_lq"`, `"gini"`, `"theil"` to the WP2 `stats` list.

### 3.5 Effective rainfall and green/blue (partly 1.0.6)

The current method (`wapor_calc_peff`, `wapor_math_peff_usda`) is the CROPWAT "USDA-SCS" simplification: Peff = P (125 - 0.2 P) / 125 for P ≤ 250 mm/month, else 125 + 0.1 P (Smith 1992). The code matches that formula.

| Method | Formula (monthly P, mm) | Source and notes |
|---|---|---|
| `usda_cropwat` (default, current) | as above | Smith (1992) CROPWAT. This is **not** the full USDA-SCS (1993) NEH 623 method, which depends on monthly ETc and soil storage depth. Rename in the docs to avoid confusion. |
| `fao_aglw` (dependable rain) | P ≤ 70: max(0, 0.6 P - 10); P > 70: 0.8 P - 24 | FAO/AGLW formula in CROPWAT (Smith 1992); roughly 80% probability of exceedance. Continuous at 70 mm (32 mm). Primary document UNVERIFIED (often attributed to Dastane 1974, FAO I&D Paper 25, or FAO 33). |
| `fixed` | Peff = f P | User fraction; no universal default (tools use 0.7 or 0.8; UNVERIFIED). Require the user to give `f`. |
| `usda_scs_full` (later) | Peff = SF (0.70917 P^0.82416 - 0.11556) 10^(0.02426 ETc), bounded by min(P, ETc) | USDA-SCS (1993) NEH 623 ch. 2; needs soil storage depth. Coefficients from a secondary implementation (UNVERIFIED). |
| `none` | Peff = P | For sensitivity analysis |

Why the choice matters: in a 60 mm month, `usda_cropwat` gives 54.2 mm and `fao_aglw` gives 26 mm. The blue water share of a winter wheat season can therefore differ by tens of percent. Muratoglu et al. (2023, Water Research 238, 120011) compared methods against soil water balances and found large differences, with FAO/AGLW performing worst in their cases (Secondary, from the search abstract).

Time step: these formulas are calibrated on monthly totals. The package correctly splits each month and then sums. Document that:

- (a) applying the monthly formula to season-weighted *partial* months slightly overestimates Peff in the start and end months;
- (b) a dekadal split gives more blue water than a monthly split, because wet and dry dekads within a month no longer compensate;
- (c) a CROPWAT dekadal variant exists (UNVERIFIED form: P_dec (125 - 0.6 P_dec) / 125 for P_dec ≤ 83.3 mm, else 125/3 + 0.1 P_dec). Do not implement it until verified.

Green/blue split, green = min(AETI, Peff):

- It ignores soil water stored before the season. Mediterranean winter crops and trees transpire stored winter rain, and that gets booked as blue water.
- It assigns blue water to rainfed crops whenever AETI > Peff.

For 1.0.6: add `water_source = c("irrigated", "rainfed")` per crop class. For rainfed classes blue = 0 (green = AETI) and the difference is reported as "unexplained" or "stored soil water". Later: a pixel soil-water-balance split (as in WA+; Karimi et al. 2013) using WaPOR RSM.

Resolution caveat: WaPOR precipitation is much coarser than L3 AETI. The native resolution of the v3 PCP and RET layers is UNVERIFIED here (CHIRPS about 5 km; AgERA5 about 10 km). So field-scale variation in green/blue at L3 comes entirely from AETI. State this in the help page.

### 3.6 Water productivity variants (1.0.6 for docs and pure functions)

| Indicator | Definition | Unit | Source |
|---|---|---|---|
| CWP (yield WP) | Y / AETI | kg/m3 | Chukalla et al. (2022) Table A1; exists |
| BWP (seasonal) | AGB / AETI | kg/m3 | exists |
| GBWP (WaPOR product) | TBP / AETI, annual | kg/m3 | WaPOR v3 L2/L3 GBWP-A (the product exists in the package's code list) |
| NBWP (WaPOR product) | TBP / T, annual | kg/m3 | WaPOR L2 NBWP-A (definition UNVERIFIED for v3; check the v3 catalogue) |
| Normalized biomass WP (WP*) | B / Σ (T_i / ET0_i) | g/m2 | Steduto et al. (2007); FAO-66. Chukalla quotes 30 to 35 g/m2 for C4 crops. C3 crops are about 15 to 20 g/m2 (Steduto et al. 2007; UNVERIFIED exact range). A climate-robust diagnostic across regions and years. |
| Blue WP | Y / blue ET | kg/m3 | Depends on the Peff method; always report the method |

Note that WaPOR GBWP and NBWP are annual and cover all land; they are not seasonal crop WP. Document the difference so users do not compare them with seasonal CWP.

### 3.7 Supply-based indicators when delivery data exist (later)

When users have delivered irrigation volumes per zone (a table joined through WP2):

- Relative water supply RWS = (irrigation + rainfall) / ETc.
- Relative irrigation supply RIS = irrigation / (ETc - Peff).
- Depleted fraction DF = AETI / (P + irrigation) (Molden 1997; Bos et al. 2005; Molden & Gates 1990).

These need no new raster input. Add `wapor_calc_supply_indicators(zonal_table, supply, id)`.

### 3.8 Yield response to water (later)

FAO-33 relation: 1 - Ya/Ym = Ky (1 - ETa/ETm) (Doorenbos & Kassam 1979; Steduto et al. 2012 FAO-66). This gives relative yield loss from adequacy. Ky per crop from FAO-33/66; transcribe with citation, never from memory.

### 3.9 Multi-season and double cropping (later, but reserve the interface now)

- A `season` id in all outputs (WP2 2.10).
- Seasons defined per pixel (start/end rasters) or per zone (table).
- Aggregate an annual value over seasons as the sum of seasonal depths and volumes, but never average ratios across seasons. Compute annual adequacy as ΣAETI / ΣETc.

### 3.10 Mixed pixels at coarse levels (1.0.6 through WP5)

- Use the fraction mask from `wapor_harmonize_mask()` as cell weights in WP2 (w = coverage_area x crop_fraction). Crop means at L1 are then not dominated by pixels that are 30% crop.
- Document that a mixed pixel's AETI is a blend of crop and non-crop ET. Weighting only reduces the influence of mixed pixels; it cannot unmix them.

---

## 4. Defaults table

"Config" = how the user changes it. All class schemes are changed through `breaks`/`labels` arguments or `options(Rwapor.class_breaks)`.

| Parameter / scheme | Recommended default | Source | Where the literature disagrees / notes | Config |
|---|---|---|---|---|
| Adequacy (AETI/ETc) | breaks 0.68, 0.80, 1.00; poor ≤ 0.68 < acceptable ≤ 0.80 < good ≤ 1.00 < "above ETc" | Karimi et al. (2019), as quoted in Chukalla et al. (2022) text (VERIFIED quote) | Molden & Gates (1990): 0.80 / 0.90 for delivered water (Secondary). The origin of 0.68 beyond Karimi (2019) is UNVERIFIED. | scheme `adequacy` |
| Equity (CV between units) | 0.10, 0.25; good / fair / poor | Bastiaanssen et al. (1996); Karimi et al. (2019); VERIFIED quote in Chukalla (2022) | Molden & Gates (1990) same limits for delivery CV (Secondary) | scheme `equity` |
| Uniformity (1 - CV within unit) | one threshold per irrigation method: surface/furrow 0.65, sprinkler 0.75, centre pivot 0.75, drip 0.85; classes "below standard" / "meets standard" | Pitts et al. (1996), quoted in Chukalla et al. (2022) (VERIFIED quote) | Standards are for applied-water distribution uniformity (likely DU_lq; UNVERIFIED), not ET; 1 - CV is optimistic relative to DU_lq | `irrigation_method`, schemes `uniformity_*` |
| Uniformity when the method is unknown | no class, values only | none | Do not guess a method | `irrigation_method = "unknown"` |
| Dependability / reliability (temporal CV) | 0.10, 0.20 (alternative scheme, not a default) | Molden & Gates (1990) (Secondary, UNVERIFIED bands) | Written for deliveries, not ET | scheme `dependability_molden_gates` |
| Spots / targets | P95 for both LP and WP; bright if both ≥ P95; dark if both ≤ P5 (package convention) | Chukalla et al. (2020) protocol, WAPORWP Module 5 (VERIFIED for P95 and bright spots) | Yield gap studies use P90 to P95 (UNVERIFIED specifics); dark spot rule not published | `breaks`, `method = "quantile"`, `reference` |
| RWD reference ETx | ETc; alternative P99 or P95 of AETI | WAPORWP Module 3 uses ETp or P99 (VERIFIED); package adequacy_p95 uses P95 | Percentile choice is arbitrary; make explicit | `etx = "etc"` / `p` |
| Quantile estimator | type 7 (unweighted); weighted estimator that reduces to type 7 | R default; existing `wapor_calc_p95_aeti` | none | internal, documented |
| Minimum values per quantile group | 30 | Existing package default (`wapor_calc_p95_aeti`, min_pixels 30) | Heuristic | `min_n` |
| SD type | population, area-weighted | WAPORWP (`np.nanstd`); Chukalla does not state | Sample SD also common; differs < 0.5% for n ≥ 100 | `sd_type` |
| Equity weighting across units | none (unweighted) | Chukalla (2022) | Area-weighted CV also used | `weights` |
| Min unit size for uniformity | `min_area_ha = 1`; warn if n_eff < 9 | Heuristic (no literature found) | Training used 100 px = 4 ha at 20 m | `min_area_ha` |
| Min cell fraction (edge pixels) | 0 in WP2; 0.5 in uniformity and spots | Heuristic | none | `min_cell_fraction` |
| Min coverage (valid / masked area) | 0.5 | Heuristic (plan) | Must apply to masked area, not zone area | `min_coverage` |
| Mask fraction threshold (harmonize) | 0.5 | Heuristic (majority rule) | Better: use fractions as weights | `min_fraction` |
| Peff method | `usda_cropwat` (current), monthly | Smith (1992) CROPWAT | FAO/AGLW gives much lower Peff; USDA full method needs soil and ETc | `peff_method` |
| Fixed Peff fraction | no default (required when `method = "fixed"`) | none | Tools use 0.7 or 0.8 (UNVERIFIED) | `peff_fraction` |
| Green/blue time step | monthly split, then sum (current) | Consistent with Peff calibration | A dekadal split gives more blue water | `split_step` (later) |
| Rainfed classes blue water | 0 | Physical reasoning | min(AETI, Peff) misattributes stored soil water | `water_source` per class |
| Citrus Kc (6 rows) | as in Sect. 2 WP4 table | FAO-56 Table 12 (VERIFIED) | +0.1 to 0.2 in humid/subhumid climates (footnotes 21, 22); Rallo et al. (2021) updates | crop table / `wapor_custom_crop()` |
| Citrus stages | 60/90/120/95, start January | FAO-56 Table 11 (VERIFIED) | Plan's "March" is wrong | crop table |
| Kc_mid climate adjustment | off by default; FAO-56 Eq. 62/65 when u2 and RHmin are supplied | Allen et al. (1998) Eq. 62, 65 (validity VERIFIED) | Not for crops with strong stomatal control without judgement | `wapor_adjust_kc_climate()` |
| fc (LUE correction) | 1 (C3) | WaPOR methodology; Chukalla (2022) used 1.6 for sugarcane | v3 generic LUE UNVERIFIED | crop params |
| NPP to TBP factor | 22.222 | Chukalla (2022) Eq. 1 (VERIFIED); code matches | none | constant |
| Volume conversion | 1 mm x 1 ha = 10 m3 | definition | none | none |

---

## 5. Test ideas with independently computable expected values

Every expected value below can be computed by hand or with base R, without calling the function under test.

**Classification and indicators**

1. Adequacy tie rule: `c(0.68, 0.80, 1.00, 1.0001)` gives poor, acceptable, good, above ETc.
2. Uniformity per method: 1 - CV = 0.70 gives "meets standard" for `surface`, "below standard" for `sprinkler`.
3. Equity: unit means c(10, 12, 14). Population CV = 0.13608, sample CV = 0.16667; both "fair".
4. RWD: AETI 400 mm, ETc 500 mm gives 0.20. With `etx = "p99"` on values 1..100, ETx = `quantile(1:100, 0.99)` = 99.01.
5. Productivity gap: yields 1..100, target P95 = 95.05, gap at yield 90 = 5.05, gap at 100 = 0. Production gap over 1 ha cells = Σ max(0, 95.05 - y) = Σ_{y=1..95}(95.05 - y) = 95 x 95.05 - 4560 = 4469.75.
6. Bright spots with LP = WP = 1..100 give 5 bright (96 to 100). With WP reversed, 0 bright.
7. A value exactly equal to P95 is bright (`>=` rule). Build the data so a value sits on the threshold, e.g. `c(1:19, 20)` with P95 set by the user as a fixed break.

**Uniformity and inequality statistics**

8. Unweighted, values 1..100: 1 - CV_pop = 0.42840, CU = 0.504950, DU_lq = 13 / 50.5 = 0.257426, Gini = 0.33, Theil(1, 2, 3, 4) = 0.106440.
9. Normal-distribution check (Monte Carlo, `set.seed`): n = 1e5, mean 100, sd 20. Expect CU close to 1 - 0.798 x 0.2 = 0.840 and DU_lq close to 1 - 1.27 x 0.2 = 0.746, both within 0.005 (relation from Warrick 1983; UNVERIFIED coefficients, so use this as a plausibility check, not a golden value).
10. Weighted quantile with equal weights equals `quantile(x, p, type = 7)` for random x and p in {0.05, 0.5, 0.95}.

**Zonal statistics (WP2)**

11. Coverage vs mask: a zone of 100 cells, mask keeps 20, 5 of those NA. Expect `mask_fraction` = 0.20, `coverage` = 15/20 = 0.75. Statistics are *not* NA at `min_coverage = 0.5`.
12. Volume of a depth layer: 100 mm over a 2 ha zone = 2000 m3.
13. Volume of a rate layer: a `mm/day` layer gives no volume without `days`. With `days = 8` (February 2023, 3rd dekad: 21 to 28 Feb), 2.0 mm/day over 1 ha = 16 mm = 160 m3. February 2024 dekad 3 = 9 days; January dekad 3 = 11 days.
14. Nested volumes: when children exactly partition the parent, parent volume = sum of child volumes (within 1e-9 relative).
15. Fraction weights: two cells, AETI 500 (crop fraction 1.0) and 300 (crop fraction 0.25), equal area. Weighted mean = (500 x 1 + 300 x 0.25) / 1.25 = 460.

**Effective rainfall and green/blue**

16. `usda_cropwat`: P = 100 gives 84.0; P = 250 gives 150.0; P = 300 gives 155.0 (continuous at 250).
17. `fao_aglw`: P = 10 gives 0; P = 50 gives 20; P = 70 gives 32 (both branches); P = 100 gives 56.
18. Green/blue for a rainfed class: AETI 300, Peff 200 gives green 300, blue 0, plus a 100 mm "unexplained / stored soil water" diagnostic.

**Kc and crop data**

19. Eq. 62 citrus: Kc_mid(Tab) 0.65, u2 = 3, RHmin = 30, h = 4 gives 0.65 + (0.04 + 0.06)(4/3)^0.3 = 0.75901.
20. Eq. 62 wheat: 1.15, u2 = 4, RHmin = 25, h = 1 gives 1.26508.
21. Eq. 65 not applied when Kc_end(Tab) = 0.30 (≤ 0.45).
22. Deciduous dormant Kc: for a 365-day year with Table 11 stages 20/70/120/60 (270 d) and `kc_dormant = 0.20`, the 95 remaining days have Kc 0.20. The annual mean Kc is computable by hand from the piecewise-linear curve.
23. Citrus Table 11 start = January (1) in the crop table.

**Water productivity**

24. Normalized WP*: B = 10 000 kg/ha (1000 g/m2), Σ(T/ET0) = 50 gives WP* = 20 g/m2.
25. CWP: 5000 kg/ha over 400 mm gives 1.25 kg/m3 (already an example; keep as a guard).

---

## 6. Open scientific questions for the package owner

1. **Target release.** The plan says Rwapor 1.1.0 (new exports mean a minor version); the review brief says 1.0.6, and `NEWS.md` has a 1.0.6 development section. Which is it? My 1.0.6 / later split assumes 1.0.6 is a feature release.
2. **Existing crop table errors** (Winter Wheat Kc_ini, Sorghum Kc_ini, Sugarcane stages). Correct them now, with new golden values, or only fix the notes?
3. **Uniformity measure.** Keep 1 - CV (Chukalla) as the headline and add DU_lq and CU as diagnostics, or make DU_lq the value compared with the method standards?
4. **Rainfed handling.** Accept `water_source` per crop class with blue = 0 for rainfed? Or keep the current min(AETI, Peff) for all classes and only document it?
5. **Peff default.** Keep `usda_cropwat` as the default for backward compatibility (known answers unchanged), with FAO/AGLW and fixed as options? I recommend yes.
6. **Adequacy reference.** Offer ETc, P95 and P99 as `adequacy_ref`? The current package has both `adequacy_etc` and `adequacy_p95`. Should RWD reuse them or be separate?
7. **Spots definition.** Accept "dark = both ≤ P5" as a documented package convention? Or offer only bright spots plus gaps, as the protocol does?
8. **Fraction masks.** Should WP2 accept a fractional mask as weights (recommended), or only binary masks?
9. **Measured yields (D1).** Add a `yield_input` so CWP works for perennials and survey data? I recommend yes; it also removes the dependence on HI/MC/AOT guesses for all crops.
10. **Climate adjustment of Kc.** Offer Eq. 62/65 using AgERA5 wind and RH automatically, or only as a manual helper?
11. **Dependability bands** from Molden & Gates (1990): can the owner or a librarian confirm the exact bands from the original paper (Table 1) before they ship as an alternative scheme?
12. **WaPOR v3 specifics to confirm from the v3 methodology document:** the native resolution of PCP and RET, the generic LUE used for NPP, and the NBWP definition.

---

## 7. References

Evidence label per entry: [V] opened during this review; [S] secondary; [U] citation from memory, check the details (DOI, pages).

- Allen, R.G., Pereira, L.S., Raes, D., Smith, M. (1998). *Crop evapotranspiration: Guidelines for computing crop water requirements.* FAO Irrigation and Drainage Paper 56. FAO, Rome. Chapter 6, Tables 11 and 12, Eqs. 62, 65, 98. https://www.fao.org/4/x0490e/x0490e0b.htm [V]
- Allen, R.G., Pereira, L.S. (2009). Estimating crop coefficients from fraction of ground cover and height. *Irrigation Science* 28, 17 to 34. https://doi.org/10.1007/s00271-009-0182-z [U]
- Ascough, G., Kiker, G. (2002). The effect of irrigation uniformity on irrigation water requirements. *Water SA* 28, 235 to 242. [S, as cited in Chukalla 2022]
- Bastiaanssen, W.G.M., Bos, M.G. (1999). Irrigation performance indicators based on remotely sensed data: a review of literature. *Irrigation and Drainage Systems* 13, 291 to 311. https://doi.org/10.1023/A:1006355315251 [S citation; DOI U]
- Bastiaanssen, W.G.M., van der Wal, T., Visser, T. (1996). Diagnosis of regional evaporation by remote sensing to support irrigation performance assessment. *Irrigation and Drainage Systems* 10, 1 to 23. [S]
- Bos, M.G., Burton, M.A., Molden, D.J. (2005). *Irrigation and Drainage Performance Assessment: Practical Guidelines.* CABI, Wallingford. https://doi.org/10.1079/9780851999678.0000 [S]
- Burt, C.M., Clemmens, A.J., Strelkoff, T.S., et al. (1997). Irrigation performance measures: efficiency and uniformity. *J. Irrig. Drain. Eng.* 123(6), 423 to 442. [S]
- Christiansen, J.E. (1942). *Irrigation by Sprinkling.* University of California Agricultural Experiment Station Bulletin 670. [U]
- Chukalla, A.D., Mul, M.L., van der Zaag, P., van Halsema, G., Mubaya, E., Muchanga, E., den Besten, N., Karimi, P. (2022). A framework for irrigation performance assessment using WaPOR data: the case of a sugarcane estate in Mozambique. *Hydrology and Earth System Sciences* 26, 2759 to 2778. https://doi.org/10.5194/hess-26-2759-2022 [V]
- Chukalla, A.D., Mul, M., Tran, B., Karimi, P. (2020). *Standardized protocol for land and water productivity analyses using WaPOR (v1.1).* Zenodo. https://doi.org/10.5281/zenodo.4641360. Notebooks: https://github.com/wateraccounting/WAPORWP (Modules 3 and 5) [V]
- Clemmens, A.J., Molden, D.J. (2007). Water uses and productivity of irrigation systems. *Irrigation Science* 25, 247 to 261. [S]
- Dastane, N.G. (1974). *Effective Rainfall in Irrigated Agriculture.* FAO Irrigation and Drainage Paper 25. https://www.fao.org/4/x5560e/x5560e00.htm [U content]
- Doorenbos, J., Kassam, A.H. (1979). *Yield Response to Water.* FAO Irrigation and Drainage Paper 33. FAO, Rome. [U]
- Karimi, P., Bastiaanssen, W.G.M., Molden, D. (2013). Water Accounting Plus (WA+): a water accounting procedure for complex river basins based on satellite measurements. *Hydrology and Earth System Sciences* 17, 2459 to 2472. https://doi.org/10.5194/hess-17-2459-2013 [U]
- Karimi, P., Bongani, B., Blatchford, M., de Fraiture, C. (2019). Global satellite-based ET products for the local level irrigation management: an application of irrigation performance assessment in the sugarbelt of Swaziland. *Remote Sensing* 11, 705. https://doi.org/10.3390/rs11060705 [S citation; DOI U]
- Lobell, D.B., Cassman, K.G., Field, C.B. (2009). Crop yield gaps: their importance, magnitudes, and causes. *Annual Review of Environment and Resources* 34, 179 to 204. [U]
- Merriam, J.L., Keller, J. (1978). *Farm Irrigation System Evaluation: A Guide for Management.* Utah State University, Logan. [U]
- Molden, D. (1997). *Accounting for Water Use and Productivity.* SWIM Paper 1. International Irrigation Management Institute, Colombo. [U]
- Molden, D.J., Gates, T.K. (1990). Performance measures for evaluation of irrigation-water-delivery systems. *J. Irrig. Drain. Eng.* 116(6), 804 to 823. https://doi.org/10.1061/(ASCE)0733-9437(1990)116:6(804) [S citation; bands S/U]
- Muratoglu, A., Bilgen, G.K., Angin, I., Kodal, S. (2023). Performance analyses of effective rainfall estimation methods for accurate quantification of agricultural water footprint. *Water Research* 238, 120011. [S, authors U]
- Pereira, L.S., Paredes, P., Hunsaker, D.J., López-Urrea, R., Mohammadi Shad, Z. (2021). Standard single and basal crop coefficients for field crops. Updates and advances to the FAO56 crop water requirements method. *Agricultural Water Management* 243, 106466. [U]
- Pitts, D., Peterson, K., Gilbert, G., Fastenau, R. (1996). Field assessment of irrigation system performance. *Applied Engineering in Agriculture* 12, 307 to 313. [S]
- Rallo, G., Paço, T.A., Paredes, P., Puig-Sirera, À., Massai, R., Provenzano, G., Pereira, L.S. (2021). Updated single and basal crop coefficients for tree and vine fruit crops. *Agricultural Water Management* 250, 106645. https://doi.org/10.1016/j.agwat.2020.106645 [S; DOI U]
- Smith, M. (1992). *CROPWAT: A Computer Program for Irrigation Planning and Management.* FAO Irrigation and Drainage Paper 46. FAO, Rome. [S]
- Steduto, P., Hsiao, T.C., Fereres, E. (2007). On the conservative behavior of biomass water productivity. *Irrigation Science* 25, 189 to 207. [U]
- Steduto, P., Hsiao, T.C., Fereres, E., Raes, D. (2012). *Crop Yield Response to Water.* FAO Irrigation and Drainage Paper 66. FAO, Rome. [U]
- USDA-SCS (1993). Chapter 2: Irrigation water requirements. In: *National Engineering Handbook*, Part 623. USDA Soil Conservation Service. [S]
- van Ittersum, M.K., Cassman, K.G., Grassini, P., Wolf, J., Tittonell, P., Hochman, Z. (2013). Yield gap analysis with local to global relevance: a review. *Field Crops Research* 143, 4 to 17. [U]
- Warrick, A.W. (1983). Interrelationships of irrigation uniformity terms. *J. Irrig. Drain. Eng.* 109(3), 317 to 332. [U]
- FAO (2024, UNVERIFIED title and year). *WaPOR v3 database methodology.* FAO, Rome. Check it for the resolution of PCP and RET, the generic LUE and the GBWP/NBWP definitions. [U]
