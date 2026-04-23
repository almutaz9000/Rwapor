# mod_visualisation.R
# Raster Visualisation and Time-Series Explorer Module

mod_visualisation_ui <- function(id) {
  ns <- shiny::NS(id)
  
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      open  = TRUE,
      title = "Raster Visualization",

      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id   = ns("analysis_accordion"),
          open = c("Raster Selection", "Color Palette"),
          
          # ── 0. Visualization Mode ────────────────────────────────
          bslib::accordion_panel(
            "Visualization Mode", icon = shiny::icon("sliders"),
            
            shiny::div(
              class = "viz-mode-group",
              shiny::radioButtons(
                ns("viz_mode"), NULL,
                choices = c(
                  "Single Raster"  = "single",
                  "Dual Compare"   = "dual",
                  "Query Filter"   = "query"
                ),
                selected = "single"
              )
            ),
            
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'query'", ns("viz_mode")),
              shiny::tags$div(
                style = "background-color: #f8f9fa; padding: 10px; border-radius: 5px; margin-top: 10px;",
                shiny::tags$strong("Query Example:"),
                shiny::tags$br(),
                shiny::tags$small("Raster1 >= 150 & Raster2 <= 20")
              )
            )
          ),

          # ── 1. Raster Selection ──────────────────────────────────
          bslib::accordion_panel(
            "Raster Selection", icon = shiny::icon("file-image"),

            shiny::div(
              class = "inline-row mb-1",
              shiny::div(
                class = "flex-1",
                shiny::selectizeInput(ns("raster_file"), "Raster 1", choices = NULL)
              ),
              shiny::actionButton(
                ns("scan_rasters"), NULL,
                icon  = shiny::icon("rotate"),
                title = "Rescan folder for raster files",
                class = "btn-outline-secondary btn-sm mt-4",
                style = "padding:0.37rem 0.6rem;"
              )
            ),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::selectInput(ns("raster_band"), "Band / Layer", choices = NULL)
              ),
              shiny::div(
                style = "padding-top: 1.8rem; margin-left: 10px;",
                shiny::checkboxInput(ns("only_seasonal"), "Seasonal Only", FALSE)
              )
            ),
            
            # Second Raster (conditional on mode) - using uiOutput for reliable module compatibility
            shiny::uiOutput(ns("raster2_ui"))
          ),

          # ── 2. Conditional Query Builder ────────────────────────
          bslib::accordion_panel(
            "Conditional Query", icon = shiny::icon("filter"),
            
            # Using uiOutput for reliable conditional rendering in modules
            shiny::uiOutput(ns("query_panel_ui"))
          ),

          # ── 3. Color Palette ─────────────────────────────────────
          bslib::accordion_panel(
            "Color Palette", icon = shiny::icon("palette"),

            # Raster 1 Palette
            shiny::tags$span("Raster 1 Colors", class = "ctrl-group-label"),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::selectInput(ns("palette_name"), "Palette",
                  choices  = c("viridis", "magma", "plasma", "inferno", "cividis",
                               "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
                  selected = "viridis")
              ),
              shiny::div(
                style = "width:70px;",
                shiny::numericInput(ns("n_colors"), "Classes",
                  value = 7, min = 3, max = 15, step = 1)
              )
            ),

            shiny::uiOutput(ns("palette_swatch")),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::sliderInput(ns("raster_opacity"), "Opacity",
                  min = 0, max = 1, value = 0.8, step = 0.05, ticks = FALSE)
              ),
              shiny::div(
                style = "padding-top:1.8rem;",
                shiny::checkboxInput(ns("reverse_palette"), "Reverse", FALSE)
              )
            ),

            shiny::tags$span("Colour method", class = "ctrl-group-label"),
            shiny::radioButtons(ns("color_method"), NULL,
              choices  = c("Continuous" = "numeric", "Binned" = "bin"),
              selected = "numeric", inline = TRUE),
            
            # Raster 2 Palette (conditional) - using uiOutput for reliable module compatibility
            shiny::uiOutput(ns("raster2_palette_ui"))
          ),

          # ── 4. Map & Layers ──────────────────────────────────────
          bslib::accordion_panel(
            "Map & Layers", icon = shiny::icon("layer-group"),

            shiny::selectInput(ns("basemap_analysis"), "Basemap",
              choices = c(
                "Esri Satellite"  = "Esri.WorldImagery",
                "OpenStreetMap"   = "OpenStreetMap",
                "Carto Light"     = "CartoDB.Positron",
                "Carto Dark"      = "CartoDB.DarkMatter"
              ),
              selected = "Esri.WorldImagery"),

            shiny::checkboxInput(ns("overlay_aoi"), "Show AOI boundary", TRUE),
            
            # Dual mode overlay options - using uiOutput for reliable module compatibility
            shiny::uiOutput(ns("dual_display_ui")),

            shiny::tags$hr(class = "ctrl-divider"),
            shiny::tags$span("Analysis Layer Overlays", class = "ctrl-group-label"),
            shiny::div(
              class = "check-row",
              shiny::checkboxInput(ns("show_crop_mask"),    "Crop Mask",    FALSE),
              shiny::checkboxInput(ns("show_season_start"), "Season Start", FALSE),
              shiny::checkboxInput(ns("show_season_end"),   "Season End",   FALSE)
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] || input['%s'] || input['%s']",
                                  ns("show_crop_mask"), ns("show_season_start"), ns("show_season_end")),
              shiny::sliderInput(ns("an_layer_opacity"), "Layer Opacity",
                min = 0, max = 1, value = 0.75, step = 0.05, ticks = FALSE)
            )
          )
        )
      )
    ),
    
    bslib::card(
      id          = ns("analysis_map_card"),
      full_screen = TRUE,
      bslib::card_header("Raster Visualization"),
      bslib::card_body(
        class = "p-0 main-map-output",
        leaflet::leafletOutput(ns("analysis_map"), height = "100%", width = "100%")
      ),
      bslib::card_footer(
        style = "padding: 0.4rem 0.6rem;",
        shiny::uiOutput(ns("raster_stat_boxes"))
      )
    )
  )
}

mod_visualisation_server <- function(id, global_folder, aoi_region, 
                                    an_crop_mask_rast = shiny::reactive(NULL),
                                    an_start_rast = shiny::reactive(NULL),
                                    an_end_rast = shiny::reactive(NULL),
                                    an_crop_params = shiny::reactive(NULL)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    loaded_raster <- shiny::reactiveVal(NULL)
    loaded_raster2 <- shiny::reactiveVal(NULL)
    query_result_raster <- shiny::reactiveVal(NULL)
    
    # ── Dynamic UI Rendering (fixes conditionalPanel module issues) ────────
    
    # Render second raster selector based on mode
    output$raster2_ui <- shiny::renderUI({
      mode <- input$viz_mode
      
      if (is.null(mode) || mode == "single") {
        return(NULL)
      }
      
      choices <- isolate(raster_choices())
      
      shiny::tagList(
        shiny::tags$hr(style = "margin: 15px 0;"),
        shiny::tags$strong("Raster 2", style = "display: block; margin-bottom: 8px;"),
        shiny::selectizeInput(ns("raster_file2"), "File", choices = choices, selected = NULL),
        shiny::selectInput(ns("raster_band2"), "Band / Layer", choices = NULL)
      )
    })
    
    # Render query panel controls
    output$query_panel_ui <- shiny::renderUI({
      mode <- input$viz_mode
      
      if (is.null(mode) || mode != "query") {
        return(shiny::tags$p("Switch to 'Conditional Query' mode to use this feature.", 
                            style = "color: #666; font-style: italic; padding: 10px;"))
      }
      
      shiny::tagList(
        shiny::textAreaInput(
          ns("query_expression"),
          "Query Expression",
          value = "Raster1 >= 100 & Raster2 <= 50",
          rows = 3,
          placeholder = "Example: Raster1 >= 150 & Raster2 <= 20"
        ),
        
        shiny::tags$div(
          style = "margin-bottom: 10px;",
          shiny::tags$strong("Operators:"),
          shiny::tags$br(),
          shiny::tags$small(">, <, >=, <=, ==, !=, &, |")
        ),
        
        shiny::div(
          class = "inline-row",
          shiny::div(
            class = "flex-1",
            shiny::selectInput(
              ns("match_color"),
              "Match Color",
              choices = c("red", "blue", "green", "yellow", "orange", "purple"),
              selected = "red"
            )
          ),
          shiny::div(
            class = "flex-1",
            shiny::selectInput(
              ns("nomatch_color"),
              "No Match Color",
              choices = c("gray", "white", "black", "lightgray"),
              selected = "gray"
            )
          )
        ),
        
        shiny::sliderInput(
          ns("query_opacity"),
          "Query Layer Opacity",
          min = 0, max = 1, value = 0.7, step = 0.05, ticks = FALSE
        ),
        
        shiny::actionButton(
          ns("apply_query"),
          "Apply Query",
          icon = shiny::icon("play"),
          class = "btn-primary w-100"
        ),
        
        shiny::tags$hr(),
        shiny::uiOutput(ns("query_stats"))
      )
    })
    
    # Render raster 2 palette controls
    output$raster2_palette_ui <- shiny::renderUI({
      mode <- input$viz_mode
      
      if (is.null(mode) || mode != "dual") {
        return(NULL)
      }
      
      shiny::tagList(
        shiny::tags$hr(style = "margin: 15px 0;"),
        shiny::tags$span("Raster 2 Colors", class = "ctrl-group-label"),
        shiny::div(
          class = "inline-row",
          shiny::div(
            class = "flex-1",
            shiny::selectInput(ns("palette_name2"), "Palette",
              choices  = c("viridis", "magma", "plasma", "inferno", "cividis",
                           "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
              selected = "plasma")
          ),
          shiny::div(
            style = "width:70px;",
            shiny::numericInput(ns("n_colors2"), "Classes",
              value = 7, min = 3, max = 15, step = 1)
          )
        ),
        shiny::sliderInput(ns("raster_opacity2"), "Opacity",
          min = 0, max = 1, value = 0.6, step = 0.05, ticks = FALSE),
        shiny::checkboxInput(ns("reverse_palette2"), "Reverse", FALSE)
      )
    })
    
    # Render dual display mode controls
    output$dual_display_ui <- shiny::renderUI({
      mode <- input$viz_mode
      
      if (is.null(mode) || mode != "dual") {
        return(NULL)
      }
      
      shiny::tagList(
        shiny::tags$hr(class = "ctrl-divider"),
        shiny::tags$span("Dual Raster Display", class = "ctrl-group-label"),
        shiny::radioButtons(
          ns("dual_display_mode"),
          NULL,
          choices = c(
            "Overlay" = "overlay",
            "Intersection Only" = "intersection"
          ),
          selected = "overlay",
          inline = FALSE
        ),
        shiny::tags$div(
          style = "background-color: #e7f3ff; padding: 8px; border-radius: 4px; margin-top: 8px;",
          shiny::tags$small(shiny::icon("info-circle"), " Use controls above to choose display mode.")
        )
      )
    })
    
    # ── Downsample Helper ──────────────────────────────────────────────────
    .vis_downsample <- function(r, max_dim = 1500) {
      dims <- dim(r)
      if (dims[1] > max_dim || dims[2] > max_dim) {
        fact <- ceiling(max(dims[1:2]) / max_dim)
        r    <- terra::aggregate(r, fact = fact, fun = "modal", na.rm = TRUE)
      }
      r
    }
    
    # ── Query Evaluation Helper ────────────────────────────────────────────
    .evaluate_query <- function(r1, r2, query_expr) {
      tryCatch({
        # Harmonize rasters to same extent/resolution
        if (!terra::compareGeom(r1, r2, stopOnError = FALSE)) {
          shiny::showNotification("Rasters have different geometries. Harmonizing...", type = "message")
          r2 <- terra::resample(r2, r1, method = "bilinear")
        }
        
        # Get values
        vals1 <- terra::values(r1)
        vals2 <- terra::values(r2)
        
        # Replace Raster1 and Raster2 with actual values in the expression
        # Parse the expression safely
        expr_clean <- gsub("Raster1", "vals1", query_expr, ignore.case = TRUE)
        expr_clean <- gsub("Raster2", "vals2", expr_clean, ignore.case = TRUE)
        
        # Evaluate the expression
        mask <- eval(parse(text = expr_clean))
        
        # Create result raster
        result <- r1
        terra::values(result) <- ifelse(mask, 1, 0)
        
        # Calculate statistics
        n_match <- sum(mask, na.rm = TRUE)
        n_total <- sum(!is.na(mask))
        pct_match <- round(100 * n_match / n_total, 2)
        
        list(
          raster = result,
          n_match = n_match,
          n_total = n_total,
          pct_match = pct_match,
          success = TRUE,
          error = NULL
        )
      }, error = function(e) {
        list(
          raster = NULL,
          success = FALSE,
          error = e$message
        )
      })
    }
    
    # ── Zoom Helper ────────────────────────────────────────────────────────
    zoom_to_raster <- function(r) {
      shiny::req(r)
      ext <- terra::ext(r)
      if (!terra::is.lonlat(r)) {
        # Project extent envelope to WGS84 for leaflet
        ext_poly <- terra::as.polygons(ext, crs = terra::crs(r))
        terra::values(ext_poly) <- NULL  # Clear NA attributes
        ext_wgs84 <- terra::project(ext_poly, "EPSG:4326")
        ext <- terra::ext(ext_wgs84)
      }
      
      leaflet::leafletProxy("analysis_map", session = session) |>
        leaflet::fitBounds(
          lng1 = as.numeric(ext$xmin), lat1 = as.numeric(ext$ymin),
          lng2 = as.numeric(ext$xmax), lat2 = as.numeric(ext$ymax)
        )
    }


    # ── Folder Scanning ────────────────────────────────────────────────────
    raster_choices <- shiny::reactive({
      folder <- global_folder()
      tif_files <- if (!is.null(folder) && dir.exists(folder)) {
        files <- list.files(folder, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
        if (isTRUE(input$only_seasonal)) {
          files <- files[grepl("_seasonal", files)]
        }
        files
      } else character(0)
      
      analysis_layers <- list()
      if (!is.null(an_crop_mask_rast())) analysis_layers["[Analysis] Crop Mask"] <- "__analysis_crop_mask__"
      if (!is.null(an_start_rast()))     analysis_layers["[Analysis] Season Start"] <- "__analysis_season_start__"
      if (!is.null(an_end_rast()))       analysis_layers["[Analysis] Season End"] <- "__analysis_season_end__"
      
      if (length(analysis_layers) > 0) {
        return(list("Local Files" = tif_files, "Analysis Layers" = unlist(analysis_layers)))
      }
      tif_files
    })

    shiny::observe({
      choices <- raster_choices()
      current <- input$raster_file
      current2 <- input$raster_file2
      shiny::updateSelectizeInput(session, "raster_file", choices = choices, selected = current, server = TRUE)
      shiny::updateSelectizeInput(session, "raster_file2", choices = choices, selected = current2, server = TRUE)
    })

    shiny::observeEvent(input$scan_rasters, {
      shiny::showNotification("Raster list updated from folder and analysis layers.", type = "message")
    })

    # ── Load Raster 1 ──────────────────────────────────────────────────────
    shiny::observeEvent(input$raster_file, {
      shiny::req(input$raster_file)
      
      r <- NULL
      if (input$raster_file == "__analysis_crop_mask__") {
        r <- an_crop_mask_rast()
      } else if (input$raster_file == "__analysis_season_start__") {
        r <- an_start_rast()
      } else if (input$raster_file == "__analysis_season_end__") {
        r <- an_end_rast()
      } else {
        full_path <- file.path(global_folder(), input$raster_file)
        if (!file.exists(full_path)) {
          shiny::showNotification("File not found.", type = "error")
          loaded_raster(NULL)
          return()
        }
        r <- tryCatch(terra::rast(full_path), error = function(e) NULL)
      }

      if (is.null(r)) {
        shiny::showNotification("Could not load selected raster.", type = "error")
        loaded_raster(NULL)
        return()
      }

      tryCatch({
        loaded_raster(r)
        n <- terra::nlyr(r)
        band_names <- names(r)
        if (is.null(band_names) || all(band_names == "")) band_names <- paste("Band", seq_len(n))
        shiny::updateSelectInput(
          session,
          "raster_band",
          choices = stats::setNames(seq_len(n), band_names),
          selected = 1
        )
        
        # Zoom to raster extent
        zoom_to_raster(r)
          
      }, error = function(e) {
        shiny::showNotification(paste("Error processing raster:", e$message), type = "error")
        loaded_raster(NULL)
      })
    })
    
    # ── Load Raster 2 ──────────────────────────────────────────────────────
    shiny::observeEvent(input$raster_file2, {
      shiny::req(input$raster_file2)
      shiny::req(input$viz_mode %in% c("dual", "query"))
      
      r <- NULL
      if (input$raster_file2 == "__analysis_crop_mask__") {
        r <- an_crop_mask_rast()
      } else if (input$raster_file2 == "__analysis_season_start__") {
        r <- an_start_rast()
      } else if (input$raster_file2 == "__analysis_season_end__") {
        r <- an_end_rast()
      } else {
        full_path <- file.path(global_folder(), input$raster_file2)
        if (!file.exists(full_path)) {
          shiny::showNotification("Raster 2 file not found.", type = "error")
          loaded_raster2(NULL)
          return()
        }
        r <- tryCatch(terra::rast(full_path), error = function(e) NULL)
      }

      if (is.null(r)) {
        shiny::showNotification("Could not load Raster 2.", type = "error")
        loaded_raster2(NULL)
        return()
      }

      tryCatch({
        loaded_raster2(r)
        n <- terra::nlyr(r)
        band_names <- names(r)
        if (is.null(band_names) || all(band_names == "")) band_names <- paste("Band", seq_len(n))
        shiny::updateSelectInput(
          session,
          "raster_band2",
          choices = stats::setNames(seq_len(n), band_names),
          selected = 1
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error processing Raster 2:", e$message), type = "error")
        loaded_raster2(NULL)
      })
    })

    selected_band <- shiny::reactive({
      r <- loaded_raster()
      shiny::req(r)
      band_idx <- as.integer(input$raster_band)
      shiny::req(band_idx)
      r_band <- r[[band_idx]]
      r_band <- terra::classify(r_band, cbind(-9999, NA))
      # Simple downsampling for display performance
      dims <- dim(r_band)
      if (max(dims) > 2000) {
        r_band <- terra::aggregate(r_band, fact = ceiling(max(dims)/2000), fun = "mean", na.rm = TRUE)
      }
      r_band
    })
    
    selected_band2 <- shiny::reactive({
      shiny::req(input$viz_mode %in% c("dual", "query"))
      r <- loaded_raster2()
      shiny::req(r)
      band_idx <- as.integer(input$raster_band2)
      shiny::req(band_idx)
      r_band <- r[[band_idx]]
      r_band <- terra::classify(r_band, cbind(-9999, NA))
      # Simple downsampling for display performance
      dims <- dim(r_band)
      if (max(dims) > 2000) {
        r_band <- terra::aggregate(r_band, fact = ceiling(max(dims)/2000), fun = "mean", na.rm = TRUE)
      }
      r_band
    })
    
    # ── Query Application ──────────────────────────────────────────────────
    shiny::observeEvent(input$apply_query, {
      shiny::req(input$viz_mode == "query")
      shiny::req(input$query_expression)
      
      r1 <- selected_band()
      r2 <- selected_band2()
      shiny::req(r1, r2)
      
      result <- .evaluate_query(r1, r2, input$query_expression)
      
      if (result$success) {
        query_result_raster(result)
        shiny::showNotification(
          sprintf("Query applied: %d pixels match (%.2f%%)", result$n_match, result$pct_match),
          type = "message"
        )
      } else {
        query_result_raster(NULL)
        shiny::showNotification(
          paste("Query error:", result$error),
          type = "error",
          duration = 10
        )
      }
    })
    
    # Clear query result when switching away from query mode
    shiny::observe({
      mode <- input$viz_mode
      if (!is.null(mode) && mode != "query") {
        query_result_raster(NULL)
      }
    })
    
    # ── Query Statistics Output ────────────────────────────────────────────
    output$query_stats <- shiny::renderUI({
      result <- query_result_raster()
      shiny::req(result)
      shiny::req(result$success)
      
      shiny::tags$div(
        style = "background-color: #e7f3ff; padding: 10px; border-radius: 5px;",
        shiny::tags$strong("Query Results:"),
        shiny::tags$br(),
        shiny::tags$small(sprintf("Matching pixels: %s", format(result$n_match, big.mark = ","))),
        shiny::tags$br(),
        shiny::tags$small(sprintf("Total pixels: %s", format(result$n_total, big.mark = ","))),
        shiny::tags$br(),
        shiny::tags$small(sprintf("Match percentage: %.2f%%", result$pct_match))
      )
    })

    raster_pal <- shiny::reactive({
      r_band <- selected_band()
      shiny::req(r_band)
      vals <- terra::values(r_band, na.rm = TRUE)
      shiny::req(length(vals) > 0)
      
      n <- input$n_colors
      colors <- if (input$palette_name %in% c("viridis", "magma", "plasma", "inferno", "cividis")) {
        viridisLite::viridis(n, option = input$palette_name)
      } else {
        RColorBrewer::brewer.pal(min(n, 8), input$palette_name) |> grDevices::colorRampPalette() |> (\(f) f(n))()
      }
      if (input$reverse_palette) colors <- rev(colors)
      
      if (input$color_method == "numeric") {
        leaflet::colorNumeric(colors, domain = range(vals, na.rm=TRUE), na.color = "transparent")
      } else {
        leaflet::colorBin(colors, domain = range(vals, na.rm=TRUE), bins = n, na.color = "transparent")
      }
    })
    
    raster_pal2 <- shiny::reactive({
      shiny::req(input$viz_mode == "dual")
      r_band <- selected_band2()
      shiny::req(r_band)
      vals <- terra::values(r_band, na.rm = TRUE)
      shiny::req(length(vals) > 0)
      
      n <- input$n_colors2
      colors <- if (input$palette_name2 %in% c("viridis", "magma", "plasma", "inferno", "cividis")) {
        viridisLite::viridis(n, option = input$palette_name2)
      } else {
        RColorBrewer::brewer.pal(min(n, 8), input$palette_name2) |> grDevices::colorRampPalette() |> (\(f) f(n))()
      }
      if (input$reverse_palette2) colors <- rev(colors)
      
      leaflet::colorNumeric(colors, domain = range(vals, na.rm=TRUE), na.color = "transparent")
    })

    # ── Map Rendering ──────────────────────────────────────────────────────
    output$analysis_map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles("Esri.WorldImagery") |>
        leaflet::setView(lng = 18, lat = 2, zoom = 3)
    })


    shiny::observeEvent(input$basemap_analysis, {
      leaflet::leafletProxy("analysis_map", session = session) |>
        leaflet::clearTiles() |>
        leaflet::addProviderTiles(input$basemap_analysis)
    })

    # Observers for Analysis Layers (Crop Mask, Season Start/End)
    # ... logic from original app.R ...
    shiny::observe({
      r     <- an_crop_mask_rast()
      show  <- isTRUE(input$show_crop_mask)
      proxy <- leaflet::leafletProxy("analysis_map", session = session)
      if (!show || is.null(r)) {
        proxy |> leaflet::clearGroup("lyr_crop_mask") |> leaflet::removeControl("leg_crop_mask")
        return()
      }
      opacity <- input$an_layer_opacity %||% 0.75
      
      # Ensure WGS84 for leaflet
      if (!is.na(terra::crs(r)) && !terra::is.lonlat(r)) {
        r <- terra::project(r, "EPSG:4326", method = "near")
      }
      
      r_ds   <- .vis_downsample(r)
      vals   <- sort(unique(na.omit(as.integer(terra::values(r_ds)))))
      cls_cols <- grDevices::hcl.colors(max(length(vals), 3), "Set2")[seq_along(vals)]
      params <- an_crop_params()
      cls_labels <- if (!is.null(params)) {
        vapply(vals, function(v) {
          idx <- which(params$class_value == v)
          if (length(idx)) params$crop_label[idx[1]] else paste("Class", v)
        }, character(1))
      } else paste("Class", vals)
      pal <- leaflet::colorFactor(cls_cols, domain = vals, na.color = "transparent")
      proxy |> leaflet::clearGroup("lyr_crop_mask") |> leaflet::removeControl("leg_crop_mask") |>
        leaflet::addRasterImage(raster::raster(r_ds), colors = pal, opacity = opacity, group = "lyr_crop_mask") |>
        leaflet::addLegend(position = "bottomleft", colors = cls_cols, labels = cls_labels, title = "Crop Mask", opacity = opacity, layerId = "leg_crop_mask")
      
      # Zoom if just toggled on
      zoom_to_raster(r)
    })


    shiny::observe({
      r <- an_start_rast()
      show <- isTRUE(input$show_season_start)
      proxy <- leaflet::leafletProxy("analysis_map", session = session)
      if (!show || is.null(r)) {
        proxy |> leaflet::clearGroup("lyr_season_start") |> leaflet::removeControl("leg_season_start")
        return()
      }

      opacity <- input$an_layer_opacity %||% 0.75
      
      if (!is.na(terra::crs(r)) && !terra::is.lonlat(r)) {
        r <- terra::project(r, "EPSG:4326")
      }
      
      r_ds <- r
      dims <- dim(r_ds)
      if (max(dims) > 1500) {
        r_ds <- terra::aggregate(r_ds, fact = ceiling(max(dims) / 1500), fun = "mean", na.rm = TRUE)
      }
      vals <- terra::values(r_ds, na.rm = TRUE)
      pal <- leaflet::colorNumeric(viridisLite::magma(7), domain = range(vals, na.rm = TRUE), na.color = "transparent")

      proxy |> leaflet::clearGroup("lyr_season_start") |> leaflet::removeControl("leg_season_start") |>
        leaflet::addRasterImage(raster::raster(r_ds), colors = pal, opacity = opacity, group = "lyr_season_start") |>
        leaflet::addLegend(position = "bottomleft", pal = pal, values = vals, title = "Season Start", opacity = opacity, layerId = "leg_season_start")

      zoom_to_raster(r)
    })


    shiny::observe({
      r <- an_end_rast()
      show <- isTRUE(input$show_season_end)
      proxy <- leaflet::leafletProxy("analysis_map", session = session)
      if (!show || is.null(r)) {
        proxy |> leaflet::clearGroup("lyr_season_end") |> leaflet::removeControl("leg_season_end")
        return()
      }

      opacity <- input$an_layer_opacity %||% 0.75
      
      if (!is.na(terra::crs(r)) && !terra::is.lonlat(r)) {
        r <- terra::project(r, "EPSG:4326")
      }
      
      r_ds <- r
      dims <- dim(r_ds)
      if (max(dims) > 1500) {
        r_ds <- terra::aggregate(r_ds, fact = ceiling(max(dims) / 1500), fun = "mean", na.rm = TRUE)
      }
      vals <- terra::values(r_ds, na.rm = TRUE)
      pal <- leaflet::colorNumeric(viridisLite::inferno(7), domain = range(vals, na.rm = TRUE), na.color = "transparent")

      proxy |> leaflet::clearGroup("lyr_season_end") |> leaflet::removeControl("leg_season_end") |>
        leaflet::addRasterImage(raster::raster(r_ds), colors = pal, opacity = opacity, group = "lyr_season_end") |>
        leaflet::addLegend(position = "bottomleft", pal = pal, values = vals, title = "Season End", opacity = opacity, layerId = "leg_season_end")

      zoom_to_raster(r)
    })


    # Raster Overlay observer - Handles all three modes
    shiny::observe({
      mode <- input$viz_mode
      shiny::req(mode)
      
      proxy <- leaflet::leafletProxy("analysis_map", session = session)
      
      # Clear ALL existing layers first - more aggressive clearing
      proxy <- proxy |> 
        leaflet::clearImages() |> 
        leaflet::clearGroup("raster") |>
        leaflet::clearGroup("raster1") |>
        leaflet::clearGroup("raster2") |>
        leaflet::clearGroup("raster_intersection") |>
        leaflet::clearGroup("raster_query") |>
        leaflet::removeControl("leg_raster") |>
        leaflet::removeControl("leg_raster2") |>
        leaflet::removeControl("leg_query") |>
        leaflet::clearGroup("aoi_overlay")
      
      # ── Single Raster Mode ──────────────────────────────────────────
      if (mode == "single") {
        r_band <- selected_band()
        shiny::req(r_band)
        pal <- raster_pal()
        shiny::req(pal)
        vals <- terra::values(r_band, na.rm = TRUE)
        
        proxy <- proxy |>
          leaflet::addRasterImage(
            raster::raster(r_band), 
            colors = pal, 
            opacity = input$raster_opacity, 
            group = "raster"
          ) |>
          leaflet::addLegend(
            position = "bottomright", 
            pal = pal, 
            values = vals, 
            title = names(r_band), 
            opacity = input$raster_opacity, 
            layerId = "leg_raster"
          )
      }
      
      # ── Dual Raster Mode ────────────────────────────────────────────
      else if (mode == "dual") {
        r_band1 <- selected_band()
        r_band2 <- selected_band2()
        shiny::req(r_band1, r_band2)
        
        pal1 <- raster_pal()
        pal2 <- raster_pal2()
        shiny::req(pal1, pal2)
        
        vals1 <- terra::values(r_band1, na.rm = TRUE)
        vals2 <- terra::values(r_band2, na.rm = TRUE)
        
        display_mode <- input$dual_display_mode
        if (is.null(display_mode) || length(display_mode) == 0) {
          display_mode <- "overlay"  # Default when UI hasn't loaded yet
        }
        
        raster_opacity2_val <- input$raster_opacity2
        if (is.null(raster_opacity2_val) || length(raster_opacity2_val) == 0) {
          raster_opacity2_val <- 0.6  # Default opacity for raster 2
        }
        
        if (display_mode == "intersection") {
          # Create intersection mask (only show where both have values)
          if (!terra::compareGeom(r_band1, r_band2, stopOnError = FALSE)) {
            r_band2 <- terra::resample(r_band2, r_band1, method = "bilinear")
          }
          
          mask1 <- !is.na(terra::values(r_band1))
          mask2 <- !is.na(terra::values(r_band2))
          intersection_mask <- mask1 & mask2
          
          r_intersection <- r_band1
          vals_int <- terra::values(r_intersection)
          vals_int[!intersection_mask] <- NA
          terra::values(r_intersection) <- vals_int
          
          proxy <- proxy |>
            leaflet::addRasterImage(
              raster::raster(r_intersection), 
              colors = pal1, 
              opacity = input$raster_opacity, 
              group = "raster_intersection"
            ) |>
            leaflet::addLegend(
              position = "bottomright", 
              pal = pal1, 
              values = vals_int[!is.na(vals_int)], 
              title = paste("Intersection:", names(r_band1)), 
              opacity = input$raster_opacity, 
              layerId = "leg_raster"
            )
        } else {
          # Overlay mode - show both rasters
          proxy <- proxy |>
            leaflet::addRasterImage(
              raster::raster(r_band1), 
              colors = pal1, 
              opacity = input$raster_opacity, 
              group = "raster1"
            ) |>
            leaflet::addRasterImage(
              raster::raster(r_band2), 
              colors = pal2, 
              opacity = raster_opacity2_val, 
              group = "raster2"
            ) |>
            leaflet::addLegend(
              position = "bottomright", 
              pal = pal1, 
              values = vals1, 
              title = paste("R1:", names(r_band1)), 
              opacity = input$raster_opacity, 
              layerId = "leg_raster"
            ) |>
            leaflet::addLegend(
              position = "bottomleft", 
              pal = pal2, 
              values = vals2, 
              title = paste("R2:", names(r_band2)), 
              opacity = raster_opacity2_val, 
              layerId = "leg_raster2"
            )
        }
      }
      
      # ── Query Mode ──────────────────────────────────────────────────
      else if (mode == "query") {
        result <- query_result_raster()
        shiny::req(result)
        shiny::req(result$success)
        
        r_query <- result$raster
        shiny::req(r_query)
        
        # Create categorical palette for match/no-match
        match_col <- input$match_color
        nomatch_col <- input$nomatch_color
        query_opacity <- input$query_opacity
        
        # Provide defaults if UI hasn't loaded yet
        if (is.null(match_col) || length(match_col) == 0) match_col <- "red"
        if (is.null(nomatch_col) || length(nomatch_col) == 0) nomatch_col <- "gray"
        if (is.null(query_opacity) || length(query_opacity) == 0) query_opacity <- 0.7
        
        pal_query <- leaflet::colorFactor(
          palette = c(nomatch_col, match_col),
          domain = c(0, 1),
          na.color = "transparent"
        )
        
        proxy <- proxy |>
          leaflet::addRasterImage(
            raster::raster(r_query), 
            colors = pal_query, 
            opacity = query_opacity, 
            group = "raster_query"
          ) |>
          leaflet::addLegend(
            position = "bottomright",
            colors = c(match_col, nomatch_col),
            labels = c("Match", "No Match"),
            title = "Query Result",
            opacity = input$query_opacity,
            layerId = "leg_query"
          )
      }
      
      # Add AOI overlay if requested
      if (isTRUE(input$overlay_aoi)) {
        reg <- aoi_region()
        if (!is.null(reg)) {
          if (is.numeric(reg)) {
            proxy <- proxy |> 
              leaflet::addRectangles(
                lng1 = reg[1], lat1 = reg[2], 
                lng2 = reg[3], lat2 = reg[4], 
                color = "yellow", fill = FALSE, weight = 2, 
                group = "aoi_overlay"
              )
          } else if (is.character(reg) && file.exists(reg)) {
            proxy <- proxy |> 
              leaflet::addPolygons(
                data = sf::st_transform(sf::st_read(reg, quiet=TRUE), 4326), 
                color = "yellow", fill = FALSE, weight = 2, 
                group = "aoi_overlay"
              )
          }
        }
      }
    })


    # Raster info table
    # ── Palette colour swatch ──────────────────────────────────────────────
    output$palette_swatch <- shiny::renderUI({
      pal_name <- input$palette_name
      shiny::req(pal_name)
      n_show <- 12L
      cols <- if (pal_name %in% c("viridis", "magma", "plasma", "inferno", "cividis")) {
        viridisLite::viridis(n_show, option = pal_name)
      } else {
        tryCatch(
          grDevices::colorRampPalette(
            RColorBrewer::brewer.pal(min(8L, max(3L, n_show)), pal_name)
          )(n_show),
          error = function(e) viridisLite::viridis(n_show)
        )
      }
      if (isTRUE(input$reverse_palette)) cols <- rev(cols)
      shiny::tags$div(
        class = "palette-swatch",
        lapply(cols, function(col) shiny::tags$span(style = paste0("background:", col, ";")))
      )
    })

    # ── Raster stat boxes (replaces plain renderTable) ─────────────────────
    output$raster_stat_boxes <- shiny::renderUI({
      mode <- input$viz_mode

      make_stat <- function(label, value, icon_name, icon_color = "#6c757d") {
        shiny::div(
          class = "raster-stat-box",
          shiny::tags$div(
            class = "rsb-icon",
            shiny::icon(icon_name, style = paste0("color:", icon_color, ";"))
          ),
          shiny::tags$div(
            shiny::tags$div(class = "rsb-label", label),
            shiny::tags$div(class = "rsb-value", as.character(value))
          )
        )
      }

      no_data_msg <- function(msg) {
        shiny::helpText(
          shiny::icon("circle-info"), msg,
          style = "font-size:0.8rem; color:#6c757d; padding:2px 0;"
        )
      }

      if (is.null(mode) || mode == "single") {
        r <- loaded_raster()
        if (is.null(r)) return(no_data_msg(" Load a raster file to see statistics."))
        band_idx <- suppressWarnings(as.integer(input$raster_band))
        if (is.na(band_idx) || band_idx < 1L || band_idx > terra::nlyr(r)) return(NULL)
        r_band <- r[[band_idx]]
        vals   <- terra::values(r_band, na.rm = TRUE)
        if (length(vals) == 0L) return(no_data_msg(" No valid pixel values."))
        res_txt <- paste(round(terra::res(r_band), 6L), collapse = " × ")
        shiny::div(
          class = "raster-stat-row",
          make_stat("Min",     round(min(vals,  na.rm = TRUE), 4L), "arrow-down",      "#1e8449"),
          make_stat("Max",     round(max(vals,  na.rm = TRUE), 4L), "arrow-up",        "#c0392b"),
          make_stat("Mean",    round(mean(vals, na.rm = TRUE), 4L), "chart-line",      "#2980b9"),
          make_stat("Res (°)", res_txt,                              "magnifying-glass","#8e44ad"),
          make_stat("Bands",   terra::nlyr(r),                       "layer-group",     "#d35400"),
          make_stat("Active",  names(r)[band_idx],                   "tag",             "#7f8c8d")
        )

      } else if (mode == "dual") {
        r1 <- loaded_raster(); r2 <- loaded_raster2()
        if (is.null(r1) || is.null(r2)) return(no_data_msg(" Load both rasters."))
        b1 <- suppressWarnings(as.integer(input$raster_band))
        b2 <- suppressWarnings(as.integer(input$raster_band2))
        if (is.na(b1) || is.na(b2)) return(NULL)
        v1 <- terra::values(r1[[min(b1, terra::nlyr(r1))]], na.rm = TRUE)
        v2 <- terra::values(r2[[min(b2, terra::nlyr(r2))]], na.rm = TRUE)
        shiny::div(
          class = "raster-stat-row",
          make_stat("R1 Min",  round(min(v1,  na.rm = TRUE), 3L), "arrow-down", "#1e8449"),
          make_stat("R1 Max",  round(max(v1,  na.rm = TRUE), 3L), "arrow-up",   "#c0392b"),
          make_stat("R1 Mean", round(mean(v1, na.rm = TRUE), 3L), "chart-line", "#2980b9"),
          make_stat("R2 Min",  round(min(v2,  na.rm = TRUE), 3L), "arrow-down", "#27ae60"),
          make_stat("R2 Max",  round(max(v2,  na.rm = TRUE), 3L), "arrow-up",   "#e74c3c"),
          make_stat("R2 Mean", round(mean(v2, na.rm = TRUE), 3L), "chart-line", "#3498db")
        )

      } else if (mode == "query") {
        result <- query_result_raster()
        if (is.null(result) || !isTRUE(result$success))
          return(no_data_msg(" Apply a query to see match statistics."))
        shiny::div(
          class = "raster-stat-row",
          make_stat("Match",    format(result$n_match,                  big.mark = ","), "check",       "#1e8449"),
          make_stat("No Match", format(result$n_total - result$n_match, big.mark = ","), "xmark",       "#c0392b"),
          make_stat("Total",    format(result$n_total,                  big.mark = ","), "table-cells", "#2980b9"),
          make_stat("Match %",  paste0(round(result$pct_match, 2L), "%"),               "percent",     "#8e44ad")
        )
      }
    })

    output$raster_info <- shiny::renderTable({
      mode <- input$viz_mode
      
      if (mode == "single") {
        r <- loaded_raster()
        shiny::req(r)
        band_idx <- as.integer(input$raster_band)
        shiny::req(band_idx)
        r_band <- r[[band_idx]]
        vals <- terra::values(r_band, na.rm = TRUE)
        data.frame(
          Property = c("Resolution", "Bands", "Selected Band", "Min", "Max", "Mean"),
          Value    = c(paste(round(terra::res(r_band), 6), collapse=", "), 
                      terra::nlyr(r), names(r)[band_idx], 
                      round(min(vals, na.rm=T), 4), 
                      round(max(vals, na.rm=T), 4), 
                      round(mean(vals, na.rm=T), 4))
        )
      } else if (mode == "dual") {
        r1 <- loaded_raster()
        r2 <- loaded_raster2()
        shiny::req(r1, r2)
        
        band_idx1 <- as.integer(input$raster_band)
        band_idx2 <- as.integer(input$raster_band2)
        shiny::req(band_idx1, band_idx2)
        
        r_band1 <- r1[[band_idx1]]
        r_band2 <- r2[[band_idx2]]
        vals1 <- terra::values(r_band1, na.rm = TRUE)
        vals2 <- terra::values(r_band2, na.rm = TRUE)
        
        data.frame(
          Property = c("Raster", "Resolution", "Selected Band", "Min", "Max", "Mean"),
          Raster1  = c("1", 
                      paste(round(terra::res(r_band1), 6), collapse=", "), 
                      names(r1)[band_idx1],
                      round(min(vals1, na.rm=T), 4), 
                      round(max(vals1, na.rm=T), 4), 
                      round(mean(vals1, na.rm=T), 4)),
          Raster2  = c("2",
                      paste(round(terra::res(r_band2), 6), collapse=", "), 
                      names(r2)[band_idx2],
                      round(min(vals2, na.rm=T), 4), 
                      round(max(vals2, na.rm=T), 4), 
                      round(mean(vals2, na.rm=T), 4))
        )
      } else if (mode == "query") {
        result <- query_result_raster()
        if (!is.null(result) && result$success) {
          data.frame(
            Property = c("Query Expression", "Matching Pixels", "Total Pixels", "Match Percentage"),
            Value    = c(input$query_expression,
                        format(result$n_match, big.mark = ","),
                        format(result$n_total, big.mark = ","),
                        paste0(result$pct_match, "%"))
          )
        } else {
          data.frame(
            Property = "Status",
            Value = "No query applied yet"
          )
        }
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)
  })
}
