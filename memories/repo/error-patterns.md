# Error Patterns

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
