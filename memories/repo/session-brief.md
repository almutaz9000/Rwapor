# Session Brief (Rolling)

## Active Focus
- **Current Session (2026-04-01 - Session 2)**: Split-screen slider JavaScript execution fix - RESOLVED
- **Status**: Fixed `htmlwidgets::onRender()` → `shinyjs::runjs()` issue, awaiting user verification of functionality
- **Previous Session (2026-04-01 - Session 1)**: Visualization module dual-raster enhancement completed
- **Previous Session (2026-03-31)**: Stabilize Shiny download AOI/L3 overlap detection path

## Top Open Issues
- **ISS-20260331-001**: L3 overlap auto-detection may report no overlap for known AOI
- **ISS-20260331-002**: Non-vanilla startup can fail while vanilla startup works

## Recently Resolved (2026-04-01 - Session 2)
- **ISS-20260401-001**: Split-screen slider JavaScript not executing - fixed by replacing `htmlwidgets::onRender()` with `shinyjs::runjs()`

## Recently Resolved (2026-04-01 - Session 1)
- **ISS-20260401-002**: conditionalPanel namespace issues - fixed with renderUI pattern
- **ISS-20260401-003**: "argument is of length zero" - fixed with NULL checks
- **ISS-20260401-004**: Map layers persisting across mode switches - fixed with explicit clearGroup()

## Recently Resolved (2026-03-31)
- **ISS-20260331-003**: Invalid details helper in Shiny UI fixed via tags$details
- **ISS-20260331-004**: `wapor_guess_region` period type mismatch fixed via character coercion
- **ISS-20260331-005**: OneDrive raster AOI diagnostics improved with actionable checks

## Pending Tasks (Top 5)
- [ ] **[USER]** Verify split-screen slider appears and functions correctly in browser
- [ ] Add keyboard controls (arrow keys) for precise slider positioning
- [ ] Validate JEN auto-detection end-to-end in live Shiny run
- [ ] Add regression tests for visualization conditional UI (renderUI pattern)
- [ ] Add regression tests for split-screen slider functionality

## Key Files Under Active Development
- `inst/shiny/mod_visualisation.R` (1100+ lines) - dual raster visualization, split-screen slider (ACTIVE)
- `inst/shiny/mod_download.R` - L3 region detection, AOI workflow
- `inst/shiny/mod_aoi.R` - raster upload diagnostics

## Guardrails
- Always use R 4.5.3 executable path: `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe`
- Read memory digest before implementation
- Move solved issues from Open Issues to Resolved Improvements
- **JavaScript debugging**: Browser console (F12), NOT R console
- **Shiny modules**: Use server-side renderUI, not conditionalPanel for namespaced inputs
- **Dynamic inputs**: NULL-check with defaults before use in conditionals
- **Leaflet JavaScript injection**: Use `shinyjs::runjs()` for immediate execution, NOT `htmlwidgets::onRender()` with proxy updates
