# mod_aoi.R
# Area of interest state and controls used by the download workflow.

mod_aoi_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$head(
      shiny::tags$style(
        shiny::HTML("
          .leaflet-drawing .leaflet-container,
          .leaflet-drawing .leaflet-grab,
          .leaflet-drawing .leaflet-interactive {
            cursor: crosshair !important;
          }
        ")
      )
    ),
    shiny::radioButtons(
      ns("aoi_method"),
      "Selection Method",
      choices = c("Draw on Map" = "draw", "Upload New" = "upload", "Project Assets" = "project"),
      selected = "draw",
      inline = TRUE
    ),
    shiny::conditionalPanel(
      condition = "input.aoi_method == 'draw'",
      ns = ns,
      shiny::radioButtons(
        ns("manual_mode"),
        "Draw Mode",
        choices = c("Rectangle" = "bbox", "Polygon" = "poly"),
        selected = "bbox",
        inline = TRUE
      ),
      shiny::fluidRow(
        shiny::column(
          4,
          shiny::actionButton(
            ns("start_manual"),
            "Start",
            icon = shiny::icon("pencil"),
            width = "100%",
            class = "btn-sm btn-outline-success"
          )
        ),
        shiny::column(
          4,
          shiny::actionButton(
            ns("finish_manual"),
            "Finish",
            icon = shiny::icon("check"),
            width = "100%",
            class = "btn-sm btn-outline-primary"
          )
        ),
        shiny::column(
          4,
          shiny::actionButton(
            ns("clear_manual"),
            "Clear",
            icon = shiny::icon("eraser"),
            width = "100%",
            class = "btn-sm btn-outline-danger"
          )
        )
      )
    ),
    shiny::conditionalPanel(
      condition = "input.aoi_method == 'upload'",
      ns = ns,
      shiny::tags$div(
        class = "mt-2",
        shiny::div(
          style = "display: flex; gap: 5px; align-items: center;",
          shiny::div(
            style = "flex: 1;",
            shinyFiles::shinyFilesButton(
              ns("browse_vector"),
              "Browse for Vector File",
              "Select vector file",
              multiple = FALSE,
              class = "w-100 btn-sm btn-outline-secondary",
              icon = shiny::icon("folder-open")
            )
          ),
          shiny::uiOutput(ns("fav_vector_btn_ui"))
        ),
        shiny::uiOutput(ns("fav_vector_list_ui"))
      )
    ),
    shiny::conditionalPanel(
      condition = "input.aoi_method == 'project'",
      ns = ns,
      shiny::div(
        class = "p-2 border rounded bg-light",
        shiny::actionButton(
          ns("scan_project_assets"),
          "Scan Project Folder",
          icon = shiny::icon("magnifying-glass"),
          class = "btn-sm btn-outline-primary w-100 mb-2"
        ),
        shiny::uiOutput(ns("project_vector_ui"))
      )
    ),
    shiny::checkboxInput(ns("mask_aoi"), "Mask to AOI boundary", FALSE),
    shiny::tags$strong(style = "font-size:0.82rem;", "Selected ROI"),
    shiny::verbatimTextOutput(ns("bbox_display"))
  )
}

mod_aoi_server <- function(id,
                           map_id = "map",
                           map_session = shiny::getDefaultReactiveDomain(),
                           l3_region = shiny::reactive(NULL),
                           global_folder = shiny::reactive(NULL),
                           l3_regions_meta = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    user_roi <- shiny::reactiveVal(NULL)
    upload_roi <- shiny::reactiveVal(NULL)
    manual_clicks <- shiny::reactiveVal(
      matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat")))
    )
    manual_active <- shiny::reactiveVal(FALSE)

    current_region <- shiny::reactive({
      if (!is.null(upload_roi())) return(upload_roi())
      if (!is.null(user_roi())) return(user_roi())

      reg <- l3_region()
      if (is_l3_code(reg)) return(reg)
      NULL
    })

    roots <- get_shinyfiles_roots()

    shinyFiles::shinyFileChoose(
      input,
      "browse_vector",
      roots = roots,
      session = session,
      filetypes = c("shp", "geojson", "gpkg", "kml")
    )

    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::rwapor_get_favorites())
    current_upload_path <- shiny::reactiveVal(NULL)
    
    shiny::observe({
      file_info <- input$browse_vector
      if (!is.null(file_info) && is.list(file_info)) {
        path <- shinyFiles::parseFilePaths(roots, file_info)$datapath
        if (length(path) > 0 && nzchar(path)) {
          # normalize path
          path <- normalizePath(path, winslash = "/", mustWork = FALSE)
          current_upload_path(path)
        }
      }
    })
    
    output$fav_vector_btn_ui <- shiny::renderUI({
      path <- current_upload_path() %||% ""
      if (!nzchar(path)) return(NULL)
      
      is_fav <- Rwapor::rwapor_is_favorite(path)
      shiny::actionLink(
        session$ns("favorite_vector_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star-fill", style = "color: #ffc107;") else shiny::icon("star"),
        style = "font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$favorite_vector_btn, {
      path <- current_upload_path() %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::rwapor_is_favorite(path)) {
        Rwapor::rwapor_remove_favorite(path)
      } else {
        Rwapor::rwapor_add_favorite(path, type = "file")
      }
      favs(Rwapor::rwapor_get_favorites())
    })
    
    output$fav_vector_list_ui <- shiny::renderUI({
      f <- favs()
      # Filter to show only vector-like files for this module
      f_files <- f[f$type == "file" & grepl("\\.(shp|geojson|gpkg|kml)$", f$path, ignore.case = TRUE), "path"]
      if (length(f_files) == 0) return(NULL)
      
      shiny::selectizeInput(
        session$ns("quick_fav_vector"),
        NULL,
        choices = c("Quick Access Vector Favorites..." = "", f_files),
        options = list(placeholder = "Select a favorite vector file")
      )
    })
    
    shiny::observeEvent(input$quick_fav_vector, {
      path <- input$quick_fav_vector
      if (nzchar(path)) {
        current_upload_path(path)
        handle_vector_file(path)
      }
    })

    handle_vector_file <- function(path) {
      tryCatch({
        shp <- sf::st_read(path, quiet = TRUE)
        if (nrow(shp) == 0) stop("Vector file contains no features.")

        shp_map <- shp
        shp_crs <- sf::st_crs(shp_map)
        if (!is.na(shp_crs) && shp_crs$epsg != 4326) {
          shp_map <- sf::st_transform(shp_map, 4326)
        }

        bbox <- sf::st_bbox(shp_map)
        leaflet::leafletProxy(map_id, session = map_session) |>
          leaflet::clearGroup("manual_draw") |>
          leaflet::clearGroup("manual_preview") |>
          leaflet::clearShapes() |>
          leaflet::clearGroup("draw") |>
          leaflet::addPolygons(
            data = shp_map,
            color = "red",
            fill = FALSE,
            weight = 2
          ) |>
          leaflet::fitBounds(
            lng1 = as.numeric(bbox["xmin"]),
            lat1 = as.numeric(bbox["ymin"]),
            lng2 = as.numeric(bbox["xmax"]),
            lat2 = as.numeric(bbox["ymax"])
          )

        upload_roi(path)
        user_roi(NULL)
        manual_active(FALSE)
      }, error = function(e) {
        shiny::showNotification(e$message, type = "error")
      })
    }

    shiny::observeEvent(input$browse_vector, {
      file_info <- shinyFiles::parseFilePaths(roots(), input$browse_vector)
      if (nrow(file_info) > 0) {
        path <- normalizePath(file_info$datapath, winslash = "/", mustWork = FALSE)
        handle_vector_file(path)
      }
    })

    # --- Project Assets Scanner ---
    project_vectors <- shiny::reactiveVal(character(0))
    
    shiny::observeEvent(input$scan_project_assets, {
      folder <- global_folder()
      if (is.null(folder) || !dir.exists(folder)) {
        shiny::showNotification("Project folder does not exist or is not set.", type = "error")
        return()
      }
      
      # Scan for vector files
      files <- list.files(
        folder, 
        pattern = "\\.(shp|geojson|gpkg|kml)$", 
        recursive = TRUE, 
        full.names = TRUE
      )
      
      if (length(files) == 0) {
        shiny::showNotification("No vector files found in the project folder.", type = "warning")
      } else {
        shiny::showNotification(sprintf("Found %d vector(s).", length(files)), type = "message")
      }
      project_vectors(files)
    })
    
    output$project_vector_ui <- shiny::renderUI({
      files <- project_vectors()
      if (length(files) == 0) return(shiny::helpText("Click scan to find files."))
      
      shiny::selectInput(
        session$ns("selected_project_vector"),
        "Select Asset",
        choices = stats::setNames(files, basename(files))
      )
    })
    
    shiny::observeEvent(input$selected_project_vector, {
      path <- input$selected_project_vector
      if (nzchar(path) && file.exists(path)) {
        handle_vector_file(path)
      }
    })

    shiny::observe({
      active <- manual_active()
      if (active) {
        shinyjs::runjs(sprintf("$('#%s').addClass('leaflet-drawing')", map_id))
      } else {
        shinyjs::runjs(sprintf("$('#%s').removeClass('leaflet-drawing')", map_id))
      }
    })

    shiny::observeEvent(input$start_manual, {
      manual_active(TRUE)
      manual_clicks(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat"))))
      upload_roi(NULL)
      leaflet::leafletProxy(map_id, session = map_session) |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::clearGroup("manual_preview")
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

        leaflet::leafletProxy(map_id, session = map_session) |>
          leaflet::clearGroup("manual_preview") |>
          leaflet::clearGroup("manual_draw") |>
          leaflet::addPolygons(
            lng = pts[, 1],
            lat = pts[, 2],
            color = "yellow",
            fill = FALSE,
            weight = 2,
            group = "manual_draw"
          ) |>
          leaflet::fitBounds(
            lng1 = min(pts[, 1]),
            lat1 = min(pts[, 2]),
            lng2 = max(pts[, 1]),
            lat2 = max(pts[, 2])
          )
      } else {
        shiny::showNotification(
          "Rectangle mode auto-finishes after 2 clicks.",
          type = "message"
        )
      }
    })

    shiny::observeEvent(input$clear_manual, {
      manual_active(FALSE)
      manual_clicks(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("lng", "lat"))))
      user_roi(NULL)
      upload_roi(NULL)
      leaflet::leafletProxy(map_id, session = map_session) |>
        leaflet::clearGroup("manual_draw") |>
        leaflet::clearGroup("manual_preview") |>
        leaflet::clearShapes()
    })

    output$bbox_display <- shiny::renderPrint({
      reg <- current_region()
      if (is.null(reg)) {
        cat("No AOI selected.")
      } else if (is_l3_code(reg)) {
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

    list(
      region = current_region,
      mask = shiny::reactive(isTRUE(input$mask_aoi)),
      manual_active = manual_active,
      manual_clicks = manual_clicks,
      user_roi = user_roi,
      upload_roi = upload_roi,
      manual_mode = shiny::reactive(input$manual_mode)
    )
  })
}
