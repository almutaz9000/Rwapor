# Rwapor Shiny Dashboard - Modularized Version
# Main entry point that assembles the various modules

# ── Dependency guard ───────────────────────────────────────────────────────────
# All packages listed here are in Suggests. Check them before attaching so
# that a missing package gives a clear, actionable error instead of a cryptic
# "there is no package called X" buried inside module code.
.RWAPOR_SHINY_PKGS <- c(
  "shiny", "bslib", "leaflet", "terra", "sf",
  "shinyFiles", "shinyvalidate", "shinyjs", "shinyAce",
  "ggplot2", "dplyr", "DT", "shinycssloaders",
  "future", "promises", "future.apply", "Rwapor"
)

.check_shiny_deps <- function(pkgs) {
  missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs)) {
    stop(
      "Rwapor dashboard requires the following package(s) that are not installed:\n  ",
      paste(missing_pkgs, collapse = ", "), "\n\n",
      "Install them with:\n  install.packages(",
      "c(", paste0("\"", missing_pkgs, "\"", collapse = ", "), "))",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

.check_shiny_deps(.RWAPOR_SHINY_PKGS)

# Attach after the guard passes — search-path attachment is needed for Shiny
# reactive contexts and for formula-based ggplot2 / dplyr pipelines in modules.
library(shiny)
library(bslib)
library(leaflet)
library(terra)
library(sf)
library(shinyFiles)
library(shinyvalidate)
library(shinyjs)
library(shinyAce)
library(ggplot2)
library(dplyr)
library(DT)
library(shinycssloaders)
library(future)
library(promises)
library(future.apply)
library(Rwapor)

# ── Parallel plan ─────────────────────────────────────────────────────────────
# Use 2 background workers for async extraction and analysis tasks.
# Cap at 2 to avoid overwhelming the WaPOR API or local disk I/O.

# Configure future options for Windows compatibility
old_future_options <- options(
  future.rscript.sh = "auto",  # Auto-detect R script path
  future.availableCores.fallback = 2L  # Fallback core count
)

old_future_plan <- future::plan()

# Fallback to sequential if multisession fails (common on Windows with path issues)
tryCatch({
  future::plan(future::multisession, workers = min(2L, future::availableCores() - 1L))
}, error = function(e) {
  warning("Could not initialize multisession plan, falling back to sequential: ", e$message)
  future::plan(future::sequential)
})

runtime_state <- new.env(parent = emptyenv())
runtime_state$restored <- FALSE
runtime_state$restore <- function() {
  if (isTRUE(runtime_state$restored)) return(invisible(NULL))

  runtime_state$restored <- TRUE
  options(old_future_options)
  try(future::plan(old_future_plan), silent = TRUE)

  invisible(NULL)
}

# --- Source Utility Functions and Modules ---
.wapor_source_app_module <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Missing Shiny app module file: %s", path), call. = FALSE)
  }

  tryCatch(
    source(path, local = FALSE),
    error = function(e) {
      stop(sprintf("Failed to source '%s': %s", path, e$message), call. = FALSE)
    }
  )
}

.wapor_source_app_module("utils_shiny.R")
.wapor_source_app_module("mod_aoi.R")
.wapor_source_app_module("mod_download.R")
.wapor_source_app_module("mod_dual_map.R")
.wapor_source_app_module("mod_visualisation.R")
.wapor_source_app_module("mod_analysis.R")
.wapor_source_app_module("mod_timeseries.R")
.wapor_source_app_module("mod_monitoring.R")

# --- Global / Static Configuration ---
# Build variable list from package metadata
all_vars <- Rwapor::wapor_available_variables(include_agera5 = TRUE)
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else if (length(all_vars) > 0) all_vars[1] else NULL
if (is.na(default_var)) default_var <- NULL

# Build L3 region choices as label -> code
# Short timeout, no retries: startup must not block for ~30 s of backoff when
# the API is slow or offline. The static list is used as the fallback.
l3_regions_df <- tryCatch({
  withCallingHandlers(
    Rwapor::wapor_fetch_l3_regions(timeout = 10, retry = FALSE),
    warning = function(w) {
      message("Using the built-in L3 region list: ", conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
}, error = function(e) {
  message("Could not fetch L3 regions: ", e$message)
  Rwapor::wapor_l3_regions_to_df(Rwapor::L3_REGIONS)
})

l3_region_labels <- sprintf("%s - %s (%s)", l3_regions_df$country, l3_regions_df$name, l3_regions_df$code)
l3_region_choices <- as.list(stats::setNames(l3_regions_df$code, l3_region_labels))
l3_regions_meta <- Rwapor::L3_REGIONS # Maintain compatibility for downstream mapping

# --- Main UI ---
ui <- bslib::page_navbar(
  title = shiny::tags$span(
    shiny::tags$strong("Rwapor"),
    shiny::tags$small(" Dashboard", style = "opacity: 0.7;")
  ),
  theme = bslib::bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary   = "#2c3e50",
    "navbar-bg" = "#2c3e50"
  ),
  header = shiny::tagList(
    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "premium_style.css")
    ),
    shinyjs::useShinyjs()
  ),

  # ── Tabs ──
  bslib::nav_panel("Download", icon = shiny::icon("cloud-arrow-down"),
    mod_download_ui("dl", all_vars, default_var, l3_region_choices)
  ),
  bslib::nav_panel("Analysis", icon = shiny::icon("flask"),
    mod_analysis_ui("an", all_vars, l3_region_choices)
  ),
  bslib::nav_panel("Visualisation", icon = shiny::icon("chart-area"),
    mod_visualisation_ui("vis")
  ),
  bslib::nav_panel("Timeseries", icon = shiny::icon("chart-line"),
    mod_timeseries_ui("ts")
  ),
  bslib::nav_panel("Monitoring", icon = shiny::icon("satellite-dish"),
    mod_monitoring_ui("mon", l3_region_choices)
  ),

  bslib::nav_spacer(),
  bslib::nav_item(shiny::actionButton("exit_btn", "Exit", icon = shiny::icon("power-off"), class = "btn-danger btn-sm"))
)

# --- Main Server ---
server <- function(input, output, session) {
  # Exit logic
  shiny::observeEvent(input$exit_btn, {
    # Ensure it's logged and some feedback is given
    log_msg("Exit requested via button.")
    shiny::showNotification("Shutting down session...", type = "warning", duration = 2)
    
    # Delay slightly to allow notification to be seen
    shinyjs::delay(500, shiny::stopApp())
  })

  # Automatically stop the app when the browser tab is closed
  session$onSessionEnded(function() {
    log_msg("Browser session ended.")
    runtime_state$restore()
  })

  shiny::onStop(function() {
    runtime_state$restore()
  })

  # Initialize Modules
  
  # 1. Download Module (manages AOI and Folder selection)
  # Passes l3_regions_meta for region lookups
  dl_out <- mod_download_server("dl", l3_regions_meta = l3_regions_meta)
  
  # 2. Analysis Module
  # Uses the shared folder and AOI from the download tab
  an_out <- mod_analysis_server("an",
                               global_folder    = dl_out$folder,
                               aoi_region       = dl_out$region,
                               download_seasons = dl_out$seasons)
  
  # 3. Visualisation Module
  # Uses the shared folder, analysis folder and AOI, plus results from the analysis module
  mod_visualisation_server("vis", 
                          global_folder = dl_out$folder, 
                          an_folder = an_out$folder,
                          aoi_region = dl_out$region,
                          an_crop_mask_rast = an_out$mask_rast,
                          an_start_rast = an_out$start_rast,
                          an_end_rast = an_out$end_rast,
                          an_crop_params = an_out$crop_params)
  
  # 4. Timeseries Module
  # Uses the shared folder and AOI from the download tab
  mod_timeseries_server("ts",
                       global_folder = dl_out$folder,
                       aoi_region = dl_out$region)

  # 5. Monitoring Module
  # Farm-level seasonal monitoring with DuckDB persistence
  mod_monitoring_server("mon",
                        global_folder = dl_out$folder,
                        aoi_region    = dl_out$region,
                        l3_regions_meta = l3_regions_meta)
}

shiny::shinyApp(ui, server)
