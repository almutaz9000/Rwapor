# Issues Log

## Open Issues

- [ ] L3 overlap auto-detection may report no overlap for known AOI in some runs
  - ID: ISS-20260331-001
  - Discovered: 2026-03-31
  - Context: Shiny download module with uploaded `Jendouba_aoi.geojson`
  - Error signature: "No L3 regions overlap with this AOI" (intermittent before fixes)
  - Suspected root cause: fragile detection path and insufficient diagnostics around parse/API interaction
  - Owner: Rwapor-dev
  - Next action: validate end-to-end in live Shiny run and add regression tests

- [ ] Non-vanilla startup can fail while vanilla startup works
  - ID: ISS-20260331-002
  - Discovered: 2026-03-31
  - Context: terminal launch (`run_wapor()`) in default profile environment
  - Error signature: intermittent startup failure in non-vanilla execution context
  - Suspected root cause: environment/profile side effects outside module code path
  - Owner: Rwapor-dev
  - Next action: compare startup environment and isolate profile-triggered differences

## Resolved Improvements

- [x] Split-screen slider JavaScript not executing with leafletProxy updates
  - ID: ISS-20260401-001
  - Resolved: 2026-04-01
  - Root cause: `htmlwidgets::onRender()` only executes when widget is first created, not when updated via `leafletProxy()`
  - Fix applied: Replaced `proxy |> htmlwidgets::onRender("...")` with `shinyjs::runjs("(function() { ... })()")` for immediate execution
  - Files: `inst/shiny/mod_visualisation.R` (split-screen slider section)
  - Validation: JavaScript now executes immediately when switching to swipe mode (verified via browser console)
  - Regression test: pending

- [x] conditionalPanel namespace issues in Shiny visualization module
  - ID: ISS-20260401-002
  - Resolved: 2026-04-01
  - Root cause: `conditionalPanel` JavaScript cannot reliably resolve namespaced inputs in Shiny modules (e.g., `input['mod-raster_var']`)
  - Fix applied: Replaced 4 `conditionalPanel` blocks with server-side `renderUI` pattern using `uiOutput`/`output$*_ui`
  - Files: `inst/shiny/mod_visualisation.R` (lines 180-330)
  - Validation: Second raster selector now appears in dual/query modes
  - Regression test: pending

- [x] "argument is of length zero" error when switching to dual raster mode
  - ID: ISS-20260401-003
  - Resolved: 2026-04-01
  - Root cause: Dynamic UI inputs (`input$dual_display_mode`, `input$raster_opacity2`, etc.) are NULL before renderUI completes, causing crashes in conditional logic
  - Fix applied: Added NULL checks with default values for 5 dynamic inputs before use
  - Pattern: `if (is.null(x) || length(x) == 0) x <- default_value`
  - Files: `inst/shiny/mod_visualisation.R` (lines 840-860)
  - Validation: No crashes when switching modes, defaults applied gracefully
  - Regression test: pending

- [x] Map layers persisting when switching visualization modes
  - ID: ISS-20260401-004
  - Resolved: 2026-04-01
  - Root cause: Insufficient layer clearing when transitioning between single/dual/query modes
  - Fix applied: Added explicit `clearGroup()` calls for all 7 possible layer groups (raster, raster1, raster2, raster_left, raster_right, raster_intersection, raster_query) before rendering new mode
  - Files: `inst/shiny/mod_visualisation.R` (lines 800-850)
  - Validation: Clean state transitions observed in testing
  - Regression test: pending

## Resolved Improvements (Previous Session)
- [x] Invalid UI tag helper for details block
  - ID: ISS-20260331-003
  - Resolved: 2026-03-31
  - Root cause: used `shiny::details` which is not exported
  - Fix applied: replaced with `shiny::tags$details`
  - Files: `inst/shiny/mod_download.R`
  - Validation: Shiny file parses without errors
  - Regression test: pending

- [x] L3 detection period type mismatch
  - ID: ISS-20260331-004
  - Resolved: 2026-03-31
  - Root cause: Date vector passed to `wapor_guess_region` requiring character dates
  - Fix applied: normalized with `as.character(period_dates)` before call
  - Files: `inst/shiny/mod_download.R`
  - Validation: error signature no longer appears after conversion
  - Regression test: pending

- [x] Raster AOI path diagnostics insufficient for OneDrive cases
  - ID: ISS-20260331-005
  - Resolved: 2026-03-31
  - Root cause: file existence failures lacked actionable diagnostics
  - Fix applied: added existence checks, directory introspection, and actionable user guidance
  - Files: `inst/shiny/mod_aoi.R`
  - Validation: enhanced error notifications show cause and next actions
  - Regression test: pending
