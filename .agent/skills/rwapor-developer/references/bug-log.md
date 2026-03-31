# Rwapor — Bug Log
_Last updated: 2026-03-31_

> Status: ❌ Open | 🔄 In Progress | ✅ Resolved | ⚠️ Known Limitation

---

## Bug Index

| # | Description | File | Function | Status |
|---|---|---|---|---|

_No open bugs currently. Add entries as encountered and confirmed._

---

## Resolved Bugs

### B01 — Extent mismatch in Raster Harmonization
- **File**: `R/analysis.R`
- **Function**: `rwapor_harmonize_to_template()`
- **Reported**: 2026-03-23 (Session b4246)
- **Symptom**: "extents do not match" error during analysis.
- **Root cause**: Harmonization was attempted on rasters with slightly different origins/resolutions without a robust comparison check.
- **Fix applied**: Implemented `compare_geom()` helper to handle epsilon-tolerance geometry checks before resampling.
- **Status**: ✅ Resolved

### B02 — Date alignment error for non-standard dekad starts
- **File**: `R/analysis.R`
- **Function**: `build_dekad_table()`
- **Reported**: 2026-03-25 (Session 5bfef)
- **Symptom**: Analysis period starting on non-standard date (e.g. 5th of month) caused data misalignment.
- **Root cause**: Logic assumed all analysis periods start on the 1st, 11th, or 21st.
- **Fix applied**: Modified table generation to correctly clamp and align periods to standard WaPOR dekad keys.
- **Status**: ✅ Resolved

### B03 — Missing export for local variable scan
- **File**: `R/analysis.R`
- **Function**: `rwapor_scan_local_variables()`
- **Reported**: 2026-03-19 (Session 02374)
- **Symptom**: `could not find function "rwapor_scan_local_variables"` in Shiny app.
- **Root cause**: Function was defined but missing `@export` tag.
- **Fix applied**: Added `@export` and ran `devtools::document()`.
- **Status**: ✅ Resolved

### B04 — Double-scaling in indicator calculations
- **File**: `R/analysis_indicators.R`
- **Function**: `rwapor_apply_masked_sum()`
- **Reported**: 2026-03-25 (Session ba84b)
- **Symptom**: Indicator values (AETI, RET) were 10x too small/large.
- **Root cause**: Scale factors were applied both during download and during analysis.
- **Fix applied**: Standardized on unit-conversion at download; analysis now expects raw scaled values or uses explicit `layer_multipliers`.
- **Status**: ✅ Resolved

---

## Known Limitations

| # | Description | File | Notes |
|---|---|---|---|
| KL01 | Fractional weights on monthly/annual slices assume uniform daily distribution | R/plan_wapor_time_slices.R | Documented in roxygen; accepted approximation |
| KL02 | `wapor_fix_proj()` only addresses Windows PROJ_LIB conflicts | R/gdal_config.R | Not needed on Linux/Mac |

---

## Design Clarifications (Not Bugs)

_Issues raised by users that turned out to be correct design decisions, documented here to prevent confusion:_

### DC01 — NPP values appearing low (2026-03-31)
- **Symptom**: User expected seasonal NPP values ~400-600 gC/m² but saw ~4.5 gC/m²/day
- **Clarification**: Dekadal NPP files store **daily rates** (gC/m²/day), not dekadal totals. The package correctly:
  1. Defaults to converting dekadal variables to dekadal totals (`unit_conversion = "dekad"`)
  2. In seasonal mode, automatically multiplies daily rates by overlap days
  3. Terra automatically applies scale factor (0.001) during read - no manual scaling needed
- **Resolution**: No bug. Added comprehensive documentation in aggregation-logic skill and project memory.

### DC02 — Seasonal temperature aggregation differs from precipitation (2026-03-31)
- **Symptom**: User noticed temperature uses mean while precipitation uses sum
- **Clarification**: This is **correct metadata-driven behavior**:
  - Temperature (units: "K") has no temporal component → intensive property → weighted_mean
  - Precipitation (units: "mm/day") has temporal component → flux variable → weighted_sum
  - Logic in `get_seasonal_aggregation_rule()` checks `extract_temporal_unit()`
- **Resolution**: No bug. Working as designed. Documented in aggregation-logic skill.

### DC03 — Dekadal variables auto-convert to dekadal totals (2026-03-31)
- **Symptom**: User expected to see daily rates (mm/day) but got dekadal totals (mm/dekad)
- **Clarification**: This is the **correct default behavior**. WaPOR dekadal files store daily rates, but users typically want dekadal totals. The package:
  - Detects dekadal variables (suffix "-D" + units with "/day")
  - Automatically sets `unit_conversion = "dekad"` unless user overrides
  - Multiplies each dekad by its actual day count (10, 10, or 11 days)
- **Resolution**: No bug. User can override with explicit `unit_conversion = "day"` if needed.

---

## Diagnosis Checklist

Before diagnosing any bug, check:

1. **Scale factor**: WaPOR layers require `scale * 0.1` or other factor — check `get_variable_metadata()` `$scale` field
   - **CRITICAL**: Terra applies scale automatically during `rast()` read - never apply manually!
2. **Unit mismatch**: Is the user expecting mm/season but getting mm/day or mm/dekad? → `unit_convertor.R`
   - Check if dekadal default conversion was applied (default for "-D" variables)
3. **Aggregation rule**: Temperature vs flux variables have different aggregation rules
   - Check `get_seasonal_aggregation_rule(variable)` - should return "weighted_mean" for temperature, "weighted_sum" for fluxes
4. **terra vs raster**: Never mix `raster` and `terra` objects — use `terra` throughout
5. **Geometry mismatch**: Rasters must share CRS/extent/resolution → `rwapor_compare_geom()` / `rwapor_harmonize_to_template()`
6. **Dekad indexing**: Season weights off by one? Check `build_dekad_table()` output and `rwapor_build_season_weights_dekad()` logic
7. **Shiny reactivity**: Missing `req()` or `isolate()`? Check all `observeEvent` blocks in `mod_analysis.R`
8. **NULL reactive**: `an_crop_mask_rast`, `an_start_rast`, `an_end_rast` are `reactiveVal(NULL)` — check `req()` guards
9. **API pagination**: `collect_responses()` may miss pages if API response structure changed
10. **L3 extent cache**: Stale cache in `get_l3_raster_extent()` — clear with `save_l3_extent_cache(list())`
11. **Parallel mode**: Errors in `future.apply` workers may be swallowed — test with `parallel=FALSE` first
12. **Temperature units**: AGERA5 temperature is now auto-converted K→°C (v0.9.2+)

---

## Template for New Entry

```
### B[N] — [Short description]
- **File**: R/filename.R or inst/shiny/mod_*.R
- **Function**: function_name()
- **Reported**: [date or session reference]
- **Symptom**: What the user observed (exact error or behaviour)
- **Root cause**: What caused it (fill in after diagnosis)
- **Fix applied**: What was changed (fill in after fix)
- **Status**: ❌ Open
- **Confirmed fixed**: [date or session, once resolved]
```
