# mod_dual_map.R
# Synchronized side-by-side dual-map comparison view.
#
# Two independent leaflet maps, each with its own raster/basemap selector,
# kept in view-sync (pan/zoom) via leaflet.extras2::addLeafletsync(). This is
# a distinct feature from the "Dual Compare" overlay mode in
# mod_visualisation.R, which draws two rasters on ONE map; here the two
# rasters are shown on two separate, independently full-screenable map
# panes whose viewport always matches.

# ── Capability guard ─────────────────────────────────────────────────────────
.wapor_dual_map_available <- function() {
  requireNamespace("leaflet.extras2", quietly = TRUE) &&
    exists("addLeafletsync", where = asNamespace("leaflet.extras2"), inherits = FALSE)
}

mod_dual_map_ui <- function(id) {
  ns <- shiny::NS(id)

  if (!.wapor_dual_map_available()) {
    return(
      shiny::div(
        class = "p-4",
        shiny::tags$div(
          class = "alert alert-warning",
          shiny::icon("triangle-exclamation"),
          " Dual Compare (synchronized maps) requires the ",
          shiny::tags$code("leaflet.extras2"),
          " package. Install it with ",
          shiny::tags$code('install.packages("leaflet.extras2")'),
          " and restart the dashboard."
        )
      )
    )
  }

  bslib::layout_sidebar(
    fillable = TRUE,
    sidebar = bslib::sidebar(
      width = 300,
      open  = TRUE,
      title = "Dual Compare (Synced)",

      shiny::div(
        class = "sidebar-scroll-area",

        shiny::tags$span("Sync", class = "ctrl-group-label"),
        shiny::checkboxInput(ns("sync_maps"), "Lock pan & zoom between maps", TRUE),
        shiny::helpText("Both maps share one viewport when locked; unlock to compare independently."),

        shiny::tags$hr(class = "ctrl-divider"),

        shiny::tags$span("Left Map", class = "ctrl-group-label req-label"),
        shiny::div(
          class = "inline-row mb-1",
          shiny::div(class = "flex-1", shiny::selectizeInput(ns("raster_left"), "Raster", choices = NULL)),
          shiny::actionButton(
            ns("scan_rasters"), NULL,
            icon  = shiny::icon("rotate"),
            title = "Rescan project folder for raster files",
            class = "btn-outline-secondary btn-sm mt-4",
            style = "padding:0.37rem 0.6rem;"
          )
        ),
        shiny::selectInput(ns("band_left"), "Band / Layer", choices = NULL),
        shiny::selectInput(ns("palette_left"), "Palette",
          choices  = c("viridis", "magma", "plasma", "inferno", "cividis",
                       "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
          selected = "viridis"),

        shiny::tags$hr(class = "ctrl-divider"),

        shiny::tags$span("Right Map", class = "ctrl-group-label req-label"),
        shiny::selectizeInput(ns("raster_right"), "Raster", choices = NULL),
        shiny::selectInput(ns("band_right"), "Band / Layer", choices = NULL),
        shiny::selectInput(ns("palette_right"), "Palette",
          choices  = c("viridis", "magma", "plasma", "inferno", "cividis",
                       "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
          selected = "plasma"),

        shiny::tags$hr(class = "ctrl-divider"),
        shiny::sliderInput(ns("raster_opacity"), "Raster Opacity",
          min = 0, max = 1, value = 0.8, step = 0.05, ticks = FALSE),
        shiny::selectInput(ns("basemap"), "Basemap",
          choices = c(
            "Esri Satellite"  = "Esri.WorldImagery",
            "OpenStreetMap"   = "OpenStreetMap",
            "Carto Light"     = "CartoDB.Positron",
            "Carto Dark"      = "CartoDB.DarkMatter"
          ),
          selected = "Esri.WorldImagery")
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Left"),
        bslib::card_body(
          class = "p-0 main-map-output",
          leaflet::leafletOutput(ns("map_left"), height = "100%", width = "100%")
        )
      ),
      bslib::card(
        full_screen = TRUE,
        bslib::card_header("Right"),
        bslib::card_body(
          class = "p-0 main-map-output",
          leaflet::leafletOutput(ns("map_right"), height = "100%", width = "100%")
        )
      )
    )
  )
}

mod_dual_map_server <- function(id, global_folder, aoi_region = shiny::reactive(NULL)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    if (!.wapor_dual_map_available()) return(invisible(NULL))

    loaded_left  <- shiny::reactiveVal(NULL)
    loaded_right <- shiny::reactiveVal(NULL)

    # ── Folder scanning (mirrors mod_visualisation.R's raster_choices) ──────
    raster_choices <- shiny::reactive({
      folder <- global_folder()
      if (!is.null(folder) && dir.exists(folder)) {
        list.files(folder, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
      } else {
        character(0)
      }
    })

    shiny::observe({
      choices <- raster_choices()
      shiny::updateSelectizeInput(session, "raster_left",  choices = choices, selected = input$raster_left,  server = TRUE)
      shiny::updateSelectizeInput(session, "raster_right", choices = choices, selected = input$raster_right, server = TRUE)
    })

    shiny::observeEvent(input$scan_rasters, {
      shiny::showNotification("Raster list updated from project folder.", type = "message")
    })

    .load_side <- function(file_input_val, band_input_id, store) {
      shiny::req(file_input_val)
      full_path <- file.path(global_folder(), file_input_val)
      if (!file.exists(full_path)) {
        shiny::showNotification(sprintf("File not found: %s", file_input_val), type = "error")
        store(NULL)
        return(invisible(NULL))
      }
      r <- tryCatch(terra::rast(full_path), error = function(e) NULL)
      if (is.null(r)) {
        shiny::showNotification("Could not load selected raster.", type = "error")
        store(NULL)
        return(invisible(NULL))
      }
      store(r)
      n <- terra::nlyr(r)
      band_names <- names(r)
      if (is.null(band_names) || all(band_names == "")) band_names <- paste("Band", seq_len(n))
      shiny::updateSelectInput(session, band_input_id, choices = stats::setNames(seq_len(n), band_names), selected = 1)
      invisible(r)
    }

    shiny::observeEvent(input$raster_left,  .load_side(input$raster_left,  "band_left",  loaded_left))
    shiny::observeEvent(input$raster_right, .load_side(input$raster_right, "band_right", loaded_right))

    .palette_fn <- function(vals, pal_name) {
      pal_colors <- grDevices::colorRampPalette(
        switch(pal_name,
          "magma"    = viridisLite::magma(11),
          "plasma"   = viridisLite::plasma(11),
          "inferno"  = viridisLite::inferno(11),
          "cividis"  = viridisLite::cividis(11),
          "RdYlGn"   = RColorBrewer::brewer.pal(11, "RdYlGn"),
          "RdYlBu"   = RColorBrewer::brewer.pal(11, "RdYlBu"),
          "Spectral" = RColorBrewer::brewer.pal(11, "Spectral"),
          "BrBG"     = RColorBrewer::brewer.pal(11, "BrBG"),
          viridisLite::viridis(11)
        )
      )(255)
      leaflet::colorNumeric(pal_colors, domain = range(vals, na.rm = TRUE), na.color = "transparent")
    }

    output$map_left <- leaflet::renderLeaflet({
      leaflet::leaflet(options = leaflet::leafletOptions(zoomControl = TRUE)) |>
        leaflet::addProviderTiles(input$basemap %||% "Esri.WorldImagery") |>
        leaflet::setView(lng = 0, lat = 20, zoom = 2)
    })

    output$map_right <- leaflet::renderLeaflet({
      leaflet::leaflet(options = leaflet::leafletOptions(zoomControl = TRUE)) |>
        leaflet::addProviderTiles(input$basemap %||% "Esri.WorldImagery") |>
        leaflet::setView(lng = 0, lat = 20, zoom = 2)
    })

    # ── Sync: apply once both maps have rendered and whenever the toggle
    # changes. addLeafletsync must run after both maps are initialized, so
    # this is deferred to session flush (after all outputs render) via
    # shiny::onFlushed(once = FALSE) is avoided in favor of a simple
    # invalidateLater-free observer keyed on sync_maps/basemap.
    shiny::observe({
      if (isTRUE(input$sync_maps)) {
        leaflet::leafletProxy("map_left", session)  |> leaflet.extras2::addLeafletsync(ids = c(ns("map_left"), ns("map_right")))
        leaflet::leafletProxy("map_right", session) |> leaflet.extras2::addLeafletsync(ids = c(ns("map_left"), ns("map_right")))
      } else {
        leaflet::leafletProxy("map_left", session)  |> leaflet.extras2::unsync()
        leaflet::leafletProxy("map_right", session) |> leaflet.extras2::unsync()
      }
    })

    .render_side <- function(map_id, r, band_input_id, pal_input_id) {
      proxy <- leaflet::leafletProxy(map_id, session)
      proxy |> leaflet::clearImages() |> leaflet::clearControls()
      if (is.null(r)) return(invisible(NULL))
      band <- suppressWarnings(as.integer(input[[band_input_id]]))
      if (is.na(band) || band < 1 || band > terra::nlyr(r)) band <- 1
      r_band <- r[[band]]
      dims <- dim(r_band)
      if (dims[1] > 1500 || dims[2] > 1500) {
        fact <- ceiling(max(dims[1:2]) / 1500)
        r_band <- terra::aggregate(r_band, fact = fact, fun = "mean", na.rm = TRUE)
      }
      vals <- terra::values(r_band, na.rm = TRUE)
      if (length(vals) == 0 || all(is.na(vals))) return(invisible(NULL))
      pal_fn <- .palette_fn(vals, input[[pal_input_id]] %||% "viridis")
      proxy |>
        leaflet::addRasterImage(r_band, colors = pal_fn, opacity = input$raster_opacity %||% 0.8, project = TRUE) |>
        leaflet::addLegend(pal = pal_fn, values = vals, position = "bottomright")
      e <- terra::ext(r_band)
      proxy |> leaflet::fitBounds(as.numeric(e$xmin), as.numeric(e$ymin), as.numeric(e$xmax), as.numeric(e$ymax))
    }

    shiny::observe({
      .render_side("map_left", loaded_left(), "band_left", "palette_left")
    })
    shiny::observe({
      .render_side("map_right", loaded_right(), "band_right", "palette_right")
    })

    shiny::observeEvent(input$basemap, {
      leaflet::leafletProxy("map_left", session)  |> leaflet::clearTiles() |> leaflet::addProviderTiles(input$basemap)
      leaflet::leafletProxy("map_right", session) |> leaflet::clearTiles() |> leaflet::addProviderTiles(input$basemap)
    })

    invisible(NULL)
  })
}
