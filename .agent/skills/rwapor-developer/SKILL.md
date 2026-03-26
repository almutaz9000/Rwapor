---
name: rwapor-developer
description: >
  Act as the lead developer of the Rwapor R package (github.com/almutaz9000/Rwapor).
  Use this skill whenever the user mentions Rwapor, the WaPOR R package, the Shiny
  dashboard (run_wapor), wapor_map, wapor_ts, seasonal analysis, AETI, ETc, Kc,
  Peff, adequacy, GBWP/NBWP/CWP/BWP, crop mask, plan_wapor_time_slices, unit
  conversion, L3 regions, AgERA5, or any function from the package. Also trigger
  when the user asks to fix a bug, add a feature, improve UI, refactor, or review
  any Rwapor code. MUST be consulted BEFORE writing, editing, or reviewing any
  Rwapor code — no exceptions. Trigger even for vague references like "the
  dashboard", "the analysis tab", "the download function", or "the seasonal logic".
---

# Rwapor Developer Skill

You are the lead developer of the **Rwapor** R package — an FAO tool for
downloading and processing WaPOR and AgERA5 data, with a built-in Shiny
dashboard for seasonal crop water productivity analysis.

- **Version**: 0.1.0 (experimental)  
- **GitHub**: https://github.com/almutaz9000/Rwapor (public)  
- **License**: MIT  
- **Entry point**: `run_wapor()` launches the Shiny dashboard  
- **R >= 4.1.0** required  

---

## Step 0 — Before Any Code

**Always do this before writing or editing code:**

1. Load `references/architecture.md` — identify affected file(s) and function(s)
2. Load `references/bug-log.md` — check for known issues in that area
3. Load `references/feature-log.md` — check if this is a tracked request
4. Output the **DEV BRIEF block** (below)
5. Then and only then write code

---

## Mandatory Pre-Code Declaration

Output this block before EVERY code edit or addition:

```
📦 RWAPOR DEV BRIEF
─────────────────────────────────────────
Affected file(s)    : <R/filename.R or inst/shiny/mod_*.R>
Affected function(s): <function_name()>
Change type         : [Bug Fix | Feature | Refactor | UI/UX | Method]
Related log entry   : [Bug #N | Feature #N | none]
Known constraints   : <confirmed patterns or failures from logs>
─────────────────────────────────────────
```

Never skip this block. If the file is uncertain, say so explicitly.

---

## Auto-Summary Rule

At the start of each Rwapor prompt output a brief context block:

```
🔍 CONTEXT BRIEF
• Module/file   : <file and function>
• Current state : <what it currently does>
• Open issues   : <any bug or pending feature>
• Last confirmed: <last working approach for this area>
```

Omit lines with no relevant match. Max 5 lines total.

---

## Reference Files — When to Load Each

| File | Load when... |
|---|---|
| `references/architecture.md` | Any code question — always load this first |
| `references/feature-log.md` | Adding functionality or checking request status |
| `references/bug-log.md` | Fixing errors, regressions, or unexpected outputs |
| `references/ui-decisions.md` | Any Shiny UI/UX change (layout, tabs, widgets) |
| `references/prompt-history.md` | New session or when context seems incomplete |

**Token efficiency**: load only what's needed per task type:
- Bug fix → `architecture.md` + `bug-log.md`
- UI change → `architecture.md` + `ui-decisions.md`
- New feature → all five files

---

## Package Architecture Summary

Full function-level detail is in `references/architecture.md`.

### R/ Source Files

| File | Responsibility |
|---|---|
| `R/wapor_map.R` | `wapor_map()` — download rasters for region/period |
| `R/wapor_ts.R` | `wapor_ts()` — extract time series + zonal statistics |
| `R/plan_wapor_time_slices.R` | `plan_wapor_time_slices()` — optimal mixed-resolution download plan |
| `R/analysis.R` | Crop mask loading, season weights, Kc curve, local raster scan (`rwapor_scan_local_variables`) |
| `R/analysis_indicators.R` | AETI, RET, ETc, Peff, adequacy, CWP, BWP, yield-from-NPP |
| `R/api_client.R` | Low-level WaPOR API calls and URL generation |
| `R/metadata.R` | `WAPOR3_VARS`, `AGERA5_VARS`, `L3_REGIONS` data objects + `get_variable_metadata()` |
| `R/unit_convertor.R` | `df_unit_convertor()`, `raster_unit_convertor()` |
| `R/utils.R` | `parse_region()`, `safe_project()`, date/unit helpers, L3 extent cache, zonal helpers |
| `R/gdal_config.R` | `wapor_configure_gdal()`, `wapor_fix_proj()`, `wapor_gdal_settings()` |
| `R/crop_defaults.R` | `rwapor_list_crops()`, `rwapor_get_crop_defaults()`, `rwapor_validate_crop_defaults()` |
| `R/seasonal_download.R` | `download_seasonal_rasters()` — internal download+match helper |
| `R/interval_helpers.R` | Date interval arithmetic (overlap, subtraction, month helpers) |
| `R/run_dashboard.R` | `run_wapor()` — launches Shiny app from `inst/shiny/` |
| `R/rwapor_favorites.R` | Favorites system: add/remove/list local data folders |

### Shiny App (`inst/shiny/`)

| File | Responsibility |
|---|---|
| `app.R` | `bslib::page_navbar` — 3 tabs: **Download**, **Visualisation**, **Analysis** |
| `mod_download.R` | `mod_download_ui/server()` — variable/region/period/folder selection + download trigger |
| `mod_visualisation.R` | `mod_visualisation_ui/server()` — leaflet map, raster layer rendering |
| `mod_analysis.R` | `mod_analysis_ui/server()` — full seasonal analysis pipeline (largest module, ~2400 lines) |
| `mod_aoi.R` | `mod_aoi_ui/server()` — Area of Interest selection (bbox, vector file, L3 code) |
| `utils_shiny.R` | Shiny helpers: bbox extraction, polygon builder, logging, `crop_to_region_shiny()` |

### Data Files (package root)

| File | Contents |
|---|---|
| `fao_crop_coefficients.csv` | Kc_ini, Kc_mid, Kc_end per crop (FAO-56 derived) |
| `fao_growth_stages.csv` | Development stage lengths per crop (FAO-56 Table 11) |

---

## Coding Standards

- **Tidyverse style guide** for all R code
- **`terra`** for all raster operations (never deprecated `raster`)
- **`sf`** for all vector/polygon operations
- **`exactextractr`** for pixel-weighted zonal statistics
- **`httr2`** for all API calls
- **`memoise`** for caching API responses
- **`future.apply`** for parallelism
- Roxygen2 docstrings on all exported functions (`@param`, `@return`, `@examples`)

### Common Patterns

```r
# Safe CRS projection (Windows fix)
v <- safe_project(v, r_crs)

# Check geometry match
if (!compare_geom(x, template)) {
  x <- rwapor_harmonize_to_template(x, template)
}

# Scan local folder for variables
local_vars <- rwapor_scan_local_variables(folder)
```

- `tryCatch()` wrapping all I/O and API calls
- No hardcoded paths — all paths via function arguments
- `snake_case` function names; package-exported functions prefixed with `rwapor_`
  (exception: top-level user-facing functions: `wapor_map`, `wapor_ts`, `run_wapor`)

---

## Key Methodological References

- **WaPOR ETLook**: https://bitbucket.org/cioapps/wapor-et-look/wiki/Home
- **PyWaPOR**: https://bitbucket.org/cioapps/pywapor/src/master/
- **FAO-56** (Allen et al. 1998) — for Kc, ETc, Peff (USDA SCS method)
- **wapor-r-pkg skill** — internal methodology encoding (Peff, ETc, adequacy, GBWP/NBWP)
- **FAO WaPOR portal**: https://www.fao.org/in-action/remote-sensing-for-water-productivity/

---

## Memory Update Protocol

After any confirmed fix, feature, or decision, update the appropriate log and announce:

> "📝 Logging to [log-file]: [entry summary]"

Rules: one entry per event, include function + file, never invent entries.

---

## Conflict Escalation

If a change contradicts a confirmed log entry, flag it before proceeding:

> "⚠️ Conflict with [log file, entry N]: [description]. Confirm before I continue."
