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
library(future)
library(promises)
library(future.apply)
library(Rwapor)

# ── Parallel plan ─────────────────────────────────────────────────────────────
# Use 2 background workers for async extraction and analysis tasks.
# Cap at 2 to avoid overwhelming the WaPOR API or local disk I/O.

# Configure future options for Windows compatibility
options(
  future.rscript.sh = "auto",  # Auto-detect R script path
  future.availableCores.fallback = 2L  # Fallback core count
)

# Fallback to sequential if multisession fails (common on Windows with path issues)
tryCatch({
  future::plan(future::multisession, workers = min(2L, future::availableCores() - 1L))
}, error = function(e) {
  warning("Could not initialize multisession plan, falling back to sequential: ", e$message)
  future::plan(future::sequential)
})

# --- Source Utility Functions and Modules ---
source("utils_shiny.R")
source("mod_aoi.R")
source("mod_download.R")
source("mod_visualisation.R")
source("mod_analysis.R")
source("mod_timeseries.R")
source("mod_monitoring.R")

# --- Global / Static Configuration ---
# Build variable list from package metadata
all_vars <- unname(sort(unique(c(names(Rwapor::WAPOR3_VARS), names(Rwapor::AGERA5_VARS)))))
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else if (length(all_vars) > 0) all_vars[1] else NULL
if (is.na(default_var)) default_var <- NULL

# Build L3 region choices as label -> code
l3_regions_df <- tryCatch({
  Rwapor::wapor_fetch_l3_regions()
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
      # Link to premium CSS
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "premium_style.css"),
      # Custom inline styles
      shiny::tags$style(shiny::HTML("
      /* ── Layout helpers ─────────────────────────────────── */
      .main-map-output .leaflet-container { height: calc(100vh - 130px) !important; min-height: 480px; }
      .sidebar-scroll-area  { flex: 1 1 auto; overflow-y: auto; padding: 0.4rem 0.7rem; }
      .sidebar-sticky-footer{ flex-shrink: 0; position: sticky; bottom: 0; background: #f8f9fa;
                                border-top: 1px solid #dee2e6; padding: 0.55rem 0.7rem; z-index: 20; }
      .code-preview-body    { max-height: 220px; overflow-y: auto; font-size: 0.78rem;
                                background: #f8f9fa; border: 1px solid #dee2e6; padding: 0.5rem; }

      /* ── Global sidebar typography ──────────────────────── */
      .bslib-sidebar-layout .accordion-button {
        font-size: 0.82rem; padding: 0.42rem 0.85rem; font-weight: 600; }
      .bslib-sidebar-layout .accordion-body { padding: 0.5rem 0.85rem 0.6rem; }
      .bslib-sidebar-layout .form-label,
      .bslib-sidebar-layout label:not(.btn):not(.form-check-label) {
        font-size: 0.82rem; margin-bottom: 2px; font-weight: 500; }
      .bslib-sidebar-layout .form-check-label  { font-size: 0.81rem; }
      .bslib-sidebar-layout .form-control,
      .bslib-sidebar-layout .form-select       { font-size: 0.82rem; }
      .bslib-sidebar-layout .help-block,
      .bslib-sidebar-layout .shiny-input-container > .help-block {
        font-size: 0.77rem; color: #6c757d; margin-top: 2px; }

      /* ── Reusable utility classes ────────────────────────── */
      .ctrl-group-label {
        font-size: 0.72rem; font-weight: 700; color: #6c757d;
        text-transform: uppercase; letter-spacing: 0.06em;
        margin: 7px 0 3px; display: block; }
      .ctrl-divider { border: none; border-top: 1px solid #e9ecef; margin: 6px 0 5px; }
      .check-row    { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 2px; }
      .check-row .form-check { margin-bottom: 2px; }
      .inline-row   { display: flex; align-items: flex-end; gap: 5px; }
      .inline-row > .flex-1 { flex: 1 1 auto; min-width: 0; }

      /* ── Save panel (Timeseries tab) ─────────────────────── */
      .ts-save-panel {
        background: #f0f4f8; border: 1px solid #cdd9e8;
        border-radius: 6px; padding: 0.6rem 0.75rem; margin-top: 0.5rem; }
      .ts-save-panel .save-title {
        font-size: 0.72rem; font-weight: 700; color: #495057;
        text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 5px; display: block; }

      /* ── Value box tweaks ────────────────────────────────── */
      .bslib-value-box .value-box-title  { font-size: 0.78rem !important; }
      .bslib-value-box .value-box-value  { font-size: 1.1rem  !important; }

      /* ── Mandatory / optional field markers ──────────────── */
      .req-label::after {
        content: ' *';
        color: #dc3545;
        font-size: 0.88em;
        font-weight: 700;
        margin-left: 1px;
      }
      .opt-label::after {
        content: ' (optional)';
        font-size: 0.76em;
        font-weight: 400;
        color: #9ca3af;
      }

      /* ── Viz-mode segmented button strip ─────────────────── */
      .viz-mode-group .shiny-options-group {
        display: flex;
        flex-direction: row;
        gap: 0;
        margin-bottom: 0;
      }
      .viz-mode-group .radio { flex: 1; margin: 0; }
      .viz-mode-group .radio label {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 100%;
        text-align: center;
        cursor: pointer;
        padding: 0.42rem 0.35rem;
        border: 1px solid #ced4da;
        margin-bottom: 0;
        font-weight: 600;
        font-size: 0.77rem;
        color: #495057;
        background: #fff;
        transition: background 0.12s, color 0.12s;
        user-select: none;
      }
      .viz-mode-group .radio:not(:first-child) label { border-left: none; }
      .viz-mode-group .radio:first-child  label { border-radius: 6px 0 0 6px; }
      .viz-mode-group .radio:last-child   label { border-radius: 0 6px 6px 0; }
      .viz-mode-group .radio input[type='radio'] { display: none; }
      .viz-mode-group .radio:has(input:checked) label {
        background: #2c3e50;
        color: #fff;
        border-color: #2c3e50;
      }

      /* ── Palette swatch strip ────────────────────────────── */
      .palette-swatch {
        display: flex;
        height: 12px;
        border-radius: 3px;
        overflow: hidden;
        margin: 2px 0 5px;
        border: 1px solid rgba(0,0,0,0.08);
      }
      .palette-swatch span { flex: 1; display: block; }

      /* ── Raster stat boxes in card footer ────────────────── */
      .raster-stat-row {
        display: flex;
        gap: 5px;
        flex-wrap: wrap;
        padding: 2px 0;
      }
      .raster-stat-box {
        display: flex;
        align-items: center;
        gap: 6px;
        background: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 5px;
        padding: 4px 9px;
        min-width: 80px;
        flex: 1 1 auto;
      }
      .raster-stat-box .rsb-icon { font-size: 0.85rem; flex-shrink: 0; }
      .raster-stat-box .rsb-label {
        font-size: 0.64rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: #6c757d;
        line-height: 1;
        white-space: nowrap;
      }
      .raster-stat-box .rsb-value {
        font-size: 0.8rem;
        font-weight: 600;
        color: #2c3e50;
        line-height: 1.3;
        max-width: 120px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      /* ── Regression axis panel in tab body ───────────────── */
      .reg-axis-panel {
        background: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 6px;
        padding: 0.5rem 0.75rem 0.1rem;
        margin-bottom: 0.55rem;
      }
      .reg-axis-panel .ctrl-group-label { margin-top: 0; }

      /* ── Project folder header strip ─────────────────────── */
      .folder-header-strip {
        padding: 6px 10px 8px;
        border-bottom: 1px solid #dee2e6;
        background: #fff;
      }
      .folder-header-strip .ctrl-group-label { margin-top: 0; margin-bottom: 3px; }
    "))),
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
                               global_folder    = dl_out$folder,
                               aoi_region       = dl_out$region,
                               download_seasons = dl_out$seasons)
  
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

  # 5. Monitoring Module
  # Farm-level seasonal monitoring with DuckDB persistence
  mod_monitoring_server("mon",
                        global_folder = dl_out$folder,
                        aoi_region    = dl_out$region,
                        l3_regions_meta = l3_regions_meta)
}

shiny::shinyApp(ui, server)
