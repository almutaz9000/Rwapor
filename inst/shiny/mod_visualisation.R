# mod_visualisation.R
# Raster Visualisation and Time-Series Explorer Module

mod_visualisation_ui <- function(id) {
  ns <- shiny::NS(id)
  
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 260,
      open  = TRUE,
      title = "Raster Visualization",
      
      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id = ns("analysis_accordion"),
          open = c("Raster Selection", "Color Palette"),
          
          # ── Raster Selection ──
          bslib::accordion_panel(
            "Raster Selection",
            icon = shiny::icon("file-image"),
            shiny::actionButton(ns("scan_rasters"), "Scan Folder",
              icon  = shiny::icon("magnifying-glass"),
              class = "btn-outline-primary w-100 mb-2 btn-sm"),
            shiny::selectInput(ns("raster_file"), "Select Raster", choices = NULL),
            shiny::selectInput(ns("raster_band"), "Band / Layer",  choices = NULL)
          ),
          
          # ── Color Palette ──
          bslib::accordion_panel(
            "Color Palette",
            icon = shiny::icon("palette"),
            shiny::selectInput(ns("palette_name"), "Palette",
              choices = as.list(c(
                "viridis", "magma", "plasma", "inferno", "cividis",
                "RdYlGn", "RdYlBu", "Spectral", "BrBG")),
              selected = "viridis"),
            shiny::sliderInput(ns("n_colors"), "Classes",
              min = 3, max = 15, value = 7, step = 1),
            shiny::sliderInput(ns("raster_opacity"), "Opacity",
              min = 0, max = 1, value = 0.8, step = 0.05),
            shiny::checkboxInput(ns("reverse_palette"), "Reverse Palette", FALSE),
            shiny::radioButtons(ns("color_method"), "Method",
              choices  = as.list(c("Continuous" = "numeric", "Binned" = "bin")),
              selected = "numeric", inline = TRUE)
          ),
          
          # ── Overlay Options ──
          bslib::accordion_panel(
            "Overlay Options",
            icon = shiny::icon("layer-group"),
            shiny::checkboxInput(ns("overlay_aoi"), "Show AOI Boundary", TRUE),
            shiny::selectInput(ns("basemap_analysis"), "Basemap",
              choices = c(
                "Esri Imagery" = "Esri.WorldImagery",
                "OpenStreetMap" = "OpenStreetMap",
                "Carto Positron" = "CartoDB.Positron",
                "Carto Dark" = "CartoDB.DarkMatter"
              ),
              selected = "CartoDB.Positron"),
            shiny::hr(style = "margin:4px 0;"),
            shiny::tags$p(shiny::tags$strong("Analysis Layers"), style = "font-size:0.8rem; margin-bottom:2px;"),
            shiny::checkboxInput(ns("show_crop_mask"),    "Crop Mask",  FALSE),
            shiny::checkboxInput(ns("show_season_start"), "Season Start", FALSE),
            shiny::checkboxInput(ns("show_season_end"),   "Season End",   FALSE),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] || input['%s'] || input['%s']", 
                                  ns("show_crop_mask"), ns("show_season_start"), ns("show_season_end")),
              shiny::sliderInput(ns("an_layer_opacity"), "Layer Opacity",
                min = 0, max = 1, value = 0.75, step = 0.05)
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
        class = "raster-footer",
        shiny::div(id = ns("raster_info_table"),
          shiny::tableOutput(ns("raster_info")))
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
    
    # ── Downsample Helper ──────────────────────────────────────────────────
    .vis_downsample <- function(r, max_dim = 1500) {
      dims <- dim(r)
      if (dims[1] > max_dim || dims[2] > max_dim) {
        fact <- ceiling(max(dims[1:2]) / max_dim)
        r    <- terra::aggregate(r, fact = fact, fun = "modal", na.rm = TRUE)
      }
      r
    }

    # ── Folder Scanning ────────────────────────────────────────────────────
    shiny::observeEvent(input$scan_rasters, {
      folder <- global_folder()
      shiny::req(folder)
      if (!dir.exists(folder)) {
        shiny::showNotification("Folder does not exist.", type = "error")
        return()
      }
      tif_files <- list.files(folder, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
      if (length(tif_files) == 0) {
        shiny::showNotification("No .tif files found.", type = "warning")
        shiny::updateSelectInput(session, "raster_file", choices = character(0))
        return()
      }
      shiny::updateSelectInput(session, "raster_file", choices = tif_files)
      shiny::showNotification(sprintf("Found %d raster file(s).", length(tif_files)), type = "message")
    })

    # ── Load Raster ────────────────────────────────────────────────────────
    shiny::observeEvent(input$raster_file, {
      shiny::req(input$raster_file)
      full_path <- file.path(global_folder(), input$raster_file)
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
        if (is.null(band_names) || all(band_names == "")) band_names <- paste("Band", seq_len(n))
        shiny::updateSelectInput(
          session,
          "raster_band",
          choices = stats::setNames(seq_len(n), band_names),
          selected = 1
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading raster:", e$message), type = "error")
        loaded_raster(NULL)
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

    # ── Map Rendering ──────────────────────────────────────────────────────
    output$analysis_map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles("CartoDB.Positron") |>
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
    })

    # Raster Overlay observer
    shiny::observe({
      r_band <- selected_band()
      shiny::req(r_band)
      pal <- raster_pal()
      shiny::req(pal)
      vals <- terra::values(r_band, na.rm = TRUE)
      ext <- terra::ext(r_band)
      proxy <- leaflet::leafletProxy("analysis_map", session = session) |>
        leaflet::clearImages() |> leaflet::removeControl("leg_raster") |> leaflet::clearGroup("aoi_overlay") |>
        leaflet::addRasterImage(raster::raster(r_band), colors = pal, opacity = input$raster_opacity, group = "raster") |>
        leaflet::addLegend(position = "bottomright", pal = pal, values = vals, title = names(r_band), opacity = input$raster_opacity, layerId = "leg_raster") |>
        leaflet::fitBounds(lng1 = ext$xmin, lat1 = ext$ymin, lng2 = ext$xmax, lat2 = ext$ymax)

      if (isTRUE(input$overlay_aoi)) {
        reg <- aoi_region()
        if (!is.null(reg)) {
           if (is.numeric(reg)) proxy |> leaflet::addRectangles(lng1 = reg[1], lat1 = reg[2], lng2 = reg[3], lat2 = reg[4], color = "yellow", fill = FALSE, weight = 2, group = "aoi_overlay")
           else if (is.character(reg) && file.exists(reg)) proxy |> leaflet::addPolygons(data = sf::st_transform(sf::st_read(reg, quiet=TRUE), 4326), color = "yellow", fill = FALSE, weight = 2, group = "aoi_overlay")
        }
      }
    })

    # Raster info table
    output$raster_info <- shiny::renderTable({
      r <- loaded_raster()
      shiny::req(r)
      band_idx <- as.integer(input$raster_band)
      shiny::req(band_idx)
      r_band <- r[[band_idx]]
      vals <- terra::values(r_band, na.rm = TRUE)
      data.frame(
        Property = c("Resolution", "Bands", "Selected Band", "Min", "Max", "Mean"),
        Value    = c(paste(round(terra::res(r_band), 6), collapse=", "), terra::nlyr(r), names(r)[band_idx], 
                    round(min(vals, na.rm=T), 4), round(max(vals, na.rm=T), 4), round(mean(vals, na.rm=T), 4))
      )
    }, striped = TRUE, hover = TRUE, bordered = TRUE)
  })
}
