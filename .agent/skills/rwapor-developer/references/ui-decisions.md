# Rwapor Shiny Dashboard — UI/UX Decisions Log
_Last updated: 2026-03-26_

> Records all confirmed UI/UX decisions for the Rwapor Shiny dashboard.
> Consult before making ANY layout, widget, or interaction change.

---

## Confirmed Decisions

### D01 — Framework: bslib page_navbar + Bootstrap 5
- **File**: inst/shiny/app.R
- **Decision**: Use `bslib::page_navbar()` with `bootswatch = "flatly"` theme, primary colour `#2c3e50`
- **Rationale**: Modern Bootstrap 5 layout; clean navbar tabs; responsive
- **Status**: ✅ Confirmed

---

### D02 — Three-Tab Layout: Download | Visualisation | Analysis
- **File**: inst/shiny/app.R
- **Decision**: Three `bslib::nav_panel()` tabs in this order, with an Exit button on the right
- **Tab icons**: cloud-download | chart-area | flask
- **Rationale**: Mirrors the user workflow — select/download data → view it → analyse it
- **Status**: ✅ Confirmed

---

### D03 — Shared State via Download Module
- **File**: inst/shiny/app.R + mod_download.R
- **Decision**: `mod_download_server()` returns `list(folder = reactive, region = reactive)` which is passed to both Analysis and Visualisation modules
- **Rationale**: Single source of truth for the working folder and AOI; avoids duplication
- **Pattern**:
  ```r
  dl_out <- mod_download_server("dl", l3_regions_meta)
  mod_analysis_server("an", global_folder = dl_out$folder, aoi_region = dl_out$region)
  mod_visualisation_server("vis", global_folder = dl_out$folder, aoi_region = dl_out$region, ...)
  ```
- **Status**: ✅ Confirmed

---

### D04 — Analysis Module: Crop Mask Toggle
- **File**: inst/shiny/mod_analysis.R
- **Decision**: Crop mask is optional — toggled with `checkboxInput("an_use_crop_mask")`
- **When off**: Single-class analysis (no class separation)
- **When on**: Per-class Kc assignment UI appears
- **Status**: ✅ Confirmed

---

### D05 — Analysis Module: Pixel-wise Season Rasters Toggle
- **File**: inst/shiny/mod_analysis.R
- **Decision**: Season start/end can be either fixed dates OR pixel-wise SpatRaster files, toggled with `checkboxInput("an_use_season_rasters")`
- **Rationale**: Supports spatially variable phenology (from remote sensing LSP products)
- **Status**: ✅ Confirmed

---

### D06 — Analysis Results: navset_card_tab Layout
- **File**: inst/shiny/mod_analysis.R
- **Decision**: Results shown in tabbed card panels (not sequential sections)
- **Results tabs**: Main Results | Adequacy | Eff. Precip | CWP/BWP
- **Input preview tabs**: Crop Mask | Season | Classes
- **Status**: ✅ Confirmed

---

### D07 — Analysis Module: Incremental Memory Optimization Toggle
- **File**: inst/shiny/mod_analysis.R
- **Decision**: `checkboxInput("an_incremental")` controls whether `rwapor_apply_masked_sum()` runs layer-by-layer to reduce peak memory
- **Default**: FALSE (faster, loads all layers at once)
- **Rationale**: Necessary for large L3 areas with many dekads
- **Status**: ✅ Confirmed

---

### D08 — shinyjs for UI State Control
- **File**: inst/shiny/app.R (header), mod_analysis.R
- **Decision**: Use `shinyjs` for toggling UI element states (e.g., `shinyjs::toggleState("an_run_btn", ...)`)
- **Status**: ✅ Confirmed

---

### D09 — shinyFiles for Folder Browser
- **File**: inst/shiny/mod_download.R, mod_analysis.R
- **Decision**: Use `shinyFiles` package for native folder browsing dialog
- **Status**: ✅ Confirmed

---

### D10 — Leaflet for Interactive Map
- **File**: inst/shiny/mod_visualisation.R
- **Decision**: Use `leaflet` + `leaflet.extras` + `leaflet.extras2` for the interactive map
- **Rationale**: Best Shiny integration; supports draw tools for AOI selection
- **Status**: ✅ Confirmed

---

### D11 — Validate → Run → Reset → Export Button Flow
- **File**: inst/shiny/mod_analysis.R
- **Decision**: Analysis pipeline has 4 explicit action buttons in order:
  1. `an_validate_btn` — validates inputs before running
  2. `an_run_btn` — runs the full analysis (enabled only after validation passes)
  3. `an_reset_btn` — clears all analysis state
  4. Export button — exports results to CSV/file
- **Status**: ✅ Confirmed

---

## Open / Undecided

_UI/UX questions not yet resolved — add here before deciding._

---

## Template for New Entry

```
### D[N] — [Decision Title]
- **File**: inst/shiny/relevant_file.R
- **Decision**: What was decided
- **Rationale**: Why
- **Implementation**: How it works technically (if relevant)
- **Status**: ✅ Confirmed | 🟡 Under Discussion
```
