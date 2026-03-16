# Build variable list from package metadata (L1, L2, L3 + AgERA5)
all_vars <- unname(sort(unique(c(names(Rwapor::WAPOR3_VARS), names(Rwapor::AGERA5_VARS)))))
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else all_vars[1]

# Build L3 region choices from package metadata: "Country - Name (CODE)"
l3_regions_meta <- Rwapor::L3_REGIONS
l3_region_labels <- vapply(names(l3_regions_meta), function(code) {
  r <- l3_regions_meta[[code]]
  sprintf("%s - %s (%s)", r$country, r$name, code)
}, character(1))
# Sort by label (country first) and build named vector: label -> code
l3_region_labels <- sort(l3_region_labels)
l3_region_choices <- as.list(stats::setNames(
  sub(".*\\(([A-Z]{3})\\)$", "\\1", l3_region_labels),
  l3_region_labels
))

draw_pkg <- if (requireNamespace("leaflet.extras", quietly = TRUE)) {
  "leaflet.extras"
} else if (requireNamespace("leaflet.extras2", quietly = TRUE)) {
  "leaflet.extras2"
} else {
  NULL
}

resolve_draw_fun <- function(pkg, candidates) {
  if (is.null(pkg)) return(NULL)
  for (nm in candidates) {
    if (exists(nm, where = asNamespace(pkg), inherits = FALSE)) {
      return(get(nm, envir = asNamespace(pkg), inherits = FALSE))
    }
  }
  NULL
}

add_draw_toolbar <- resolve_draw_fun(draw_pkg, c("addDrawToolbar", "add_draw_toolbar"))
edit_toolbar_options <- resolve_draw_fun(draw_pkg, c("editToolbarOptions", "edit_toolbar_options"))
selected_path_options <- resolve_draw_fun(draw_pkg, c("selectedPathOptions", "selected_path_options"))
has_draw_tools <- !is.null(add_draw_toolbar) &&
  !is.null(edit_toolbar_options) &&
  !is.null(selected_path_options)

extract_bbox_from_feature <- function(feature) {
  if (is.null(feature) || is.null(feature$geometry) || is.null(feature$geometry$coordinates)) {
    return(NULL)
  }
  gtype <- feature$geometry$type
  coords <- switch(
    gtype,
    "Polygon" = feature$geometry$coordinates[[1]],
    "MultiPolygon" = feature$geometry$coordinates[[1]][[1]],
    NULL
  )
  if (is.null(coords) || length(coords) == 0) {
    return(NULL)
  }
  mat <- do.call(rbind, lapply(coords, unlist))
  if (is.null(dim(mat)) || ncol(mat) < 2) {
    return(NULL)
  }
  c(min(mat[, 1]), min(mat[, 2]), max(mat[, 1]), max(mat[, 2]))
}

build_polygon_file <- function(coords_mat) {
  if (nrow(coords_mat) < 3) return(NULL)
  if (!all(coords_mat[1, ] == coords_mat[nrow(coords_mat), ])) {
    coords_mat <- rbind(coords_mat, coords_mat[1, ])
  }
  poly <- sf::st_polygon(list(coords_mat))
  shp <- sf::st_sf(id = 1L, geometry = sf::st_sfc(poly, crs = 4326))
  temp_path <- tempfile(fileext = ".geojson")
  sf::st_write(shp, temp_path, quiet = TRUE, delete_dsn = TRUE)
  temp_path
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
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
  header = shiny::tags$head(shiny::tags$style(shiny::HTML("

    /* ── Map fills the viewport ─────────────────────────────────── */
    .main-map-output .leaflet-container {
      height: calc(100vh - 130px) !important;
      min-height: 480px;
      border-radius: 0.375rem;
    }
    .main-map-output {
      height: calc(100vh - 130px) !important;
      min-height: 480px;
    }

    /* ── Remove old square-map constraints ──────────────────────── */
    #analysis_map_card .leaflet-container,
    #download_map_card  .leaflet-container { aspect-ratio: unset; }

    /* ── Sidebar: flex column so sticky footer works ────────────── */
    .bslib-sidebar-layout > .sidebar > .sidebar-content {
      display: flex;
      flex-direction: column;
      height: 100%;
      overflow-y: auto;
      padding-bottom: 0 !important;
    }
    .sidebar-scroll-area {
      flex: 1 1 auto;
      overflow-y: auto;
      padding: 0.5rem 0.75rem 0.25rem;
    }
    .sidebar-sticky-footer {
      flex-shrink: 0;
      position: sticky;
      bottom: 0;
      background: #f8f9fa;
      border-top: 1px solid #dee2e6;
      padding: 0.6rem 0.75rem;
      z-index: 20;
    }

    /* ── Compact accordion ──────────────────────────────────────── */
    .accordion-body       { padding: 0.4rem 0.6rem; }
    .accordion-button     { padding: 0.5rem 0.75rem; font-size: 0.88rem; }
    .accordion-button:focus { box-shadow: none; }

    /* ── Compact sidebar inputs ─────────────────────────────────── */
    .sidebar .form-label,
    .sidebar label         { font-size: 0.82rem; margin-bottom: 0.15rem; }
    .sidebar .form-control,
    .sidebar .form-select  { font-size: 0.82rem; padding: 0.25rem 0.5rem; }
    .sidebar .form-check-label { font-size: 0.82rem; }
    .sidebar .shiny-input-container { margin-bottom: 0.4rem; }
    .sidebar hr { margin: 0.4rem 0; }

    /* ── Code preview collapsible panel ─────────────────────────── */
    .code-preview-toggle {
      width: 100%;
      text-align: left;
      font-size: 0.82rem;
      border-radius: 0 0 0.375rem 0.375rem;
    }
    .code-preview-body {
      max-height: 220px;
      overflow-y: auto;
      font-size: 0.78rem;
      background: #f8f9fa;
      border: 1px solid #dee2e6;
      border-top: none;
      padding: 0.5rem;
      border-radius: 0 0 0.375rem 0.375rem;
    }
    .code-preview-body pre { margin: 0; font-size: 0.78rem; }

    /* ── Raster info in card footer ─────────────────────────────── */
    #raster_info_table       { font-size: 0.8rem; }
    #raster_info_table table { margin-bottom: 0; }
    .card-footer.raster-footer {
      padding: 0.3rem 0.75rem;
      background: #f8f9fa;
      font-size: 0.8rem;
    }

    /* ── General card tightening ────────────────────────────────── */
    .card          { margin-bottom: 0.6rem; }
    .card-header   { padding: 0.4rem 0.75rem; font-size: 0.88rem; }
    .card-body.compact { padding: 0.4rem; }

    /* ── Download btn in sidebar ────────────────────────────────── */
    .btn-sm-sidebar { font-size: 0.82rem; padding: 0.3rem 0.6rem; }
  "))),

  # ── Download Tab ────────────────────────────────────────────────────────────
  bslib::nav_panel(
    "Download",
    icon = shiny::icon("cloud-download"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 300,
        # open = TRUE keeps it open; built-in toggle button collapses it
        open  = TRUE,
        title = "Download Configuration",

        shiny::div(
          class = "sidebar-scroll-area",

          bslib::accordion(
            id   = "download_accordion",
            open = c("Variable & Period", "Area of Interest"),

            # ── Variable & Period ──────────────────────────────────
            bslib::accordion_panel(
              "Variable & Period",
              icon = shiny::icon("database"),
              shiny::selectInput("variable", "Variable",
                choices = all_vars, selected = default_var),
              shiny::conditionalPanel(
                condition = "input.variable.startsWith('L3-')",
                shiny::selectInput("l3_region", "L3 Region",
                  choices = l3_region_choices),
                shiny::helpText("L3 variables require a specific region.")
              ),
              shiny::dateRangeInput("period", "Period",
                start  = Sys.Date() - 30,
                end    = Sys.Date(),
                format = "yyyy-mm-dd")
            ),

            # ── Output Settings (starts collapsed) ────────────────
            bslib::accordion_panel(
              "Output Settings",
              icon = shiny::icon("folder"),
              shiny::fluidRow(
                shiny::column(8, shiny::textInput("folder", "Output Folder",
                  value = file.path(getwd(), "wapor_output"))),
                shiny::column(4, shinyFiles::shinyDirButton("browse_folder",
                  "Browse", "Select output directory", width = "100%"))
              ),
              shiny::checkboxInput("seasonal",       "Seasonal Aggregation", FALSE),
              shiny::checkboxInput("separate_files", "Save as Separate Files", FALSE),
              shiny::conditionalPanel(
                condition = "input.seasonal && input.separate_files",
                shiny::helpText(shiny::tags$em(
                  "Both selected: seasonal + individual time-step files."))
              ),
              shiny::selectInput("unit_conversion", "Unit Conversion",
                choices  = as.list(c("none", "day", "dekad", "month", "year")),
                selected = "none")
            ),

            # ── Area of Interest ──────────────────────────────────
            bslib::accordion_panel(
              "Area of Interest",
              icon = shiny::icon("map"),
              shiny::conditionalPanel(
                condition = "input.variable.startsWith('L3-')",
                shiny::helpText(shiny::tags$em(
                  "AOI clips data; leave empty to download whole region."))
              ),
              shiny::radioButtons("manual_mode", "Draw Mode",
                choices  = as.list(c("Rectangle" = "bbox", "Polygon" = "poly")),
                selected = "bbox", inline = TRUE),
              shiny::fluidRow(
                shiny::column(4, shiny::actionButton("start_manual",  "Start",
                  icon = shiny::icon("pencil"), width = "100%",
                  class = "btn-sm btn-outline-success")),
                shiny::column(4, shiny::actionButton("finish_manual", "Finish",
                  icon = shiny::icon("check"),  width = "100%",
                  class = "btn-sm btn-outline-primary")),
                shiny::column(4, shiny::actionButton("clear_manual",  "Clear",
                  icon = shiny::icon("eraser"), width = "100%",
                  class = "btn-sm btn-outline-danger"))
              ),
              shiny::tags$small(class = "text-muted",
                "Works even without leaflet.extras."),
              shiny::tags$div(class = "mt-2",
                shinyFiles::shinyFilesButton("browse_vector",
                  "Select Vector File (.geojson, .gpkg, .kml)",
                  "Select vector file",
                  multiple = FALSE,
                  class    = "w-100 btn-sm btn-outline-secondary",
                  icon     = shiny::icon("folder-open"))
              ),
              shiny::checkboxInput("mask_aoi", "Mask to AOI boundary", FALSE),
              shiny::tags$strong(style = "font-size:0.82rem;", "Selected ROI"),
              shiny::verbatimTextOutput("bbox_display")
            )
          )
        ), # end sidebar-scroll-area

        # ── Sticky footer: Download button ───────────────────────
        shiny::div(
          class = "sidebar-sticky-footer",
          shiny::actionButton("download_btn", "Download Data",
            class = "btn-primary w-100",
            icon  = shiny::icon("cloud-download"))
        )
      ), # end sidebar

      # ── Main panel ──────────────────────────────────────────────
      shiny::div(
        bslib::card(
          id = "download_map_card",
          full_screen = TRUE,
          bslib::card_header("Map"),
          bslib::card_body(
            class = "p-0 main-map-output",
            leaflet::leafletOutput("map", height = "100%", width = "100%")
          )
        ),

        # ── R Code Preview — collapsible below map ───────────────
        shiny::tags$button(
          class            = "btn btn-sm btn-outline-secondary code-preview-toggle mt-1",
          `data-bs-toggle` = "collapse",
          `data-bs-target` = "#codePreviewCollapse",
          `aria-expanded`  = "false",
          shiny::icon("code"), " R Code Preview"
        ),
        shiny::div(
          id    = "codePreviewCollapse",
          class = "collapse code-preview-body",
          shiny::verbatimTextOutput("code_preview")
        )
      )
    )
  ),

  # ── Visualisation Tab ───────────────────────────────────────────────────────
  bslib::nav_panel(
    "Visualisation",
    icon = shiny::icon("chart-area"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 260,
        open  = TRUE,
        title = "Raster Visualization",

        shiny::div(
          class = "sidebar-scroll-area",

          bslib::accordion(
            id   = "analysis_accordion",
            open = c("Raster Selection", "Color Palette"),

            # ── Raster Selection ────────────────────────────────
            bslib::accordion_panel(
              "Raster Selection",
              icon = shiny::icon("file-image"),
              shiny::fluidRow(
                shiny::column(8, shiny::textInput("analysis_folder", "Raster Folder",
                  value = file.path(getwd(), "wapor_output"))),
                shiny::column(4, shinyFiles::shinyDirButton("browse_analysis_folder",
                  "Browse", "Select raster directory", width = "100%"))
              ),
              shiny::actionButton("scan_rasters", "Scan Folder",
                icon  = shiny::icon("magnifying-glass"),
                class = "btn-outline-primary w-100 mb-2 btn-sm"),
              shiny::selectInput("raster_file", "Select Raster", choices = NULL),
              shiny::selectInput("raster_band", "Band / Layer",  choices = NULL)
            ),

            # ── Color Palette ───────────────────────────────────
            bslib::accordion_panel(
              "Color Palette",
              icon = shiny::icon("palette"),
              shiny::selectInput("palette_name", "Palette",
                choices = as.list(c(
                  "viridis", "magma", "plasma", "inferno", "cividis",
                  "terrain.colors", "heat.colors", "topo.colors",
                  "RdYlGn", "RdYlBu", "Spectral", "BrBG")),
                selected = "viridis"),
              shiny::sliderInput("n_colors", "Classes",
                min = 3, max = 15, value = 7, step = 1),
              shiny::sliderInput("raster_opacity", "Opacity",
                min = 0, max = 1, value = 0.8, step = 0.05),
              shiny::checkboxInput("reverse_palette", "Reverse Palette", FALSE),
              shiny::radioButtons("color_method", "Method",
                choices  = as.list(c("Continuous" = "numeric", "Binned" = "bin")),
                selected = "numeric", inline = TRUE)
            ),

            # ── Overlay Options ─────────────────────────────────
            bslib::accordion_panel(
              "Overlay Options",
              icon = shiny::icon("layer-group"),

              shiny::checkboxInput("overlay_aoi", "Show AOI Boundary", TRUE),
              shiny::selectInput("basemap_analysis", "Basemap",
                choices = as.list(c(
                  "Esri.WorldImagery", "OpenStreetMap",
                  "CartoDB.Positron",  "CartoDB.DarkMatter")),
                selected = "CartoDB.Positron"),

              shiny::hr(style = "margin:4px 0;"),

              # --- Analysis Layers (populated from Analysis tab uploads) ---
              shiny::tags$p(
                shiny::tags$strong("Analysis Layers"),
                style = "font-size:0.8rem; color:#2c3e50; margin-bottom:2px;"
              ),
              shiny::tags$small(
                class = "text-muted d-block mb-1",
                "Upload rasters in the Analysis tab to enable these layers."
              ),
              shiny::checkboxInput("show_crop_mask",    "Crop Mask (categorical)",  FALSE),
              shiny::checkboxInput("show_season_start", "Season Start (Julian DOY)", FALSE),
              shiny::checkboxInput("show_season_end",   "Season End (Julian DOY)",   FALSE),

              # Opacity slider shared for analysis layers
              shiny::conditionalPanel(
                condition = "input.show_crop_mask || input.show_season_start || input.show_season_end",
                shiny::sliderInput("an_layer_opacity", "Layer Opacity",
                  min = 0, max = 1, value = 0.75, step = 0.05)
              )
            )
          )
        )
      ), # end sidebar

      # ── Main panel: map + raster info in footer ──────────────────
      bslib::card(
        id          = "analysis_map_card",
        full_screen = TRUE,
        bslib::card_header("Raster Visualization"),
        bslib::card_body(
          class = "p-0 main-map-output",
          leaflet::leafletOutput("analysis_map", height = "100%", width = "100%")
        ),
        bslib::card_footer(
          class = "raster-footer",
          shiny::div(id = "raster_info_table",
            shiny::tableOutput("raster_info"))
        )
      )
    )
  ),

  # ── Analysis Tab ────────────────────────────────────────────────────────────
  bslib::nav_panel(
    "Analysis",
    icon = shiny::icon("flask"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 360,
        open  = TRUE,
        title = "Crop Season Analysis",

        # ── Scrollable accordion area ────────────────────────────
        shiny::div(
          class = "sidebar-scroll-area",

          bslib::accordion(
            id   = "analysis_config_accordion",
            open = c("Season Definition", "Data Inputs"),

            # ── Season Definition ────────────────────────────────
            bslib::accordion_panel(
              "Season Definition",
              icon = shiny::icon("calendar"),
              shiny::textInput("an_season_label", "Season Label",
                value       = "Winter 2023",
                placeholder = "e.g. Winter 2023"),
              shiny::fluidRow(
                shiny::column(5,
                  shiny::numericInput("an_ref_year", "Ref. Year",
                    value = 2023, min = 2009, max = 2030, step = 1)),
                shiny::column(7,
                  shiny::dateRangeInput("an_period", "Analysis Period",
                    start  = "2023-01-01",
                    end    = "2023-12-31",
                    format = "yyyy-mm-dd"))
              )
            ),

            # ── Data Inputs ──────────────────────────────────────
            bslib::accordion_panel(
              "Data Inputs",
              icon = shiny::icon("upload"),
              # File uploads side by side to save space
              shiny::fluidRow(
                shiny::column(12,
                  shiny::fileInput("an_crop_mask",    "Crop Mask",
                    accept = c(".tif", ".tiff"))),
                shiny::column(6,
                  shiny::fileInput("an_season_start", "Season Start (DOY)",
                    accept = c(".tif", ".tiff"))),
                shiny::column(6,
                  shiny::fileInput("an_season_end",   "Season End (DOY)",
                    accept = c(".tif", ".tiff")))
              ),
              shiny::hr(),
              shiny::fluidRow(
                shiny::column(6,
                  shiny::selectInput("an_aeti_var", "AETI",
                    choices  = grep("AETI-D", all_vars, value = TRUE),
                    selected = if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else NULL)),
                shiny::column(6,
                  shiny::selectInput("an_ret_var",   "RET",
                    choices  = grep("RET|ET0", all_vars, value = TRUE),
                    selected = if ("L1-RET-D" %in% all_vars) "L1-RET-D" else NULL))
              ),
              shiny::fluidRow(
                shiny::column(6,
                  shiny::selectInput("an_precip_var", "Precip",
                    choices  = grep("PCP|PF", all_vars, value = TRUE),
                    selected = if ("L1-PCP-D" %in% all_vars) "L1-PCP-D" else NULL)),
                shiny::column(6,
                  shiny::selectInput("an_npp_var",    "NPP",
                    choices  = grep("NPP|TBP", all_vars, value = TRUE),
                    selected = if ("L1-NPP-D" %in% all_vars) "L1-NPP-D" else NULL))
              ),
              shiny::conditionalPanel(
                condition = "input.an_aeti_var.startsWith('L3-')",
                shiny::selectInput("an_l3_region", "L3 Region",
                  choices = l3_region_choices)
              )
            ),

            # ── Crop Classes ─────────────────────────────────────
            bslib::accordion_panel(
              "Crop Classes",
              icon = shiny::icon("seedling"),
              shiny::helpText("Upload crop mask first, then assign profiles per class."),
              shiny::uiOutput("an_crop_class_ui")
            ),

            # ── Indicators ───────────────────────────────────────────────
            bslib::accordion_panel(
              "Indicators",
              icon = shiny::icon("chart-line"),

              # --- Group 1: Seasonal Aggregation ---
              shiny::tags$p(
                shiny::tags$strong("Seasonal Aggregation"),
                style = "font-size:0.8rem; color:#2c3e50; margin-bottom:2px;"
              ),
              shiny::tags$small(
                class = "text-muted d-block mb-1",
                "Select which variables to aggregate over the season."
              ),
              shiny::checkboxGroupInput(
                "an_agg_vars", NULL,
                choiceNames = list(
                  "AETI  (Actual ET)",
                  "RET   (Reference ET)",
                  "NPP   (Biomass)",
                  "PCP   (Precipitation)",
                  "Peff  (Effective Precip, USDA)"
                ),
                choiceValues = list(
                  "agg_aeti", "agg_ret", "agg_npp", "agg_pcp", "agg_peff"
                ),
                selected = c("agg_aeti", "agg_ret")
              ),

              shiny::hr(style = "margin:4px 0;"),

              # --- Group 2: Derived Indicators ---
              shiny::tags$p(
                shiny::tags$strong("Derived Indicators"),
                style = "font-size:0.8rem; color:#2c3e50; margin-bottom:2px;"
              ),
              shiny::checkboxGroupInput(
                "an_derived_vars", NULL,
                choiceNames = list(
                  "ETc  (RET \u00d7 Kc)",
                  "Adequacy \u2014 ETc",
                  "Adequacy \u2014 P95",
                  "CWP / BWP"
                ),
                choiceValues = list("etc", "adequacy_etc", "adequacy_p95", "cwp_bwp"),
                selected = c("etc", "adequacy_etc")
              ),

              # --- CWP/BWP file inputs (conditional) ---
              shiny::conditionalPanel(
                condition = "input.an_derived_vars.indexOf('cwp_bwp') > -1",
                shiny::fluidRow(
                  shiny::column(6,
                    shiny::fileInput("an_yield_file", "Yield Raster",
                      accept = c(".tif", ".tiff")),
                    shiny::selectInput("an_yield_unit", "Unit",
                      choices = as.list(c("kg/ha", "t/ha")), selected = "kg/ha")
                  ),
                  shiny::column(6,
                    shiny::fileInput("an_biomass_file", "Biomass Raster",
                      accept = c(".tif", ".tiff")),
                    shiny::selectInput("an_biomass_unit", "Unit",
                      choices = as.list(c("kg/ha", "t/ha")), selected = "kg/ha")
                  )
                )
              )
            )
          )
        ), # end sidebar-scroll-area

        # ── Sticky footer: Run Controls ──────────────────────────
        shiny::div(
          class = "sidebar-sticky-footer",
          shiny::fluidRow(
            shiny::column(4,
              shiny::actionButton("an_validate_btn", "Validate",
                class = "btn-sm btn-outline-primary w-100",
                icon  = shiny::icon("check-circle"))),
            shiny::column(4,
              shiny::actionButton("an_run_btn", "Run",
                class = "btn-sm btn-primary w-100",
                icon  = shiny::icon("play"))),
            shiny::column(4,
              shiny::actionButton("an_reset_btn", "Reset",
                class = "btn-sm btn-outline-danger w-100",
                icon  = shiny::icon("rotate-left")))
          )
        )
      ), # end sidebar

      # ── Main panel ──────────────────────────────────────────────
      bslib::layout_column_wrap(
        width = 1,

        # Season summary banner (compact)
        bslib::card(
          bslib::card_header("Season Summary"),
          bslib::card_body(
            class = "compact",
            shiny::verbatimTextOutput("an_season_summary"))
        ),

        # Crop data + season rasters (tabbed)
        bslib::navset_card_tab(
          title = "Crop Data",
          bslib::nav_panel("Crop Mask Preview",
            shiny::plotOutput("an_crop_mask_plot", height = "300px")),
          bslib::nav_panel("Season Rasters",
            shiny::verbatimTextOutput("an_season_raster_info")),
          bslib::nav_panel("Crop Class Table",
            shiny::tableOutput("an_crop_class_table"))
        ),

        # Kc Curves
        bslib::card(
          bslib::card_header("Kc Curves by Class"),
          bslib::card_body(
            shiny::plotOutput("an_kc_plot", height = "300px"))
        ),

        # Results (tabbed)
        bslib::navset_card_tab(
          title = "Analysis Results",
          bslib::nav_panel("ETc & AETI",
            shiny::tableOutput("an_etc_aeti_table")),
          bslib::nav_panel("Adequacy",
            shiny::tableOutput("an_adequacy_table")),
          bslib::nav_panel("Effective Precip",
            shiny::tableOutput("an_peff_table")),
          bslib::nav_panel("CWP / BWP",
            shiny::tableOutput("an_cwp_bwp_table"))
        ),

        # Export + collapsible code preview
        bslib::card(
          bslib::card_header("Export"),
          bslib::card_body(
            shiny::fluidRow(
              shiny::column(4,
                shiny::downloadButton("an_dl_crop_params",
                  "Crop Parameters CSV",
                  class = "btn-outline-primary w-100 btn-sm mb-1")),
              shiny::column(4,
                shiny::downloadButton("an_dl_results",
                  "Seasonal Results CSV",
                  class = "btn-outline-primary w-100 btn-sm mb-1")),
              shiny::column(4,
                shiny::downloadButton("an_dl_peff",
                  "Monthly Peff CSV",
                  class = "btn-outline-primary w-100 btn-sm mb-1"))
            )
          )
        ),
        shiny::tags$button(
          class            = "btn btn-sm btn-outline-secondary code-preview-toggle",
          `data-bs-toggle` = "collapse",
          `data-bs-target` = "#anCodePreviewCollapse",
          `aria-expanded`  = "false",
          shiny::icon("code"), " R Code Preview"
        ),
        shiny::div(
          id    = "anCodePreviewCollapse",
          class = "collapse code-preview-body",
          shiny::verbatimTextOutput("an_code_preview")
        )
      )
    )
  ),

  # ---- Navbar extras -------------------------------------------------------
  bslib::nav_spacer(),
  bslib::nav_item(
    shiny::tags$a(
      shiny::icon("github"), " GitHub",
      href = "https://github.com/almutaz9000/Rwapor",
      target = "_blank",
      style = "color: rgba(255,255,255,0.85);"
    )
  ),
  bslib::nav_item(
    shiny::actionButton("exit_btn", "Exit", 
      icon = shiny::icon("power-off"),
      class = "btn-danger btn-sm",
      style = "margin-left: 10px; color: white;")
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
server <- function(input, output, session) {

  # ---- Null-coalescing operator (compatible with R < 4.4) ------------------
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

  # ---- Shared reactive state -----------------------------------------------
  user_roi <- shiny::reactiveVal(NULL)
  upload_roi <- shiny::reactiveVal(NULL)
  manual_clicks <- shiny::reactiveVal(matrix(numeric(), ncol = 2,
    dimnames = list(NULL, c("lng", "lat"))))
  manual_active <- shiny::reactiveVal(FALSE)
  
  # ---- Exit Dashboard ------------------------------------------------------
  shiny::observeEvent(input$exit_btn, {
    log_msg("Shutting down dashboard...")
    shiny::stopApp()
  })

  current_region <- shiny::reactive({
    # Prioritize manual ROI (drawn or uploaded) for clipping
    if (!is.null(upload_roi())) return(upload_roi())
    if (!is.null(user_roi())) return(user_roi())

    # Fall back to L3 region code for L3 variables if no manual ROI
    if (grepl("^L3-", input$variable)) {
      reg <- input$l3_region
      if (!is.null(reg) && nzchar(reg)) return(reg)
    }
    NULL
  })

  # ---- Folder browser ------------------------------------------------------
  roots <- c(Home = normalizePath("~", winslash = "/"), "C:/" = "C:/")
  shinyFiles::shinyDirChoose(input, "browse_folder", roots = roots,
    session = session)
  shiny::observeEvent(input$browse_folder, {
    dir_path <- shinyFiles::parseDirPath(roots, input$browse_folder)
    if (length(dir_path) == 1 && nzchar(dir_path)) {
      shiny::updateTextInput(session, "folder", value = dir_path)
    }
  })
  
  # Browser for vector files
  shinyFiles::shinyFileChoose(input, "browse_vector", roots = roots, 
    session = session, filetypes = c("geojson", "gpkg", "kml"))
  
  shiny::observeEvent(input$browse_vector, {
    file_info <- shinyFiles::parseFilePaths(roots, input$browse_vector)
    if (nrow(file_info) > 0) {
      path <- normalizePath(file_info$datapath, winslash = "/", mustWork = FALSE)
      # Trigger the same logic as vector_file upload
      handle_vector_file(path)
    }
  })

  handle_vector_file <- function(path) {
    ext <- tolower(tools::file_ext(path))
    allowed_ext <- c("geojson", "gpkg", "kml")
    if (!ext %in% allowed_ext) {
      shiny::showNotification(
        sprintf("Unsupported format '.%s'. Use: %s", ext,
          paste(allowed_ext, collapse = ", ")),
        type = "error")
      return()
    }
    tryCatch({
      shp <- sf::st_read(path, quiet = TRUE)
      if (nrow(shp) == 0) stop("Vector file contains no features.")
      shp_map <- shp
      shp_crs <- sf::st_crs(shp_map)
      if (!is.na(shp_crs) && shp_crs$epsg != 4326) {
        shp_map <- sf::st_transform(shp_map, 4326)
      }
      bbox <- sf::st_bbox(shp_map)
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::clearGroup("manual_preview") |>
        leaflet::clearShapes() |>
        leaflet::clearGroup("draw") |>
        leaflet::addPolygons(data = shp_map, color = "red",
          fill = FALSE, weight = 2) |>
        leaflet::addRectangles(
          lng1 = as.numeric(bbox["xmin"]), lat1 = as.numeric(bbox["ymin"]),
          lng2 = as.numeric(bbox["xmax"]), lat2 = as.numeric(bbox["ymax"]),
          color = "blue", fill = FALSE, weight = 1, dashArray = "4") |>
        leaflet::fitBounds(
          lng1 = as.numeric(bbox["xmin"]), lat1 = as.numeric(bbox["ymin"]),
          lng2 = as.numeric(bbox["xmax"]), lat2 = as.numeric(bbox["ymax"]))
      upload_roi(path)
      user_roi(NULL)
      manual_active(FALSE)
      shiny::showNotification("Vector file loaded successfully.",
        type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error reading vector file:", e$message),
        type = "error")
    })
  }

  # Sync analysis folder with download folder (initially or on change)
  shiny::observeEvent(input$folder, {
    # Only update if they match (still on default/sync)
    # or if analysis_folder is empty
    if (!nzchar(input$analysis_folder) || 
        isTRUE(getOption("rwapor.sync_folders", TRUE))) {
       shiny::updateTextInput(session, "analysis_folder", value = input$folder)
    }
  })

  shinyFiles::shinyDirChoose(input, "browse_analysis_folder", roots = roots,
    session = session)
  shiny::observeEvent(input$browse_analysis_folder, {
    dir_path <- shinyFiles::parseDirPath(roots, input$browse_analysis_folder)
    if (length(dir_path) == 1 && nzchar(dir_path)) {
      shiny::updateTextInput(session, "analysis_folder", value = dir_path)
      # Once manually changed, we might want to stop auto-sync
      options(rwapor.sync_folders = FALSE)
    }
  })

  # ==========================================================================
  # DOWNLOAD TAB SERVER
  # ==========================================================================

  output$map <- leaflet::renderLeaflet({
    m <- leaflet::leaflet() |>
      leaflet::addProviderTiles("Esri.WorldImagery")
    if (has_draw_tools) {
      m <- m |>
        add_draw_toolbar(
          targetGroup = "draw",
          polylineOptions = FALSE,
          circleOptions = FALSE,
          markerOptions = FALSE,
          circleMarkerOptions = FALSE,
          editOptions = edit_toolbar_options(
            selectedPathOptions = selected_path_options())
        )
    }
    m |> leaflet::setView(lng = 18, lat = 2, zoom = 3)
  })

  # ---- Manual draw ---------------------------------------------------------
  shiny::observeEvent(input$start_manual, {
    manual_active(TRUE)
    manual_clicks(matrix(numeric(), ncol = 2,
      dimnames = list(NULL, c("lng", "lat"))))
    upload_roi(NULL)
    shiny::showNotification(
      "Manual draw started. Click on map to add points.", type = "message")
    leaflet::leafletProxy("map") |> leaflet::clearGroup("manual_draw")
  })

  shiny::observeEvent(input$map_click, {
    if (!manual_active()) return()
    click <- input$map_click
    current <- manual_clicks()
    current <- rbind(current, c(click$lng, click$lat))
    manual_clicks(current)
    leaflet::leafletProxy("map") |>
      leaflet::addCircleMarkers(lng = click$lng, lat = click$lat,
        radius = 4, group = "manual_draw", fillOpacity = 1)

    if (input$manual_mode == "bbox" && nrow(current) >= 2) {
      bbox <- c(min(current[, 1]), min(current[, 2]),
                max(current[, 1]), max(current[, 2]))
      user_roi(bbox)
      upload_roi(NULL)
      manual_active(FALSE)
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::addRectangles(
          lng1 = bbox[1], lat1 = bbox[2], lng2 = bbox[3], lat2 = bbox[4],
          color = "yellow", fill = FALSE, weight = 2, group = "manual_draw") |>
        leaflet::fitBounds(lng1 = bbox[1], lat1 = bbox[2], 
                           lng2 = bbox[3], lat2 = bbox[4])
      shiny::showNotification("Rectangle AOI set.", type = "message")
    } else if (input$manual_mode == "poly" && nrow(current) >= 2) {
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_preview") |>
        leaflet::addPolylines(lng = current[, 1], lat = current[, 2],
          color = "yellow", weight = 2, group = "manual_preview")
    }
  })

  shiny::observeEvent(input$finish_manual, {
    if (!manual_active()) {
      shiny::showNotification("Start manual draw first.", type = "warning")
      return()
    }
    pts <- manual_clicks()
    if (input$manual_mode == "poly") {
      if (nrow(pts) < 3) {
        shiny::showNotification("Polygon needs at least 3 points.",
          type = "error")
        return()
      }
      poly_path <- tryCatch(build_polygon_file(pts), error = function(e) NULL)
      if (is.null(poly_path) || !file.exists(poly_path)) {
        shiny::showNotification("Failed to build polygon AOI.", type = "error")
        return()
      }
      upload_roi(poly_path)
      user_roi(NULL)
      manual_active(FALSE)
      if (!all(pts[1, ] == pts[nrow(pts), ])) {
        pts <- rbind(pts, pts[1, ])
      }
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_preview") |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::addPolygons(lng = pts[, 1], lat = pts[, 2],
          color = "yellow", fill = FALSE, weight = 2, group = "manual_draw") |>
        leaflet::fitBounds(lng1 = min(pts[, 1]), lat1 = min(pts[, 2]),
                           lng2 = max(pts[, 1]), lat2 = max(pts[, 2]))
      shiny::showNotification("Polygon AOI set.", type = "message")
    } else {
      shiny::showNotification(
        "Rectangle mode auto-finishes after 2 clicks.", type = "message")
    }
  })

  shiny::observeEvent(input$clear_manual, {
    manual_active(FALSE)
    manual_clicks(matrix(numeric(), ncol = 2,
      dimnames = list(NULL, c("lng", "lat"))))
    user_roi(NULL)
    upload_roi(NULL)
    leaflet::leafletProxy("map") |>
      leaflet::clearGroup("manual_draw") |>
      leaflet::clearGroup("manual_preview") |>
      leaflet::clearShapes()
  })

  # ---- Draw toolbar events -------------------------------------------------
  shiny::observeEvent(input$map_draw_new_feature, {
    bbox <- extract_bbox_from_feature(input$map_draw_new_feature)
    if (!is.null(bbox)) {
      user_roi(bbox)
      upload_roi(NULL)
      manual_active(FALSE)
    }
  })

  shiny::observeEvent(input$map_draw_edited_features, {
    edited <- input$map_draw_edited_features$features
    if (length(edited) > 0) {
      bbox <- extract_bbox_from_feature(edited[[1]])
      if (!is.null(bbox)) {
        user_roi(bbox)
        upload_roi(NULL)
      }
    }
  })

  shiny::observeEvent(input$map_draw_deleted_features, {
    user_roi(NULL)
    upload_roi(NULL)
  })

  # (input$vector_file observer removed as user prefers local Browse)

  # ---- ROI display ---------------------------------------------------------
  output$bbox_display <- shiny::renderPrint({
    reg <- current_region()
    if (is.null(reg)) {
      cat("No AOI selected.")
    } else if (is.character(reg) && nchar(reg) == 3 && grepl("^[A-Z]{3}$", reg)) {
      r_meta <- l3_regions_meta[[reg]]
      if (!is.null(r_meta)) {
        cat(sprintf("L3 Region: %s - %s (%s)", r_meta$country, r_meta$name, reg))
      } else {
        cat(sprintf("L3 Region: %s", reg))
      }
    } else if (is.character(reg)) {
      cat("Vector file:\n", reg)
    } else if (is.numeric(reg)) {
      cat(sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4]))
    }
  })

  # ---- Code preview --------------------------------------------------------
  output$code_preview <- shiny::renderText({
    reg <- current_region()
    if (is.null(reg)) {
      reg_str <- "NULL  # Please select an AOI on the map or upload a file"
    } else if (is.character(reg) && nchar(reg) == 3 && grepl("^[A-Z]{3}$", reg)) {
      reg_str <- sprintf("\"%s\"", reg)
    } else if (is.character(reg)) {
      reg_str <- sprintf("\"%s\"",
        normalizePath(reg, winslash = "/", mustWork = FALSE))
    } else {
      reg_str <- sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
    }
    period_str <- sprintf("c(\"%s\", \"%s\")", input$period[1], input$period[2])
    unit_conv <- if (input$unit_conversion == "none") "NULL" else
      sprintf("\"%s\"", input$unit_conversion)
    mask_str <- if (input$mask_aoi) "TRUE" else "FALSE"

    # When both seasonal and separate_files are selected, show two calls
    if (input$seasonal && input$separate_files) {
      sprintf(
        paste0(
          "library(Rwapor)\n\n",
          "region <- %s\n",
          "period <- %s\n",
          "folder <- \"%s\"\n\n",
          "# 1. Download seasonal aggregate\n",
          "seasonal_path <- wapor_map(\n",
          "  region = region,\n",
          "  variable = \"%s\",\n",
          "  period = period,\n",
          "  folder = folder,\n",
          "  unit_conversion = %s,\n",
          "  seasonal = TRUE,\n",
          "  separate_files = FALSE,\n",
          "  mask = %s\n",
          ")\n\n",
          "# 2. Download individual time step files\n",
          "file_paths <- wapor_map(\n",
          "  region = region,\n",
          "  variable = \"%s\",\n",
          "  period = period,\n",
          "  folder = folder,\n",
          "  unit_conversion = %s,\n",
          "  seasonal = FALSE,\n",
          "  separate_files = TRUE,\n",
          "  mask = %s\n",
          ")"
        ),
        reg_str, period_str, input$folder, input$variable,
        unit_conv, mask_str, input$variable, unit_conv, mask_str
      )
    } else {
      sprintf(
        paste0(
          "library(Rwapor)\n\n",
          "region <- %s\n",
          "period <- %s\n",
          "folder <- \"%s\"\n\n",
          "map_path <- wapor_map(\n",
          "  region = region,\n",
          "  variable = \"%s\",\n",
          "  period = period,\n",
          "  folder = folder,\n",
          "  unit_conversion = %s,\n",
          "  seasonal = %s,\n",
          "  separate_files = %s,\n",
          "  mask = %s\n",
          ")"
        ),
        reg_str, period_str, input$folder, input$variable,
        unit_conv, input$seasonal, input$separate_files, mask_str
      )
    }
  })

  # ---- Download action -----------------------------------------------------
  shiny::observeEvent(input$download_btn, {
    log_msg("Starting download request from Dashboard...")
    reg <- current_region()
    if (is.null(reg)) {
      shiny::showNotification("Please select an AOI before downloading.",
        type = "error")
      return()
    }
    if (!nzchar(input$folder)) {
      shiny::showNotification("Output folder cannot be empty.", type = "error")
      return()
    }

    # When both seasonal and separate_files are checked, run two downloads
    if (input$seasonal && input$separate_files) {
      shiny::withProgress(message = "Downloading data...", value = 0, {
        tryCatch({
          unit_conv <- if (input$unit_conversion == "none") NULL else
            input$unit_conversion

          # Step 1: Seasonal aggregate
          shiny::incProgress(0.05,
            detail = "Downloading seasonal aggregate...")
          seasonal_path <- Rwapor::wapor_map(
            region = reg,
            variable = input$variable,
            period = as.character(input$period),
            folder = input$folder,
            unit_conversion = unit_conv,
            seasonal = TRUE,
            separate_files = FALSE,
            mask = input$mask_aoi
          )

          # Step 2: Individual time step files
          shiny::incProgress(0.5,
            detail = "Downloading individual time steps...")
          ind_paths <- Rwapor::wapor_map(
            region = reg,
            variable = input$variable,
            period = as.character(input$period),
            folder = input$folder,
            unit_conversion = unit_conv,
            seasonal = FALSE,
            separate_files = TRUE,
            mask = input$mask_aoi
          )

          shiny::incProgress(0.45, detail = "Complete!")
          all_paths <- c(seasonal_path, ind_paths)
          n_files <- length(all_paths)
          log_msg(sprintf("Dashboard download success. Saved %d files to %s.", 
            n_files, normalizePath(input$folder, winslash = "/", mustWork = FALSE)))
          shiny::showNotification(
            sprintf("Download successful. %d files written (1 seasonal + %d individual).",
              n_files, n_files - 1),
            type = "message", duration = 10)
        }, error = function(e) {
          log_msg("Dashboard download failed: ", e$message)
          shiny::showNotification(paste("Download failed:", e$message),
            type = "error", duration = 15)
        })
      })
    } else {
      # Standard single download
      shiny::withProgress(message = "Downloading data...", value = 0, {
        tryCatch({
          shiny::incProgress(0.1, detail = "Initializing download...")
          unit_conv <- if (input$unit_conversion == "none") NULL else
            input$unit_conversion
          out_path <- Rwapor::wapor_map(
            region = reg,
            variable = input$variable,
            period = as.character(input$period),
            folder = input$folder,
            unit_conversion = unit_conv,
            seasonal = input$seasonal,
            separate_files = input$separate_files,
            mask = input$mask_aoi
          )
          shiny::incProgress(0.9, detail = "Finalizing...")
          if (length(out_path) == 0 || !all(file.exists(out_path))) {
            stop("Download completed but output file(s) were not found on disk.")
          }
          log_msg(sprintf("Dashboard download success. Saved %d files to %s.", 
            length(out_path), normalizePath(dirname(out_path[1]), winslash = "/", mustWork = FALSE)))
          if (length(out_path) > 1) {
            shiny::showNotification(
              sprintf("Download successful. %d files written in %s",
                length(out_path), dirname(out_path[1])),
              type = "message", duration = 10)
          } else {
            shiny::showNotification(
              sprintf("Download successful. Saved to: %s", out_path),
              type = "message", duration = 10)
          }
        }, error = function(e) {
          log_msg("Dashboard download failed: ", e$message)
          shiny::showNotification(paste("Download failed:", e$message),
            type = "error", duration = 15)
        })
      })
    }
  })

  # ==========================================================================
  # VISUALISATION TAB SERVER
  # ==========================================================================

  loaded_raster <- shiny::reactiveVal(NULL)

  # ---- Scan folder for .tif files ------------------------------------------
  shiny::observeEvent(input$scan_rasters, {
    folder <- input$analysis_folder
    if (!dir.exists(folder)) {
      shiny::showNotification("Folder does not exist.", type = "error")
      return()
    }
    tif_files <- list.files(folder, pattern = "\\.tif$",
      recursive = TRUE, full.names = FALSE)
    if (length(tif_files) == 0) {
      shiny::showNotification("No .tif files found in this folder.",
        type = "warning")
      shiny::updateSelectInput(session, "raster_file", choices = character(0))
      return()
    }
    shiny::updateSelectInput(session, "raster_file", choices = tif_files)
    shiny::showNotification(
      sprintf("Found %d raster file(s).", length(tif_files)),
      type = "message")
  })

  # ---- Load raster and update band selector --------------------------------
  shiny::observeEvent(input$raster_file, {
    shiny::req(input$raster_file)
    full_path <- file.path(input$analysis_folder, input$raster_file)
    if (!file.exists(full_path)) {
      shiny::showNotification("File not found.", type = "error")
      loaded_raster(NULL)
      return()
    }
    tryCatch({
      r <- terra::rast(full_path)
      loaded_raster(r)
      n <- terra::nlyr(r)
      band_names <- names(r)
      if (is.null(band_names) || all(band_names == "")) {
        band_names <- paste("Band", seq_len(n))
      }
      choices <- stats::setNames(seq_len(n), band_names)
      shiny::updateSelectInput(session, "raster_band", choices = choices)
    }, error = function(e) {
      shiny::showNotification(
        paste("Error loading raster:", e$message), type = "error")
      loaded_raster(NULL)
    })
  })

  # ---- Selected single band (with NA cleanup and downsampling) -------------
  selected_band <- shiny::reactive({
    r <- loaded_raster()
    shiny::req(r)
    band_idx <- as.integer(input$raster_band)
    shiny::req(band_idx)
    r_band <- r[[band_idx]]
    r_band <- terra::classify(r_band, cbind(-9999, NA))

    # Downsample large rasters for leaflet performance
    dims <- dim(r_band)
    max_dim <- 2000
    if (dims[1] > max_dim || dims[2] > max_dim) {
      fact <- ceiling(max(dims[1], dims[2]) / max_dim)
      r_band <- terra::aggregate(r_band, fact = fact, fun = "mean",
        na.rm = TRUE)
      shiny::showNotification(
        sprintf("Raster downsampled by factor %d for display.", fact),
        type = "message", id = "downsample_msg")
    }
    r_band
  })

  # ---- Build color palette -------------------------------------------------
  raster_pal <- shiny::reactive({
    r_band <- selected_band()
    shiny::req(r_band)

    vals <- terra::values(r_band, na.rm = TRUE)
    shiny::req(length(vals) > 0)

    pal_name <- input$palette_name
    n <- input$n_colors

    # Generate color vector
    colors <- switch(pal_name,
      "viridis"        = viridisLite::viridis(n),
      "magma"          = viridisLite::magma(n),
      "plasma"         = viridisLite::plasma(n),
      "inferno"        = viridisLite::inferno(n),
      "cividis"        = viridisLite::cividis(n),
      "terrain.colors" = grDevices::terrain.colors(n),
      "heat.colors"    = grDevices::heat.colors(n),
      "topo.colors"    = grDevices::topo.colors(n),
      {
        # RColorBrewer palettes
        max_n <- min(n, 11)
        base_cols <- RColorBrewer::brewer.pal(max_n, pal_name)
        if (n > 11) grDevices::colorRampPalette(base_cols)(n) else base_cols
      }
    )

    if (input$reverse_palette) colors <- rev(colors)

    val_range <- range(vals, na.rm = TRUE)
    if (input$color_method == "numeric") {
      leaflet::colorNumeric(colors, domain = val_range,
        na.color = "transparent")
    } else {
      leaflet::colorBin(colors, domain = val_range, bins = n,
        na.color = "transparent")
    }
  })

  # ---- Render analysis map -------------------------------------------------
  output$analysis_map <- leaflet::renderLeaflet({
    leaflet::leaflet() |>
      leaflet::addProviderTiles("CartoDB.Positron") |>
      leaflet::setView(lng = 18, lat = 2, zoom = 3)
  })

  # Update basemap when selector changes
  shiny::observeEvent(input$basemap_analysis, {
    leaflet::leafletProxy("analysis_map") |>
      leaflet::clearTiles() |>
      leaflet::addProviderTiles(input$basemap_analysis)
  })

  # ── Helper: downsample a terra raster for leaflet display ──────────────────
  .vis_downsample <- function(r, max_dim = 1500) {
    dims <- dim(r)
    if (dims[1] > max_dim || dims[2] > max_dim) {
      fact <- ceiling(max(dims[1:2]) / max_dim)
      r    <- terra::aggregate(r, fact = fact, fun = "modal", na.rm = TRUE)
    }
    r
  }

  # ── Observer: Crop Mask layer (categorical) ─────────────────────────────────
  shiny::observe({
    r     <- an_crop_mask_rast()
    show  <- isTRUE(input$show_crop_mask)
    proxy <- leaflet::leafletProxy("analysis_map")

    if (!show || is.null(r)) {
      proxy |>
        leaflet::clearGroup("lyr_crop_mask") |>
        leaflet::removeControl("leg_crop_mask")
      if (show && is.null(r))
        shiny::showNotification(
          "Upload a Crop Mask in the Analysis tab first.", type = "warning")
      return()
    }

    opacity <- input$an_layer_opacity %||% 0.75

    # Build categorical palette
    r_ds   <- .vis_downsample(r)
    vals   <- sort(unique(na.omit(as.integer(terra::values(r_ds)))))
    n_cls  <- length(vals)
    cls_cols <- grDevices::hcl.colors(max(n_cls, 3), "Set2")[seq_len(n_cls)]
    # Assign labels from crop params if available
    params <- an_crop_params()
    cls_labels <- if (!is.null(params)) {
      vapply(vals, function(v) {
        idx <- which(params$class_value == v)
        if (length(idx)) params$crop_label[idx[1]] else paste("Class", v)
      }, character(1))
    } else {
      paste("Class", vals)
    }

    pal    <- leaflet::colorFactor(cls_cols, domain = vals, na.color = "transparent")
    r_leg  <- raster::raster(r_ds)

    proxy |>
      leaflet::clearGroup("lyr_crop_mask") |>
      leaflet::removeControl("leg_crop_mask") |>
      leaflet::addRasterImage(r_leg, colors = pal, opacity = opacity,
        group = "lyr_crop_mask") |>
      leaflet::addLegend(
        position = "bottomleft",
        colors   = cls_cols,
        labels   = cls_labels,
        title    = "Crop Mask",
        opacity  = opacity,
        layerId  = "leg_crop_mask"
      )
  })

  # ── Observer: Season Start layer (continuous DOY) ───────────────────────────
  shiny::observe({
    r     <- an_start_rast()
    show  <- isTRUE(input$show_season_start)
    proxy <- leaflet::leafletProxy("analysis_map")

    if (!show || is.null(r)) {
      proxy |>
        leaflet::clearGroup("lyr_season_start") |>
        leaflet::removeControl("leg_season_start")
      if (show && is.null(r))
        shiny::showNotification(
          "Upload a Season Start raster in the Analysis tab first.", type = "warning")
      return()
    }

    opacity <- input$an_layer_opacity %||% 0.75
    r_ds    <- .vis_downsample(r)
    vals    <- terra::values(r_ds, na.rm = TRUE)
    pal     <- leaflet::colorNumeric(
      viridisLite::viridis(10), domain = range(vals),
      na.color = "transparent")
    r_leg   <- raster::raster(r_ds)

    proxy |>
      leaflet::clearGroup("lyr_season_start") |>
      leaflet::removeControl("leg_season_start") |>
      leaflet::addRasterImage(r_leg, colors = pal, opacity = opacity,
        group = "lyr_season_start") |>
      leaflet::addLegend(
        position  = "bottomleft",
        pal       = pal,
        values    = vals,
        title     = "Season Start<br><small>(Julian DOY)</small>",
        opacity   = opacity,
        layerId   = "leg_season_start"
      )
  })

  # ── Observer: Season End layer (continuous DOY) ─────────────────────────────
  shiny::observe({
    r     <- an_end_rast()
    show  <- isTRUE(input$show_season_end)
    proxy <- leaflet::leafletProxy("analysis_map")

    if (!show || is.null(r)) {
      proxy |>
        leaflet::clearGroup("lyr_season_end") |>
        leaflet::removeControl("leg_season_end")
      if (show && is.null(r))
        shiny::showNotification(
          "Upload a Season End raster in the Analysis tab first.", type = "warning")
      return()
    }

    opacity <- input$an_layer_opacity %||% 0.75
    r_ds    <- .vis_downsample(r)
    vals    <- terra::values(r_ds, na.rm = TRUE)
    pal     <- leaflet::colorNumeric(
      rev(viridisLite::magma(10)), domain = range(vals),
      na.color = "transparent")
    r_leg   <- raster::raster(r_ds)

    proxy |>
      leaflet::clearGroup("lyr_season_end") |>
      leaflet::removeControl("leg_season_end") |>
      leaflet::addRasterImage(r_leg, colors = pal, opacity = opacity,
        group = "lyr_season_end") |>
      leaflet::addLegend(
        position  = "bottomleft",
        pal       = pal,
        values    = vals,
        title     = "Season End<br><small>(Julian DOY)</small>",
        opacity   = opacity,
        layerId   = "leg_season_end"
      )
  })

  # ---- Update raster overlay -----------------------------------------------
  shiny::observe({
    r_band <- selected_band()
    shiny::req(r_band)
    pal <- raster_pal()
    shiny::req(pal)

    vals <- terra::values(r_band, na.rm = TRUE)
    ext <- terra::ext(r_band)

    # Convert to raster package object for leaflet compatibility
    r_legacy <- raster::raster(r_band)

    proxy <- leaflet::leafletProxy("analysis_map") |>
      leaflet::clearImages() |>
      leaflet::clearControls() |>
      leaflet::clearGroup("aoi_overlay") |>
      leaflet::addRasterImage(r_legacy, colors = pal,
        opacity = input$raster_opacity, group = "raster") |>
      leaflet::addLegend(position = "bottomright", pal = pal,
        values = vals, title = names(r_band),
        opacity = input$raster_opacity) |>
      leaflet::fitBounds(
        lng1 = ext$xmin, lat1 = ext$ymin,
        lng2 = ext$xmax, lat2 = ext$ymax)

    # Overlay AOI if requested
    if (isTRUE(input$overlay_aoi)) {
      reg <- current_region()
      if (!is.null(reg)) {
        if (is.numeric(reg)) {
          proxy <- proxy |>
            leaflet::addRectangles(
              lng1 = reg[1], lat1 = reg[2], lng2 = reg[3], lat2 = reg[4],
              color = "yellow", fill = FALSE, weight = 2,
              group = "aoi_overlay")
        } else if (is.character(reg) && file.exists(reg)) {
          aoi_sf <- sf::st_read(reg, quiet = TRUE)
          aoi_crs <- sf::st_crs(aoi_sf)
          if (!is.na(aoi_crs) && aoi_crs$epsg != 4326) {
            aoi_sf <- sf::st_transform(aoi_sf, 4326)
          }
          proxy <- proxy |>
            leaflet::addPolygons(data = aoi_sf, color = "yellow",
              fill = FALSE, weight = 2, group = "aoi_overlay")
        }
      }
    }

    proxy
  })

  # ---- Raster information table --------------------------------------------
  output$raster_info <- shiny::renderTable({
    r <- loaded_raster()
    shiny::req(r)
    band_idx <- as.integer(input$raster_band)
    shiny::req(band_idx)

    r_band <- r[[band_idx]]
    r_band <- terra::classify(r_band, cbind(-9999, NA))
    ext <- terra::ext(r_band)
    res <- terra::res(r_band)
    vals <- terra::values(r_band, na.rm = TRUE)
    crs_info <- terra::crs(r_band, describe = TRUE)

    data.frame(
      Property = c(
        "Extent (xmin, ymin, xmax, ymax)",
        "Resolution (x, y)",
        "CRS",
        "Total Bands",
        "Selected Band",
        "Min Value",
        "Max Value",
        "Mean Value",
        "NA Pixels"
      ),
      Value = c(
        sprintf("%.4f, %.4f, %.4f, %.4f",
          ext$xmin, ext$ymin, ext$xmax, ext$ymax),
        sprintf("%.6f, %.6f", res[1], res[2]),
        if (nrow(crs_info) > 0) crs_info$name[1] else "Unknown",
        as.character(terra::nlyr(r)),
        names(r)[band_idx],
        sprintf("%.4f", min(vals)),
        sprintf("%.4f", max(vals)),
        sprintf("%.4f", mean(vals)),
        as.character(sum(is.na(terra::values(r_band))))
      ),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ==========================================================================
  # ANALYSIS TAB SERVER
  # ==========================================================================

  # ---- Analysis reactive state ----
  an_crop_mask_rast  <- shiny::reactiveVal(NULL)
  an_start_rast      <- shiny::reactiveVal(NULL)
  an_end_rast        <- shiny::reactiveVal(NULL)
  an_crop_classes    <- shiny::reactiveVal(NULL)
  an_crop_params     <- shiny::reactiveVal(NULL)
  an_results         <- shiny::reactiveVal(NULL)
  an_peff_monthly    <- shiny::reactiveVal(NULL)

  # ---- Load crop mask on upload ----
  shiny::observeEvent(input$an_crop_mask, {
    shiny::req(input$an_crop_mask)
    tryCatch({
      r <- Rwapor::rwapor_load_crop_mask(input$an_crop_mask$datapath)
      an_crop_mask_rast(r)
      classes <- Rwapor::rwapor_extract_crop_classes(r)
      an_crop_classes(classes)
      # Pre-build empty assignment table
      tbl <- Rwapor::rwapor_build_crop_assignment_table(classes$class_value)
      an_crop_params(tbl)
      shiny::showNotification(
        sprintf("Crop mask loaded: %d classes found.", nrow(classes)),
        type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error loading crop mask:", e$message),
        type = "error")
    })
  })

  # ---- Load season start raster ----
  shiny::observeEvent(input$an_season_start, {
    shiny::req(input$an_season_start)
    tryCatch({
      r <- Rwapor::rwapor_load_season_raster(input$an_season_start$datapath)
      an_start_rast(r)
      shiny::showNotification("Season start raster loaded.", type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error:", e$message), type = "error")
    })
  })

  # ---- Load season end raster ----
  shiny::observeEvent(input$an_season_end, {
    shiny::req(input$an_season_end)
    tryCatch({
      r <- Rwapor::rwapor_load_season_raster(input$an_season_end$datapath)
      an_end_rast(r)
      shiny::showNotification("Season end raster loaded.", type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error:", e$message), type = "error")
    })
  })

  # ---- Dynamic crop class assignment UI ----
  output$an_crop_class_ui <- shiny::renderUI({
    classes <- an_crop_classes()
    if (is.null(classes)) {
      return(shiny::p("No crop mask loaded yet."))
    }
    crop_choices <- c("(Custom)" = "custom", Rwapor::rwapor_list_crops())
    names(crop_choices) <- c("(Custom)", Rwapor::rwapor_list_crops())

    class_panels <- lapply(seq_len(nrow(classes)), function(i) {
      cls <- classes$class_value[i]
      prefix <- paste0("an_cls_", cls, "_")
      shiny::tagList(
        shiny::tags$strong(sprintf("Class %d (%d px, %.1f ha)",
          cls, classes$pixel_count[i], classes$area_ha[i])),
        shiny::fluidRow(
          shiny::column(6, shiny::selectInput(
            paste0(prefix, "profile"), "Profile", choices = crop_choices)),
          shiny::column(6, shiny::textInput(
            paste0(prefix, "label"), "Label", value = paste("Class", cls)))
        ),
        shiny::fluidRow(
          shiny::column(4, shiny::numericInput(paste0(prefix, "kc_ini"), "Kc ini", value = 0.3, step = 0.05)),
          shiny::column(4, shiny::numericInput(paste0(prefix, "kc_mid"), "Kc mid", value = 1.15, step = 0.05)),
          shiny::column(4, shiny::numericInput(paste0(prefix, "kc_end"), "Kc end", value = 0.3, step = 0.05))
        ),
        shiny::fluidRow(
          shiny::column(3, shiny::numericInput(paste0(prefix, "l_ini"), "L ini (d)", value = 30, min = 0)),
          shiny::column(3, shiny::numericInput(paste0(prefix, "l_mid"), "L mid (d)", value = 40, min = 0)),
          shiny::column(3, shiny::numericInput(paste0(prefix, "l_late"), "L late (d)", value = 30, min = 0)),
          shiny::column(3, shiny::numericInput(paste0(prefix, "height"), "H (m)", value = 1.0, step = 0.1))
        ),
        shiny::hr()
      )
    })
    shiny::tagList(class_panels)
  })

  # ---- Auto-fill from crop profile selection ----
  shiny::observe({
    classes <- an_crop_classes()
    shiny::req(classes)
    for (i in seq_len(nrow(classes))) {
      local({
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
        profile_id <- paste0(prefix, "profile")

        shiny::observeEvent(input[[profile_id]], {
          profile_name <- input[[profile_id]]
          if (!is.null(profile_name) && profile_name != "custom") {
            defaults <- Rwapor::rwapor_get_crop_defaults(profile_name)
            if (!is.null(defaults)) {
              shiny::updateTextInput(session, paste0(prefix, "label"),
                value = defaults$crop_name)
              shiny::updateNumericInput(session, paste0(prefix, "kc_ini"),
                value = defaults$Kc_ini)
              shiny::updateNumericInput(session, paste0(prefix, "kc_mid"),
                value = defaults$Kc_mid)
              shiny::updateNumericInput(session, paste0(prefix, "kc_end"),
                value = defaults$Kc_end)
              shiny::updateNumericInput(session, paste0(prefix, "l_ini"),
                value = defaults$L_ini_days)
              shiny::updateNumericInput(session, paste0(prefix, "l_mid"),
                value = defaults$L_mid_days)
              shiny::updateNumericInput(session, paste0(prefix, "l_late"),
                value = defaults$L_late_days)
              shiny::updateNumericInput(session, paste0(prefix, "height"),
                value = defaults$max_height_m)
            }
          }
        }, ignoreInit = TRUE)
      })
    }
  })

  # ---- Collect crop parameters from dynamic inputs ----
  # Helper for NULL-safe defaults (compatible with R < 4.4)
  null_default <- function(x, default) if (!is.null(x)) x else default

  collect_crop_params <- function() {
    classes <- an_crop_classes()
    if (is.null(classes)) return(NULL)
    rows <- lapply(seq_len(nrow(classes)), function(i) {
      cls <- classes$class_value[i]
      prefix <- paste0("an_cls_", cls, "_")
      data.frame(
        class_value  = cls,
        crop_label   = null_default(input[[paste0(prefix, "label")]], paste("Class", cls)),
        Kc_ini       = null_default(input[[paste0(prefix, "kc_ini")]], 0.3),
        Kc_mid       = null_default(input[[paste0(prefix, "kc_mid")]], 1.15),
        Kc_end       = null_default(input[[paste0(prefix, "kc_end")]], 0.3),
        L_ini_days   = as.integer(null_default(input[[paste0(prefix, "l_ini")]], 30)),
        L_mid_days   = as.integer(null_default(input[[paste0(prefix, "l_mid")]], 40)),
        L_late_days  = as.integer(null_default(input[[paste0(prefix, "l_late")]], 30)),
        max_height_m = null_default(input[[paste0(prefix, "height")]], 1.0),
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  }

  # Real-time Kc preview data
  active_kc_data <- shiny::reactive({
    params <- collect_crop_params()
    shiny::req(params)
    total_days <- 150 # Default for preview
    total_days_vec <- stats::setNames(
      rep(total_days, nrow(params)),
      as.character(params$class_value)
    )
    tryCatch({
      Rwapor::rwapor_build_kc_by_class(params, total_days_vec)
    }, error = function(e) NULL)
  })

  # ---- Season summary output ----
  output$an_season_summary <- shiny::renderPrint({
    cat("Season:", input$an_season_label, "\n")
    cat("Reference Year:", input$an_ref_year, "\n")
    cat("Analysis Period:", as.character(input$an_period[1]), "to",
        as.character(input$an_period[2]), "\n")
    cat("AETI:", input$an_aeti_var, "\n")
    cat("RET:", input$an_ret_var, "\n")
    cat("Precip:", input$an_precip_var, "\n")
    cat("\n--- Raster Status ---\n")
    cat("Crop Mask:", if (!is.null(an_crop_mask_rast())) "Loaded" else "Not loaded", "\n")
    cat("Season Start:", if (!is.null(an_start_rast())) "Loaded" else "Not loaded", "\n")
    cat("Season End:", if (!is.null(an_end_rast())) "Loaded" else "Not loaded", "\n")
  })

  # ---- Crop mask preview plot ----
  output$an_crop_mask_plot <- shiny::renderPlot({
    r <- an_crop_mask_rast()
    shiny::req(r)
    terra::plot(r, main = "Crop Mask Classes", col = grDevices::hcl.colors(20, "Set2"))
  })

  # ---- Season raster info ----
  output$an_season_raster_info <- shiny::renderPrint({
    s_start <- an_start_rast()
    s_end   <- an_end_rast()
    if (is.null(s_start) && is.null(s_end)) {
      cat("No season rasters loaded yet.")
      return()
    }
    if (!is.null(s_start)) {
      cat("--- Season Start Raster ---\n")
      vals <- terra::values(s_start, na.rm = TRUE)
      cat(sprintf("  Dimensions: %d x %d\n", nrow(s_start), ncol(s_start)))
      cat(sprintf("  Value range: %d - %d (Julian DOY)\n",
          min(vals), max(vals)))
      cat(sprintf("  Non-NA pixels: %d\n", length(vals)))
    }
    if (!is.null(s_end)) {
      cat("\n--- Season End Raster ---\n")
      vals <- terra::values(s_end, na.rm = TRUE)
      cat(sprintf("  Dimensions: %d x %d\n", nrow(s_end), ncol(s_end)))
      cat(sprintf("  Value range: %d - %d (Julian DOY)\n",
          min(vals), max(vals)))
      cat(sprintf("  Non-NA pixels: %d\n", length(vals)))
    }
  })

  # ---- Crop class table output ----
  output$an_crop_class_table <- shiny::renderTable({
    classes <- an_crop_classes()
    shiny::req(classes)
    classes
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ---- Validate inputs ----
  shiny::observeEvent(input$an_validate_btn, {
    errors <- character()
    if (is.null(an_crop_mask_rast()))
      errors <- c(errors, "Crop mask raster not uploaded.")
    if (is.null(an_start_rast()))
      errors <- c(errors, "Season start raster not uploaded.")
    if (is.null(an_end_rast()))
      errors <- c(errors, "Season end raster not uploaded.")
    if (is.null(an_crop_classes()))
      errors <- c(errors, "No crop classes found.")

    # Check crop parameters
    params <- collect_crop_params()
    if (!is.null(params)) {
      if (any(is.na(params$Kc_ini) | is.na(params$Kc_mid) | is.na(params$Kc_end)))
        errors <- c(errors, "Some Kc values are missing.")
      if (any(is.na(params$L_ini_days) | is.na(params$L_mid_days) | is.na(params$L_late_days)))
        errors <- c(errors, "Some stage length values are missing.")
    }

    if (length(errors) > 0) {
      shiny::showNotification(
        shiny::HTML(paste("<b>Validation errors:</b><br>",
          paste("-", errors, collapse = "<br>"))),
        type = "error", duration = 10)
    } else {
      shiny::showNotification("All inputs validated successfully.",
        type = "message")
    }
  })

  # ---- Reset ----
  shiny::observeEvent(input$an_reset_btn, {
    an_crop_mask_rast(NULL)
    an_start_rast(NULL)
    an_end_rast(NULL)
    an_crop_classes(NULL)
    an_crop_params(NULL)
    an_results(NULL)
    an_peff_monthly(NULL)
    shiny::showNotification("Analysis state reset.", type = "message")
  })

  # ---- Run Analysis ----
  shiny::observeEvent(input$an_run_btn, {
    # Validate required inputs
    if (is.null(an_crop_mask_rast()) || is.null(an_start_rast()) ||
        is.null(an_end_rast())) {
      shiny::showNotification(
        "Please upload crop mask, season start, and season end rasters first.",
        type = "error")
      return()
    }

    crop_params <- collect_crop_params()
    if (is.null(crop_params) || nrow(crop_params) == 0) {
      shiny::showNotification("No crop class parameters defined.", type = "error")
      return()
    }

    shiny::withProgress(message = "Running analysis...", value = 0, {
      tryCatch({
        ref_year <- input$an_ref_year
        period <- as.character(input$an_period)

        # Collect combined indicator list from both inputs
        agg_vars     <- input$an_agg_vars     %||% character(0)
        derived_vars <- input$an_derived_vars %||% character(0)
        indicators   <- c(agg_vars, derived_vars)

        # Pre-compute which data stacks are needed
        need_aeti_stack   <- any(c("agg_aeti", "etc", "adequacy_etc",
                                   "adequacy_p95", "cwp_bwp") %in% indicators)
        need_ret_stack    <- any(c("agg_ret", "etc", "adequacy_etc") %in% indicators)
        need_npp_stack    <- "agg_npp"  %in% indicators
        need_precip_stack <- any(c("agg_pcp", "agg_peff") %in% indicators)

        # --- Step 1: Harmonize rasters ---
        shiny::incProgress(0.05, detail = "Fetching reference AETI raster...")
        # Get AOI from current shared state
        reg <- current_region()
        aeti_var <- input$an_aeti_var
        ret_var  <- input$an_ret_var
        precip_var <- input$an_precip_var

        # Fetch a single AETI raster as geometry template
        l3_code <- NULL
        if (grepl("^L3-", aeti_var)) {
          l3_code <- input$an_l3_region
        }
        ref_urls <- Rwapor::wapor_generate_urls(aeti_var, l3_region = l3_code,
          period = period)
        if (length(ref_urls) == 0) {
          stop("No AETI data found for the specified period.")
        }
        template_r <- terra::rast(paste0("/vsicurl/", ref_urls[1]))
        if (!is.null(reg)) {
          reg_info <- Rwapor::parse_region(reg)
          template_r <- crop_to_region(template_r, reg_info, do_mask = FALSE)
        }

        shiny::incProgress(0.1, detail = "Harmonizing rasters...")
        h_mask  <- Rwapor::rwapor_harmonize_crop_mask(an_crop_mask_rast(), template_r)
        h_start <- Rwapor::rwapor_harmonize_to_template(an_start_rast(), template_r, method = "near")
        h_end   <- Rwapor::rwapor_harmonize_to_template(an_end_rast(), template_r, method = "near")

        # Validate season rasters
        s_start_vals <- terra::values(h_start, na.rm = TRUE)
        s_end_vals   <- terra::values(h_end, na.rm = TRUE)
        if (length(s_start_vals) == 0 || length(s_end_vals) == 0) {
          stop("Season rasters have no valid pixels after harmonization.")
        }

        # --- Step 2: Compute total days & validate L_dev ---
        shiny::incProgress(0.1, detail = "Computing season duration...")
        total_days_r <- Rwapor::rwapor_compute_total_days_raster(h_start, h_end)
        mean_total_days <- round(mean(terra::values(total_days_r, na.rm = TRUE)))

        # Check L_dev for each class
        for (j in seq_len(nrow(crop_params))) {
          fixed_sum <- crop_params$L_ini_days[j] + crop_params$L_mid_days[j] +
                       crop_params$L_late_days[j]
          if (fixed_sum >= mean_total_days) {
            warning(sprintf(
              "Class %s: ini+mid+late=%d >= mean total days=%d. L_dev will be <=0.",
              crop_params$crop_label[j], fixed_sum, mean_total_days))
          }
        }

        # --- Step 3: Build Kc curves ---
        shiny::incProgress(0.1, detail = "Building Kc curves...")
        total_days_vec <- stats::setNames(
          rep(mean_total_days, nrow(crop_params)),
          as.character(crop_params$class_value)
        )
        kc_by_class <- Rwapor::rwapor_build_kc_by_class(crop_params, total_days_vec)

        # --- Step 4: Build dekadal season weights ---
        shiny::incProgress(0.1, detail = "Building season weights...")
        sw <- Rwapor::rwapor_build_season_weights_dekad(
          period[1], period[2], h_start, h_end, ref_year
        )
        season_weights <- sw$weights
        dekad_table    <- sw$dekad_table

        # --- Step 5: Fetch required remote data stacks ---
        shiny::incProgress(0.15, detail = "Fetching required WaPOR data...")

        aeti_stack <- ret_stack <- precip_stack <- npp_stack <- NULL

        if (need_aeti_stack || need_ret_stack) {
          aeti_urls <- Rwapor::wapor_generate_urls(aeti_var,
            l3_region = l3_code, period = period)
          aeti_stack <- terra::rast(paste0("/vsicurl/", aeti_urls))
          if (!is.null(reg))
            aeti_stack <- crop_to_region(aeti_stack, reg_info, do_mask = FALSE)
          aeti_meta  <- Rwapor::get_variable_metadata(aeti_var)
          if (!is.null(aeti_meta)) aeti_stack <- aeti_stack * aeti_meta$scale
        }

        if (need_ret_stack) {
          ret_urls <- Rwapor::wapor_generate_urls(ret_var,
            l3_region = l3_code, period = period)
          ret_stack <- terra::rast(paste0("/vsicurl/", ret_urls))
          if (!is.null(reg))
            ret_stack <- crop_to_region(ret_stack, reg_info, do_mask = FALSE)
          ret_meta  <- Rwapor::get_variable_metadata(ret_var)
          if (!is.null(ret_meta)) ret_stack <- ret_stack * ret_meta$scale
        }

        if (need_precip_stack) {
          tryCatch({
            precip_urls  <- Rwapor::wapor_generate_urls(precip_var,
              l3_region = l3_code, period = period)
            if (length(precip_urls) > 0) {
              precip_stack <- terra::rast(paste0("/vsicurl/", precip_urls))
              if (!is.null(reg))
                precip_stack <- crop_to_region(precip_stack, reg_info, do_mask = FALSE)
              precip_meta  <- Rwapor::get_variable_metadata(precip_var)
              if (!is.null(precip_meta)) precip_stack <- precip_stack * precip_meta$scale
            }
          }, error = function(e) warning("Precip fetch failed: ", e$message))
        }

        if (need_npp_stack) {
          tryCatch({
            npp_urls <- Rwapor::wapor_generate_urls(input$an_npp_var,
              l3_region = l3_code, period = period)
            if (length(npp_urls) > 0) {
              npp_stack <- terra::rast(paste0("/vsicurl/", npp_urls))
              if (!is.null(reg))
                npp_stack <- crop_to_region(npp_stack, reg_info, do_mask = FALSE)
              npp_meta  <- Rwapor::get_variable_metadata(input$an_npp_var)
              if (!is.null(npp_meta)) npp_stack <- npp_stack * npp_meta$scale
            }
          }, error = function(e) warning("NPP fetch failed: ", e$message))
        }

        # Align layer counts to season weights
        n_wt <- terra::nlyr(season_weights)
        trim_stack <- function(s, n) if (!is.null(s)) s[[seq_len(min(terra::nlyr(s), n))]] else NULL
        aeti_stack   <- trim_stack(aeti_stack,   n_wt)
        ret_stack    <- trim_stack(ret_stack,    n_wt)
        precip_stack <- trim_stack(precip_stack, n_wt)
        npp_stack    <- trim_stack(npp_stack,    n_wt)
        n_layers     <- n_wt

        # --- Step 6: Per-variable seasonal aggregation ---
        shiny::incProgress(0.10, detail = "Computing seasonal aggregations...")
        results <- list()

        if ("agg_aeti" %in% indicators || need_aeti_stack) {
          if (!is.null(aeti_stack)) {
            aeti_result <- Rwapor::rwapor_calc_seasonal_aeti_masked(
              aeti_stack, season_weights, h_mask)
            results$seasonal_aeti <- aeti_result
          }
        }

        if ("agg_ret" %in% indicators || need_ret_stack) {
          if (!is.null(ret_stack)) {
            ret_result <- Rwapor::rwapor_calc_seasonal_ret_masked(
              ret_stack, season_weights, h_mask)
            results$seasonal_ret <- ret_result
          }
        }

        if ("agg_npp" %in% indicators && !is.null(npp_stack)) {
          npp_seasonal <- terra::app(
            npp_stack[[seq_len(n_layers)]] * season_weights,
            fun = "sum", na.rm = TRUE)
          # Convert gC/m2 → kg dry matter/ha for NPP-D variables
          if (grepl("-NPP-", input$an_npp_var)) npp_seasonal <- npp_seasonal * 22.22
          results$seasonal_npp <- npp_seasonal
        }

        if ("agg_pcp" %in% indicators && !is.null(precip_stack)) {
          results$seasonal_pcp <- terra::app(
            precip_stack[[seq_len(n_layers)]] * season_weights,
            fun = "sum", na.rm = TRUE)
        }

        # --- Step 7: ETc ---
        if ("etc" %in% indicators || "adequacy_etc" %in% indicators) {
          shiny::incProgress(0.05, detail = "Computing ETc...")
          # Build per-class dekadal Kc and compute ETc
          etc_by_class <- list()
          for (j in seq_len(nrow(crop_params))) {
            cls <- as.character(crop_params$class_value[j])
            kc_daily <- kc_by_class[[cls]]
            if (length(kc_daily) == 0) next
            # Aggregate daily Kc to dekadal
            dk_tbl <- dekad_table[seq_len(n_layers), , drop = FALSE]
            season_start_date <- as.Date(sprintf("%04d-01-01", ref_year)) +
              (round(mean(s_start_vals)) - 1)
            kc_dekad <- Rwapor::rwapor_aggregate_kc_dekad(kc_daily, dk_tbl,
              season_start_date)
            # Compute ETc for this class (scalar Kc per dekad)
            kc_dekad <- kc_dekad[seq_len(n_layers)]
            etc_class <- Rwapor::rwapor_calc_etc_dekad(ret_stack, kc_dekad)
            # Mask to this class only
            class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
            etc_class_masked <- etc_class * class_mask
            etc_seasonal <- terra::app(etc_class_masked * season_weights,
              fun = "sum", na.rm = TRUE)
            etc_by_class[[cls]] <- list(
              kc_dekad = kc_dekad,
              etc_seasonal = etc_seasonal
            )
          }
          results$etc_by_class <- etc_by_class
        }

        # --- Step 8: Adequacy ---
        if ("adequacy_etc" %in% indicators) {
          shiny::incProgress(0.05, detail = "Computing adequacy (ETc)...")
          # Combine all class ETc into one raster
          all_etc <- lapply(results$etc_by_class, function(x) x$etc_seasonal)
          if (length(all_etc) > 0) {
            combined_etc <- all_etc[[1]]
            for (k in seq_along(all_etc)[-1]) {
              combined_etc <- terra::cover(combined_etc, all_etc[[k]])
            }
            results$adequacy_etc <- Rwapor::rwapor_calc_adequacy_etc(
              results$seasonal_aeti$raster, combined_etc)
          }
        }

        if ("adequacy_p95" %in% indicators) {
          shiny::incProgress(0.05, detail = "Computing adequacy (P95)...")
          p95_table <- Rwapor::rwapor_calc_class_p95_aeti(
            results$seasonal_aeti$raster, h_mask)
          results$p95_table <- p95_table
          results$adequacy_p95 <- Rwapor::rwapor_calc_adequacy_p95(
            results$seasonal_aeti$raster, h_mask, p95_table)
        }

        # --- Step 9: Effective Precipitation (USDA SCS) ---
        if ("agg_peff" %in% indicators && !is.null(precip_stack)) {
          shiny::incProgress(0.05, detail = "Computing effective precipitation...")
          tryCatch({
            precip_means <- terra::global(
              precip_stack[[seq_len(n_layers)]], fun = "mean", na.rm = TRUE)$mean
            parts  <- strsplit(precip_var, "-")[[1]]
            tres   <- utils::tail(parts, 1)
            precip_urls <- Rwapor::wapor_generate_urls(precip_var,
              l3_region = l3_code, period = period)
            precip_dates <- lapply(precip_urls, function(u) Rwapor::get_date_info(u, tres))
            precip_ts <- data.frame(
              date  = as.Date(vapply(precip_dates,
                function(x) x$start_date, character(1))),
              value = precip_means,
              stringsAsFactors = FALSE
            )
            monthly_p        <- Rwapor::rwapor_aggregate_precip_monthly(precip_ts)
            monthly_p$peff_mm <- Rwapor::rwapor_calc_peff_usda_monthly(monthly_p$p_monthly_mm)
            an_peff_monthly(monthly_p)
            results$peff_seasonal <- sum(monthly_p$peff_mm, na.rm = TRUE)
            results$peff_monthly  <- monthly_p
          }, error = function(e) warning("Peff computation failed: ", e$message))
        }

        if ("cwp_bwp" %in% indicators) {
          shiny::incProgress(0.05, detail = "Computing CWP/BWP...")
          mean_aeti <- mean(terra::values(results$seasonal_aeti$raster,
            na.rm = TRUE))
          cwp_val <- NULL; bwp_val <- NULL
          if (!is.null(input$an_yield_file)) {
            tryCatch({
              yield_r <- terra::rast(input$an_yield_file$datapath)
              yield_h <- Rwapor::rwapor_harmonize_to_template(yield_r, template_r)
              mean_yield <- mean(terra::values(yield_h, na.rm = TRUE))
              cwp_val <- Rwapor::rwapor_calc_cwp(mean_yield, mean_aeti,
                input$an_yield_unit)
            }, error = function(e) {
              warning("CWP computation failed: ", e$message)
            })
          }
          # Fetch Biomass from local file OR WaPOR NPP
          bio_h <- NULL
          if (!is.null(input$an_biomass_file)) {
            tryCatch({
              bio_r <- terra::rast(input$an_biomass_file$datapath)
              bio_h <- Rwapor::rwapor_harmonize_to_template(bio_r, template_r)
            }, error = function(e) warning("Local biomass load failed: ", e$message))
          } else if (!is.null(input$an_npp_var)) {
            tryCatch({
              npp_urls <- Rwapor::wapor_generate_urls(input$an_npp_var,
                l3_region = l3_code, period = period)
              if (length(npp_urls) > 0) {
                # Fetch, mask, scale, and aggregate NPP
                npp_stack <- terra::rast(paste0("/vsicurl/", npp_urls))
                if (!is.null(reg)) npp_stack <- crop_to_region(npp_stack, reg_info, do_mask = FALSE)
                npp_meta <- Rwapor::get_variable_metadata(input$an_npp_var)
                if (!is.null(npp_meta)) npp_stack <- npp_stack * npp_meta$scale
                # Aggregate to seasonal total using weights (result is in gC/m2 if NPP)
                bio_rast <- terra::app(npp_stack[[seq_len(n_layers)]] * season_weights, 
                                     fun = "sum", na.rm = TRUE)
                # Convert gC/m2 to kgDM/ha: 1 gC/m2 ~= 2.22 g dry matter/m2 = 22.22 kg dry matter/ha
                # If variable is TBP, units are already kg/ha, but NPP-D is gC/m2/day.
                if (grepl("-NPP-", input$an_npp_var)) {
                  bio_h <- bio_rast * 22.22
                } else {
                  # For TBP variables or others, assume they are handled or already in kg/ha
                  bio_h <- bio_rast
                }
              }
            }, error = function(e) warning("WaPOR NPP fetch failed: ", e$message))
          }
          
          if (!is.null(bio_h)) {
            tryCatch({
              mean_bio <- mean(terra::values(bio_h, na.rm = TRUE))
              bwp_val <- Rwapor::rwapor_calc_bwp(mean_bio, mean_aeti,
                input$an_biomass_unit)
            }, error = function(e) {
              warning("BWP computation failed: ", e$message)
            })
          }
          results$cwp <- cwp_val
          results$bwp <- bwp_val
        }

        shiny::incProgress(0.05, detail = "Done!")
        results$crop_params <- crop_params
        results$kc_by_class <- kc_by_class
        results$dekad_table <- dekad_table[seq_len(n_layers), , drop = FALSE]
        an_results(results)
        an_crop_params(crop_params)
        shiny::showNotification("Analysis complete!", type = "message",
          duration = 8)

      }, error = function(e) {
        shiny::showNotification(paste("Analysis failed:", e$message),
          type = "error", duration = 15)
      })
    })
  })

  output$an_kc_plot <- shiny::renderPlot({
    kc_list <- active_kc_data()
    params  <- collect_crop_params()
    shiny::req(kc_list, params)
    if (length(kc_list) == 0) return()

    max_len <- max(vapply(kc_list, length, integer(1)))
    if (max_len == 0) return()

    # ── Fix: tighten margins so base R doesn't overflow a compact plot area
    old_par <- graphics::par(
      mar  = c(4, 4, 2.5, 1),   # bottom, left, top, right (lines)
      mgp  = c(2.5, 0.8, 0),    # axis title, label, line distances
      tcl  = -0.3               # tick length
    )
    on.exit(graphics::par(old_par), add = TRUE)

    n_cls <- length(kc_list)
    cols  <- grDevices::hcl.colors(n_cls, "Set2")

    tryCatch({
      plot(NULL,
        xlim = c(1, max_len), ylim = c(0, 1.6),
        xlab = "Day of Season", ylab = "Kc (crop coefficient)",
        main = "Crop Coefficient Curves (Preview)",
        cex.main = 0.95, cex.lab = 0.85, cex.axis = 0.80,
        panel.first = {
          graphics::grid(nx = NULL, ny = NULL, col = "#e0e0e0", lty = 1)
          graphics::abline(h = seq(0, 1.6, 0.2), col = "#e8e8e8", lty = 1)
        }
      )

      for (i in seq_along(kc_list)) {
        kc <- kc_list[[i]]
        if (length(kc) > 0) {
          graphics::lines(seq_along(kc), kc, col = cols[i], lwd = 2.5)
        }
      }

      # Legend outside the plot area if many classes; inside if ≤ 3
      legend_pos <- if (n_cls <= 3) "topright" else "top"
      graphics::legend(
        legend_pos,
        legend  = params$crop_label,
        col     = cols,
        lwd     = 2.5,
        cex     = 0.78,
        bg      = "white",
        box.lwd = 0.5,
        inset   = 0.01,
        horiz   = (n_cls > 3)   # horizontal legend for many classes
      )
    }, error = function(e) {
      graphics::plot.new()
      graphics::text(0.5, 0.5,
        paste("Plot error:", conditionMessage(e)),
        col = "red", cex = 0.85, adj = 0.5)
    })
  }, res = 96, bg = "white")

  # ---- ETc & AETI table ----
  output$an_etc_aeti_table <- shiny::renderTable({
    res <- an_results()
    shiny::req(res)
    rows <- list()
    if (!is.null(res$seasonal_aeti$by_class)) {
      aeti_tbl <- res$seasonal_aeti$by_class
      ret_tbl  <- res$seasonal_ret$by_class
      etc_means <- vapply(names(res$etc_by_class), function(cls) {
        etc_r <- res$etc_by_class[[cls]]$etc_seasonal
        if (!is.null(etc_r)) mean(terra::values(etc_r, na.rm = TRUE)) else NA_real_
      }, numeric(1))

      for (i in seq_len(nrow(aeti_tbl))) {
        cls_str <- as.character(aeti_tbl$class_value[i])
        label <- if (!is.null(res$crop_params)) {
          idx <- which(res$crop_params$class_value == aeti_tbl$class_value[i])
          if (length(idx) > 0) res$crop_params$crop_label[idx[1]] else cls_str
        } else cls_str

        rows[[i]] <- data.frame(
          Class = label,
          `AETI (mm)` = round(aeti_tbl$mean_seasonal_aeti[i], 1),
          `RET (mm)` = round(ret_tbl$mean_seasonal_ret[i], 1),
          `ETc (mm)` = if (cls_str %in% names(etc_means)) round(etc_means[cls_str], 1) else NA,
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
    }
    if (length(rows) > 0) do.call(rbind, rows) else
      data.frame(Message = "Run analysis first.", stringsAsFactors = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ---- Adequacy table ----
  output$an_adequacy_table <- shiny::renderTable({
    res <- an_results()
    shiny::req(res)
    rows <- list()
    params <- res$crop_params

    # ETc adequacy
    if (!is.null(res$adequacy_etc)) {
      classes <- terra::freq(an_crop_mask_rast())
      classes <- classes[!is.na(classes$value), ]
      for (i in seq_len(nrow(classes))) {
        cls <- classes$value[i]
        cls_mask <- terra::ifel(an_crop_mask_rast() == cls, 1L, NA)
        adq_vals <- terra::values(res$adequacy_etc * cls_mask, na.rm = TRUE)
        label <- if (!is.null(params)) {
          idx <- which(params$class_value == cls)
          if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
        } else as.character(cls)
        rows[[length(rows) + 1]] <- data.frame(
          Class = label,
          Indicator = "Adequacy_ETc",
          Mean = if (length(adq_vals) > 0) round(mean(adq_vals), 3) else NA,
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
    }

    # P95 adequacy
    if (!is.null(res$adequacy_p95)) {
      p95_tbl <- res$p95_table
      for (i in seq_len(nrow(p95_tbl))) {
        cls <- p95_tbl$class_value[i]
        label <- if (!is.null(params)) {
          idx <- which(params$class_value == cls)
          if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
        } else as.character(cls)
        rows[[length(rows) + 1]] <- data.frame(
          Class = label,
          Indicator = "Adequacy_P95",
          Mean = if (p95_tbl$valid[i]) round(p95_tbl$p95_aeti[i], 1) else NA,
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
    }

    if (length(rows) > 0) do.call(rbind, rows) else
      data.frame(Message = "Run analysis with adequacy indicators selected.",
        stringsAsFactors = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ---- Peff table ----
  output$an_peff_table <- shiny::renderTable({
    res <- an_results()
    peff_m <- an_peff_monthly()
    if (!is.null(peff_m)) {
      peff_m$month_name <- month.abb[peff_m$month]
      out <- peff_m[, c("year", "month_name", "p_monthly_mm", "peff_mm")]
      names(out) <- c("Year", "Month", "Precip (mm)", "Peff (mm)")
      total_row <- data.frame(
        Year = "", Month = "TOTAL",
        `Precip (mm)` = round(sum(peff_m$p_monthly_mm, na.rm = TRUE), 1),
        `Peff (mm)` = round(sum(peff_m$peff_mm, na.rm = TRUE), 1),
        check.names = FALSE, stringsAsFactors = FALSE
      )
      out <- rbind(out, total_row)
      out
    } else {
      data.frame(Message = "Run analysis with Peff indicator selected.",
        stringsAsFactors = FALSE)
    }
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ---- CWP/BWP table ----
  output$an_cwp_bwp_table <- shiny::renderTable({
    res <- an_results()
    shiny::req(res)
    rows <- list()
    if (!is.null(res$cwp)) {
      rows[[length(rows) + 1]] <- data.frame(
        Metric = "CWP", Value = round(res$cwp, 3), Unit = "kg/m3",
        stringsAsFactors = FALSE)
    }
    if (!is.null(res$bwp)) {
      rows[[length(rows) + 1]] <- data.frame(
        Metric = "BWP", Value = round(res$bwp, 3), Unit = "kg/m3",
        stringsAsFactors = FALSE)
    }
    if (length(rows) > 0) do.call(rbind, rows) else
      data.frame(Message = "Upload yield/biomass rasters and run analysis.",
        stringsAsFactors = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ---- Download handlers ----
  output$an_dl_crop_params <- shiny::downloadHandler(
    filename = function() {
      paste0("crop_parameters_", Sys.Date(), ".csv")
    },
    content = function(file) {
      params <- an_crop_params()
      if (!is.null(params)) {
        utils::write.csv(params, file, row.names = FALSE)
      }
    }
  )

  output$an_dl_results <- shiny::downloadHandler(
    filename = function() {
      paste0("seasonal_results_", Sys.Date(), ".csv")
    },
    content = function(file) {
      res <- an_results()
      if (!is.null(res) && !is.null(res$seasonal_aeti$by_class)) {
        out <- res$seasonal_aeti$by_class
        if (!is.null(res$seasonal_ret$by_class)) {
          out <- merge(out, res$seasonal_ret$by_class, by = "class_value",
            all = TRUE)
        }
        out$season <- input$an_season_label
        out$ref_year <- input$an_ref_year
        utils::write.csv(out, file, row.names = FALSE)
      }
    }
  )

  output$an_dl_peff <- shiny::downloadHandler(
    filename = function() {
      paste0("monthly_peff_", Sys.Date(), ".csv")
    },
    content = function(file) {
      peff_m <- an_peff_monthly()
      if (!is.null(peff_m)) {
        peff_m$method <- "USDA_SCS"
        utils::write.csv(peff_m, file, row.names = FALSE)
      }
    }
  )

  # ---- Code preview ----
  output$an_code_preview <- shiny::renderText({
    reg <- current_region()
    reg_str <- if (is.null(reg)) "NULL" else if (is.character(reg)) {
      sprintf("\"%s\"", reg)
    } else {
      sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
    }
    sprintf(paste0(
      "library(Rwapor)\n\n",
      "# 1. Load rasters\n",
      "crop_mask <- rwapor_load_crop_mask(\"crop_mask.tif\")\n",
      "season_start <- rwapor_load_season_raster(\"season_start.tif\")\n",
      "season_end <- rwapor_load_season_raster(\"season_end.tif\")\n\n",
      "# 2. Harmonize to AETI grid\n",
      "template <- terra::rast(\"aeti_reference.tif\")\n",
      "crop_mask_h <- rwapor_harmonize_crop_mask(crop_mask, template)\n",
      "start_h <- rwapor_harmonize_to_template(season_start, template)\n",
      "end_h <- rwapor_harmonize_to_template(season_end, template)\n\n",
      "# 3. Build season weights\n",
      "sw <- rwapor_build_season_weights_dekad(\n",
      "  \"%s\", \"%s\", start_h, end_h, %d\n",
      ")\n\n",
      "# 4. Fetch data and compute indicators\n",
      "# aeti_ts <- wapor_ts(region = %s, variable = \"%s\", ...)\n",
      "# See package documentation for full workflow"
    ), input$an_period[1], input$an_period[2], input$an_ref_year,
    reg_str, input$an_aeti_var)
  })
}

shiny::shinyApp(ui, server)
