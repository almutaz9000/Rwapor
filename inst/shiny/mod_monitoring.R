# mod_monitoring.R
# Farm Monitoring Module – WaPOR Seasonal Performance Dashboard
# Fetches WaPOR data per farm polygon, stores to DuckDB, and provides
# agronomic stress visualisations.

# ── Load helper functions ──────────────────────────────────────────────────────
source(system.file("shiny", "monitoring_helpers.R", package = "Rwapor"), local = TRUE)

# ── Constants ──────────────────────────────────────────────────────────────────

# Default WaPOR variables recommended for crop monitoring.
# RET is included so the default stress dashboard can compute ETa/ETp.
.MON_DEFAULT_VARS <- c("L1-AETI-D", "L1-RET-D", "L1-T-D", "L1-E-D", "L1-NPP-D")

# L3 products are offered when the farm layer or shared AOI overlaps an L3 area.
.MON_L3_DEFAULT_VARS <- c("L3-AETI-D", "L3-T-D", "L3-E-D", "L3-NPP-D")

# API vars that are useful for field monitoring.
.MON_ALL_VARS <- c(
  "L1-AETI-D", "L1-RET-D",  "L1-T-D",    "L1-E-D",    "L1-NPP-D",
  "L1-PCP-D",
  "L2-AETI-D", "L2-RET-D",  "L2-T-D",    "L2-E-D",    "L2-NPP-D",
  "L2-PCP-D",
  "L3-AETI-D", "L3-T-D",    "L3-E-D",    "L3-NPP-D",  "L3-RSM-D"
)

.MON_AETI_D_VARS <- c("L3-AETI-D", "L2-AETI-D", "L1-AETI-D")
.MON_RET_D_VARS  <- c("L3-RET-D",  "L2-RET-D",  "L1-RET-D")
.MON_T_D_VARS    <- c("L3-T-D",    "L2-T-D",    "L1-T-D")
.MON_E_D_VARS    <- c("L3-E-D",    "L2-E-D",    "L1-E-D")
.MON_NPP_D_VARS  <- c("L3-NPP-D",  "L2-NPP-D",  "L1-NPP-D")

.mon_variable_choices <- function(vars = .MON_ALL_VARS) {
  labels <- vapply(vars, function(v) {
    meta <- tryCatch(Rwapor::wapor_variable_metadata(v), error = function(e) NULL)
    if (!is.null(meta) && !is.null(meta$long_name)) {
      sprintf("%s - %s", v, meta$long_name)
    } else {
      v
    }
  }, character(1), USE.NAMES = FALSE)
  stats::setNames(vars, labels)
}

.mon_l3_region_choices <- function(codes, l3_regions_meta) {
  stats::setNames(
    codes,
    vapply(codes, function(code) {
      r <- l3_regions_meta[[code]]
      if (!is.null(r)) sprintf("%s - %s (%s)", r$country, r$name, code) else code
    }, character(1), USE.NAMES = FALSE)
  )
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
          open     = TRUE,
          multiple = TRUE,

          # 1 · Farm Layer ────────────────────────────────────────────────────
          bslib::accordion_panel(
            "Farm Layer", icon = shiny::icon("draw-polygon"),

            shiny::tags$span("Upload vector file", class = "ctrl-group-label"),
            shiny::fileInput(
              ns("farm_file"), NULL,
              accept      = c(".geojson", ".gpkg", ".shp", ".kml", ".zip"),
              buttonLabel = shiny::icon("folder-open"),
              placeholder = "GeoJSON / GPKG / SHP"
            ),
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
              shinyFiles::shinyFilesButton(
                ns("browse_db"), label = "",
                title  = "Select or create DuckDB file",
                icon   = shiny::icon("folder-open"),
                class  = "btn-outline-secondary btn-sm",
                style  = "padding:0.37rem 0.6rem;",
                multiple = FALSE
              )
            ),
            shiny::uiOutput(ns("db_status_ui")),

            shiny::checkboxInput(
              ns("also_save_rasters"),
              "Also clip & save raster layers to database",
              value = FALSE
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
            leaflet::leafletOutput(ns("raster_map"), height = "calc(100vh - 280px)") |>
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

    # ── Helper: append log message ─────────────────────────────────────────────
    add_log <- function(...) {
      msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste(...))
      rv$log_msgs <- c(rv$log_msgs, msg)
    }

    # ── DuckDB helpers ─────────────────────────────────────────────────────────

    open_db <- function(path) {
      if (!requireNamespace("duckdb", quietly = TRUE))
        stop("Package 'duckdb' is required for the Monitoring tab. Install with: install.packages('duckdb')", call. = FALSE)
      tryCatch({
        con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = path)
        
        # Enhanced schema with std, percentiles, threshold tracking, and extents
        DBI::dbExecute(con, "
          CREATE TABLE IF NOT EXISTS farm_timeseries (
            farm_id       TEXT,
            crop_type     TEXT,
            sowing_date   DATE,
            variable      TEXT,
            start_date    DATE,
            end_date      DATE,
            mean_val      DOUBLE,
            min_val       DOUBLE,
            max_val       DOUBLE,
            std_val       DOUBLE,
            p05_val       DOUBLE,
            p95_val       DOUBLE,
            threshold_pct DOUBLE DEFAULT 0,
            pixels_used   INTEGER,
            pixels_total  INTEGER,
            updated_at    TIMESTAMP DEFAULT current_timestamp,
            PRIMARY KEY (farm_id, variable, start_date)
          )
        ")
        
        # Enhanced farm_rasters with extent metadata
        DBI::dbExecute(con, "
          CREATE TABLE IF NOT EXISTS farm_rasters (
            farm_id     TEXT,
            variable    TEXT,
            date_key    DATE,
            raster_blob BLOB,
            xmin        DOUBLE,
            xmax        DOUBLE,
            ymin        DOUBLE,
            ymax        DOUBLE,
            nrow        INTEGER,
            ncol        INTEGER,
            updated_at  TIMESTAMP DEFAULT current_timestamp,
            PRIMARY KEY (farm_id, variable, date_key)
          )
        ")
        
        # Farm metadata for quick lookups
        DBI::dbExecute(con, "
          CREATE TABLE IF NOT EXISTS farm_metadata (
            farm_id     TEXT PRIMARY KEY,
            crop_type   TEXT,
            sowing_date DATE,
            area_ha     DOUBLE,
            xmin        DOUBLE,
            xmax        DOUBLE,
            ymin        DOUBLE,
            ymax        DOUBLE
          )
        ")
        
        DBI::dbExecute(con, "
          CREATE TABLE IF NOT EXISTS monitoring_log (
            run_id      TEXT,
            started_at  TIMESTAMP,
            finished_at TIMESTAMP,
            n_records   INTEGER,
            status      TEXT,
            message     TEXT
          )
        ")
        
        # Create indices for performance
        DBI::dbExecute(con, "
          CREATE INDEX IF NOT EXISTS idx_timeseries_farm_var 
          ON farm_timeseries(farm_id, variable)
        ")
        DBI::dbExecute(con, "
          CREATE INDEX IF NOT EXISTS idx_timeseries_date 
          ON farm_timeseries(start_date)
        ")
        DBI::dbExecute(con, "
          CREATE INDEX IF NOT EXISTS idx_rasters_farm_var 
          ON farm_rasters(farm_id, variable)
        ")
        
        con
      }, error = function(e) {
        shiny::showNotification(paste("DB error:", e$message), type = "error")
        NULL
      })
    }

    close_db <- function() {
      if (!is.null(rv$db_con)) {
        tryCatch(DBI::dbDisconnect(rv$db_con, shutdown = TRUE), error = function(e) NULL)
        rv$db_con <- NULL
      }
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

    # ── File roots for shinyFiles ──────────────────────────────────────────────
    roots <- get_shinyfiles_roots()

    shinyFiles::shinyFileChoose(input, "browse_db", roots = roots, session = session,
                                filetypes = c("duckdb", "db"))

    shiny::observeEvent(input$browse_db, {
      p <- shinyFiles::parseFilePaths(roots, input$browse_db)
      if (nrow(p) > 0) shiny::updateTextInput(session, "db_path", value = p$datapath[1])
    })

    # ── 1. Load farm vector file ───────────────────────────────────────────────
    shiny::observeEvent(input$farm_file, {
      shiny::req(input$farm_file)
      tryCatch({
        path <- input$farm_file$datapath
        ext  <- tolower(tools::file_ext(input$farm_file$name))
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
      shiny::req(input$db_path)
      shiny::req(!isTRUE(rv$monitoring))

      farms_sf     <- rv$farms_sf
      sel_vars     <- input$mon_vars
      has_l3_vars  <- any(grepl("^L3-", sel_vars))
      l3_region    <- if (has_l3_vars) input$mon_l3_region else NULL
      sowing_date  <- as.character(input$sowing_date)
      harvest_date <- as.character(input$harvest_date)
      db_path      <- input$db_path
      crop_col     <- if (!is.null(input$crop_col) && nzchar(input$crop_col)) input$crop_col else NULL
      label_col    <- if (!is.null(input$label_col) && nzchar(input$label_col)) input$label_col else NULL
      save_rasters <- isTRUE(input$also_save_rasters)

      if (has_l3_vars && !is_l3_code(l3_region)) {
        shiny::showNotification("Select an L3 region before monitoring with L3 variables.", type = "error")
        return()
      }

      rv$monitoring <- TRUE
      rv$log_msgs   <- character(0)
      run_started_at <- Sys.time()
      add_log("Starting monitoring run…")

      # Run synchronously (could be made async with promises for large datasets)
      tryCatch({
        # Open / create DB
        con <- open_db(db_path)
        if (is.null(con)) { rv$monitoring <- FALSE; return() }

        # Determine per-variable start dates (incremental)
        last_dates <- get_last_dates(con)
        add_log(sprintf("Opened DB. %d existing records.", nrow(last_dates)))

        total_new <- 0L
        run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
        if (has_l3_vars) add_log(sprintf("Using L3 region: %s", l3_region))

        for (var in sel_vars) {
          add_log(sprintf("Variable: %s", var))

          # Determine start date for this variable
          last_row <- last_dates[last_dates$variable == var, ]
          start_str <- if (nrow(last_row) > 0 && !is.na(last_row$last_date[1])) {
            as.character(as.Date(last_row$last_date[1]) + 1)
          } else {
            sowing_date
          }

          if (as.Date(start_str) > as.Date(harvest_date)) {
            add_log(sprintf("  %s: already up to date.", var))
            next
          }

          add_log(sprintf("  Fetching %s → %s", start_str, harvest_date))

          # Fetch time series for each farm
          ts_df <- tryCatch({
            Rwapor::wapor_ts(
              region          = farms_sf,
              variable        = var,
              period          = c(start_str, harvest_date),
              identifier      = "farm_id",
              unit_conversion = if (grepl("-D$", var)) "dekad" else "none",
              batching        = TRUE,
              batch_size      = 6L,
              l3_region       = if (grepl("^L3-", var)) l3_region else NULL
            )
          }, error = function(e) {
            add_log(sprintf("  ERROR fetching %s: %s", var, e$message))
            NULL
          })

          if (is.null(ts_df) || nrow(ts_df) == 0) next

          # Add metadata columns
          ts_df$variable <- var
          if (!is.null(crop_col) && crop_col %in% names(farms_sf)) {
            farm_meta <- sf::st_drop_geometry(farms_sf[, c("farm_id", crop_col)])
            ts_df <- merge(ts_df, farm_meta, by = "farm_id", all.x = TRUE)
            names(ts_df)[names(ts_df) == crop_col] <- "crop_type"
          } else {
            ts_df$crop_type <- NA_character_
          }
          ts_df$sowing_date <- sowing_date

          # Normalise column names
          if (!"mean" %in% names(ts_df) && "mean_val" %in% names(ts_df))
            names(ts_df)[names(ts_df) == "mean_val"] <- "mean"
          if (!"min" %in% names(ts_df) && "min_val" %in% names(ts_df))
            names(ts_df)[names(ts_df) == "min_val"] <- "min"
          if (!"max" %in% names(ts_df) && "max_val" %in% names(ts_df))
            names(ts_df)[names(ts_df) == "max_val"] <- "max"

          # Select columns for DB insert
          insert_df <- data.frame(
            farm_id     = as.character(ts_df$farm_id),
            crop_type   = as.character(if ("crop_type" %in% names(ts_df)) ts_df$crop_type else NA_character_),
            sowing_date = as.Date(sowing_date),
            variable    = as.character(ts_df$variable),
            start_date  = as.Date(ts_df$start_date),
            end_date    = as.Date(ts_df$end_date),
            mean_val    = as.numeric(ts_df[["mean"]]),
            min_val     = as.numeric(ts_df[["min"]]),
            max_val     = as.numeric(ts_df[["max"]]),
            stringsAsFactors = FALSE
          )

            # Delete only the specific farm+variable+date-range records being replaced
          farm_ids_to_update <- unique(as.character(ts_df$farm_id))
          for (fid in farm_ids_to_update) {
            DBI::dbExecute(con,
              "DELETE FROM farm_timeseries WHERE farm_id = ? AND variable = ? AND start_date >= ? AND start_date <= ?",
              params = list(fid, var, as.Date(start_str), as.Date(harvest_date))
            )
          }
          # Insert fresh data for this period
          duckdb::dbWriteTable(con, "farm_timeseries", insert_df,
                               append = TRUE, overwrite = FALSE)

          n_new <- nrow(insert_df)
          total_new <- total_new + n_new
          add_log(sprintf("  Saved %d rows for %s.", n_new, var))

          # Optionally clip and save raster blobs
          if (save_rasters) {
            .save_raster_blobs(
              con,
              farms_sf,
              var,
              c(start_str, harvest_date),
              add_log,
              l3_region = if (grepl("^L3-", var)) l3_region else NULL
            )
          }
        } # end for var

        # Log run summary using parameterized query
        DBI::dbExecute(con,
          "INSERT INTO monitoring_log (run_id, started_at, finished_at, n_records, status, message) VALUES (?, ?, ?, ?, ?, ?)",
          params = list(
            run_id,
            format(run_started_at, "%Y-%m-%d %H:%M:%S"),
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            as.integer(total_new),
            "success",
            "OK"
          )
        )

        add_log(sprintf("Done. %d new records inserted.", total_new))
        shiny::showNotification(
          sprintf("\u2714 Monitoring updated: %d new records", total_new),
          type = "message", duration = 5
        )

        # Read back full dataset and store in rv
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
        rv$ts_data <- DBI::dbGetQuery(con, "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date")
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
      n_rasters <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM farm_rasters")$n
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
          
          n_updated <- tryCatch(
            wapor_recalculate_stats_from_rasters(
              con, farm_id, farm_geom, input$threshold_pct
            ),
            error = function(e) {
              message(sprintf("Error for farm %s: %s", farm_id, e$message))
              0
            }
          )
          total_updated <- total_updated + n_updated
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
      
      # Get selected farm and variable (use ts_farm_select and ts_variable inputs)
      farm_id <- input$ts_farm_select
      variable <- input$ts_variable
      
      if (is.null(farm_id) || is.null(variable)) {
        shiny::showNotification("Please select a farm and variable in the Time Series tab first.",
                               type = "warning")
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
      
      p <- tryCatch(
        wapor_plot_raster_timeseries(con, farm_id, variable),
        error = function(e) {
          shiny::showNotification(paste("Plot error:", e$message), type = "error")
          NULL
        }
      )
      
      DBI::dbDisconnect(con, shutdown = TRUE)
      
      if (!is.null(p)) {
        shiny::showModal(shiny::modalDialog(
          title = sprintf("Raster Time Series: %s - %s", farm_id, variable),
          shiny::renderPlot(p, height = 500),
          size = "l",
          easyClose = TRUE,
          footer = shiny::modalButton("Close")
        ))
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
        )

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

    output$rast_var_ui <- shiny::renderUI({
      vars <- names(rv$rast_layers)
      if (length(vars) == 0) {
        ts <- rv$ts_data
        vars <- if (!is.null(ts)) sort(unique(ts$variable)) else .MON_ALL_VARS
      }
      shiny::selectInput(ns("rast_var"), "Variable", choices = vars)
    })

    output$rast_date_ui <- shiny::renderUI({
      ts <- rv$ts_data
      var <- input$rast_var
      if (is.null(ts) || is.null(var)) return(shiny::selectInput(ns("rast_date"), "Date", choices = NULL))
      dates <- sort(unique(ts$start_date[ts$variable == var]))
      shiny::selectInput(ns("rast_date"), "Dekad / Date", choices = as.character(dates))
    })

    output$raster_map <- leaflet::renderLeaflet({
      m <- leaflet::leaflet() |>
        leaflet::addProviderTiles("Esri.WorldImagery", group = "Satellite") |>
        leaflet::addProviderTiles("OpenStreetMap",     group = "OSM") |>
        leaflet::addLayersControl(
          baseGroups = c("Satellite", "OSM"),
          options    = leaflet::layersControlOptions(collapsed = FALSE)
        )

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

      # Try to load raster from DB blobs if available and duckdb is open
      rast_var  <- input$rast_var
      rast_date <- input$rast_date
      if (is.null(rast_var) || is.null(rast_date) ||
          !requireNamespace("duckdb", quietly = TRUE)) return(m)

      db_path <- input$db_path
      if (is.null(db_path) || !file.exists(db_path)) return(m)

      tryCatch({
        con <- open_db(db_path)
        if (is.null(con)) return(m)
        blob_row <- DBI::dbGetQuery(con,
          "SELECT raster_blob FROM farm_rasters WHERE variable = ? AND date_key = ? LIMIT 1",
          params = list(rast_var, rast_date)
        )
        DBI::dbDisconnect(con, shutdown = TRUE)

        if (nrow(blob_row) == 0 || is.null(blob_row$raster_blob[[1]])) return(m)

        tmp_tif <- tempfile(fileext = ".tif")
        writeBin(as.raw(blob_row$raster_blob[[1]]), tmp_tif)
        r <- terra::rast(tmp_tif)

        pal_name <- input$rast_palette %||% "viridis"
        pal_colors <- grDevices::colorRampPalette(
          switch(pal_name,
            "magma"   = viridisLite::magma(11),
            "RdYlGn"  = RColorBrewer::brewer.pal(11, "RdYlGn"),
            "RdYlBu"  = RColorBrewer::brewer.pal(11, "RdYlBu"),
            "Spectral"= RColorBrewer::brewer.pal(11, "Spectral"),
            viridisLite::viridis(11)
          )
        )(255)

        vals <- terra::values(r, na.rm = TRUE)
        pal_fn <- leaflet::colorNumeric(pal_colors,
                                        domain = range(vals, na.rm = TRUE),
                                        na.color = "transparent")

        m |>
          leaflet::addRasterImage(r, colors = pal_fn, opacity = 0.75, group = "Raster") |>
          leaflet::addLegend(pal = pal_fn, values = vals,
                             title = paste0(rast_var, "\n", rast_date),
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

    # ── Cleanup on session end ─────────────────────────────────────────────────
    session$onSessionEnded(function() close_db())

  }) # /moduleServer
} # /mod_monitoring_server


# ── Internal: save raster blobs to DuckDB ─────────────────────────────────────
#
# Clips the full AOI raster for a given variable/period and stores each
# dekadal layer as a compressed BLOB in the farm_rasters table.
# This is optional and only runs when the user ticks "Also save rasters".
#
.save_raster_blobs <- function(con, farms_sf, variable, period, add_log_fn, l3_region = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(invisible(NULL))

  tryCatch({
    # Build bounding box from union of all farms
    bb <- sf::st_bbox(sf::st_union(farms_sf))
    reg <- as.numeric(c(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]))

    urls <- tryCatch(
      Rwapor::wapor_generate_urls(
        variable,
        l3_region = if (grepl("^L3-", variable)) l3_region else NULL,
        period = period
      ),
      error = function(e) { add_log_fn(sprintf("  Raster URLs error: %s", e$message)); NULL }
    )
    if (is.null(urls) || length(urls) == 0) return(invisible(NULL))

    urls_vs <- paste0("/vsicurl/", urls)

    add_log_fn(sprintf("  Saving %d raster layers for %s (per farm)…", length(urls_vs), variable))

    # Process each raster time step
    for (i in seq_along(urls_vs)) {
      tryCatch({
        # Load and crop full extent raster
        r_full <- suppressWarnings(terra::rast(urls_vs[i]))
        r_full <- terra::crop(r_full, terra::ext(reg[1], reg[3], reg[2], reg[4]))
        
        # Extract date from URL
        date_key <- gsub(".*\\.([0-9]{4}-[0-9]{2}-[0-9]{2})\\.tif.*", "\\1",
                         basename(urls[i]))
        if (!nzchar(date_key) || date_key == basename(urls[i])) {
          date_key <- format(Sys.Date() - (length(urls_vs) - i) * 10, "%Y-%m-%d")
        }
        
        # Clip and save raster for each farm
        for (j in seq_len(nrow(farms_sf))) {
          farm_id <- as.character(farms_sf$farm_id[j])
          farm_geom <- farms_sf[j, ]
          
          # Clip to farm extent
          farm_bb <- sf::st_bbox(farm_geom)
          r_farm <- terra::crop(r_full, terra::ext(farm_bb["xmin"], farm_bb["xmax"], 
                                                     farm_bb["ymin"], farm_bb["ymax"]))
          
          # Save using helper function (with extent metadata)
          n_saved <- wapor_save_raster_to_db(con, farm_id, variable, date_key, r_farm)
          
          # Update farm metadata if not already set
          if (j == 1) {  # Only check once per monitoring run
            existing <- DBI::dbGetQuery(con, 
              "SELECT farm_id FROM farm_metadata WHERE farm_id = ?", 
              params = list(farm_id)
            )
            if (nrow(existing) == 0) {
              # Insert placeholder
              DBI::dbExecute(con, 
                "INSERT INTO farm_metadata (farm_id) VALUES (?)",
                params = list(farm_id)
              )
            }
            wapor_update_farm_metadata(con, farm_id, farm_geom)
          }
        }
        
        add_log_fn(sprintf("    Saved layer %d/%d (%s)", i, length(urls_vs), date_key))
        
      }, error = function(e) {
        add_log_fn(sprintf("  Raster blob error layer %d: %s", i, e$message))
      })
    }
    
    add_log_fn(sprintf("  ✓ Saved %d rasters for %d farms", length(urls_vs), nrow(farms_sf)))
    
  }, error = function(e) {
    add_log_fn(sprintf("  .save_raster_blobs error: %s", e$message))
  })
  invisible(NULL)
}
