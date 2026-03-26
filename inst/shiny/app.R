# Rwapor Shiny Dashboard - Modularized Version
# Main entry point that assembles the various modules

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
library(Rwapor)

# --- Source Utility Functions and Modules ---
source("utils_shiny.R")
source("mod_aoi.R")
source("mod_download.R")
source("mod_visualisation.R")
source("mod_analysis.R")
source("mod_timeseries.R")

# --- Global / Static Configuration ---
# Build variable list from package metadata
all_vars <- unname(sort(unique(c(names(Rwapor::WAPOR3_VARS), names(Rwapor::AGERA5_VARS)))))
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else if (length(all_vars) > 0) all_vars[1] else NULL
if (is.na(default_var)) default_var <- NULL

# Build L3 region choices as label -> code
l3_regions_meta <- Rwapor::L3_REGIONS
l3_region_labels <- vapply(names(l3_regions_meta), function(code) {
  r <- l3_regions_meta[[code]]
  sprintf("%s - %s (%s)", r$country, r$name, code)
}, character(1))
l3_region_labels <- sort(l3_region_labels)
l3_region_choices <- as.list(stats::setNames(
  sub(".*\\(([A-Z]{3})\\)$", "\\1", l3_region_labels),
  l3_region_labels
))

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
    shiny::tags$head(shiny::tags$style(shiny::HTML("
      .main-map-output .leaflet-container { height: calc(100vh - 130px) !important; min-height: 480px; }
      .sidebar-scroll-area { flex: 1 1 auto; overflow-y: auto; padding: 0.5rem 0.75rem; }
      .sidebar-sticky-footer { flex-shrink: 0; position: sticky; bottom: 0; background: #f8f9fa; border-top: 1px solid #dee2e6; padding: 0.6rem 0.75rem; z-index: 20; }
      .code-preview-body { max-height: 220px; overflow-y: auto; font-size: 0.78rem; background: #f8f9fa; border: 1px solid #dee2e6; padding: 0.5rem; }
    "))),
    shinyjs::useShinyjs()
  ),

  # ── Tabs ──
  bslib::nav_panel("Download", icon = shiny::icon("cloud-download"),
    mod_download_ui("dl", all_vars, default_var, l3_region_choices)
  ),
  bslib::nav_panel("Visualisation", icon = shiny::icon("chart-area"),
    mod_visualisation_ui("vis")
  ),
  bslib::nav_panel("Analysis", icon = shiny::icon("flask"),
    mod_analysis_ui("an", all_vars, l3_region_choices)
  ),
  bslib::nav_panel("Timeseries", icon = shiny::icon("chart-line"),
    mod_timeseries_ui("ts")
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
    log_msg("Browser session ended. Stopping app.")
    shiny::stopApp()
  })

  # Initialize Modules
  
  # 1. Download Module (manages AOI and Folder selection)
  # Passes l3_regions_meta for region lookups
  dl_out <- mod_download_server("dl", l3_regions_meta = l3_regions_meta)
  
  # 2. Analysis Module
  # Uses the shared folder and AOI from the download tab
  an_out <- mod_analysis_server("an", 
                               global_folder = dl_out$folder, 
                               aoi_region = dl_out$region)
  
  # 3. Visualisation Module
  # Uses the shared folder and AOI, plus results from the analysis module
  mod_visualisation_server("vis", 
                          global_folder = dl_out$folder, 
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
}

shiny::shinyApp(ui, server)
