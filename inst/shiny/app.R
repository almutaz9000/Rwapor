# Build variable list from package metadata (L1, L2, L3 + AgERA5)
all_vars <- sort(unique(c(names(Rwapor::WAPOR3_VARS), names(Rwapor::AGERA5_VARS))))
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else all_vars[1]

# Build L3 region choices from package metadata: "Country - Name (CODE)"
l3_regions_meta <- Rwapor::L3_REGIONS
l3_region_labels <- vapply(names(l3_regions_meta), function(code) {
  r <- l3_regions_meta[[code]]
  sprintf("%s - %s (%s)", r$country, r$name, code)
}, character(1))
# Sort by label (country first) and build named vector: label -> code
l3_region_labels <- sort(l3_region_labels)
l3_region_choices <- stats::setNames(
  sub(".*\\(([A-Z]{3})\\)$", "\\1", l3_region_labels),
  l3_region_labels
)

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
    primary = "#2c3e50",
    "navbar-bg" = "#2c3e50"
  ),
  header = shiny::tags$head(shiny::tags$style(shiny::HTML("
    .card { margin-bottom: 1rem; }
    .leaflet-container { border-radius: 0.375rem; }
    .accordion-button:focus { box-shadow: none; }
    #analysis_map_card .leaflet-container, 
    #download_map_card .leaflet-container {
      aspect-ratio: 1;
      max-height: 800px;
    }
    #raster_info_table { font-size: 0.85rem; }
    #raster_info_table table { margin-bottom: 0; }
    .card-body.compact { padding: 0.5rem; }
  "))),

  # ---- Download Tab --------------------------------------------------------
  bslib::nav_panel(
    "Download",
    icon = shiny::icon("cloud-download"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 380,
        title = "Download Configuration",

        bslib::accordion(
          id = "download_accordion",
          open = c("Variable & Period", "Area of Interest"),

          bslib::accordion_panel(
            "Variable & Period",
            icon = shiny::icon("database"),
            shiny::selectInput("variable", "Variable",
              choices = all_vars, selected = default_var),
            # L3 region selector (shown only for L3 variables)
            shiny::conditionalPanel(
              condition = "input.variable.startsWith('L3-')",
              shiny::selectInput("l3_region", "L3 Region",
                choices = l3_region_choices),
              shiny::helpText("L3 variables require a specific region.")
            ),
            shiny::dateRangeInput("period", "Period",
              start = Sys.Date() - 30, end = Sys.Date(),
              format = "yyyy-mm-dd")
          ),

          bslib::accordion_panel(
            "Output Settings",
            icon = shiny::icon("folder"),
            shiny::fluidRow(
              shiny::column(9, shiny::textInput("folder", "Output Folder",
                value = file.path(getwd(), "wapor_output"))),
              shiny::column(3, shinyFiles::shinyDirButton("browse_folder",
                "Browse", "Select output directory", width = "100%"))
            ),
            shiny::checkboxInput("seasonal", "Seasonal Aggregation",
              value = FALSE),
            shiny::checkboxInput("separate_files", "Save as Separate Files",
              value = FALSE),
            shiny::helpText(
              shiny::conditionalPanel(
                condition = "input.seasonal && input.separate_files",
                shiny::tags$em("Both selected: will download seasonal raster AND individual time step files.")
              )
            ),
            shiny::selectInput("unit_conversion", "Unit Conversion",
              choices = c("none", "day", "dekad", "month", "year"),
              selected = "none")
          ),

          bslib::accordion_panel(
            "Area of Interest",
            icon = shiny::icon("map"),
            shiny::conditionalPanel(
              condition = "!input.variable.startsWith('L3-')",
              shiny::p("Draw on map, use manual draw, or upload a vector file."),
              shiny::radioButtons("manual_mode", "Manual Draw Mode",
                choices = c("Rectangle (2 clicks)" = "bbox",
                            "Polygon (click vertices)" = "poly"),
                selected = "bbox", inline = TRUE),
              shiny::fluidRow(
                shiny::column(4, shiny::actionButton("start_manual",
                  "Start", icon = shiny::icon("pencil"), width = "100%")),
                shiny::column(4, shiny::actionButton("finish_manual",
                  "Finish", icon = shiny::icon("check"), width = "100%")),
                shiny::column(4, shiny::actionButton("clear_manual",
                  "Clear", icon = shiny::icon("eraser"), width = "100%"))
              ),
              shiny::helpText("Manual mode works even if leaflet.extras is unavailable."),
              shiny::fileInput("vector_file", "Upload Vector File",
                accept = c(".geojson", ".gpkg", ".kml"))
            ),
            shiny::conditionalPanel(
              condition = "input.variable.startsWith('L3-')",
              shiny::p("L3 variables use predefined regions. Select a region above.")
            ),
            shiny::hr(),
            shiny::tags$strong("Selected ROI"),
            shiny::verbatimTextOutput("bbox_display")
          )
        ),

        shiny::actionButton("download_btn", "Download Data",
          class = "btn-primary w-100 mt-3",
          icon = shiny::icon("cloud-download"))
      ),

      # Main content
      bslib::layout_column_wrap(
        width = 1,
        bslib::card(
          id = "download_map_card",
          bslib::card_header("Map"),
          bslib::card_body(
            class = "p-0",
            leaflet::leafletOutput("map", height = "700px")
          )
        ),
        bslib::card(
          bslib::card_header("R Code Preview"),
          bslib::card_body(
            shiny::verbatimTextOutput("code_preview")
          )
        )
      )
    )
  ),

  # ---- Visualisation Tab ---------------------------------------------------
  bslib::nav_panel(
    "Visualisation",
    icon = shiny::icon("chart-area"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 350,
        title = "Raster Visualization",

        bslib::accordion(
          id = "analysis_accordion",
          open = c("Raster Selection", "Color Palette"),

          bslib::accordion_panel(
            "Raster Selection",
            icon = shiny::icon("file-image"),
            shiny::textInput("analysis_folder", "Raster Folder",
              value = file.path(getwd(), "wapor_output")),
            shiny::actionButton("scan_rasters", "Scan Folder",
              icon = shiny::icon("magnifying-glass"),
              class = "btn-outline-primary w-100 mb-2"),
            shiny::selectInput("raster_file", "Select Raster", choices = NULL),
            shiny::selectInput("raster_band", "Band / Layer", choices = NULL)
          ),

          bslib::accordion_panel(
            "Color Palette",
            icon = shiny::icon("palette"),
            shiny::selectInput("palette_name", "Palette",
              choices = c("viridis", "magma", "plasma", "inferno", "cividis",
                          "terrain.colors", "heat.colors", "topo.colors",
                          "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
              selected = "viridis"),
            shiny::sliderInput("n_colors", "Number of Classes",
              min = 3, max = 15, value = 7, step = 1),
            shiny::sliderInput("raster_opacity", "Opacity",
              min = 0, max = 1, value = 0.8, step = 0.05),
            shiny::checkboxInput("reverse_palette", "Reverse Palette", FALSE),
            shiny::radioButtons("color_method", "Method",
              choices = c("Continuous" = "numeric", "Binned" = "bin"),
              selected = "numeric", inline = TRUE)
          ),

          bslib::accordion_panel(
            "Overlay Options",
            icon = shiny::icon("layer-group"),
            shiny::checkboxInput("overlay_aoi", "Show AOI Boundary", TRUE),
            shiny::selectInput("basemap_analysis", "Basemap",
              choices = c("Esri.WorldImagery", "OpenStreetMap",
                          "CartoDB.Positron", "CartoDB.DarkMatter"),
              selected = "CartoDB.Positron")
          )
        )
      ),

      # Main content - square map card
      bslib::layout_column_wrap(
        width = 1,
        bslib::card(
          id = "analysis_map_card",
          bslib::card_header("Raster Visualization"),
          bslib::card_body(
            class = "p-0",
            leaflet::leafletOutput("analysis_map", height = "700px",
              width = "100%")
          )
        ),
        bslib::card(
          bslib::card_header("Raster Information"),
          bslib::card_body(
            class = "compact",
            shiny::div(id = "raster_info_table", shiny::tableOutput("raster_info"))
          )
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

  # ---- Shared reactive state -----------------------------------------------
  user_roi <- shiny::reactiveVal(NULL)
  upload_roi <- shiny::reactiveVal(NULL)
  manual_clicks <- shiny::reactiveVal(matrix(numeric(), ncol = 2,
    dimnames = list(NULL, c("lng", "lat"))))
  manual_active <- shiny::reactiveVal(FALSE)
  
  # ---- Exit Dashboard ------------------------------------------------------
  shiny::observeEvent(input$exit_btn, {
    shiny::showNotification("Shutting down dashboard...", type = "message")
    shiny::stopApp()
  })

  current_region <- shiny::reactive({
    # For L3 variables, use the selected L3 region code
    if (grepl("^L3-", input$variable)) {
      reg <- input$l3_region
      if (!is.null(reg) && nzchar(reg)) return(reg)
      return(NULL)
    }
    if (!is.null(upload_roi())) return(upload_roi())
    if (!is.null(user_roi())) return(user_roi())
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

  # Sync analysis folder with download folder
  shiny::observe({
    shiny::updateTextInput(session, "analysis_folder", value = input$folder)
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
    m |> leaflet::setView(lng = 0, lat = 0, zoom = 2)
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
          color = "yellow", fill = FALSE, weight = 2, group = "manual_draw")
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
          color = "yellow", fill = FALSE, weight = 2, group = "manual_draw")
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

  # ---- Vector file upload --------------------------------------------------
  shiny::observeEvent(input$vector_file, {
    shiny::req(input$vector_file)
    ext <- tolower(tools::file_ext(input$vector_file$name))
    allowed_ext <- c("geojson", "gpkg", "kml")
    if (!ext %in% allowed_ext) {
      shiny::showNotification(
        sprintf("Unsupported format '.%s'. Use: %s", ext,
          paste(allowed_ext, collapse = ", ")),
        type = "error")
      return()
    }
    tryCatch({
      temp_path <- tempfile(fileext = paste0(".", ext))
      copied <- file.copy(input$vector_file$datapath, temp_path,
        overwrite = TRUE)
      if (!copied) stop("Failed to copy uploaded file to temporary location.")
      shp <- sf::st_read(temp_path, quiet = TRUE)
      if (nrow(shp) == 0) stop("Uploaded vector file contains no features.")
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
          lng1 = bbox["xmin"], lat1 = bbox["ymin"],
          lng2 = bbox["xmax"], lat2 = bbox["ymax"],
          color = "blue", fill = FALSE, weight = 1, dashArray = "4") |>
        leaflet::fitBounds(lng1 = bbox["xmin"], lat1 = bbox["ymin"],
          lng2 = bbox["xmax"], lat2 = bbox["ymax"])
      upload_roi(temp_path)
      user_roi(NULL)
      manual_active(FALSE)
      shiny::showNotification("Vector file uploaded successfully.",
        type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error reading vector file:", e$message),
        type = "error")
    })
  })

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
          "  separate_files = FALSE\n",
          ")\n\n",
          "# 2. Download individual time step files\n",
          "file_paths <- wapor_map(\n",
          "  region = region,\n",
          "  variable = \"%s\",\n",
          "  period = period,\n",
          "  folder = folder,\n",
          "  unit_conversion = %s,\n",
          "  seasonal = FALSE,\n",
          "  separate_files = TRUE\n",
          ")"
        ),
        reg_str, period_str, input$folder, input$variable,
        unit_conv, input$variable, unit_conv
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
          "  separate_files = %s\n",
          ")"
        ),
        reg_str, period_str, input$folder, input$variable,
        unit_conv, input$seasonal, input$separate_files
      )
    }
  })

  # ---- Download action -----------------------------------------------------
  shiny::observeEvent(input$download_btn, {
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
            separate_files = FALSE
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
            separate_files = TRUE
          )

          shiny::incProgress(0.45, detail = "Complete!")
          all_paths <- c(seasonal_path, ind_paths)
          n_files <- length(all_paths)
          message("Dashboard download success. Output: ",
            paste(all_paths, collapse = ", "))
          shiny::showNotification(
            sprintf("Download successful. %d files written (1 seasonal + %d individual).",
              n_files, n_files - 1),
            type = "message", duration = 10)
        }, error = function(e) {
          message("Dashboard download failed: ", e$message)
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
            separate_files = input$separate_files
          )
          shiny::incProgress(0.9, detail = "Finalizing...")
          if (length(out_path) == 0 || !all(file.exists(out_path))) {
            stop("Download completed but output file(s) were not found on disk.")
          }
          message("Dashboard download success. Output: ",
            paste(out_path, collapse = ", "))
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
          message("Dashboard download failed: ", e$message)
          shiny::showNotification(paste("Download failed:", e$message),
            type = "error", duration = 15)
        })
      })
    }
  })

  # ==========================================================================
  # ANALYSIS TAB SERVER
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
      leaflet::setView(lng = 0, lat = 0, zoom = 2)
  })

  # Update basemap when selector changes
  shiny::observeEvent(input$basemap_analysis, {
    leaflet::leafletProxy("analysis_map") |>
      leaflet::clearTiles() |>
      leaflet::addProviderTiles(input$basemap_analysis)
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
}

shiny::shinyApp(ui, server)
