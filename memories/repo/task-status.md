# Task Status Ledger

## 2026-04-01

### Success
- [x] Fixed conditionalPanel namespace issues in visualization module - replaced with renderUI pattern.
- [x] Second raster selector now appears correctly in dual/query modes.
- [x] Fixed "argument is of length zero" errors with NULL checks for dynamic inputs.
- [x] Map layer clearing improved - explicit clearGroup() for all 7 layer groups.
- [x] Conditional query panel renders properly with all controls.
- [x] Implemented split-screen slider JavaScript with CSS clipping approach.
- [x] Added extensive console logging for slider debugging.
- [x] Enhanced slider visuals: 4px white line, 50px circular handle with ⇔ symbol.
- [x] Added notification message when swipe mode activates.
- [x] Fixed split-screen slider JavaScript execution - replaced htmlwidgets::onRender with shinyjs::runjs.

### Pending
- [ ] User to verify split-screen slider now appears and functions correctly in browser.
- [ ] Add keyboard controls for slider positioning once functionality confirmed.
- [ ] Implement slider position persistence across mode switches.
- [ ] Add documentation for conditional query and split-screen slider features.
- [ ] Add regression tests for split-screen slider functionality.

### Failed/Blocked
(None - previous blocker resolved)

## 2026-03-31

### Success
- [x] Added L3 AOI-first workflow in Shiny download module.
- [x] Added L3 overlap detection messaging and diagnostics in download UI.
- [x] Fixed `shiny::details` usage by switching to `shiny::tags$details`.
- [x] Fixed `wapor_guess_region` period type by converting to character.
- [x] Added repository memory agent and initialized memory files.

### Pending
- [ ] Validate JEN auto-detection end-to-end using uploaded Jendouba AOI in live Shiny run.
- [ ] Add test coverage for L3 detection path (period coercion and status mapping).
- [ ] Add regression test for AOI raster upload diagnostics on OneDrive/local paths.

### Failed/Blocked
- [ ] Direct non-vanilla run path intermittently fails in some sessions.
  - Blocker: Environment/profile startup behavior outside module code path.
  - Next action: Reproduce with startup diagnostics and compare `--vanilla` vs default session.
