# CLAUDE.md - Rwapor Project Agent Instructions

## Quick Reference

**Package**: Rwapor v0.1.0
**Purpose**: Download/analyze WaPOR & AgERA5 raster data
**Main Branch**: version-0.9
**Core Stack**: terra, sf, httr2, exactextractr, shiny

---

## File Map (Token-Efficient Navigation)

| Category | Key Files | Notes |
|----------|-----------|-------|
| **API** | `R/api_client.R`, `R/metadata.R` | Memoized; use `memoise::forget()` to clear cache |
| **Download** | `R/wapor_map.R`, `R/wapor_ts.R` | Entry points for raster/time-series |
| **Analysis** | `R/analysis.R`, `R/analysis_indicators.R` | Kc curves, season masks, crop classes |
| **Shiny** | `inst/shiny/mod_*.R` | `mod_analysis.R` is large (~33k tokens) |
| **Utils** | `R/utils.R`, `R/unit_convertor.R` | `parse_region()`, `crop_to_region()` |

---

## Operational Rules

### Before Any Task
1. State which specific file(s) are affected
2. Do NOT analyze the whole package for localized fixes
3. Provide **Patch Blocks** (targeted edits) unless full rewrite is requested

### R Package Standards
- Use `terra` (not `raster`) for all raster operations
- Add `@export` tag for public functions; run `devtools::document()` after
- Never manually edit `NAMESPACE` - it's Roxygen2-managed
- Tests: `devtools::test()` before finalizing changes

### Shiny Module Standards
- Always use `NS(id)` for UI elements
- Use `moduleServer(id, ...)` pattern for server logic
- `mod_analysis.R` sections are marked with `## ---` comments
- Use `shinyvalidate` for input validation
- Long tasks: use `future` patterns to avoid UI blocking

---

## WaPOR API Quick Reference

```
Base URLs:
  L1/L2: https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets
  L3:    https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets
  AgERA5: https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets

Filter syntax: ?filter=code:CONTAINS:{region};time:OVERLAPS:{start}:{end};
Response: items[], links[] (pagination), downloadUrl
```

---

## Dependency Chain (Critical Paths)

```
wapor_map() / wapor_ts()
  -> parse_region()        [utils.R]
  -> wapor_generate_urls() [api_client.R]
  -> crop_to_region()      [utils.R]
  -> raster_unit_convertor() [unit_convertor.R]

mod_download_server()
  -> mod_aoi_server()      [mod_aoi.R]
  -> wapor_map()           [wapor_map.R]

Analysis chain:
  rwapor_load_crop_mask() -> rwapor_harmonize_to_template()
  -> rwapor_extract_crop_classes() -> rwapor_build_crop_assignment_table()
```

---

## Development Status

| File | Status |
|------|--------|
| `R/*.R` | Stable |
| `inst/shiny/mod_analysis.R` | In-Development |
| `inst/shiny/mod_aoi.R` | In-Development |
| `inst/shiny/mod_download.R` | In-Development |

---

## Commands

```powershell
# Document changes (after modifying R/ files)
Rscript -e "devtools::document()"

# Run tests
Rscript -e "devtools::test()"

# Check package
Rscript -e "devtools::check()"

# Launch Shiny dashboard
Rscript -e "Rwapor::run_wapor()"
```

---

## Requirements Log

<!-- Add user-defined constraints here as they emerge -->
*Empty - awaiting constraints*

---

## Change Log

| Session | Files Modified | Summary |
|---------|----------------|---------|
| -- | -- | Initial manifest created |
