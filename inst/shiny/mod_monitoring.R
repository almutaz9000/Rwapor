# mod_monitoring.R
# Farm Monitoring Module – WaPOR Seasonal Performance Dashboard
# Fetches WaPOR data per farm polygon, stores to DuckDB, and provides
# agronomic stress visualisations.

# ── Load helper functions ──────────────────────────────────────────────────────
if (exists(".wapor_source_app_module", mode = "function")) {
  .wapor_source_app_module("monitoring_helpers.R", local = TRUE)
} else {
  source(system.file("shiny", "monitoring_helpers.R", package = "Rwapor"), local = TRUE)
}

# ── Constants ──────────────────────────────────────────────────────────────────

# Default WaPOR variables recommended for crop monitoring.
# RET is included so the default stress dashboard can compute ETa/ETp.
.MON_DEFAULT_VARS <- c("L1-AETI-D", "L1-RET-D", "L1-T-D", "L1-E-D", "L1-NPP-D")

# L3 products are offered when the farm layer or shared AOI overlaps an L3 area.
.MON_L3_DEFAULT_VARS <- c("L3-AETI-D", "L3-T-D", "L3-E-D", "L3-NPP-D")

# API vars that are useful for field monitoring.
.MON_ALL_VARS <- unname(sort(unique(c(names(Rwapor::WAPOR3_VARS), names(Rwapor::AGERA5_VARS)))))

.MON_AETI_D_VARS <- grep("-AETI-D$", .MON_ALL_VARS, value = TRUE)
.MON_RET_D_VARS  <- grep("-RET-D$",  .MON_ALL_VARS, value = TRUE)
.MON_T_D_VARS    <- grep("-T-D$",    .MON_ALL_VARS, value = TRUE)
.MON_E_D_VARS    <- grep("-E-D$",    .MON_ALL_VARS, value = TRUE)
.MON_NPP_D_VARS  <- grep("-NPP-D$",  .MON_ALL_VARS, value = TRUE)

.mon_variable_choices <- function(vars = .MON_ALL_VARS) {
  labels <- vapply(vars, function(v) {
    meta <- tryCatch(Rwapor::wapor_variable_metadata(v), error = function(e) NULL)
    if (!is.null(meta) && !is.null(meta$long_name)) {
      sprintf("%s - %s", v, meta$long_name)
    } else {
      v
    }
  }, character(1), USE.NAMES = FALSE)
  as.list(stats::setNames(vars, labels))
}

.mon_l3_region_choices <- function(codes, l3_regions_meta) {
  as.list(stats::setNames(
    codes,
    vapply(codes, function(code) {
      r <- l3_regions_meta[[code]]
      if (!is.null(r)) sprintf("%s - %s (%s)", r$country, r$name, code) else code
    }, character(1), USE.NAMES = FALSE)
  ))
}

.mon_first_available_var <- function(ts_df, candidates) {
  vars <- unique(ts_df$variable)
  match <- candidates[candidates %in% vars]
  if (length(match) == 0) NULL else match[1]
}

.mon_records_for_family <- function(ts_df, candidates) {
  var <- .mon_first_available_var(ts_df, candidates)
  if (is.null(var)) return(ts_df[0, , drop = FALSE])
  ts_df[ts_df$variable == var, , drop = FALSE]
}

# Stress thresholds (ETa/ETp based)
.MON_STRESS_HIGH   <- 0.8   # below this: moderate stress
.MON_STRESS_SEVERE <- 0.6   # below this: severe stress

# ── UI ─────────────────────────────────────────────────────────────────────────

mod_monitoring_ui <- function(id, l3_region_choices = NULL) {
  ns <- shiny::NS(id)
  if (is.null(l3_region_choices)) {
    l3_regions_meta <- Rwapor::L3_REGIONS
    l3_region_choices <- .mon_l3_region_choices(names(l3_regions_meta), l3_regions_meta)
  }

  bslib::page_fillable(
    padding = 0,

    bslib::layout_sidebar(
      fillable = TRUE,

      # ── SIDEBAR ──────────────────────────────────────────────────────────────
      sidebar = bslib::sidebar(
        width   = 330,
        open    = TRUE,
        gap     = "0.3rem",
        padding = "0.5rem",

        bslib::accordion(
          open     = c("Farm Layer", "Season Setup"),
          multiple = TRUE,

          # 0 · Project Management ───────────────────────────────────────────
          bslib::accordion_panel(
            "Project Management", icon = shiny::icon("folder-tree"),
            shiny::tags$span("Data Source", class = "ctrl-group-label"),
            shiny::radioButtons(
              ns("mon_source"), NULL,
              choices = c("DuckDB Database" = "db", "Project Folder (Live)" = "folder"),
              selected = "db",
              inline = TRUE
            ),
            
            shiny::tags$span("Base Directory", class = "ctrl-group-label"),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::textInput(
                  ns("project_dir_path"), NULL,
                  value       = "projects",
                  placeholder = "Folder for project files/data"
                )
              ),
              shinyFiles::shinyDirButton(
                ns("browse_proj_dir"), label = "",
                title  = "Select project base directory",
                icon   = shiny::icon("folder-open"),
                class  = "btn-outline-secondary btn-sm",
                style  = "padding:0.37rem 0.6rem;"
              )
            ),

            shiny::tags$span("Project Name", class = "ctrl-group-label"),
            shiny::textInput(
              ns("project_name"), NULL,
              placeholder = "e.g. Sudan_Savola_2024"
            ),
            shiny::div(
              class = "btn-group w-100",
              shiny::actionButton(
                ns("btn_save_project"), "Save",
                icon = shiny::icon("floppy-disk"),
                class = "btn-outline-primary btn-sm"
              ),
              shiny::actionButton(
                ns("btn_load_project"), "Load",
                icon = shiny::icon("folder-open"),
                class = "btn-outline-secondary btn-sm"
              )
            ),
            shiny::uiOutput(ns("project_list_ui")),
            shiny::helpText("Manage project-specific settings and database paths.")
          ),

          # 1 · Farm Layer ────────────────────────────────────────────────────
          bslib::accordion_panel(
            "Farm Layer", icon = shiny::icon("draw-polygon"),


            shiny::tags$span("Upload vector file", class = "ctrl-group-label"),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::textInput(
                  ns("farm_path"), NULL,
                  placeholder = "GeoJSON / GPKG / SHP"
                )
              ),
              shiny::uiOutput(ns("fav_farm_btn_ui")),
              shinyFiles::shinyFilesButton(
                ns("browse_farm"), label = "",
                title  = "Select farm vector file",
                icon   = shiny::icon("folder-open"),
                class  = "btn-outline-secondary btn-sm",
                style  = "padding:0.37rem 0.6rem;",
                multiple = FALSE
              )
            ),
            shiny::uiOutput(ns("fav_farm_list_ui")),
            shiny::uiOutput(ns("farm_info_ui")),

            shiny::tags$hr(class = "ctrl-divider"),
            shiny::tags$span("Crop column", class = "ctrl-group-label"),
            shiny::uiOutput(ns("crop_col_ui")),

            shiny::tags$span("Farm label column (optional)", class = "ctrl-group-label"),
            shiny::uiOutput(ns("label_col_ui"))
          ),

          # 2 · Season Setup ──────────────────────────────────────────────────
          bslib::accordion_panel(
            "Season Setup", icon = shiny::icon("seedling"),

            shiny::tags$span("Sowing date", class = "ctrl-group-label"),
            shiny::dateInput(
              ns("sowing_date"), NULL,
              value  = Sys.Date() - 180,
              format = "yyyy-mm-dd"
            ),

            shiny::tags$span("End of monitoring (harvest / today)", class = "ctrl-group-label"),
            shiny::dateInput(
              ns("harvest_date"), NULL,
              value  = Sys.Date(),
              format = "yyyy-mm-dd"
            ),

            shiny::helpText(
              shiny::icon("info-circle"),
              " Only missing dekads are fetched on subsequent Monitor runs.",
              style = "font-size:0.78rem;"
            ),

            shiny::hr(class = "ctrl-divider"),
            shiny::tags$div(
              style = "margin-top:0.5rem; background: rgba(52, 152, 219, 0.05); padding: 0.5rem; border-radius: 4px; border: 1px solid rgba(52, 152, 219, 0.1);",
              shiny::tags$strong("Per-Farm Seasonal Override", style = "font-size: 0.82rem; color: #2c3e50; display: block; margin-bottom: 0.3rem;"),
              shiny::tags$span("Farm Start Date Column", class = "ctrl-group-label"),
              shiny::uiOutput(ns("start_date_col_ui")),
              shiny::tags$span("Farm End Date Column", class = "ctrl-group-label"),
              shiny::uiOutput(ns("end_date_col_ui")),
              shiny::helpText(
                shiny::icon("circle-info"),
                " Use these if each farm has its own sowing/harvest dates. The main 'Monitor' run will still fetch the full bulk range to ensure data availability.",
                style = "font-size: 0.72rem; margin-top: 5px; line-height: 1.1;"
              )
            )
          ),

          # 3 · WaPOR Variables ───────────────────────────────────────────────
          bslib::accordion_panel(
            "WaPOR Variables", icon = shiny::icon("layer-group"),

            shiny::selectizeInput(
              ns("mon_vars"), NULL,
              choices  = .mon_variable_choices(),
              selected = .MON_DEFAULT_VARS,
              multiple = TRUE,
              options  = list(
                placeholder = "Select monitoring variables",
                plugins = list("remove_button")
              )
            ),
            shiny::uiOutput(ns("mon_l3_availability_ui")),
            shiny::conditionalPanel(
              condition = "input.mon_vars && input.mon_vars.some(v => v.startsWith('L3-'))",
              ns = ns,
              shiny::selectInput(
                ns("mon_l3_region"), "L3 Region",
                choices = l3_region_choices
              ),
              shiny::uiOutput(ns("mon_l3_region_message")),
              shiny::helpText("Required when monitoring with L3 variables.")
            ),
            shiny::helpText(
              "AETI + RET → ETa/ETp stress index.  T + E → transpiration fraction.",
              style = "font-size:0.77rem; color:#6c757d;"
            )
          ),

          # 4 · Database ──────────────────────────────────────────────────────
          bslib::accordion_panel(
            "Database", icon = shiny::icon("database"),

            shiny::tags$span("DuckDB file path", class = "ctrl-group-label"),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::textInput(
                  ns("db_path"), NULL,
                  value       = file.path(getwd(), "monitoring.duckdb"),
                  placeholder = "Path to .duckdb file"
                )
              ),
              shiny::uiOutput(ns("fav_db_btn_ui")),
              shinyFiles::shinyFilesButton(
                ns("browse_db"), label = "",
                title  = "Select or create DuckDB file",
                icon   = shiny::icon("folder-open"),
                class  = "btn-outline-secondary btn-sm",
                style  = "padding:0.37rem 0.6rem;",
                multiple = FALSE
              )
            ),
            shiny::uiOutput(ns("fav_db_list_ui")),
            shiny::uiOutput(ns("db_status_ui")),

            shiny::checkboxInput(
              ns("also_save_rasters"),
              "Also clip & save raster layers to database",
              value = TRUE
            ),
            shiny::helpText(
              "Rasters are stored as compressed blobs (~5-20 MB each). Disable if disk space is limited.",
              style = "font-size:0.77rem; color:#6c757d;"
            )
          ),

          # 5 · Enhanced Analysis ─────────────────────────────────────────────
          bslib::accordion_panel(
            "Enhanced Analysis", icon = shiny::icon("chart-area"),

            shiny::tags$span("Threshold percentile (removes low values)", class = "ctrl-group-label"),
            shiny::sliderInput(
              ns("threshold_pct"),
              NULL,
              min = 0, max = 50, value = 5, step = 1,
              post = "%"
            ),
            shiny::helpText(
              "Removes pixels below this percentile (e.g., 5% removes bare soil).",
              style = "font-size:0.77rem; color:#6c757d;"
            ),
            
            shiny::tags$hr(class = "ctrl-divider"),
            
            shiny::actionButton(
              ns("btn_recalculate"), "Recalculate Stats with Threshold",
              icon  = shiny::icon("calculator"),
              class = "btn-outline-primary w-100 btn-sm"
            ),
            shiny::helpText(
              "Recalculates zonal stats from saved rasters using new threshold.",
              style = "font-size:0.77rem; color:#6c757d;"
            ),
            
            shiny::tags$hr(class = "ctrl-divider"),
            
            shiny::actionButton(
              ns("btn_plot_rasters"), "Plot Raster Time Series",
              icon  = shiny::icon("chart-line"),
              class = "btn-outline-info w-100 btn-sm"
            ),
            shiny::helpText(
              "View time series with mean ± std ribbons for selected farm.",
              style = "font-size:0.77rem; color:#6c757d;"
            ),
            
            shiny::tags$hr(class = "ctrl-divider"),
            
            shiny::actionButton(
              ns("btn_zoom_farms"), "Zoom Map to Farm Extent",
              icon  = shiny::icon("expand"),
              class = "btn-outline-secondary w-100 btn-sm"
            ),

            shiny::tags$hr(class = "ctrl-divider"),
            
            shiny::actionButton(
              ns("btn_seasonal_raster"), "Produce Seasonal Rasters",
              icon  = shiny::icon("mountain-sun"),
              class = "btn-outline-success w-100 btn-sm"
            ),
            shiny::helpText(
              "Aggregates dekadal rasters based on per-farm start/end columns.",
              style = "font-size:0.77rem; color:#6c757d;"
            ),
            
            shiny::tags$hr(class = "ctrl-divider"),
            
            # --- New Seasonal Adaptive Masking Section ---
            shiny::tags$div(
              style = "background: rgba(46, 204, 113, 0.05); padding: 0.6rem; border-radius: 6px; border: 1px solid rgba(46, 204, 113, 0.2); margin-top: 5px;",
              shiny::tags$strong("Seasonal Adaptive Masking", style = "font-size: 0.82rem; color: #27ae60; display: block; margin-bottom: 0.4rem;"),
              shiny::selectInput(
                ns("mask_ref_var"), "Reference Variable",
                choices = c("Actual ET (L3)" = "L3-AETI-D", "Net Primary Prod (L3)" = "L3-NPP-D"),
                selected = "L3-AETI-D"
              ),
              shiny::sliderInput(
                ns("mask_threshold"), "Discard bare soil (bottom %)",
                min = 0, max = 80, value = 40, step = 5, post = "%"
              ),
              shiny::actionButton(
                ns("btn_recalculate_seasonal"), "Apply Seasonal Mask",
                icon  = shiny::icon("wand-magic-sparkles"),
                class = "btn-success w-100 btn-sm mt-2",
                style = "color: white; font-weight: 500;"
              ),
              shiny::helpText(
                "Creates a mask from total seasonal sum to isolate cultivated areas.",
                style = "font-size:0.72rem; margin-top: 5px; color:#2c3e50;"
              )
            )
          ),

          # 6 · Run ───────────────────────────────────────────────────────────
          bslib::accordion_panel(
            "Monitor", icon = shiny::icon("satellite-dish"),

            shiny::actionButton(
              ns("btn_monitor"), "Monitor / Update",
              icon  = shiny::icon("satellite-dish"),
              class = "btn-success w-100",
              style = "font-weight:600; font-size:0.9rem;"
            ),
            shiny::br(),
            shiny::uiOutput(ns("monitor_progress_ui")),
            shiny::br(),
            shiny::actionButton(
              ns("btn_load_db"), "Load from Database",
              icon  = shiny::icon("database"),
              class = "btn-outline-primary w-100 btn-sm"
            ),
            shiny::actionButton(
              ns("btn_clear_db"), "Clear Database",
              icon  = shiny::icon("trash"),
              class = "btn-outline-danger w-100 btn-sm mt-1"
            )
          )
        ) # /accordion
      ), # /sidebar

      # ── MAIN PANEL ──────────────────────────────────────────────────────────
      bslib::navset_card_tab(
        id = ns("main_tabs"),

        # Tab 1 · Farm Map ────────────────────────────────────────────────────
        bslib::nav_panel(
          "Farm Map", icon = shiny::icon("map"),
          bslib::card_body(
            fillable = TRUE,
            shiny::div(
              class = "inline-row mb-2",
              shiny::div(
                class = "flex-1",
                shiny::selectInput(
                  ns("map_indicator"), "Colour farms by",
                  choices = c(
                    "Latest ETa/ETp (stress index)"     = "eta_etp",
                    "Cumulative AETI (mm)"               = "cum_aeti",
                    "Mean Transpiration Fraction (T/ET)" = "t_frac",
                    "Latest NPP"                         = "npp_latest"
                  ),
                  selected = "eta_etp"
                )
              ),
              shiny::div(
                style = "width:120px;",
                shiny::selectInput(
                  ns("map_period_agg"), "Period",
                  choices = c("Last dekad" = "last", "Last 30d" = "30d",
                              "Season to date" = "season"),
                  selected = "season"
                )
              )
            ),
            leaflet::leafletOutput(ns("farm_map"), height = "calc(100vh - 250px)") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50")
          )
        ),

        # Tab 2 · Time Series ─────────────────────────────────────────────────
        bslib::nav_panel(
          "Time Series", icon = shiny::icon("chart-line"),
          bslib::card_body(
            fillable = TRUE,
            shiny::div(
              class = "inline-row mb-2",
              shiny::div(
                class = "flex-1",
                shiny::uiOutput(ns("ts_farm_select_ui"))
              ),
              shiny::div(
                class = "flex-1",
                shiny::selectInput(
                  ns("ts_variable"), "Variable",
                  choices = .MON_DEFAULT_VARS,
                  selected = .MON_DEFAULT_VARS[1]
                )
              ),
              shiny::div(
                style = "width: 150px;",
                shiny::selectInput(
                  ns("ts_derived"), "Derived Indicator",
                  choices = c(
                    "Raw variable"              = "raw",
                    "ETa/ETp (water stress)"    = "eta_etp",
                    "T/(T+E) transpiration frac"= "t_frac",
                    "Cum. AETI from sowing"     = "cum_aeti"
                  ),
                  selected = "raw"
                )
              )
            ),
            shiny::plotOutput(ns("plot_ts"), height = "420px") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50"),
            shiny::hr(style = "margin:6px 0;"),
            shiny::div(
              style = "display:flex; gap:8px;",
              shiny::downloadButton(ns("dl_ts_png"), "PNG",
                                    class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_ts_csv"), "CSV",
                                    class = "btn-sm btn-outline-secondary")
            )
          )
        ),

        # Tab 3 · Raster View ─────────────────────────────────────────────────
        bslib::nav_panel(
          "Raster View", icon = shiny::icon("image"),
          bslib::card_body(
            fillable = TRUE,
            shiny::div(
              class = "inline-row mb-2",
              shiny::div(
                class = "flex-1",
                shiny::uiOutput(ns("rast_farm_ui"))
              ),
              shiny::div(
                class = "flex-1",
                shiny::uiOutput(ns("rast_var_ui"))
              ),
              shiny::div(
                class = "flex-1",
                shiny::uiOutput(ns("rast_date_ui"))
              ),
              shiny::div(
                style = "width:120px;",
                shiny::selectInput(
                  ns("rast_palette"), "Palette",
                  choices  = c("viridis", "magma", "RdYlGn", "RdYlBu", "Spectral"),
                  selected = "RdYlGn"
                )
              )
            ),
            leaflet::leafletOutput(ns("raster_map"), height = "calc(100vh - 300px)") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50")
          )
        ),

        # Tab 4 · Stress Dashboard ────────────────────────────────────────────
        bslib::nav_panel(
          "Stress Dashboard", icon = shiny::icon("triangle-exclamation"),
          bslib::card_body(
            fillable = FALSE,
            shiny::uiOutput(ns("stress_valueboxes_ui")),
            shiny::hr(),
            shiny::h6("Farm Performance Summary", class = "text-muted"),
            DT::DTOutput(ns("stress_table"))
          )
        ),

        # Tab 5 · Data Table ──────────────────────────────────────────────────
        bslib::nav_panel(
          "Data Table", icon = shiny::icon("table"),
          bslib::card_body(
            shiny::div(
              style = "display:flex; gap:8px; margin-bottom:8px;",
              shiny::downloadButton(ns("dl_csv"), "CSV",
                                    class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_parquet"), "Parquet",
                                    class = "btn-sm btn-outline-secondary")
            ),
            DT::DTOutput(ns("tbl_data"))
          )
        )
      ) # /navset_card_tab
    ) # /layout_sidebar
  ) # /page_fillable
}


# ── SERVER ─────────────────────────────────────────────────────────────────────

mod_monitoring_server <- function(id, global_folder = reactive(NULL),
                                   aoi_region = reactive(NULL),
                                   l3_regions_meta = Rwapor::L3_REGIONS) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Reactive state ─────────────────────────────────────────────────────────
    rv <- shiny::reactiveValues(
      farms_sf       = NULL,   # sf object with farm polygons
      ts_data        = NULL,   # long data.frame from DB
      rast_layers    = list(), # named list of terra SpatRaster objects
      monitoring     = FALSE,  # TRUE while background fetch is running
      log_msgs       = character(0),
      db_con         = NULL    # open DuckDB connection
    )

    # Roots for shinyFiles
    roots <- get_shinyfiles_roots()

    # Directory picker for projects
    shinyFiles::shinyDirChoose(
      input, "browse_proj_dir", 
      roots = roots, 
      session = session
    )

    shiny::observe({
      dir_info <- input$browse_proj_dir
      if (!is.null(dir_info) && is.list(dir_info)) {
        path <- shinyFiles::parseDirPath(roots, dir_info)
        if (length(path) > 0 && nzchar(path)) {
          path <- normalizePath(path, winslash = "/", mustWork = FALSE)
          shiny::updateTextInput(session, "project_dir_path", value = path)
        }
      }
    })

    # Reactive project directory
    get_project_dir <- shiny::reactive({
      d <- input$project_dir_path
      if (is.null(d) || !nzchar(d)) d <- "projects"
      if (!dir.exists(d)) tryCatch(dir.create(d, recursive = TRUE, showWarnings = FALSE), error = function(e) NULL)
      d
    })

    # ── Helper: Refresh Time Series Data from Source ──────────────────────────
    refresh_ts_data <- function() {
      source_type <- input$mon_source
      
      if (source_type == "folder") {
        # Folder Mode: Live extraction
        pdir <- input$project_dir_path
        shiny::req(rv$farms_sf, pdir)
        
        shiny::withProgress(message = "Scanning folder & extracting stats...", value = 0, {
          rv$ts_data <- wapor_extract_stats_from_folder(
            folder = pdir,
            polygons = rv$farms_sf,
            variables = input$mon_vars,
            threshold_pct = input$threshold_pct
          )
        })
        
        if (is.null(rv$ts_data) || nrow(rv$ts_data) == 0) {
          shiny::showNotification("No matching rasters found in the project folder.", type = "warning")
        }
        
      } else {
        # Database Mode: Load from DuckDB
        db_path <- input$db_path
        if (is.null(db_path) || !file.exists(db_path)) return()
        
        tryCatch({
          con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
          on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))
          rv$ts_data <- DBI::dbGetQuery(con, 
            "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date"
          )
        }, error = function(e) {
          add_log("Error refreshing database data: ", e$message)
        })
      }
    }

    # ── Helper: append log message ─────────────────────────────────────────────
    add_log <- function(...) {
      msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste(...))
      rv$log_msgs <- c(rv$log_msgs, msg)
    }

    # ── DuckDB helpers ─────────────────────────────────────────────────────────

    open_db <- function(path) {
      if (!requireNamespace("duckdb", quietly = TRUE))
        stop("Package 'duckdb' is required for the Monitoring tab.", call. = FALSE)
      
      tryCatch({
        con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = path)
        # Use the core package function to initialize/migrate schema
        Rwapor::wapor_init_monitoring_db(con)
        con
      }, error = function(e) {
        shiny::showNotification(paste("DB error:", e$message), type = "error")
        NULL
      })
    }


    close_db <- function() {
      con <- shiny::isolate(rv$db_con)
      if (!is.null(con)) {
        tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL)
        shiny::isolate(rv$db_con <- NULL)
      }
    }

    # ── Save farm polygon geometries to DB ────────────────────────────────────
    save_farms_to_db <- function(con, farms_sf, crop_col = NULL, label_col = NULL) {
      if (is.null(con) || is.null(farms_sf) || nrow(farms_sf) == 0) return(invisible(0L))
      n_saved <- 0L
      for (i in seq_len(nrow(farms_sf))) {
        farm      <- farms_sf[i, ]
        farm_drop <- sf::st_drop_geometry(farm)
        farm_id   <- as.character(farm_drop$farm_id)

        geom_wkt  <- tryCatch(
          sf::st_as_text(sf::st_geometry(farm)[[1]]),
          error = function(e) NA_character_
        )
        crop_type <- if (!is.null(crop_col) && nzchar(crop_col %||% "") &&
                          crop_col %in% names(farm_drop)) {
          as.character(farm_drop[[crop_col]])
        } else NA_character_

        label <- if (!is.null(label_col) && nzchar(label_col %||% "") &&
                      label_col %in% names(farm_drop)) {
          as.character(farm_drop[[label_col]])
        } else farm_id

        farm_aea <- tryCatch(
          sf::st_transform(farm, crs = "+proj=aea +lat_1=20 +lat_2=60 +lat_0=40 +lon_0=0"),
          error = function(e) farm
        )
        area_ha <- tryCatch(
          as.numeric(sf::st_area(farm_aea)) / 10000,
          error = function(e) NA_real_
        )

        tryCatch({
          DBI::dbExecute(con, "
            INSERT INTO farm_polygons (farm_id, crop_type, label, area_ha, geometry_wkt, crs_epsg)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (farm_id) DO UPDATE SET
              crop_type    = EXCLUDED.crop_type,
              label        = EXCLUDED.label,
              area_ha      = EXCLUDED.area_ha,
              geometry_wkt = EXCLUDED.geometry_wkt,
              crs_epsg     = EXCLUDED.crs_epsg
          ", params = list(farm_id, crop_type, label, area_ha, geom_wkt, 4326L))
          n_saved <- n_saved + 1L
        }, error = function(e) {
          add_log(sprintf("  Warning: could not save polygon for %s: %s", farm_id, e$message))
        })
      }
      add_log(sprintf("  Saved %d farm polygon(s) to farm_polygons table.", n_saved))
      invisible(n_saved)
    }

    # Get the last fetched date per farm+variable to enable incremental updates
    get_last_dates <- function(con) {
      empty_df <- data.frame(
        farm_id   = character(),
        variable  = character(),
        last_date = as.Date(character()),
        stringsAsFactors = FALSE
      )
      if (is.null(con)) return(empty_df)
      tryCatch(
        DBI::dbGetQuery(con, "
          SELECT farm_id, variable, MAX(end_date) AS last_date
          FROM farm_timeseries
          GROUP BY farm_id, variable
        "),
        error = function(e) empty_df
      )
    }

    # ── 0. Project Management Logic ───────────────────────────────────────────
    
    # List available projects
    output$project_list_ui <- shiny::renderUI({
      pdir <- get_project_dir()
      files <- list.files(pdir, pattern = "\\.json$", full.names = FALSE)
      if (length(files) == 0) return(NULL)
      projects <- sub("\\.json$", "", files)
      shiny::selectInput(ns("sel_project"), "Existing Projects", 
                         choices = c("Select project to load..." = "", projects))
    })

    # Save Project
    shiny::observeEvent(input$btn_save_project, {
      name <- input$project_name
      pdir <- get_project_dir()
      
      if (!nzchar(name)) {
        shiny::showNotification("Enter a project name first.", type = "error")
        return()
      }
      
      # Sanitize name
      safe_name <- gsub("[^a-zA-Z0-9_]", "_", name)
      config <- list(
        project_name      = name,
        project_dir_path  = pdir,
        farm_path         = input$farm_path,
        db_path           = input$db_path,
        mon_vars          = input$mon_vars,
        mon_l3_region     = input$mon_l3_region,
        sowing_date       = as.character(input$sowing_date),
        harvest_date      = as.character(input$harvest_date),
        crop_col          = input$crop_col,
        label_col         = input$label_col,
        start_date_col    = input$start_date_col,
        end_date_col      = input$end_date_col,
        also_save_rasters = input$also_save_rasters,
        threshold_pct     = input$threshold_pct
      )
      
      jsonlite::write_json(config, file.path(pdir, paste0(safe_name, ".json")), pretty = TRUE)
      shiny::showNotification(sprintf("Project '%s' saved.", name), type = "message")
    })

    # Load Project
    shiny::observeEvent(input$btn_load_project, {
      name <- input$sel_project
      if (!nzchar(name)) {
        name <- input$project_name
      }
      if (!nzchar(name)) {
        shiny::showNotification("Select or enter a project name.", type = "error")
        return()
      }
      
      safe_name <- gsub("[^a-zA-Z0-9_]", "_", name)
      path <- file.path(project_dir, paste0(safe_name, ".json"))
      
      if (!file.exists(path)) {
        shiny::showNotification("Project file not found.", type = "error")
        return()
      }
      
      config <- jsonlite::read_json(path, simplifyVector = TRUE)
      
      # Update UI
      shiny::updateTextInput(session, "project_name", value = config$project_name %||% name)
      shiny::updateTextInput(session, "farm_path",    value = config$farm_path %||% "")
      shiny::updateTextInput(session, "db_path",      value = config$db_path %||% "")
      shiny::updateSelectizeInput(session, "mon_vars", selected = config$mon_vars)
      shiny::updateSelectInput(session, "mon_l3_region", selected = config$mon_l3_region)
      shiny::updateDateInput(session, "sowing_date",  value = as.Date(config$sowing_date %||% (Sys.Date() - 180)))
      shiny::updateDateInput(session, "harvest_date", value = as.Date(config$harvest_date %||% Sys.Date()))
      shiny::updateCheckboxInput(session, "also_save_rasters", value = config$also_save_rasters %||% TRUE)
      shiny::updateSliderInput(session, "threshold_pct", value = config$threshold_pct %||% 5)
      
      # We delay updating column selectors since they depend on farm_path being loaded
      shiny::observe({
        shiny::req(rv$farms_sf)
        shiny::updateSelectInput(session, "crop_col",       selected = config$crop_col %||% "")
        shiny::updateSelectInput(session, "label_col",      selected = config$label_col %||% "")
        shiny::updateSelectInput(session, "start_date_col", selected = config$start_date_col %||% "")
        shiny::updateSelectInput(session, "end_date_col",   selected = config$end_date_col %||% "")
      }) |> shiny::bindEvent(rv$farms_sf, once = TRUE)
      
      shiny::showNotification(sprintf("Project '%s' loaded.", name), type = "message")
    })

    # ── 4. Database logic ─────────────────────────────────────────────────────

    shinyFiles::shinyFileChoose(
      input, "browse_db", 
      roots = roots, 
      session = session,
      filetypes = c("duckdb", "db", "sqlite")
    )

    shiny::observe({
      file_info <- input$browse_db
      if (!is.null(file_info) && is.list(file_info)) {
        path <- shinyFiles::parseFilePaths(roots, file_info)$datapath
        if (length(path) > 0 && nzchar(path)) {
          path <- normalizePath(path, winslash = "/", mustWork = FALSE)
          shiny::updateTextInput(session, "db_path", value = path)
        }
      }
    })

    # Update DB Path automatically when project name changes
    shiny::observeEvent(input$project_name, {
      name <- input$project_name
      if (nzchar(name)) {
        safe_name <- gsub("[^a-zA-Z0-9_]", "_", name)
        # Check if user has a custom path or if we should default it
        # Default to a file in the projects directory or root
        current_db <- input$db_path
        if (!nzchar(current_db) || grepl("monitoring\\.duckdb$", current_db)) {
           shiny::updateTextInput(session, "db_path", value = file.path(getwd(), paste0(safe_name, ".duckdb")))
        }
      }
    })

    # ── 1. Load farm vector file ───────────────────────────────────────────────

    shinyFiles::shinyFileChoose(
      input, "browse_farm", 
      roots = roots, 
      session = session,
      filetypes = c("shp", "geojson", "gpkg", "kml", "zip")
    )

    shiny::observe({
      file_info <- input$browse_farm
      if (!is.null(file_info) && is.list(file_info)) {
        path <- shinyFiles::parseFilePaths(roots, file_info)$datapath
        if (length(path) > 0 && nzchar(path)) {
          path <- normalizePath(path, winslash = "/", mustWork = FALSE)
          shiny::updateTextInput(session, "farm_path", value = path)
        }
      }
    })

    shiny::observeEvent(input$farm_path, {
      shiny::req(input$farm_path)
      tryCatch({
        path <- input$farm_path
        if (!file.exists(path)) return()
        
        ext  <- tolower(tools::file_ext(path))
        if (ext == "zip") {
          tmp <- tempfile(); dir.create(tmp)
          utils::unzip(path, exdir = tmp)
          shp <- list.files(tmp, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)
          if (length(shp) == 0) stop("No .shp found in zip archive.")
          path <- shp[1]
        }
        sf_obj <- sf::st_read(path, quiet = TRUE)
        if (!inherits(sf::st_geometry(sf_obj), c("sfc_POLYGON", "sfc_MULTIPOLYGON")))
          sf_obj <- sf::st_cast(sf_obj, "MULTIPOLYGON")
        if (is.na(sf::st_crs(sf_obj))) sf_obj <- sf::st_set_crs(sf_obj, 4326)
        if (sf::st_crs(sf_obj)$epsg != 4326)
          sf_obj <- sf::st_transform(sf_obj, 4326)
        # Ensure unique farm ID column
        if (!"farm_id" %in% names(sf_obj))
          sf_obj$farm_id <- paste0("farm_", seq_len(nrow(sf_obj)))
        rv$farms_sf <- sf_obj
        shiny::showNotification(
          sprintf("\u2714 Loaded %d farm polygon(s)", nrow(sf_obj)),
          type = "message", duration = 5
        )
      }, error = function(e) {
        shiny::showNotification(paste("Farm file error:", e$message), type = "error")
        rv$farms_sf <- NULL
      })
    })

    # ── Farm info UI ──────────────────────────────────────────────────────────
    output$farm_info_ui <- shiny::renderUI({
      sf_obj <- rv$farms_sf
      if (is.null(sf_obj)) return(shiny::helpText("No file loaded."))
      shiny::tagList(
        shiny::helpText(
          shiny::icon("check-circle", style = "color:green;"),
          sprintf(" %d farms loaded", nrow(sf_obj)),
          style = "color:#27ae60; font-size:0.82rem;"
        )
      )
    })

    # ── Crop column selector ──────────────────────────────────────────────────
    output$crop_col_ui <- shiny::renderUI({
      sf_obj <- rv$farms_sf
      if (is.null(sf_obj)) {
        return(shiny::helpText("Load a farm file first.", style = "font-size:0.8rem;"))
      }
      cols <- setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
      shiny::selectInput(ns("crop_col"), NULL, choices = c("(none)" = "", cols))
    })

    # ── Label column selector ─────────────────────────────────────────────────
    output$label_col_ui <- shiny::renderUI({
      sf_obj <- rv$farms_sf
      if (is.null(sf_obj)) return(NULL)
      cols <- setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
      shiny::selectInput(ns("label_col"), NULL, choices = c("(none)" = "", cols))
    })

    # ── per-farm start date column selector ──────────────────────────────────
    output$start_date_col_ui <- shiny::renderUI({
      sf_obj <- rv$farms_sf
      if (is.null(sf_obj)) return(NULL)
      cols <- setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
      shiny::selectInput(ns("start_date_col"), NULL, choices = c("(none)" = "", cols))
    })

    # ── per-farm end date column selector ────────────────────────────────────
    output$end_date_col_ui <- shiny::renderUI({
      sf_obj <- rv$farms_sf
      if (is.null(sf_obj)) return(NULL)
      cols <- setdiff(names(sf_obj), attr(sf_obj, "sf_column"))
      shiny::selectInput(ns("end_date_col"), NULL, choices = c("(none)" = "", cols))
    })

    # ── DB status UI ──────────────────────────────────────────────────────────
    output$db_status_ui <- shiny::renderUI({
      shiny::req(input$db_path)
      path <- input$db_path
      if (file.exists(path)) {
        shiny::tagList(
          shiny::helpText(
            shiny::icon("circle-check", style = "color:green;"),
            " Database found",
            style = "color:#27ae60; font-size:0.8rem;"
          )
        )
      } else {
        shiny::helpText(
          shiny::icon("circle-info"),
          " Will be created on first Monitor run.",
          style = "font-size:0.8rem;"
        )
      }
    })

    # ── Monitor progress UI ───────────────────────────────────────────────────
    output$monitor_progress_ui <- shiny::renderUI({
      if (length(rv$log_msgs) == 0) return(NULL)
      last_msgs <- tail(rv$log_msgs, 8)
      shiny::div(
        class = "ts-save-panel",
        shiny::tags$span("Progress", class = "save-title"),
        shiny::tags$pre(
          paste(last_msgs, collapse = "\n"),
          style = "font-size:0.72rem; margin:0; white-space:pre-wrap; max-height:150px; overflow-y:auto;"
        )
      )
    })

    # ── 2. MONITOR BUTTON ─────────────────────────────────────────────────────
    monitoring_l3_aoi <- shiny::reactive({
      farms_sf <- rv$farms_sf
      if (!is.null(farms_sf) && nrow(farms_sf) > 0) return(farms_sf)
      aoi_region()
    })

    monitoring_period <- shiny::reactive({
      start <- input$sowing_date %||% (Sys.Date() - 180)
      end   <- input$harvest_date %||% Sys.Date()
      as.character(c(start, end))
    })

    detected_l3_regions <- shiny::reactive({
      reg <- monitoring_l3_aoi()
      if (is.null(reg)) {
        return(list(codes = NULL, status = "no_aoi", message = "No farm layer or shared AOI defined"))
      }

      if (is_l3_code(reg)) {
        return(list(codes = reg, status = "success", message = NULL))
      }

      reg_info <- tryCatch(
        Rwapor::wapor_parse_region(reg),
        error = function(e) list(error = e$message)
      )

      if (is.null(reg_info)) {
        return(list(codes = NULL, status = "parse_error", message = "Could not parse monitoring AOI"))
      }
      if (!is.null(reg_info$error)) {
        return(list(codes = NULL, status = "parse_error", message = reg_info$error))
      }

      codes <- tryCatch(
        Rwapor::wapor_guess_region("L3-AETI-D", reg_info, monitoring_period()),
        error = function(e) paste0("Detection error: ", e$message)
      )

      if (is.character(codes) && length(codes) == 1 && !grepl("^[A-Z]{3}$", codes)) {
        return(list(codes = NULL, status = "detection_error", message = codes))
      }
      if (is.null(codes) || length(codes) == 0) {
        return(list(codes = NULL, status = "no_overlap", message = "No L3 regions detected"))
      }

      list(codes = codes, status = "success", message = NULL)
    })

    shiny::observe({
      result <- detected_l3_regions()
      codes <- result$codes
      if (is.null(codes) || length(codes) == 0) return()

      choices <- .mon_l3_region_choices(codes, l3_regions_meta)
      current <- input$mon_l3_region %||% ""
      selected <- if (current %in% codes) current else codes[1]

      shiny::updateSelectInput(
        session,
        "mon_l3_region",
        choices = choices,
        selected = selected
      )
    })

    output$mon_l3_availability_ui <- shiny::renderUI({
      result <- detected_l3_regions()
      codes <- result$codes
      has_l3_selected <- any(grepl("^L3-", input$mon_vars %||% character(0)))

      if (has_l3_selected) return(NULL)
      if (is.null(codes) || length(codes) == 0 || result$status != "success") return(NULL)

      shiny::div(
        class = "alert alert-info mt-2",
        style = "font-size:0.82rem; padding:0.5rem;",
        shiny::icon("circle-info"),
        sprintf(
          " L3 data overlap this monitoring AOI (%s). Select L3 variables above to use them.",
          paste(codes, collapse = ", ")
        )
      )
    })

    output$mon_l3_region_message <- shiny::renderUI({
      result <- detected_l3_regions()
      codes <- result$codes
      status <- result$status
      msg <- result$message

      if (!any(grepl("^L3-", input$mon_vars %||% character(0)))) return(NULL)

      if (status == "no_aoi") {
        return(shiny::div(
          class = "alert alert-info mt-2",
          style = "font-size:0.82rem; padding:0.5rem;",
          shiny::icon("info-circle"),
          " Load a farm layer or define an AOI in the Download tab to auto-detect L3 regions."
        ))
      }

      if (status == "no_overlap") {
        return(shiny::div(
          class = "alert alert-warning mt-2",
          style = "font-size:0.82rem; padding:0.5rem;",
          shiny::icon("triangle-exclamation"),
          " No L3 regions overlap this monitoring AOI. Use L1/L2 variables or adjust the AOI."
        ))
      }

      if (status %in% c("detection_error", "parse_error")) {
        return(shiny::div(
          class = "alert alert-danger mt-2",
          style = "font-size:0.82rem; padding:0.5rem;",
          shiny::icon("exclamation-circle"),
          " L3 detection failed. Select an L3 region manually.",
          shiny::br(),
          shiny::span(style = "font-size:0.75rem;", msg)
        ))
      }

      if (!is.null(codes) && length(codes) == 1) {
        r_meta <- l3_regions_meta[[codes[1]]]
        region_name <- if (!is.null(r_meta)) sprintf("%s - %s", r_meta$country, r_meta$name) else codes[1]
        return(shiny::div(
          class = "alert alert-success mt-2",
          style = "font-size:0.82rem; padding:0.5rem;",
          shiny::icon("circle-check"),
          sprintf(" Auto-selected: %s", region_name)
        ))
      }

      if (!is.null(codes) && length(codes) > 1) {
        return(shiny::div(
          class = "alert alert-warning mt-2",
          style = "font-size:0.82rem; padding:0.5rem;",
          shiny::icon("triangle-exclamation"),
          sprintf(" Multiple L3 regions overlap (%s). Select the source region for monitoring.", paste(codes, collapse = ", "))
        ))
      }

      NULL
    })

    shiny::observeEvent(input$btn_monitor, {
      shiny::req(rv$farms_sf)
      shiny::req(length(input$mon_vars) > 0)
      shiny::req(!isTRUE(rv$monitoring))

      source_type <- input$mon_source
      
      if (source_type == "folder") {
        # --- Folder Mode Flow ---
        add_log("Starting local folder scan & extraction...")
        rv$monitoring <- TRUE
        tryCatch({
          refresh_ts_data()
          add_log("Folder scan complete.")
        }, error = function(e) {
          add_log("Extraction error: ", e$message)
        }, finally = {
          rv$monitoring <- FALSE
        })
        return()
      }

      # --- Database Mode Flow (Existing) ---
      shiny::req(input$db_path)

      farms_sf     <- rv$farms_sf
      sel_vars     <- input$mon_vars
      has_l3_vars  <- any(grepl("^L3-", sel_vars))
      l3_region    <- if (has_l3_vars) input$mon_l3_region else NULL
      db_path      <- input$db_path
      save_rasters <- isTRUE(input$also_save_rasters)
      
      period <- as.character(c(input$sowing_date, input$harvest_date))

      if (has_l3_vars && !is_l3_code(l3_region)) {
        shiny::showNotification("Select an L3 region before monitoring with L3 variables.", type = "error")
        return()
      }

      rv$monitoring <- TRUE
      rv$log_msgs   <- character(0)
      add_log("Starting monitoring run (Generalized)...")

      tryCatch({
        # Open DB
        con <- open_db(db_path)
        if (is.null(con)) { rv$monitoring <- FALSE; return() }
        
        # 1. Save geometries/metadata to DB
        save_farms_to_db(con, farms_sf, input$crop_col, input$label_col)

        # 2. Run core monitoring logic from package
        res <- Rwapor::wapor_run_monitoring(
          con          = con,
          farms_sf     = farms_sf,
          variables    = sel_vars,
          period       = period,
          save_rasters = save_rasters,
          l3_region    = l3_region,
          log_fn       = add_log
        )

        add_log(sprintf("Done. %d new records inserted.", res$total_ts))
        shiny::showNotification(
          sprintf("\u2714 Monitoring updated: %d new records", res$total_ts),
          type = "message", duration = 5
        )

        # Read back full dataset
        rv$ts_data <- DBI::dbGetQuery(con, "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date")
        DBI::dbDisconnect(con, shutdown = TRUE)

      }, error = function(e) {
        add_log(sprintf("FATAL: %s", e$message))
        shiny::showNotification(paste("Monitor error:", e$message), type = "error")
      }, finally = {
        rv$monitoring <- FALSE
      })
    })


    # ── 3. Load from DB button ────────────────────────────────────────────────
    shiny::observeEvent(input$btn_load_db, {
      shiny::req(input$db_path, file.exists(input$db_path))
      tryCatch({
        con <- open_db(input$db_path)
        if (is.null(con)) return()

        # Load timeseries
        rv$ts_data <- DBI::dbGetQuery(con,
          "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date")

        # Restore farm polygons from DB if not already loaded
        if (is.null(rv$farms_sf)) {
          poly_df <- tryCatch(
            DBI::dbGetQuery(con,
              "SELECT farm_id, crop_type, label, area_ha, geometry_wkt, crs_epsg
               FROM farm_polygons"),
            error = function(e) NULL
          )
          if (!is.null(poly_df) && nrow(poly_df) > 0 &&
              !is.null(poly_df$geometry_wkt) && any(!is.na(poly_df$geometry_wkt))) {
            tryCatch({
              geoms <- sf::st_as_sfc(poly_df$geometry_wkt,
                                     crs = as.integer(poly_df$crs_epsg[1] %||% 4326L))
              rv$farms_sf <- sf::st_sf(
                farm_id   = poly_df$farm_id,
                crop_type = poly_df$crop_type,
                label     = poly_df$label,
                area_ha   = poly_df$area_ha,
                geometry  = geoms
              )
              shiny::showNotification(
                sprintf("\u2714 Restored %d farm polygon(s) from DB.", nrow(poly_df)),
                type = "message", duration = 4
              )
            }, error = function(e) {
              message("Could not restore farm polygons from DB: ", e$message)
            })
          }
        }

        DBI::dbDisconnect(con, shutdown = TRUE)
        shiny::showNotification(
          sprintf("\u2714 Loaded %d records from DB.", nrow(rv$ts_data)),
          type = "message", duration = 4
        )
      }, error = function(e) {
        shiny::showNotification(paste("Load error:", e$message), type = "error")
      })
    })

    # ── 4. Clear DB button ────────────────────────────────────────────────────
    shiny::observeEvent(input$btn_clear_db, {
      shiny::req(input$db_path)
      tryCatch({
        path <- input$db_path
        if (file.exists(path)) file.remove(path)
        rv$ts_data <- NULL
        rv$log_msgs <- character(0)
        shiny::showNotification("\u2714 Database cleared.", type = "message", duration = 3)
      }, error = function(e) {
        shiny::showNotification(paste("Clear error:", e$message), type = "error")
      })
    })

    # ── 5. Recalculate Stats with Threshold ───────────────────────────────────
    shiny::observeEvent(input$btn_recalculate, {
      shiny::req(rv$farms_sf, input$db_path, input$threshold_pct)
      
      if (!file.exists(input$db_path)) {
        shiny::showNotification("Database not found.", type = "error")
        return()
      }
      
      con <- tryCatch(
        duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
        error = function(e) {
          shiny::showNotification(paste("DB error:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(con)) return()
      
      # Check if rasters exist
      n_rasters <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM monitoring_rasters")$n
      if (n_rasters == 0) {
        # Fallback check
        n_rasters <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM farm_rasters")$n
      }
      
      if (n_rasters == 0) {
        DBI::dbDisconnect(con, shutdown = TRUE)
        shiny::showNotification(
          "No saved rasters found. Run monitoring with 'Save rasters' enabled first.",
          type = "warning", duration = 8
        )
        return()
      }
      
      shiny::withProgress(message = "Recalculating stats...", {
        total_updated <- 0
        for (i in seq_len(nrow(rv$farms_sf))) {
          farm_id <- as.character(rv$farms_sf$farm_id[i])
          farm_geom <- rv$farms_sf[i, ]
          
          updated_df <- tryCatch(
            wapor_recalculate_stats_from_rasters(
              con, farm_id, farm_geom, input$threshold_pct
            ),
            error = function(e) {
              message(sprintf("Error for farm %s: %s", farm_id, e$message))
              NULL
            }
          )
          total_updated <- total_updated + if (!is.null(updated_df)) nrow(updated_df) else 0L
          shiny::incProgress(1 / nrow(rv$farms_sf), 
                            detail = sprintf("Farm %d/%d", i, nrow(rv$farms_sf)))
        }
        
        # Reload data
        rv$ts_data <- DBI::dbGetQuery(con, 
          "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date"
        )
        
        shiny::showNotification(
          sprintf("\u2714 Recalculated %d records with %d%% threshold", 
                  total_updated, input$threshold_pct),
          type = "message", duration = 5
        )
      })
      
      DBI::dbDisconnect(con, shutdown = TRUE)
    })

    # ── 6. Plot Raster Time Series ────────────────────────────────────────────
    shiny::observeEvent(input$btn_plot_rasters, {
      shiny::req(input$db_path)
      
      if (!file.exists(input$db_path)) {
        shiny::showNotification("Database not found.", type = "error")
        return()
      }
      
      # Open database to get available data
      con <- tryCatch(
        duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
        error = function(e) {
          shiny::showNotification(paste("DB error:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(con)) return()
      
      # Get available data
      available <- wapor_get_available_raster_data(con)
      DBI::dbDisconnect(con, shutdown = TRUE)
      
      # Check if any data available
      if (length(available$farms) == 0 || length(available$variables) == 0) {
        shiny::showNotification(
          "No saved rasters found. Run monitoring with 'Save rasters' enabled first.",
          type = "warning", duration = 8
        )
        return()
      }
      
      # Show modal with selection controls
      shiny::showModal(shiny::modalDialog(
        title = "📊 Plot Raster Time Series",
        size = "l",
        easyClose = FALSE,
        
        shiny::fluidRow(
          shiny::column(
            width = 6,
            shiny::h4("Select Farms"),
            shiny::checkboxInput(
              ns("plot_select_all_farms"),
              "Select All Farms",
              value = TRUE
            ),
            shiny::checkboxGroupInput(
              ns("plot_farms"),
              NULL,
              choices = available$farms,
              selected = if (length(available$farms) <= 5) available$farms else available$farms[1]
            )
          ),
          shiny::column(
            width = 6,
            shiny::h4("Select Variables"),
            shiny::checkboxGroupInput(
              ns("plot_variables"),
              NULL,
              choices = available$variables,
              selected = available$variables[1]
            )
          )
        ),
        
        shiny::hr(),
        
        shiny::fluidRow(
          shiny::column(
            width = 12,
            shiny::h4("Date Range (Optional)"),
            shiny::dateRangeInput(
              ns("plot_date_range"),
              NULL,
              start = if (!is.null(available$date_range)) available$date_range[1] else NULL,
              end = if (!is.null(available$date_range)) available$date_range[2] else NULL,
              min = if (!is.null(available$date_range)) available$date_range[1] else NULL,
              max = if (!is.null(available$date_range)) available$date_range[2] else NULL
            ),
            shiny::helpText("Leave as is to plot all available dates")
          )
        ),
        
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("plot_generate"), "Generate Plot", 
                             class = "btn-primary")
        )
      ))
    })
    
    # Handle "Select All Farms" checkbox
    shiny::observeEvent(input$plot_select_all_farms, {
      if (!is.null(input$plot_select_all_farms) && input$plot_select_all_farms) {
        # Get current choices
        con <- tryCatch(
          duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
          error = function(e) NULL
        )
        if (!is.null(con)) {
          available <- wapor_get_available_raster_data(con)
          DBI::dbDisconnect(con, shutdown = TRUE)
          shiny::updateCheckboxGroupInput(session, "plot_farms", selected = available$farms)
        }
      } else {
        shiny::updateCheckboxGroupInput(session, "plot_farms", selected = character(0))
      }
    })
    
    # Generate plot when button clicked
    shiny::observeEvent(input$plot_generate, {
      shiny::req(input$db_path, input$plot_farms, input$plot_variables)
      
      # Validation
      if (length(input$plot_farms) == 0) {
        shiny::showNotification("Please select at least one farm.", type = "warning")
        return()
      }
      
      if (length(input$plot_variables) == 0) {
        shiny::showNotification("Please select at least one variable.", type = "warning")
        return()
      }
      
      # Check for too many combinations
      n_combinations <- length(input$plot_farms) * length(input$plot_variables)
      if (n_combinations > 100) {
        shiny::showNotification(
          sprintf("Too many combinations (%d). Please select fewer farms or variables.", n_combinations),
          type = "warning", duration = 5
        )
        return()
      }
      
      # Open database
      con <- tryCatch(
        duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
        error = function(e) {
          shiny::showNotification(paste("DB error:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(con)) return()
      
      # Get date range (NULL if not specified)
      date_range <- NULL
      if (!is.null(input$plot_date_range)) {
        date_range <- c(input$plot_date_range[1], input$plot_date_range[2])
      }
      
      # Generate plot
      p <- tryCatch(
        wapor_plot_raster_timeseries_multi(
          con, 
          input$plot_farms, 
          input$plot_variables,
          date_range
        ),
        error = function(e) {
          shiny::showNotification(paste("Plot error:", e$message), type = "error")
          NULL
        }
      )
      
      DBI::dbDisconnect(con, shutdown = TRUE)
      
      # Remove selection modal and show plot modal
      shiny::removeModal()
      
      if (!is.null(p)) {
        # Calculate appropriate height based on number of variables
        plot_height <- max(400, min(800, 300 * length(input$plot_variables)))
        
        shiny::showModal(shiny::modalDialog(
          title = "Raster Time Series Plot",
          size = "xl",
          easyClose = TRUE,
          shiny::plotOutput(ns("raster_plot_output"), height = plot_height),
          footer = shiny::tagList(
            shiny::downloadButton(ns("download_plot"), "Download Plot"),
            shiny::modalButton("Close")
          )
        ))
        
        # Render plot
        output$raster_plot_output <- shiny::renderPlot({
          p
        })
        
        # Download handler
        output$download_plot <- shiny::downloadHandler(
          filename = function() {
            sprintf("raster_timeseries_%s.png", format(Sys.Date(), "%Y%m%d"))
          },
          content = function(file) {
            ggplot2::ggsave(file, plot = p, width = 12, height = plot_height/100, dpi = 300)
          }
        )
      }
    })

    # ── 7. Zoom Map to Farm Extent ────────────────────────────────────────────
    shiny::observeEvent(input$btn_zoom_farms, {
      shiny::req(input$db_path)
      
      if (!file.exists(input$db_path)) {
        shiny::showNotification("Database not found.", type = "error")
        return()
      }
      
      con <- tryCatch(
        duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
        error = function(e) {
          shiny::showNotification(paste("DB error:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(con)) return()
      
      extent <- tryCatch(
        wapor_get_farms_extent(con),
        error = function(e) {
          shiny::showNotification(paste("Extent error:", e$message), type = "warning")
          NULL
        }
      )
      
      DBI::dbDisconnect(con, shutdown = TRUE)
      
      if (!is.null(extent) && length(extent) == 4) {
        leaflet::leafletProxy("farm_map", session) %>%
          leaflet::fitBounds(extent[1], extent[3], extent[2], extent[4])
        
        shiny::showNotification("\u2714 Map zoomed to farms extent",
                               type = "message", duration = 2)
      } else {
        shiny::showNotification(
          "No farm extents available. Run monitoring with 'Save rasters' enabled.",
          type = "warning", duration = 5
        )
      }
    })

    # ── 8. Produce Seasonal Rasters ───────────────────────────────────────────
    shiny::observeEvent(input$btn_seasonal_raster, {
      shiny::req(input$db_path)
      farms_sf <- rv$farms_sf
      
      if (is.null(farms_sf) || nrow(farms_sf) == 0) {
        shiny::showNotification("No farm layer loaded.", type = "error")
        return()
      }
      
      start_col <- input$start_date_col
      end_col   <- input$end_date_col
      
      if (start_col == "" || end_col == "") {
        shiny::showNotification("Please select Season Start and End columns first.", type = "warning")
        return()
      }
      
      # Open DB
      con <- tryCatch(
        duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
        error = function(e) {
          shiny::showNotification(paste("DB connection failed:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(con)) return()
      on.exit(duckdb::dbDisconnect(con, shutdown = TRUE))
      
      # Determine variables to aggregate
      # We aggregate everything currently in the database for these farms
      avail <- wapor_get_available_raster_data(con)
      vars_to_agg <- avail$variables
      
      if (length(vars_to_agg) == 0) {
        shiny::showNotification("No dekadal rasters found in database to aggregate.", type = "warning")
        return()
      }
      
      shiny::withProgress(message = 'Generating seasonal rasters...', value = 0, {
        n_farms <- nrow(farms_sf)
        success_count <- 0
        
        for (i in seq_len(n_farms)) {
          farm <- farms_sf[i, ]
          farm_id <- as.character(sf::st_drop_geometry(farm)$farm_id)
          
          # Get dates
          start_date <- tryCatch(as.Date(farm[[start_col]]), error = function(e) NA)
          end_date   <- tryCatch(as.Date(farm[[end_col]]), error = function(e) NA)
          
          if (is.na(start_date) || is.na(end_date)) {
            add_log("Skipping farm", farm_id, "- invalid dates in columns.")
            next
          }
          
          season_id <- sprintf("SEASON_%s_%s", format(start_date, "%Y%m%d"), format(end_date, "%Y%m%d"))
          
          for (var in vars_to_agg) {
            # Generate aggregate
            agg_rast <- wapor_generate_seasonal_raster(con, farm_id, farm, var, start_date, end_date)
            
            if (!is.null(agg_rast)) {
              # Save to DB
              wapor_save_seasonal_raster_to_db(con, farm_id, var, season_id, agg_rast)
              success_count <- success_count + 1
            }
          }
          
          shiny::incProgress(1/n_farms, detail = paste("Farm:", farm_id))
        }
        
        if (success_count > 0) {
          add_log("\u2714 Generated", success_count, "seasonal aggregate rasters.")
          shiny::showNotification(sprintf("\u2714 Successfully generated %d seasonal rasters.", success_count), type = "message")
        } else {
          shiny::showNotification("No seasonal rasters could be generated. Check your date ranges and database contents.", type = "warning")
        }
      })
    })

    # ── DERIVED DATA ──────────────────────────────────────────────────────────

    # Helper: compute ETa/ETp ratio per farm per dekad
    derive_eta_etp <- function(ts_df) {
      if (is.null(ts_df) || nrow(ts_df) == 0) return(NULL)
      aeti <- .mon_records_for_family(ts_df, .MON_AETI_D_VARS)
      ret  <- .mon_records_for_family(ts_df, .MON_RET_D_VARS)
      if (nrow(aeti) == 0 || nrow(ret) == 0) return(NULL)
      merged <- merge(
        aeti[, c("farm_id", "start_date", "mean_val")],
        ret[,  c("farm_id", "start_date", "mean_val")],
        by = c("farm_id", "start_date"), suffixes = c("_aeti", "_ret")
      )
      merged$eta_etp <- ifelse(merged$mean_val_ret > 0,
                               merged$mean_val_aeti / merged$mean_val_ret, NA_real_)
      # Cap at 1.5: values slightly above 1.0 occur when crop ET exceeds reference ET
      # (e.g. tall crops, advection).  Values > 1.5 are likely data artefacts.
      merged$eta_etp <- pmin(pmax(merged$eta_etp, 0), 1.5)
      merged
    }

    # Helper: compute T/(T+E) per farm per dekad
    derive_t_frac <- function(ts_df) {
      if (is.null(ts_df) || nrow(ts_df) == 0) return(NULL)
      t_df  <- .mon_records_for_family(ts_df, .MON_T_D_VARS)
      e_df  <- .mon_records_for_family(ts_df, .MON_E_D_VARS)
      if (nrow(t_df) == 0 || nrow(e_df) == 0) return(NULL)
      merged <- merge(
        t_df[, c("farm_id", "start_date", "mean_val")],
        e_df[, c("farm_id", "start_date", "mean_val")],
        by = c("farm_id", "start_date"), suffixes = c("_t", "_e")
      )
      merged$t_frac <- ifelse((merged$mean_val_t + merged$mean_val_e) > 0,
                              merged$mean_val_t / (merged$mean_val_t + merged$mean_val_e),
                              NA_real_)
      merged
    }

    # ── FARM MAP ──────────────────────────────────────────────────────────────
    output$farm_map <- leaflet::renderLeaflet({
      sf_obj  <- rv$farms_sf
      ts_data <- rv$ts_data
      ind     <- input$map_indicator %||% "eta_etp"
      period  <- input$map_period_agg %||% "season"
      sowing  <- input$sowing_date

      m <- leaflet::leaflet() |>
        leaflet::addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
        leaflet::addProviderTiles("OpenStreetMap",     group = "OSM") |>
        leaflet::addLayersControl(
          baseGroups    = c("Satellite", "OSM"),
          options       = leaflet::layersControlOptions(collapsed = FALSE)
        ) |>
        leaflet::setView(lng = 18, lat = 2, zoom = 3)

      if (is.null(sf_obj) || nrow(sf_obj) == 0) return(m)

      # Default: show farms without colour
      if (is.null(ts_data) || nrow(ts_data) == 0) {
        return(m |>
          leaflet::addPolygons(data = sf_obj, color = "#3498db",
                               weight = 2, fillOpacity = 0.3,
                               label  = ~farm_id) |>
          leaflet::fitBounds(
            lng1 = sf::st_bbox(sf_obj)[["xmin"]],
            lat1 = sf::st_bbox(sf_obj)[["ymin"]],
            lng2 = sf::st_bbox(sf_obj)[["xmax"]],
            lat2 = sf::st_bbox(sf_obj)[["ymax"]]
          )
        )
      }

      # Compute indicator per farm
      indicator_df <- tryCatch({
        if (ind == "eta_etp") {
          d <- derive_eta_etp(ts_data)
          if (is.null(d) || nrow(d) == 0) NULL
          else {
            if (period == "last") {
              d <- d[d$start_date == max(d$start_date), ]
            } else if (period == "30d") {
              cutoff <- Sys.Date() - 30
              d <- d[as.Date(d$start_date) >= cutoff, ]
            }
            agg <- stats::aggregate(eta_etp ~ farm_id, data = d, FUN = mean, na.rm = TRUE)
            names(agg)[2] <- "value"
            agg
          }
        } else if (ind == "cum_aeti") {
          aeti <- .mon_records_for_family(ts_data, .MON_AETI_D_VARS)
          if (period == "season" && !is.null(sowing))
            aeti <- aeti[as.Date(aeti$start_date) >= as.Date(sowing), ]
          if (nrow(aeti) == 0) NULL
          else {
            agg <- stats::aggregate(mean_val ~ farm_id, data = aeti, FUN = sum, na.rm = TRUE)
            names(agg)[2] <- "value"
            agg
          }
        } else if (ind == "t_frac") {
          d <- derive_t_frac(ts_data)
          if (is.null(d) || nrow(d) == 0) NULL
          else {
            agg <- stats::aggregate(t_frac ~ farm_id, data = d, FUN = mean, na.rm = TRUE)
            names(agg)[2] <- "value"
            agg
          }
        } else if (ind == "npp_latest") {
          npp <- .mon_records_for_family(ts_data, .MON_NPP_D_VARS)
          if (nrow(npp) == 0) NULL
          else {
            npp <- npp[npp$start_date == max(npp$start_date), ]
            agg <- stats::aggregate(mean_val ~ farm_id, data = npp, FUN = mean, na.rm = TRUE)
            names(agg)[2] <- "value"
            agg
          }
        } else {
          NULL
        }
      }, error = function(e) NULL)

      if (is.null(indicator_df) || nrow(indicator_df) == 0) {
        return(m |>
          leaflet::addPolygons(data = sf_obj, color = "#3498db",
                               weight = 2, fillOpacity = 0.3,
                               label  = ~farm_id) |>
          leaflet::fitBounds(
            lng1 = sf::st_bbox(sf_obj)[["xmin"]],
            lat1 = sf::st_bbox(sf_obj)[["ymin"]],
            lng2 = sf::st_bbox(sf_obj)[["xmax"]],
            lat2 = sf::st_bbox(sf_obj)[["ymax"]]
          ))
      }

      # Merge indicator onto sf object
      sf_plot <- merge(sf_obj, indicator_df, by = "farm_id", all.x = TRUE)

      # Colour palette
      pal_fn <- if (ind == "eta_etp") {
        leaflet::colorNumeric("RdYlGn", domain = c(0, 1.2), na.color = "#aaaaaa")
      } else if (ind == "t_frac") {
        leaflet::colorNumeric("RdYlGn", domain = c(0, 1),   na.color = "#aaaaaa")
      } else {
        leaflet::colorNumeric("YlOrRd", domain = range(sf_plot$value, na.rm = TRUE), na.color = "#aaaaaa")
      }

      label_col_name <- input$label_col %||% ""
      label_vals <- if (nzchar(label_col_name) && label_col_name %in% names(sf_plot)) {
        sf_plot[[label_col_name]]
      } else {
        sf_plot$farm_id
      }

      tooltip <- paste0(
        "<b>", label_vals, "</b><br/>",
        ind, ": ", round(sf_plot$value, 3)
      )

      m |>
        leaflet::addPolygons(
          data        = sf_plot,
          fillColor   = ~pal_fn(value),
          fillOpacity = 0.75,
          color       = "#333333", weight = 1,
          label       = lapply(tooltip, shiny::HTML)
        ) |>
        leaflet::addLegend(
          pal      = pal_fn,
          values   = sf_plot$value,
          title    = ind,
          position = "bottomright"
        ) |>
        leaflet::fitBounds(
          lng1 = sf::st_bbox(sf_obj)[["xmin"]],
          lat1 = sf::st_bbox(sf_obj)[["ymin"]],
          lng2 = sf::st_bbox(sf_obj)[["xmax"]],
          lat2 = sf::st_bbox(sf_obj)[["ymax"]]
        )
    })

    # ── TIME SERIES TAB ───────────────────────────────────────────────────────

    # Dynamic farm selector
    output$ts_farm_select_ui <- shiny::renderUI({
      ts <- rv$ts_data
      if (is.null(ts) || nrow(ts) == 0) {
        farms <- if (!is.null(rv$farms_sf)) rv$farms_sf$farm_id else "No data"
      } else {
        farms <- sort(unique(ts$farm_id))
      }
      shiny::selectizeInput(
        ns("ts_farm"), "Farm(s)",
        choices  = farms,
        selected = farms[1],
        multiple = TRUE,
        options  = list(maxItems = 10)
      )
    })

    # Update variable selector based on available data
    shiny::observe({
      ts <- rv$ts_data
      if (is.null(ts) || nrow(ts) == 0) return()
      vars <- sort(unique(ts$variable))
      shiny::updateSelectInput(session, "ts_variable", choices = vars,
                               selected = vars[1])
    })

    output$plot_ts <- shiny::renderPlot({
      shiny::req(rv$ts_data, input$ts_farm, input$ts_variable)
      ts    <- rv$ts_data
      farms <- input$ts_farm
      var   <- input$ts_variable
      deriv <- input$ts_derived %||% "raw"

      if (deriv == "raw") {
        df <- ts[ts$farm_id %in% farms & ts$variable == var, ]
        if (nrow(df) == 0) {
          graphics::plot.new(); graphics::title(sprintf("No data for %s", var)); return()
        }
        df$start_date <- as.Date(df$start_date)
        p <- ggplot2::ggplot(df, ggplot2::aes(x = start_date, y = mean_val,
                                               colour = farm_id, group = farm_id)) +
          ggplot2::geom_line(linewidth = 0.8) +
          ggplot2::geom_point(size = 1.5) +
          ggplot2::labs(title = var, x = "Date", y = var, colour = "Farm") +
          ggplot2::theme_minimal(base_size = 12)

      } else if (deriv == "eta_etp") {
        df <- derive_eta_etp(ts)
        if (is.null(df) || nrow(df) == 0) {
          graphics::plot.new()
          graphics::title("Need both AETI and RET variables")
          return()
        }
        df <- df[df$farm_id %in% farms, ]
        df$start_date <- as.Date(df$start_date)
        p <- ggplot2::ggplot(df, ggplot2::aes(x = start_date, y = eta_etp,
                                               colour = farm_id, group = farm_id)) +
          ggplot2::geom_line(linewidth = 0.8) +
          ggplot2::geom_point(size = 1.5) +
          ggplot2::geom_hline(yintercept = .MON_STRESS_HIGH,   linetype = "dashed",
                              colour = "#e67e22", linewidth = 0.6) +
          ggplot2::geom_hline(yintercept = .MON_STRESS_SEVERE, linetype = "dashed",
                              colour = "#c0392b", linewidth = 0.6) +
          ggplot2::annotate("text", x = -Inf, y = .MON_STRESS_HIGH + 0.02,
                            label = "Moderate stress threshold", hjust = -0.05,
                            size = 3, colour = "#e67e22") +
          ggplot2::annotate("text", x = -Inf, y = .MON_STRESS_SEVERE + 0.02,
                            label = "Severe stress threshold", hjust = -0.05,
                            size = 3, colour = "#c0392b") +
          ggplot2::labs(title = "ETa/ETp – Water Stress Index",
                        x = "Date", y = "ETa/ETp (dimensionless)", colour = "Farm") +
          ggplot2::scale_y_continuous(limits = c(0, 1.4)) +
          ggplot2::theme_minimal(base_size = 12)

      } else if (deriv == "t_frac") {
        df <- derive_t_frac(ts)
        if (is.null(df) || nrow(df) == 0) {
          graphics::plot.new()
          graphics::title("Need both T and E variables")
          return()
        }
        df <- df[df$farm_id %in% farms, ]
        df$start_date <- as.Date(df$start_date)
        p <- ggplot2::ggplot(df, ggplot2::aes(x = start_date, y = t_frac,
                                               colour = farm_id, group = farm_id)) +
          ggplot2::geom_line(linewidth = 0.8) +
          ggplot2::geom_point(size = 1.5) +
          ggplot2::labs(title = "Transpiration Fraction T/(T+E)",
                        x = "Date", y = "T/(T+E)", colour = "Farm") +
          ggplot2::scale_y_continuous(limits = c(0, 1)) +
          ggplot2::theme_minimal(base_size = 12)

      } else if (deriv == "cum_aeti") {
        aeti <- .mon_records_for_family(ts, .MON_AETI_D_VARS)
        aeti <- aeti[aeti$farm_id %in% farms, ]
        if (nrow(aeti) == 0) {
          graphics::plot.new()
          graphics::title("No AETI data available")
          return()
        }
        aeti <- aeti[order(aeti$farm_id, aeti$start_date), ]
        aeti$start_date <- as.Date(aeti$start_date)
        sowing_dt <- tryCatch(as.Date(input$sowing_date), error = function(e) NULL)
        if (!is.null(sowing_dt))
          aeti <- aeti[aeti$start_date >= sowing_dt, ]
        aeti$cum_aeti <- stats::ave(aeti$mean_val, aeti$farm_id, FUN = cumsum)
        p <- ggplot2::ggplot(aeti, ggplot2::aes(x = start_date, y = cum_aeti,
                                                  colour = farm_id, group = farm_id)) +
          ggplot2::geom_line(linewidth = 0.8) +
          ggplot2::geom_point(size = 1.5) +
          ggplot2::labs(title = "Cumulative AETI from Sowing (mm)",
                        x = "Date", y = "Cumulative AETI (mm)", colour = "Farm") +
          ggplot2::theme_minimal(base_size = 12)
      } else {
        graphics::plot.new()
        return()
      }

      print(p)
    })

    # Download time series PNG
    output$dl_ts_png <- shiny::downloadHandler(
      filename = function() paste0("monitoring_ts_", Sys.Date(), ".png"),
      content  = function(file) {
        shiny::req(rv$ts_data)
        # Re-use the same plot logic – wrapped in tryCatch
        tryCatch({
          ts    <- rv$ts_data
          farms <- input$ts_farm
          var   <- input$ts_variable
          df    <- ts[ts$farm_id %in% farms & ts$variable == var, ]
          df$start_date <- as.Date(df$start_date)
          p <- ggplot2::ggplot(df, ggplot2::aes(x = start_date, y = mean_val,
                                                  colour = farm_id)) +
            ggplot2::geom_line(linewidth = 0.8) +
            ggplot2::geom_point(size = 1.5) +
            ggplot2::labs(title = var, x = "Date", y = var) +
            ggplot2::theme_minimal(base_size = 12)
          ggplot2::ggsave(file, p, width = 10, height = 5, dpi = 150)
        }, error = function(e) shiny::showNotification(e$message, type = "error"))
      }
    )

    # Download CSV
    output$dl_ts_csv <- shiny::downloadHandler(
      filename = function() paste0("monitoring_ts_", Sys.Date(), ".csv"),
      content  = function(file) {
        shiny::req(rv$ts_data)
        utils::write.csv(rv$ts_data, file, row.names = FALSE)
      }
    )

    # ── RASTER VIEW TAB ───────────────────────────────────────────────────────

    # Farm selector – populated from saved rasters in DB (or fallback to farms_sf)
    output$rast_farm_ui <- shiny::renderUI({
      db_path <- input$db_path
      farms <- NULL
      if (!is.null(db_path) && file.exists(db_path)) {
        farms <- tryCatch({
          con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
          on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))
          
          # If we have global rasters, we can show all farms in the project
          has_global <- DBI::dbGetQuery(con, "SELECT count(*) as n FROM monitoring_rasters")$n > 0
          if (has_global) {
             # Get all farms from polygons table
             DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_polygons ORDER BY farm_id")$farm_id
          } else {
             # Legacy: only show farms that have blobs
             DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_rasters ORDER BY farm_id")$farm_id
          }
        }, error = function(e) NULL)
      }
      if (is.null(farms) || length(farms) == 0) {
        farms <- if (!is.null(rv$farms_sf)) rv$farms_sf$farm_id else character(0)
      }
      if (length(farms) == 0) return(shiny::helpText("No rasters in DB yet."))
      shiny::selectInput(ns("rast_farm"), "Farm", choices = farms, selected = farms[1])
    })

    output$rast_var_ui <- shiny::renderUI({
      # Prefer variables from saved rasters (including seasonal)
      db_path <- input$db_path
      rast_farm <- input$rast_farm
      vars <- NULL
      if (!is.null(db_path) && file.exists(db_path) && !is.null(rast_farm) && nzchar(rast_farm)) {
        vars <- tryCatch({
          con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
          on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))
          
          # Get vars from global, dekad and seasonal tables
          v_global <- tryCatch(
            DBI::dbGetQuery(con, "SELECT DISTINCT variable FROM monitoring_rasters")$variable,
            error = function(e) character(0)
          )
          v_dekad <- DBI::dbGetQuery(con,
            "SELECT DISTINCT variable FROM farm_rasters WHERE farm_id = ?",
            params = list(rast_farm)
          )$variable
          
          v_season <- tryCatch(
            DBI::dbGetQuery(con, 
              "SELECT DISTINCT variable FROM farm_seasonal_rasters WHERE farm_id = ?",
              params = list(rast_farm)
            )$variable,
            error = function(e) character(0)
          )
          
          sort(unique(c(v_global, v_dekad, v_season)))
        }, error = function(e) NULL)
      }
      if (is.null(vars) || length(vars) == 0) {
        ts <- rv$ts_data
        vars <- if (!is.null(ts)) sort(unique(ts$variable)) else character(0)
      }
      if (length(vars) == 0) return(shiny::helpText("No rasters saved yet."))
      shiny::selectInput(ns("rast_var"), "Variable", choices = vars, selected = vars[1])
    })

    output$rast_date_ui <- shiny::renderUI({
      db_path   <- input$db_path
      rast_farm <- input$rast_farm
      rast_var  <- input$rast_var
      if (is.null(rast_farm) || !nzchar(rast_farm %||% "") ||
          is.null(rast_var)  || !nzchar(rast_var  %||% "")) {
        return(shiny::selectInput(ns("rast_date"), "Date", choices = NULL))
      }
      choices <- list()
      if (!is.null(db_path) && file.exists(db_path)) {
        res <- tryCatch({
          con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
          on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))
          
          # Global dates for this variable
          gl_dates <- tryCatch(
            DBI::dbGetQuery(con,
              "SELECT DISTINCT CAST(date_key AS VARCHAR) as dk FROM monitoring_rasters
               WHERE variable = ? ORDER BY dk",
              params = list(rast_var)
            )$dk,
            error = function(e) character(0)
          )

          # Dekadal dates
          dk_dates <- DBI::dbGetQuery(con,
            "SELECT DISTINCT CAST(date_key AS VARCHAR) as dk FROM farm_rasters
             WHERE farm_id = ? AND variable = ? ORDER BY dk",
            params = list(rast_farm, rast_var)
          )$dk
          
          # Seasonal IDs
          sn_ids <- tryCatch(
            DBI::dbGetQuery(con,
              "SELECT DISTINCT season_id FROM farm_seasonal_rasters
               WHERE farm_id = ? AND variable = ? ORDER BY season_id",
              params = list(rast_farm, rast_var)
            )$season_id,
            error = function(e) character(0)
          )
          
          list(dekadal = dk_dates, seasonal = sn_ids)
        }, error = function(e) NULL)
        
        if (!is.null(res)) {
          if (length(res$seasonal) > 0) {
            # Map seasonal IDs to a display name with prefix
            s_choices <- as.list(stats::setNames(paste0("SEASONAL:", res$seasonal), 
                                               gsub("SEASON_", "Season: ", res$seasonal)))
            choices[["Seasonal Aggregates"]] <- s_choices
          }
          if (length(res$dekadal) > 0 || length(res$global) > 0) {
            choices[["Dekadal Snapshots"]] <- as.list(sort(unique(c(res$dekadal, res$global))))
          }
        }
      }
      
      if (length(choices) == 0) {
        ts <- rv$ts_data
        if (!is.null(ts)) {
          dates <- as.character(sort(unique(ts$start_date[ts$variable == (rast_var %||% "")])))
          if (length(dates) > 0) choices[["Dekadal Snapshots"]] <- dates
        }
      }
      
      if (length(choices) == 0)
        return(shiny::selectInput(ns("rast_date"), "Date", choices = NULL))
        
      shiny::selectInput(ns("rast_date"), "Period / Date",
                         choices = choices)
    })

    output$raster_map <- leaflet::renderLeaflet({
      m <- leaflet::leaflet() |>
        leaflet::addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
        leaflet::addProviderTiles("OpenStreetMap",     group = "OSM") |>
        leaflet::addLayersControl(
          baseGroups = c("Satellite", "OSM"),
          options    = leaflet::layersControlOptions(collapsed = FALSE)
        ) |>
        leaflet::setView(lng = 18, lat = 2, zoom = 3)

      farms_sf <- rv$farms_sf
      if (!is.null(farms_sf) && nrow(farms_sf) > 0) {
        m <- m |>
          leaflet::addPolygons(data = farms_sf, color = "#ffffff",
                               weight = 2, fillOpacity = 0.1,
                               label  = ~farm_id) |>
          leaflet::fitBounds(
            lng1 = sf::st_bbox(farms_sf)[["xmin"]],
            lat1 = sf::st_bbox(farms_sf)[["ymin"]],
            lng2 = sf::st_bbox(farms_sf)[["xmax"]],
            lat2 = sf::st_bbox(farms_sf)[["ymax"]]
          )
      }

      rast_farm <- input$rast_farm
      rast_var  <- input$rast_var
      rast_date <- input$rast_date

      if (is.null(rast_farm) || !nzchar(rast_farm %||% "") ||
          is.null(rast_var)  || !nzchar(rast_var  %||% "") ||
          is.null(rast_date) || !nzchar(rast_date %||% "") ||
          !requireNamespace("duckdb", quietly = TRUE)) return(m)

      db_path <- input$db_path
      if (is.null(db_path) || !file.exists(db_path)) return(m)

      tryCatch({
        con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
        on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))

        # Check GLOBAL table first
        if (!grepl("^SEASONAL:", rast_date)) {
           blob_row <- DBI::dbGetQuery(con,
             "SELECT raster_blob FROM monitoring_rasters
              WHERE variable = ? AND CAST(date_key AS VARCHAR) = ?
              LIMIT 1",
             params = list(rast_var, rast_date)
           )
           
           is_global <- nrow(blob_row) > 0
        } else {
           is_global <- FALSE
        }

        # Check if seasonal or dekadal (Fallback to legacy if not found in global)
        if (!is_global) {
          if (grepl("^SEASONAL:", rast_date)) {
            season_id <- sub("^SEASONAL:", "", rast_date)
            blob_row <- DBI::dbGetQuery(con,
              "SELECT raster_blob FROM farm_seasonal_rasters
               WHERE farm_id = ? AND variable = ? AND season_id = ?
               LIMIT 1",
              params = list(rast_farm, rast_var, season_id)
            )
          } else {
            blob_row <- DBI::dbGetQuery(con,
              "SELECT raster_blob FROM farm_rasters
               WHERE farm_id = ? AND variable = ? AND CAST(date_key AS VARCHAR) = ?
               LIMIT 1",
              params = list(rast_farm, rast_var, rast_date)
            )
          }
        }

        if (nrow(blob_row) == 0 || is.null(blob_row$raster_blob[[1]])) {
          shiny::showNotification(
            sprintf("No raster found for farm=%s, var=%s, date=%s",
                    rast_farm, rast_var, rast_date),
            type = "warning", duration = 5
          )
          return(m)
        }

        # Load Raster
        r_full <- wapor_raster_from_blob(blob_row$raster_blob[[1]])
        if (is.null(r_full)) return(m)
        
        # DYNAMIC CLIP if it's a global raster
        if (is_global) {
           # Get farm polygon
           poly <- farms_sf[farms_sf$farm_id == rast_farm, ]
           if (nrow(poly) > 0) {
              f_bb <- sf::st_bbox(poly)
              f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                                 as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))
              r <- terra::crop(r_full, f_ext)
           } else {
              r <- r_full
           }
        } else {
           r <- r_full
        }

        pal_name <- input$rast_palette %||% "viridis"
        pal_colors <- grDevices::colorRampPalette(
          switch(pal_name,
            "magma"    = viridisLite::magma(11),
            "RdYlGn"   = RColorBrewer::brewer.pal(11, "RdYlGn"),
            "RdYlBu"   = RColorBrewer::brewer.pal(11, "RdYlBu"),
            "Spectral"  = RColorBrewer::brewer.pal(11, "Spectral"),
            viridisLite::viridis(11)
          )
        )(255)

        vals <- terra::values(r, na.rm = TRUE)
        if (length(vals) == 0 || all(is.na(vals))) {
          shiny::showNotification("Raster has no valid values.", type = "warning", duration = 4)
          return(m)
        }
        pal_fn <- leaflet::colorNumeric(pal_colors,
                                        domain = range(vals, na.rm = TRUE),
                                        na.color = "transparent")

        m |>
          leaflet::addRasterImage(r, colors = pal_fn, opacity = 0.75, group = "Raster") |>
          leaflet::addLegend(pal = pal_fn, values = vals,
                             title  = paste0(rast_var, "\n", rast_date),
                             position = "bottomright")
      }, error = function(e) {
        shiny::showNotification(paste("Raster load error:", e$message), type = "warning", duration = 5)
        m
      })
    })

    # ── STRESS DASHBOARD ──────────────────────────────────────────────────────

    # Compute summary per farm: latest ETa/ETp, cumulative AETI, mean T fraction
    stress_summary <- shiny::reactive({
      ts <- rv$ts_data
      if (is.null(ts) || nrow(ts) == 0) return(NULL)

      farms_sf <- rv$farms_sf
      farm_ids <- if (!is.null(farms_sf)) farms_sf$farm_id else unique(ts$farm_id)

      # ETa/ETp
      eta_etp_df <- tryCatch({
        d <- derive_eta_etp(ts)
        if (is.null(d) || nrow(d) == 0) NULL
        else stats::aggregate(eta_etp ~ farm_id, data = d, FUN = mean, na.rm = TRUE)
      }, error = function(e) NULL)

      # Cumulative AETI
      cum_aeti_df <- tryCatch({
        aeti <- .mon_records_for_family(ts, .MON_AETI_D_VARS)
        sowing_dt <- tryCatch(as.Date(input$sowing_date), error = function(e) NULL)
        if (!is.null(sowing_dt)) aeti <- aeti[as.Date(aeti$start_date) >= sowing_dt, ]
        if (nrow(aeti) == 0) NULL
        else stats::aggregate(mean_val ~ farm_id, data = aeti, FUN = sum, na.rm = TRUE)
      }, error = function(e) NULL)

      # T fraction
      t_frac_df <- tryCatch({
        d <- derive_t_frac(ts)
        if (is.null(d) || nrow(d) == 0) NULL
        else stats::aggregate(t_frac ~ farm_id, data = d, FUN = mean, na.rm = TRUE)
      }, error = function(e) NULL)

      # Latest NPP
      npp_df <- tryCatch({
        npp <- .mon_records_for_family(ts, .MON_NPP_D_VARS)
        if (nrow(npp) == 0) NULL
        else {
          last_date <- max(npp$start_date)
          npp_last  <- npp[npp$start_date == last_date, c("farm_id", "mean_val")]
          names(npp_last)[2] <- "latest_npp"
          npp_last
        }
      }, error = function(e) NULL)

      # Merge all
      result <- data.frame(farm_id = farm_ids, stringsAsFactors = FALSE)
      if (!is.null(eta_etp_df))  result <- merge(result, eta_etp_df,                                    by = "farm_id", all.x = TRUE)
      if (!is.null(cum_aeti_df)) result <- merge(result, cum_aeti_df[, c("farm_id", "mean_val")],       by = "farm_id", all.x = TRUE)
      if (!is.null(t_frac_df))   result <- merge(result, t_frac_df,                                     by = "farm_id", all.x = TRUE)
      if (!is.null(npp_df))      result <- merge(result, npp_df,                                        by = "farm_id", all.x = TRUE)

      # Rename
      if ("mean_val" %in% names(result)) names(result)[names(result) == "mean_val"] <- "cum_aeti_mm"
      if (!is.null(eta_etp_df) && "eta_etp" %in% names(result)) {
        result$stress_class <- dplyr::case_when(
          result$eta_etp >= .MON_STRESS_HIGH   ~ "Good",
          result$eta_etp >= .MON_STRESS_SEVERE ~ "Moderate stress",
          !is.na(result$eta_etp)               ~ "Severe stress",
          TRUE                                  ~ "N/A"
        )
      }

      # Add crop type if available
      if (!is.null(farms_sf) && !is.null(input$crop_col) && nzchar(input$crop_col) &&
          input$crop_col %in% names(farms_sf)) {
        crop_meta <- sf::st_drop_geometry(farms_sf[, c("farm_id", input$crop_col)])
        names(crop_meta)[2] <- "crop_type"
        result <- merge(result, crop_meta, by = "farm_id", all.x = TRUE)
      }

      result
    })

    output$stress_valueboxes_ui <- shiny::renderUI({
      df <- stress_summary()
      if (is.null(df) || nrow(df) == 0) {
        return(shiny::div(class = "alert alert-info",
                          "Run Monitor to populate the stress dashboard."))
      }

      n_total   <- nrow(df)
      n_severe  <- if ("stress_class" %in% names(df)) sum(df$stress_class == "Severe stress",   na.rm = TRUE) else 0L
      n_mod     <- if ("stress_class" %in% names(df)) sum(df$stress_class == "Moderate stress", na.rm = TRUE) else 0L
      n_good    <- if ("stress_class" %in% names(df)) sum(df$stress_class == "Good",            na.rm = TRUE) else 0L
      mean_eta  <- if ("eta_etp" %in% names(df)) round(mean(df$eta_etp, na.rm = TRUE), 2) else NA

      bslib::layout_column_wrap(
        width = 1/4, gap = "0.6rem",
        bslib::value_box(
          title    = "Total Farms",
          value    = n_total,
          showcase = shiny::icon("layer-group"),
          theme    = "primary"
        ),
        bslib::value_box(
          title    = "Severe Stress",
          value    = n_severe,
          showcase = shiny::icon("triangle-exclamation"),
          theme    = if (n_severe > 0) "danger" else "success"
        ),
        bslib::value_box(
          title    = "Moderate Stress",
          value    = n_mod,
          showcase = shiny::icon("circle-exclamation"),
          theme    = if (n_mod > 0) "warning" else "success"
        ),
        bslib::value_box(
          title    = "Mean ETa/ETp",
          value    = if (is.na(mean_eta)) "N/A" else mean_eta,
          showcase = shiny::icon("droplet"),
          theme    = "info"
        )
      )
    })

    output$stress_table <- DT::renderDT({
      df <- stress_summary()
      if (is.null(df) || nrow(df) == 0) return(DT::datatable(data.frame(Message = "No data available")))

      # Round numeric columns
      num_cols <- sapply(df, is.numeric)
      df[, num_cols] <- round(df[, num_cols], 3)

      DT::datatable(
        df,
        rownames = FALSE,
        options  = list(pageLength = 15, scrollX = TRUE),
        filter   = "top"
      ) |> DT::formatStyle(
        columns    = if ("stress_class" %in% names(df)) "stress_class" else character(0),
        target     = "row",
        backgroundColor = DT::styleEqual(
          c("Severe stress", "Moderate stress", "Good"),
          c("#f8d7da",       "#fff3cd",         "#d4edda")
        )
      )
    })

    # ── DATA TABLE ────────────────────────────────────────────────────────────
    output$tbl_data <- DT::renderDT({
      ts <- rv$ts_data
      if (is.null(ts) || nrow(ts) == 0)
        return(DT::datatable(data.frame(Message = "No data. Run Monitor or Load from Database.")))
      DT::datatable(ts, rownames = FALSE,
                    options = list(pageLength = 20, scrollX = TRUE),
                    filter  = "top")
    })

    output$dl_csv <- shiny::downloadHandler(
      filename = function() paste0("wapor_monitoring_", Sys.Date(), ".csv"),
      content  = function(file) {
        shiny::req(rv$ts_data)
        utils::write.csv(rv$ts_data, file, row.names = FALSE)
      }
    )

    output$dl_parquet <- shiny::downloadHandler(
      filename = function() paste0("wapor_monitoring_", Sys.Date(), ".parquet"),
      content  = function(file) {
        shiny::req(rv$ts_data)
        if (!requireNamespace("arrow", quietly = TRUE)) {
          shiny::showNotification("arrow package required for Parquet export.", type = "error")
          return()
        }
        arrow::write_parquet(rv$ts_data, file)
      }
    )

    # ── 15. Seasonal Adaptive Recalculation ────────────────────────────────────
    
    shiny::observeEvent(input$btn_recalculate_seasonal, {
      shiny::req(rv$db_con, rv$farms_sf)
      
      # Determine farm to process
      sel_farm <- input$ts_farm_select
      if (!nzchar(sel_farm %||% "")) {
        shiny::showNotification("Please select a farm in the Time Series tab first.", type = "warning")
        return()
      }
      
      poly <- rv$farms_sf[rv$farms_sf$farm_id == sel_farm, ]
      if (nrow(poly) == 0) return()
      
      shiny::withProgress(message = "Applying Seasonal Adaptive Mask", value = 0, {
        
        # Determine dates (use the main UI dates as the season window)
        start_d <- input$sowing_date
        end_d   <- input$harvest_date
        
        add_log(sprintf("Starting Seasonal Adaptive Recalculation for %s (%s to %s)", 
                        sel_farm, start_d, end_d))
        
        tryCatch({
          res <- Rwapor::wapor_apply_seasonal_mask_recalc(
            con = rv$db_con,
            farm_id = sel_farm,
            polygon = poly,
            start_date = start_d,
            end_date = end_d,
            mask_variable = input$mask_ref_var,
            percentile_threshold = input$mask_threshold
          )
          
          if (!is.null(res)) {
            add_log(sprintf("Successfully updated %d records for %s with seasonal mask.", 
                            nrow(res), sel_farm))
            shiny::showNotification(sprintf("Recalculation complete for %s", sel_farm), type = "message")
            
            # Refresh data
            refresh_ts_data()
          } else {
            shiny::showNotification("Recalculation failed. Check if rasters are available for the reference variable.", type = "error")
          }
          
        }, error = function(e) {
          add_log("Error in seasonal recalculation: ", e$message)
          shiny::showNotification(paste("Error:", e$message), type = "error")
        })
      })
    })

    # ── Cleanup on session end ─────────────────────────────────────────────────
    session$onSessionEnded(function() close_db())

  }) # /moduleServer
} # /mod_monitoring_server

# .save_raster_blobs() is defined in monitoring_helpers.R (sourced at the top of this file).
