# Rwapor Repository Memory

## 2026-04-16 — Package Structure Review & Developer Skills Catalog

### Summary
Conducted a full review of the Rwapor package structure and goals. Created a comprehensive
developer skill catalog at `memories/repo/developer-skills.md` (SKILL-001 through SKILL-010).

### Package Architecture (Confirmed)

**Two-layer design:**
1. `R/` — Core library: download, time-series extraction, analysis, anomaly detection, comparison
2. `inst/shiny/` — Interactive dashboard: 5 modules (Download, Visualisation, Analysis, Timeseries, Monitoring)

**Key module communication pattern:** reactive return values (NOT global state)
```
dl_out → an_out → vis_out (via reactive() return lists)
```

**Dashboard layout:** `bslib::page_navbar` + Bootstrap 5 + bootswatch "flatly"

### Skills Catalog Created

Full catalog at `memories/repo/developer-skills.md`:
- **SKILL-001**: Package architecture and file map
- **SKILL-002**: WaPOR/AgERA5 data download patterns
- **SKILL-003**: Analysis/indicator calculation patterns
- **SKILL-004**: Raster visualization and map export
- **SKILL-005**: Professional Shiny dashboard patterns (10 sub-patterns)
- **SKILL-006**: Monitoring module (DuckDB persistence)
- **SKILL-007**: Export and reporting (PNG, PDF, GeoTIFF, R Markdown)
- **SKILL-008**: Adding a new Shiny module (checklist + skeleton)
- **SKILL-009**: Testing conventions
- **SKILL-010**: Package-wide coding conventions

### Key Patterns for Shiny Dashboard Development

| Pattern | Rule |
|---|---|
| Conditional UI | Always `renderUI` + `uiOutput`, NEVER `conditionalPanel` with module inputs |
| Dynamic input safety | NULL-check ALL inputs from `renderUI` before conditional logic |
| Layer clearing | Clear ALL 7 layer groups on mode switch |
| JavaScript injection | Use `shinyjs::runjs()`, NOT `htmlwidgets::onRender()` with proxy |
| Async operations | Use `future::future() %...>%` pipeline for long-running tasks |
| Cross-module state | Reactive return values only (never `session$userData` or globals) |

### Map/Figure Export for Reports (New)

```r
# Publication-quality static map
ggplot() +
  tidyterra::geom_spatraster(data = r) +
  scale_fill_gradientn(colours = rev(viridisLite::viridis(20))) +
  geom_sf(data = aoi_sf, fill = NA, colour = "black") +
  theme_minimal()
ggsave("output.png", width = 10, height = 8, dpi = 300)
```

---

## 2026-04-01 - Visualization Module Dual-Raster Enhancement

### Context
- Goal: Enable two-raster visualization with conditional queries and split-screen slider comparison
- Files: `inst/shiny/mod_visualisation.R` (1100+ lines, major refactoring)
- Feature requests: (1) conditional query on 2 rasters, (2) interactive split-screen slider for side-by-side comparison

### What Worked
- **Server-side rendering pattern**: Replacing `conditionalPanel` with `renderUI` resolved namespace issues in Shiny modules
- **NULL-safety pattern**: Adding checks `if (is.null(x) || length(x) == 0) x <- default` prevented crashes from dynamic UI timing
- **Explicit layer clearing**: Using `clearGroup()` for all 7 layer groups ensured clean transitions between visualization modes
- **CSS clipping approach**: Using `style.clip = 'rect(0px, xpx, ...'` to split raster display works without external plugins
- **JavaScript injection**: `htmlwidgets::onRender()` successfully injects custom JavaScript into leaflet maps
- **Console logging strategy**: Extensive `console.log()` messages help debug browser-side JavaScript execution

### What Failed
- **conditionalPanel with module namespaces**: JavaScript condition `input['mod-raster_var'] !== null` doesn't resolve reliably in modules
- **Direct dynamic input access**: Using `input$dual_display_mode` without NULL checks causes "argument is of length zero" errors
- **Minimal layer clearing**: Only clearing "raster" group left orphaned layers when switching between single/dual/query modes
- **Split-screen slider visibility**: Despite JavaScript implementation, visual elements (white line, circular handle) not appearing (investigation ongoing)

### Error Signatures
- Error: "argument is of length zero" in `if (display_mode == "swipe")`
  - Root cause: `input$dual_display_mode` is NULL while renderUI hasn't completed
  - Fix: Add `if (is.null(display_mode) || length(display_mode) == 0) display_mode <- "overlay"` before use

- Issue: Second raster selector not appearing in dual mode
  - Root cause: `conditionalPanel(condition = "input.viz_mode !== 'single'", ...)` namespace resolution failure
  - Fix: Replace with `uiOutput("raster2_ui")` + `output$raster2_ui <- renderUI({ if (mode != "single") { ...selector... } })`

- Issue: Split-screen slider invisible despite JavaScript
  - Root cause: Unknown (debugging in progress with browser console)
  - Investigation: Console logging, element existence checks, CSS visibility tests
  - Next: User to provide browser console output

### Skill Improvements
- **Shiny module conditional UI**: Always use server-side `renderUI` pattern, never `conditionalPanel` for namespaced inputs
- **Dynamic input safety**: All inputs from `renderUI` must be NULL-checked with defaults before use in logic or conditionals
- **Leaflet layer management**: Explicitly clear ALL possible layer groups when changing visualization modes, not just default group
- **JavaScript debugging in Shiny**: Add console.log at each step, use setTimeout for timing-sensitive DOM operations, check element existence before manipulation
- **Browser vs R console**: Clarify to users that JavaScript commands (e.g., `document.querySelector...`) run in browser F12 console, not R console

### Code Patterns
**Server-side conditional UI (preferred over conditionalPanel):**
```r
# UI
uiOutput(NS(id, "raster2_ui"))

# Server
output$raster2_ui <- renderUI({
  mode <- input$viz_mode
  if (is.null(mode) || mode == "single") return(NULL)
  # Return UI elements
  selectInput(NS(id, "raster2_var"), ...)
})
```

**NULL-safe dynamic input access:**
```r
display_mode <- input$dual_display_mode
if (is.null(display_mode) || length(display_mode) == 0) {
  display_mode <- "overlay"  # Safe default
}
```

**Aggressive leaflet layer clearing:**
```r
leafletProxy("map_viz") |>
  clearImages() |>
  clearGroup("raster") |>
  clearGroup("raster1") |>
  clearGroup("raster2") |>
  clearGroup("raster_left") |>
  clearGroup("raster_right") |>
  clearGroup("raster_intersection") |>
  clearGroup("raster_query")
```

### Next-session checklist
- [ ] Confirm split-screen slider JavaScript execution via browser console output
- [ ] If JavaScript not executing: investigate htmlwidgets::onRender timing, try alternative injection method
- [ ] If JavaScript executing but invisible: adjust z-index, positioning, CSS styling
- [ ] Add keyboard controls (arrow keys) for slider positioning
- [ ] Document conditional query and split-screen slider features in user guide
- [ ] Add regression tests for server-side conditional UI rendering

## 2026-03-31 - Shiny L3 AOI Auto-Detection Stabilization

### Context
- Goal: Improve download-module AOI flow and L3 overlap auto-detection behavior.
- Files: `inst/shiny/mod_download.R`, `inst/shiny/mod_aoi.R`, `README.md`, `NEWS.md`, `vignettes/shiny-dashboard.Rmd`.

### What Worked
- Reordering AOI selection before variable selection improved UX and made L3 filtering logical.
- Converting period to character before calling `wapor_guess_region()` resolved strict input validation errors.
- Using richer status states (`no_aoi`, `no_overlap`, `parse_error`, `detection_error`) improved diagnosis instead of silent failure.
- Adding file existence diagnostics for raster AOI uploads reduced ambiguity for OneDrive/path-related issues.

### What Failed
- Using `shiny::details()` failed because it is not exported in `shiny`; HTML tag wrapper is required.
- Passing Date values directly into `wapor_guess_region()` caused runtime validation errors.
- Early overlap detection implementation masked errors by returning `NULL`, making root cause unclear.

### Error Signatures
- Error: "'details' is not an exported object from 'namespace:shiny'"
  - Root cause: Incorrect function call for HTML details element.
  - Fix: Replace with `shiny::tags$details(...)`.

- Error: "'period' must be a character vector of length 2: c(start_date, end_date)"
  - Root cause: `input$period`/`Sys.Date()` values passed as Date instead of character.
  - Fix: `period <- as.character(period_dates)` before `wapor_guess_region()`.

- Error: "[rast] file does not exist"
  - Root cause: AOI upload path not locally available/synced (common with OneDrive Files On-Demand) or path mismatch.
  - Fix: Validate `file.exists()`, inspect directory contents for diagnostics, instruct local sync, and show actionable error text.

### Skill Improvements
- Add explicit check: all internal API calls requiring `period` should receive character vectors.
- In Shiny modules, never swallow `tryCatch` errors to `NULL` without surfacing diagnostic status.
- For Windows + OneDrive, prefer proactive path diagnostics and user guidance in UI notifications.

### Next-session checklist
- [ ] Verify L3 detection for vector AOI where overlap is known (e.g., JEN).
- [ ] Add targeted test coverage for period type conversion in overlap detection path.
- [ ] Add regression test for `tags$details` usage in UI construction.
- [ ] Validate raster AOI upload on local path and OneDrive path.
