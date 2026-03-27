---
name: shiny-developer
description: >
  Shiny module development and UI/UX work for the Rwapor dashboard. Trigger when
  the user mentions a specific Shiny issue: reactive not updating, UI not rendering,
  leaflet map problems, input validation (shinyvalidate), folder/file picker
  (shinyFiles), progress bars, module communication (shared reactives), tab layout,
  bslib theming, "the dashboard tab", "the analysis tab UI", "the download UI",
  "the AOI module", sidebar layout, output not displaying, observeEvent not firing,
  or any bug/feature scoped to inst/shiny/ files. Always load alongside rwapor-developer
  for full project context.
---

# Shiny Developer - Rwapor Context

## Module Map
| Module | Purpose | Size |
|--------|---------|------|
| `mod_download.R` | Data download workflow | ~537 lines |
| `mod_aoi.R` | AOI selection (Leaflet) | ~407 lines |
| `mod_analysis.R` | Analysis engine | **Large** (~33k tokens) |
| `mod_visualisation.R` | Results display | Medium |

## Architecture
```
app.R (entry)
  -> mod_download_server()
       -> mod_aoi_server()
  -> mod_analysis_server()
  -> mod_visualisation_server()
```

## Module Template
```r
# UI
mod_example_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::textInput(ns("input1"), "Label")
  )
}

# Server
mod_example_server <- function(id, shared_reactive = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # Logic here
    list(result = shiny::reactive(input$input1))
  })
}
```

## Large File Navigation (mod_analysis.R)
Look for section markers:
- `## --- UI Components`
- `## --- Reactive Logic`
- `## --- Indicators`
- `## --- Zonal Statistics`

## Best Practices
- `shinyvalidate::InputValidator` for robust input validation (see mod_download.R:214)
- `shinyFiles::shinyDirButton` and `shinyDirChoose` for project folder selection
- `leaflet::leafletProxy()` for map updates without full redraw
- `future.apply::future_lapply()` for long tasks
- Return reactive lists from modules for cross-module communication

## Common Patterns

```r
# Input Validation (standard pattern)
iv <- shinyvalidate::InputValidator$new()
iv$add_rule("folder", shinyvalidate::sv_required("Folder is required."))
iv$enable()

# Folder Selection (shinyFiles)
shinyFiles::shinyDirChoose(input, "browse_folder", roots = roots, session = session)
dir_path <- shinyFiles::parseDirPath(roots, input$browse_folder)

# Favorites toggle (persistent folder access)
if (Rwapor::rwapor_is_favorite(path)) {
  Rwapor::rwapor_remove_favorite(path)
} else {
  Rwapor::rwapor_add_favorite(path, type = "directory")
}
```

# Progress feedback
shiny::withProgress(message = "Processing", value = 0, {
  shiny::incProgress(0.5, detail = "Step 1")
})
```
