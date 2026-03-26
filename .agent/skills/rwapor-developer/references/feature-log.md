# Rwapor — Feature Request Log
_Last updated: 2026-03-26_

> Status: 🟡 Pending | 🔵 In Progress | ✅ Done | ❌ Rejected

---

## Feature Index

| # | Feature | File(s) | Status |
|---|---|---|---|
| F01 | `wapor_map()` — raster download with batching + parallel | R/wapor_map.R | ✅ Done |
| F02 | `wapor_ts()` — time series extraction with zonal stats | R/wapor_ts.R | ✅ Done |
| F03 | `plan_wapor_time_slices()` — mixed-resolution download plan | R/plan_wapor_time_slices.R | ✅ Done |
| F04 | Seasonal aggregation mode (`seasonal=TRUE`) in map + ts | R/seasonal_download.R | ✅ Done |
| F05 | Crop mask integration in analysis pipeline | R/analysis.R | ✅ Done |
| F06 | Pixel-wise season start/end raster support | R/analysis.R | ✅ Done |
| F07 | FAO-56 Kc curve builder (daily → dekadal) | R/analysis.R | ✅ Done |
| F08 | Per-class Kc assignment from crop mask | R/analysis.R | ✅ Done |
| F09 | USDA SCS Peff (monthly → seasonal) | R/analysis_indicators.R | ✅ Done |
| F10 | Adequacy: ETc-based and P95-based | R/analysis_indicators.R | ✅ Done |
| F11 | CWP and BWP calculations | R/analysis_indicators.R | ✅ Done |
| F12 | Yield estimation from NPP (harvest index method) | R/analysis_indicators.R | ✅ Done |
| F13 | Unit conversion (df + raster) | R/unit_convertor.R | ✅ Done |
| F14 | Shiny dashboard with Download/Visualisation/Analysis tabs | inst/shiny/ | ✅ Done |
| F15 | Favorites system for local data folders | R/rwapor_favorites.R | ✅ Done |
| F16 | Incremental (memory-optimized) seasonal aggregation | R/analysis_indicators.R | ✅ Done |
| F17 | AgERA5 variable support (ET0, TMIN, TMAX, SRF, WS, PF) | R/metadata.R | ✅ Done |
| F18 | L3 regional data support with extent caching | R/utils.R | ✅ Done |
| F19 | GDAL configuration helper + Windows PROJ fix | R/gdal_config.R | ✅ Done |
| F20 | Memoised API calls for performance | R/api_client.R, R/metadata.R | ✅ Done |

---

## Pending / In Progress

_Add new feature requests here as they arise._

---

## Rejected Features

_Features explicitly decided against, with rationale._

---

## Template for New Entry

```
### F[N] — [Feature Title]
- **File(s)**: R/filename.R or inst/shiny/mod_*.R
- **Function(s)**: function_name()
- **Description**: What it should do
- **Requested**: [date or session reference]
- **Status**: 🟡 Pending
- **Notes**: Any constraints, related bugs, or dependencies
```
