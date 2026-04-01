# Error Patterns

## htmlwidgets-onrender-not-executing-on-proxy-update
- Signature: Split-screen slider JavaScript not executing, `document.querySelectorAll('.leaflet-sbs-container').length` returns 0
- Trigger: Using `htmlwidgets::onRender()` with `leafletProxy()` to inject JavaScript when switching display modes
- Root cause: `onRender()` only executes when widget is first created, not when updated via proxy
- Resolution: Use `shinyjs::runjs()` instead to execute JavaScript immediately when mode changes
- Prevention: Never use `htmlwidgets::onRender()` with proxy updates - use `shinyjs::runjs()` for immediate execution
- File example: `inst/shiny/mod_visualisation.R` split-screen slider implementation

## shiny-argument-length-zero-dynamic-inputs
- Signature: `Error in if: argument is of length zero`
- Trigger: Accessing `input$*` from dynamically rendered UI (`renderUI`) in conditionals without NULL check.
- Root cause: Input value is NULL before `renderUI` completes, causing `if (input$var == "value")` to fail.
- Resolution: Add NULL check with default: `if (is.null(input$var) || length(input$var) == 0) input$var <- "default"`
- Prevention: Always NULL-check dynamic inputs before use in logic or conditionals.
- File example: `inst/shiny/mod_visualisation.R` lines 840-860

## shiny-conditionalpanel-namespace-failure
- Signature: Second raster selector or conditional UI not appearing despite correct JavaScript condition
- Trigger: Using `conditionalPanel(condition = "input.var !== null", ...)` with namespaced module inputs.
- Root cause: JavaScript in `conditionalPanel` cannot reliably resolve namespaced inputs (e.g., `input['mod-var']`).
- Resolution: Replace with server-side pattern: `uiOutput("ui_id")` + `output$ui_id <- renderUI({ if (condition) { ...UI... } })`
- Prevention: Never use `conditionalPanel` for module-namespaced inputs - always use server-side `renderUI`.
- File example: `inst/shiny/mod_visualisation.R` lines 180-330

## leaflet-layers-persist-across-modes
- Signature: Previous map layers remain visible when switching visualization modes
- Trigger: Using only `clearImages()` or single `clearGroup("raster")` when multiple layer groups exist.
- Root cause: Leaflet maintains separate layer groups (raster, raster1, raster2, raster_left, etc.) that must be explicitly cleared.
- Resolution: Clear ALL possible groups: `clearImages() %>% clearGroup("raster") %>% clearGroup("raster1") %>% ... (all 7 groups)`
- Prevention: When switching major map states, aggressively clear all known layer groups.
- File example: `inst/shiny/mod_visualisation.R` lines 800-850

## shiny-details-not-exported
- Signature: `'details' is not an exported object from 'namespace:shiny'`
- Trigger: UI uses `shiny::details(...)`.
- Root cause: `details` is an HTML tag, not an exported Shiny helper.
- Resolution: Use `shiny::tags$details(...)`.
- Prevention: For unsupported HTML helpers, use `shiny::tags$<tag>`.

## wapor-guess-region-period-type
- Signature: `'period' must be a character vector of length 2: c(start_date, end_date)`
- Trigger: Passing Date objects from `input$period` or `Sys.Date()` to `wapor_guess_region()`.
- Root cause: Strict input validator expects character dates.
- Resolution: Convert with `as.character(period_dates)` before call.
- Prevention: Normalize all period arguments at module boundary.

## raster-path-not-found-onedrive
- Signature: `[rast] file does not exist`
- Trigger: Uploading raster AOI from OneDrive path with Files On-Demand or unavailable local file.
- Root cause: File not present on disk at runtime.
- Resolution: Add `file.exists()` diagnostics, inspect directory, prompt user to sync locally.
- Prevention: Show upload hint for OneDrive local sync and actionable errors.
