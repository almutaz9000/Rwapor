# Rwapor Repository Memory

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
