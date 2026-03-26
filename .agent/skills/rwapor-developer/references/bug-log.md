# Rwapor — Bug Log
_Last updated: 2026-03-26_

> Status: ❌ Open | 🔄 In Progress | ✅ Resolved | ⚠️ Known Limitation

---

## Bug Index

| # | Description | File | Function | Status |
|---|---|---|---|---|

_No bugs logged yet. Add entries as encountered and confirmed._

---

## Resolved Bugs

_None yet._

---

## Known Limitations

| # | Description | File | Notes |
|---|---|---|---|
| KL01 | Fractional weights on monthly/annual slices assume uniform daily distribution | R/plan_wapor_time_slices.R | Documented in roxygen; accepted approximation |
| KL02 | `wapor_fix_proj()` only addresses Windows PROJ_LIB conflicts | R/gdal_config.R | Not needed on Linux/Mac |

---

## Diagnosis Checklist

Before diagnosing any bug, check:

1. **Scale factor**: WaPOR layers require `scale * 0.1` or other factor — check `get_variable_metadata()` `$scale` field
2. **Unit mismatch**: Is the user expecting mm/season but getting mm/day or mm/dekad? → `unit_convertor.R`
3. **terra vs raster**: Never mix `raster` and `terra` objects — use `terra` throughout
4. **Geometry mismatch**: Rasters must share CRS/extent/resolution → `rwapor_compare_geom()` / `rwapor_harmonize_to_template()`
5. **Dekad indexing**: Season weights off by one? Check `build_dekad_table()` output and `rwapor_build_season_weights_dekad()` logic
6. **Shiny reactivity**: Missing `req()` or `isolate()`? Check all `observeEvent` blocks in `mod_analysis.R`
7. **NULL reactive**: `an_crop_mask_rast`, `an_start_rast`, `an_end_rast` are `reactiveVal(NULL)` — check `req()` guards
8. **API pagination**: `collect_responses()` may miss pages if API response structure changed
9. **L3 extent cache**: Stale cache in `get_l3_raster_extent()` — clear with `save_l3_extent_cache(list())`
10. **Parallel mode**: Errors in `future.apply` workers may be swallowed — test with `parallel=FALSE` first

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
