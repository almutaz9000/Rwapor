# Rwapor — Structured Prompt History
_Last updated: 2026-03-26_

> A structured log of development sessions — what was requested, what was
> built, and what was confirmed or rejected.
> Use at session start to reconstruct context without re-reading all history.

---

## Quick Reference Index

| Area | Last activity | Key outcome |
|---|---|---|
| Dashboard UI | Prior sessions | bslib page_navbar, 3-tab layout, shinyjs, shinyFiles confirmed |
| Analysis module | Prior sessions | Full seasonal pipeline: crop mask, Kc, ETc, Peff, adequacy, CWP/BWP |
| Seasonal download | Prior sessions | Mixed-resolution plan (plan_wapor_time_slices) + incremental aggregation |
| FAO-56 data | Prior sessions | fao_crop_coefficients.csv + fao_growth_stages.csv in package root |
| Shiny dashboard | Prior sessions | run_wapor() entry point confirmed; Exit button with stopApp() |
| Unit conversion | Prior sessions | df_unit_convertor + raster_unit_convertor confirmed |

---

## Session Log

### Session S01 — Initial Package Structure
- **Date**: Prior sessions
- **Requests**: Core download functions: `wapor_map()`, `wapor_ts()`
- **Files created**: R/wapor_map.R, R/wapor_ts.R, R/api_client.R, R/metadata.R, R/utils.R
- **Outcome**: ✅ Confirmed — v0.1.0 initial release
- **Notes**: `terra` + `exactextractr` + `httr2` chosen as core dependencies

---

### Session S02 — Seasonal Download Pipeline
- **Date**: Prior sessions
- **Request**: Smart seasonal download plan that minimises API calls by using
  coarser temporal resolution (A > M > D > E) for fully covered periods
- **Files created/modified**: R/plan_wapor_time_slices.R, R/seasonal_download.R, R/interval_helpers.R
- **Key function**: `plan_wapor_time_slices()` — returns data.frame of optimal slices with weights
- **Outcome**: ✅ Confirmed
- **Notes**: Fractional weights on monthly/annual slices assume uniform daily
  distribution — documented as known approximation

---

### Session S03 — Analysis Pipeline
- **Date**: Prior sessions
- **Request**: Full seasonal water productivity analysis using crop mask + Kc curves
- **Files created**: R/analysis.R, R/analysis_indicators.R, R/crop_defaults.R
- **Functions added**: Crop mask loading, season mask, Kc builder, ETc, AETI aggregation,
  Peff (USDA SCS), adequacy (ETc-based + P95-based), CWP, BWP, yield-from-NPP
- **Data files**: fao_crop_coefficients.csv, fao_growth_stages.csv
- **Outcome**: ✅ Confirmed

---

### Session S04 — Shiny Dashboard
- **Date**: Prior sessions
- **Request**: Interactive Shiny dashboard for data download, visualisation, and analysis
- **Files created**: inst/shiny/app.R, mod_download.R, mod_visualisation.R,
  mod_analysis.R, mod_aoi.R, utils_shiny.R
- **Framework**: bslib page_navbar, Bootstrap 5 "flatly", leaflet, shinyjs, shinyFiles
- **Key decisions**: 3-tab layout (Download/Vis/Analysis), shared state via dl_out$folder + dl_out$region,
  validate→run→reset→export button flow, incremental memory toggle
- **Outcome**: ✅ Confirmed

---

### Session S05 — Unit Conversion + GDAL Config
- **Date**: Prior sessions
- **Request**: Unit conversion functions + GDAL/PROJ setup helpers
- **Files created**: R/unit_convertor.R, R/gdal_config.R
- **Outcome**: ✅ Confirmed
- **Notes**: `wapor_fix_proj()` specifically targets Windows PROJ_LIB conflict

---

### Session S06 — Favorites System
- **Date**: Prior sessions
- **Request**: Persist local data folder paths across sessions
- **Files created**: R/rwapor_favorites.R
- **Outcome**: ✅ Confirmed

---

## Template for New Session Entry

```
### Session S[N] — [Title]
- **Date**: [YYYY-MM-DD or session reference]
- **Request**: [What was asked]
- **Files touched**: [list of R/ or inst/shiny/ files]
- **Functions added/changed**: [function_name() — what changed]
- **Outcome**: [Confirmed ✅ | Rejected ❌ | Pending 🟡]
- **Notes**: [Important context, constraints, or gotchas]
```
