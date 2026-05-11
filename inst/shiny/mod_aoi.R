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
            style = "flex: 1; display: flex; gap: 5px;",
            shiny::div(
              style = "flex: 1;",
              shinyFiles::shinyDirButton(
                ns("browse_vector_dir"),
                "Browse Folder",
                "Select a folder to explore",
                class = "w-100 btn-sm btn-outline-secondary",
                icon = shiny::icon("folder-tree")
              )
            ),
            shiny::div(
              style = "flex: 1;",
              shinyFiles::shinyFilesButton(
                ns("browse_vector"),
                "Direct File Picker",
                "Select vector or raster file",
                multiple = FALSE,
                class = "w-100 btn-sm btn-outline-secondary",
                icon = shiny::icon("folder-open")
              )
            )
          ),
          shiny::uiOutput(ns("fav_vector_btn_ui"))
        ),
        shiny::uiOutput(ns("vector_browser_ui")),
        shiny::helpText(
          "Supported: .shp, .geojson, .gpkg, .kml, .zip, .tif, .tiff, .img, .nc, .grd, .asc, .sdat",
          shiny::br(),
          shiny::span(
            style = "color: #6c757d; font-size: 0.85em;",
            "⚠️ For OneDrive files: ensure file is ",
            shiny::strong("fully downloaded"),
            " (right-click folder → OneDrive → 'Always keep on this device')"
          )
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
    spatial_filetypes <- c("shp", "geojson", "gpkg", "kml", "zip", "tif", "tiff", "img", "nc", "grd", "asc", "sdat")
    spatial_file_pattern <- sprintf("\\.(%s)$", paste(spatial_filetypes, collapse = "|"))
    current_browser_dir <- shiny::reactiveVal(NULL)

    list_spatial_dir_entries <- function(path) {
      if (!is.character(path) || length(path) != 1 || !nzchar(path) || !dir.exists(path)) {
        return(list(directories = character(0), files = character(0)))
      }

      entries <- list.files(path, full.names = TRUE, all.files = FALSE, no.. = TRUE)
      directories <- entries[dir.exists(entries)]
      files <- entries[file.exists(entries) & !dir.exists(entries) &
        grepl(spatial_file_pattern, entries, ignore.case = TRUE)]

      directories <- directories[order(tolower(basename(directories)))]
      files <- files[order(tolower(basename(files)))]

      list(directories = directories, files = files)
    }

    normalize_existing_path <- function(path) {
      if (!is.character(path) || length(path) != 1 || !nzchar(path)) return(NULL)
      if (!file.exists(path) && !dir.exists(path)) return(NULL)
      normalizePath(path, winslash = "/", mustWork = FALSE)
    }

    default_browser_dir <- shiny::reactive({
      folder <- tryCatch(global_folder(), error = function(e) NULL)
      folder <- normalize_existing_path(folder)
      if (!is.null(folder) && dir.exists(folder)) return(folder)

      project_dir <- normalize_existing_path(getwd())
      if (!is.null(project_dir) && dir.exists(project_dir)) return(project_dir)

      home_dir <- normalize_existing_path(path.expand("~"))
      if (!is.null(home_dir) && dir.exists(home_dir)) return(home_dir)

      NULL
    })

    shiny::observe({
      if (is.null(current_browser_dir())) {
        current_browser_dir(default_browser_dir())
      }
    })

    shinyFiles::shinyDirChoose(
      input,
      "browse_vector_dir",
      roots = roots,
      session = session
    )

    shinyFiles::shinyFileChoose(
      input,
      "browse_vector",
      roots = roots,
      session = session,
      filetypes = spatial_filetypes
    )

    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::wapor_get_favorites())
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

    shiny::observeEvent(input$browse_vector_dir, {
      dir_path <- shinyFiles::parseDirPath(roots, input$browse_vector_dir)
      if (length(dir_path) > 0 && nzchar(dir_path) && dir.exists(dir_path)) {
        current_browser_dir(normalizePath(dir_path, winslash = "/", mustWork = FALSE))
      }
    })
    
    output$fav_vector_btn_ui <- shiny::renderUI({
      path <- current_upload_path() %||% ""
      if (!nzchar(path)) return(NULL)
      
      is_fav <- Rwapor::wapor_is_favorite(path)
      shiny::actionLink(
        session$ns("favorite_vector_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star", style = "color: #ffc107;") else shiny::icon("star"),
        style = "font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$favorite_vector_btn, {
      path <- current_upload_path() %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::wapor_is_favorite(path)) {
        Rwapor::wapor_remove_favorite(path)
      } else {
        Rwapor::wapor_add_favorite(path, type = "file")
      }
      favs(Rwapor::wapor_get_favorites())
    })
    
    output$fav_vector_list_ui <- shiny::renderUI({
      f <- favs()
      # Filter to show vector and raster files for this module
      f_files <- f[f$type == "file" & grepl(spatial_file_pattern, f$path, ignore.case = TRUE), "path"]
      if (length(f_files) == 0) return(NULL)
      
      shiny::selectizeInput(
        session$ns("quick_fav_vector"),
        NULL,
        choices = c("Quick Access Favorites..." = "", f_files),
        options = list(placeholder = "Select a favorite file (vector or raster)")
      )
    })

    output$vector_browser_ui <- shiny::renderUI({
      folder <- current_browser_dir()
      if (is.null(folder) || !dir.exists(folder)) {
        return(
          shiny::helpText(
            "Select a starting folder, then browse subfolders and supported spatial files here."
          )
        )
      }

      entries <- list_spatial_dir_entries(folder)
      dir_choices <- stats::setNames(entries$directories, basename(entries$directories))
      file_choices <- stats::setNames(entries$files, basename(entries$files))

      shiny::div(
        class = "mt-2 p-2 border rounded bg-light",
        shiny::tags$div(
          style = "font-size: 0.85rem; font-weight: 600; margin-bottom: 4px;",
          "Local File Explorer"
        ),
        shiny::textInput(
          session$ns("vector_current_dir"),
          "Current folder",
          value = folder,
          width = "100%"
        ),
        shiny::fluidRow(
          shiny::column(
            4,
            shiny::actionButton(
              session$ns("vector_go_up"),
              "Up",
              icon = shiny::icon("level-up-alt"),
              class = "btn-sm btn-outline-secondary w-100"
            )
          ),
          shiny::column(
            4,
            shiny::actionButton(
              session$ns("vector_refresh_dir"),
              "Refresh",
              icon = shiny::icon("rotate"),
              class = "btn-sm btn-outline-secondary w-100"
            )
          ),
          shiny::column(
            4,
            shiny::actionButton(
              session$ns("vector_open_dir"),
              "Open Folder",
              icon = shiny::icon("folder-open"),
              class = "btn-sm btn-outline-primary w-100"
            )
          )
        ),
        shiny::fluidRow(
          shiny::column(
            6,
            shiny::selectInput(
              session$ns("vector_subdir"),
              sprintf("Subfolders (%d)", length(dir_choices)),
              choices = c("Select a subfolder..." = "", dir_choices),
              selected = ""
            )
          ),
          shiny::column(
            6,
            shiny::selectInput(
              session$ns("vector_file"),
              sprintf("Spatial files (%d)", length(file_choices)),
              choices = c("Select a file..." = "", file_choices),
              selected = ""
            )
          )
        ),
        shiny::actionButton(
          session$ns("load_browser_vector"),
          "Load Selected File",
          icon = shiny::icon("map"),
          class = "btn-sm btn-outline-success w-100"
        )
      )
    })

    shiny::observeEvent(input$vector_open_dir, {
      path <- trimws(input$vector_current_dir %||% "")
      if (!nzchar(path)) return()

      normalized <- normalize_existing_path(path)
      if (is.null(normalized) || !dir.exists(normalized)) {
        shiny::showNotification("Folder does not exist or is not accessible.", type = "warning")
        return()
      }

      current_browser_dir(normalized)
    })

    shiny::observeEvent(input$vector_go_up, {
      folder <- current_browser_dir()
      if (is.null(folder) || !dir.exists(folder)) return()

      parent <- normalizePath(dirname(folder), winslash = "/", mustWork = FALSE)
      if (!identical(parent, folder) && dir.exists(parent)) {
        current_browser_dir(parent)
      }
    })

    shiny::observeEvent(input$vector_refresh_dir, {
      folder <- current_browser_dir()
      if (!is.null(folder) && dir.exists(folder)) {
        current_browser_dir(normalizePath(folder, winslash = "/", mustWork = FALSE))
      }
    })

    shiny::observeEvent(input$load_browser_vector, {
      path <- input$vector_file %||% ""
      if (!nzchar(path)) {
        shiny::showNotification("Select a spatial file first.", type = "warning")
        return()
      }

      normalized <- normalize_existing_path(path)
      if (is.null(normalized) || !file.exists(normalized)) {
        shiny::showNotification("Selected file is no longer available.", type = "warning")
        return()
      }

      current_upload_path(normalized)
      handle_vector_file(normalized)
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
        # Detect if file is raster or vector by extension
        ext <- tolower(tools::file_ext(path))
        is_raster <- ext %in% c("tif", "tiff", "nc", "grd", "asc", "sdat", "img")
        is_zip <- ext %in% "zip"

        if (is_zip) {
          tmp_dir <- tempfile("rwapor_aoi_zip_")
          dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
          utils::unzip(path, exdir = tmp_dir)
          shp_files <- list.files(tmp_dir, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)
          if (length(shp_files) == 0) {
            stop("Zip archive does not contain a .shp file.", call. = FALSE)
          }
          path <- shp_files[1]
          ext <- "shp"
        }
        
        if (is_raster) {
          # Handle raster file - extract extent
          # Verify file exists first (handle paths with spaces and OneDrive)
          file_exists <- file.exists(path)
          
          if (!file_exists) {
            # Diagnose the issue
            dir_path <- dirname(path)
            filename <- basename(path)
            dir_exists <- dir.exists(dir_path)
            
            # Try to list files in the directory to see what's actually there
            files_in_dir <- character(0)
            if (dir_exists) {
              files_in_dir <- list.files(dir_path, pattern = "\\.(tif|tiff|nc|grd)$", ignore.case = TRUE)
            }
            
            diagnostic_msg <- sprintf(
              "Raster file not found: %s\n\n$Diagnostics:\n• File: %s\n• Directory exists: %s\n",
              filename,
              basename(path),
              dir_exists
            )
            
            if (dir_exists && length(files_in_dir) > 0) {
              diagnostic_msg <- paste0(
                diagnostic_msg,
                "• Files found in directory:\n  - ",
                paste(files_in_dir, collapse = "\n  - "),
                "\n"
              )
            } else if (dir_exists) {
              diagnostic_msg <- paste0(diagnostic_msg, "• No raster files found in directory\n")
            }
            
            stop(diagnostic_msg, call. = FALSE)
          }
          
          r <- terra::rast(path)
          ext_obj <- terra::ext(r)
          
          # Get CRS and transform extent to WGS84 if needed
          raster_crs_desc <- tryCatch(terra::crs(r, describe = TRUE), error = function(e) NULL)
          raster_crs <- if (!is.null(raster_crs_desc) && "code" %in% names(raster_crs_desc)) {
            raster_crs_desc$code
          } else {
            NA_character_
          }
          
          if (!is.na(raster_crs) && raster_crs != "EPSG:4326") {
            # Create a polygon from extent and transform
            ext_poly <- terra::as.polygons(ext_obj, crs = terra::crs(r))
            
            # Remove attributes that may contain NA values (fixes "row names contain missing values" error)
            if (nrow(terra::as.data.frame(ext_poly)) > 0) {
              # Clear all attributes to avoid NA issues
              terra::values(ext_poly) <- NULL
            }
            
            ext_poly_4326 <- terra::project(ext_poly, "EPSG:4326")
            ext_4326 <- terra::ext(ext_poly_4326)
          } else {
            ext_4326 <- ext_obj
          }
          
          # Create bbox for leaflet
          bbox <- c(
            xmin = ext_4326$xmin,
            ymin = ext_4326$ymin,
            xmax = ext_4326$xmax,
            ymax = ext_4326$ymax
          )
          
          # Display extent as rectangle on map
          leaflet::leafletProxy(map_id, session = map_session) |>
            leaflet::clearGroup("manual_draw") |>
            leaflet::clearGroup("manual_preview") |>
            leaflet::clearShapes() |>
            leaflet::clearGroup("draw") |>
            leaflet::addRectangles(
              lng1 = bbox["xmin"],
              lat1 = bbox["ymin"],
              lng2 = bbox["xmax"],
              lat2 = bbox["ymax"],
              color = "blue",
              fill = FALSE,
              weight = 2,
              dashArray = "5, 5"
            ) |>
            leaflet::fitBounds(
              lng1 = bbox["xmin"],
              lat1 = bbox["ymin"],
              lng2 = bbox["xmax"],
              lat2 = bbox["ymax"]
            )
          
          shiny::showNotification(
            sprintf("Raster extent loaded: %.2f° × %.2f°", 
                    bbox["xmax"] - bbox["xmin"], 
                    bbox["ymax"] - bbox["ymin"]),
            type = "message"
          )
        } else {
          # Handle vector file (original code)
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
        }

        upload_roi(path)
        user_roi(NULL)
        manual_active(FALSE)
      }, error = function(e) {
        # Provide more detailed error message
        error_msg <- e$message
        
        # Check if it's a file not found issue
        if (grepl("does not exist|no such file|not found", error_msg, ignore.case = TRUE)) {
          shiny::showNotification(
            HTML(paste0(
              "<strong>⚠️ File not found or not accessible</strong><br/>",
              "<small style='line-height:1.6'>",
              error_msg,
              "<br/><br/>",
              "<strong>Possible causes:</strong><br/>",
              "• OneDrive has not fully synced the file to this computer<br/>",
              "• File was moved, deleted, or renamed<br/>",
              "• Folder permissions issue<br/>",
              "• OneDrive 'Files On-Demand' not downloaded<br/>",
              "<br/>",
              "<strong>Solutions:</strong><br/>",
              "1. Right-click the folder in File Explorer → OneDrive → 'Always keep on this device'<br/>",
              "2. Check Windows File Explorer - navigate to the folder manually<br/>",
              "3. Try copying the file to a local folder (not OneDrive) and upload from there<br/>",
              "</small>"
            )),
            type = "error",
            duration = 20
          )
        } else if (grepl("CRS|crs|projection", error_msg, ignore.case = TRUE)) {
          shiny::showNotification(
            HTML(paste0(
              "<strong>⚠️ Raster CRS issue</strong><br/>",
              "<small>",
              error_msg,
              "<br/><br/>",
              "The raster file exists but has CRS/projection problems. ",
              "Try opening the file in QGIS to check and fix the CRS.",
              "</small>"
            )),
            type = "error",
            duration = 15
          )
        } else {
          shiny::showNotification(
            HTML(paste0(
              "<strong>Error loading file</strong><br/>",
              "<small>", error_msg, "</small>"
            )),
            type = "error",
            duration = 10
          )
        }
      })
    }

    shiny::observeEvent(input$browse_vector, {
      file_info <- shinyFiles::parseFilePaths(roots, input$browse_vector)
      if (nrow(file_info) > 0) {
        # Get the datapath and normalize it carefully
        path <- file_info$datapath[1]
        
        # Try multiple path normalizations to handle various formats
        if (!file.exists(path)) {
          # Try with forward slashes
          path_fwd <- gsub("\\\\", "/", path)
          if (file.exists(path_fwd)) {
            path <- path_fwd
          } else {
            # Try with expanded path (handles ~ and environment variables)
            path_expanded <- path.expand(path_fwd)
            if (file.exists(path_expanded)) {
              path <- path_expanded
            } else {
              # Try normalizePath which handles symlinks and relative paths
              path_norm <- tryCatch(
                normalizePath(path_expanded, winslash = "/", mustWork = TRUE),
                error = function(e) path_expanded
              )
              path <- path_norm
            }
          }
        }
        
        current_browser_dir(normalizePath(dirname(path), winslash = "/", mustWork = FALSE))
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
      
      # Scan for vector and raster files
      files <- list.files(
        folder, 
        pattern = "\\.(shp|geojson|gpkg|kml|tif|tiff|nc|grd|asc|sdat)$", 
        recursive = TRUE, 
        full.names = TRUE
      )
      
      if (length(files) == 0) {
        shiny::showNotification("No spatial files found in the project folder.", type = "warning")
      } else {
        shiny::showNotification(sprintf("Found %d spatial file(s).", length(files)), type = "message")
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
