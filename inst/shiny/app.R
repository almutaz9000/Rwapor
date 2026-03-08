wapor_vars <- names(Rwapor::WAPOR3_VARS)
agera5_vars <- names(Rwapor::AGERA5_VARS)
all_vars <- sort(c(wapor_vars, agera5_vars))
default_var <- if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else all_vars[1]

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

ui <- shiny::fluidPage(
  shiny::titlePanel("Rwapor Dashboard"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      shiny::h4("Download Configuration"),
      shiny::selectInput("variable", "Variable", choices = all_vars, selected = default_var),
      shiny::dateRangeInput("period", "Period", start = Sys.Date() - 30, end = Sys.Date(), format = "yyyy-mm-dd"),
      shiny::fluidRow(
        shiny::column(9, shiny::textInput("folder", "Output Folder", value = file.path(getwd(), "wapor_output"))),
        shiny::column(3, shinyFiles::shinyDirButton("browse_folder", "Browse", "Select output directory", width = "100%"))
      ),
      shiny::checkboxInput("seasonal", "Seasonal Aggregation", value = FALSE),
      shiny::checkboxInput("separate_files", "Save as Separate Files", value = FALSE),
      shiny::selectInput("unit_conversion", "Unit Conversion", choices = c("none", "day", "dekad", "month", "year"), selected = "none"),
      shiny::hr(),
      shiny::h4("Area of Interest (AOI)"),
      shiny::p("Use map drawing tools, or use manual draw below, or upload a vector file."),
      shiny::radioButtons("manual_mode", "Manual Draw Mode", choices = c("Rectangle (2 clicks)" = "bbox", "Polygon (click vertices + Finish)" = "poly"), selected = "bbox"),
      shiny::fluidRow(
        shiny::column(4, shiny::actionButton("start_manual", "Start Draw", width = "100%")),
        shiny::column(4, shiny::actionButton("finish_manual", "Finish", width = "100%")),
        shiny::column(4, shiny::actionButton("clear_manual", "Clear", width = "100%"))
      ),
      shiny::helpText("Manual mode works even if leaflet.extras tools are unavailable."),
      shiny::fileInput("vector_file", "Upload Vector File", accept = c(".geojson", ".gpkg", ".kml")),
      shiny::hr(),
      shiny::h4("Selected ROI/BBOX"),
      shiny::verbatimTextOutput("bbox_display"),
      shiny::actionButton("download_btn", "Download Data", class = "btn-primary", style = "width:100%; margin-top:10px;")
    ),
    shiny::mainPanel(
      leaflet::leafletOutput("map", height = "500px"),
      shiny::hr(),
      shiny::h4("R Code Preview"),
      shiny::verbatimTextOutput("code_preview")
    )
  )
)

server <- function(input, output, session) {
  user_roi <- shiny::reactiveVal(NULL)
  upload_roi <- shiny::reactiveVal(NULL)
  manual_clicks <- shiny::reactiveVal(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat"))))
  manual_active <- shiny::reactiveVal(FALSE)

  roots <- c(Home = normalizePath("~", winslash = "/"), "C:/" = "C:/")
  shinyFiles::shinyDirChoose(input, "browse_folder", roots = roots, session = session)
  shiny::observeEvent(input$browse_folder, {
    dir_path <- shinyFiles::parseDirPath(roots, input$browse_folder)
    if (length(dir_path) == 1 && nzchar(dir_path)) {
      shiny::updateTextInput(session, "folder", value = dir_path)
    }
  })

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
          editOptions = edit_toolbar_options(selectedPathOptions = selected_path_options())
        )
    }
    m |>
      leaflet::setView(lng = 0, lat = 0, zoom = 2)
  })

  shiny::observeEvent(input$start_manual, {
    manual_active(TRUE)
    manual_clicks(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat"))))
    upload_roi(NULL)
    shiny::showNotification("Manual draw started. Click on map to add points.", type = "message")
    leaflet::leafletProxy("map") |>
      leaflet::clearGroup("manual_draw")
  })

  shiny::observeEvent(input$map_click, {
    if (!manual_active()) return()
    click <- input$map_click
    current <- manual_clicks()
    current <- rbind(current, c(click$lng, click$lat))
    manual_clicks(current)
    leaflet::leafletProxy("map") |>
      leaflet::addCircleMarkers(lng = click$lng, lat = click$lat, radius = 4, group = "manual_draw", fillOpacity = 1)

    if (input$manual_mode == "bbox" && nrow(current) >= 2) {
      bbox <- c(min(current[, 1]), min(current[, 2]), max(current[, 1]), max(current[, 2]))
      user_roi(bbox)
      upload_roi(NULL)
      manual_active(FALSE)
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::addRectangles(
          lng1 = bbox[1], lat1 = bbox[2], lng2 = bbox[3], lat2 = bbox[4],
          color = "yellow", fill = FALSE, weight = 2, group = "manual_draw"
        )
      shiny::showNotification("Rectangle AOI set.", type = "message")
    } else if (input$manual_mode == "poly" && nrow(current) >= 2) {
      leaflet::leafletProxy("map") |>
        leaflet::clearGroup("manual_preview") |>
        leaflet::addPolylines(lng = current[, 1], lat = current[, 2], color = "yellow", weight = 2, group = "manual_preview")
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
        shiny::showNotification("Polygon needs at least 3 points.", type = "error")
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
        leaflet::addPolygons(lng = pts[, 1], lat = pts[, 2], color = "yellow", fill = FALSE, weight = 2, group = "manual_draw")
      shiny::showNotification("Polygon AOI set.", type = "message")
    } else {
      shiny::showNotification("Rectangle mode auto-finishes after 2 clicks.", type = "message")
    }
  })

  shiny::observeEvent(input$clear_manual, {
    manual_active(FALSE)
    manual_clicks(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat"))))
    user_roi(NULL)
    upload_roi(NULL)
    leaflet::leafletProxy("map") |>
      leaflet::clearGroup("manual_draw") |>
      leaflet::clearGroup("manual_preview") |>
      leaflet::clearShapes()
  })

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

  shiny::observeEvent(input$vector_file, {
    shiny::req(input$vector_file)
    ext <- tolower(tools::file_ext(input$vector_file$name))
    allowed_ext <- c("geojson", "gpkg", "kml")
    if (!ext %in% allowed_ext) {
      shiny::showNotification(sprintf("Unsupported format '.%s'. Use: %s", ext, paste(allowed_ext, collapse = ", ")), type = "error")
      return()
    }
    tryCatch({
      temp_path <- tempfile(fileext = paste0(".", ext))
      copied <- file.copy(input$vector_file$datapath, temp_path, overwrite = TRUE)
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
        leaflet::addPolygons(data = shp_map, color = "red", fill = FALSE, weight = 2) |>
        leaflet::addRectangles(
          lng1 = bbox["xmin"], lat1 = bbox["ymin"],
          lng2 = bbox["xmax"], lat2 = bbox["ymax"],
          color = "blue", fill = FALSE, weight = 1, dashArray = "4"
        ) |>
        leaflet::fitBounds(lng1 = bbox["xmin"], lat1 = bbox["ymin"], lng2 = bbox["xmax"], lat2 = bbox["ymax"])
      upload_roi(temp_path)
      user_roi(NULL)
      manual_active(FALSE)
      shiny::showNotification("Vector file uploaded successfully.", type = "message")
    }, error = function(e) {
      shiny::showNotification(paste("Error reading vector file:", e$message), type = "error")
    })
  })

  current_region <- shiny::reactive({
    if (!is.null(upload_roi())) return(upload_roi())
    if (!is.null(user_roi())) return(user_roi())
    NULL
  })

  output$bbox_display <- shiny::renderPrint({
    reg <- current_region()
    if (is.null(reg)) {
      cat("No AOI selected.")
    } else if (is.character(reg)) {
      cat("Vector file:\n", reg)
    } else if (is.numeric(reg)) {
      cat(sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4]))
    }
  })

  output$code_preview <- shiny::renderText({
    reg <- current_region()
    if (is.null(reg)) {
      reg_str <- "NULL  # Please select an AOI on the map or upload a file"
    } else if (is.character(reg)) {
      reg_str <- sprintf("\"%s\"", normalizePath(reg, winslash = "/", mustWork = FALSE))
    } else {
      reg_str <- sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
    }
    period_str <- sprintf("c(\"%s\", \"%s\")", input$period[1], input$period[2])
    unit_conv <- if (input$unit_conversion == "none") "NULL" else sprintf("\"%s\"", input$unit_conversion)
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
      reg_str, period_str, input$folder, input$variable, unit_conv, input$seasonal, input$separate_files
    )
  })

  shiny::observeEvent(input$download_btn, {
    reg <- current_region()
    if (is.null(reg)) {
      shiny::showNotification("Please select an AOI before downloading.", type = "error")
      return()
    }
    if (!nzchar(input$folder)) {
      shiny::showNotification("Output folder cannot be empty.", type = "error")
      return()
    }
    shiny::showModal(shiny::modalDialog(
      title = "Downloading...",
      "Execution is running. The R console shows detailed progress.",
      footer = NULL
    ))
    tryCatch({
      unit_conv <- if (input$unit_conversion == "none") NULL else input$unit_conversion
      out_path <- Rwapor::wapor_map(
        region = reg,
        variable = input$variable,
        period = as.character(input$period),
        folder = input$folder,
        unit_conversion = unit_conv,
        seasonal = input$seasonal,
        separate_files = input$separate_files
      )
      if (length(out_path) == 0 || !all(file.exists(out_path))) {
        stop("Download completed but output file(s) were not found on disk.")
      }
      shiny::removeModal()
      message("Dashboard download success. Output: ", paste(out_path, collapse = ", "))
      if (length(out_path) > 1) {
        shiny::showNotification(sprintf("Download successful. %d files written in %s", length(out_path), dirname(out_path[1])), type = "message", duration = 10)
      } else {
        shiny::showNotification(sprintf("Download successful. Saved to: %s", out_path), type = "message", duration = 10)
      }
    }, error = function(e) {
      shiny::removeModal()
      message("Dashboard download failed: ", e$message)
      shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
    })
  })
}

shiny::shinyApp(ui, server)
