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

        shiny::div(
          class = "d-flex align-items-center justify-content-between mb-1",
          shiny::tags$span("Sync", class = "ctrl-group-label mb-0"),
          shiny::actionLink(ns("sync_guide_btn"), "Sync Guide", icon = shiny::icon("circle-question"), class = "small text-primary")
        ),
        shiny::checkboxInput(ns("sync_maps"), "Lock pan & zoom between maps", TRUE),
        shiny::helpText("Both maps share one viewport when locked; unlock to compare independently."),

        shiny::tags$hr(class = "ctrl-divider"),

        shiny::tags$span("Left Map", class = "ctrl-group-label req-label"),
        shiny::div(
          class = "inline-row mb-1",
          shiny::div(class = "flex-1", shiny::selectizeInput(
            ns("raster_left"), "Raster", choices = NULL,
            options = list(maxOptions = 100000L, placeholder = "Select a raster...")
          )),
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
        shiny::selectizeInput(
          ns("raster_right"), "Raster", choices = NULL,
          options = list(maxOptions = 100000L, placeholder = "Select a raster...")
        ),
        shiny::selectInput(ns("band_right"), "Band / Layer", choices = NULL),
        shiny::selectInput(ns("palette_right"), "Palette",
          choices  = c("viridis", "magma", "plasma", "inferno", "cividis",
                       "RdYlGn", "RdYlBu", "Spectral", "BrBG"),
          selected = "plasma"),

        shiny::tags$hr(class = "ctrl-divider"),
        shiny::uiOutput(ns("dual_compat_ui")),
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

mod_dual_map_server <- function(id, global_folder, aoi_region = shiny::reactive(NULL), an_folder = shiny::reactive(NULL)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    if (!.wapor_dual_map_available()) return(invisible(NULL))

    loaded_left  <- shiny::reactiveVal(NULL)
    loaded_right <- shiny::reactiveVal(NULL)
    scan_nonce <- shiny::reactiveVal(0L)

    # ── Folder scanning & Path resolution ───────────────────────────────────
    .resolve_path <- function(rel_path) {
      if (is.null(rel_path) || !nzchar(rel_path)) return(NULL)
      if (grepl("^\\[AN\\]\\s*", rel_path)) {
        clean_rel <- sub("^\\[AN\\]\\s*", "", rel_path)
        an_dir <- if (is.function(an_folder)) an_folder() else NULL
        if (!is.null(an_dir) && file.exists(file.path(an_dir, clean_rel))) {
          return(file.path(an_dir, clean_rel))
        }
      }
      dl_dir <- if (is.function(global_folder)) global_folder() else NULL
      if (!is.null(dl_dir) && file.exists(file.path(dl_dir, rel_path))) {
        return(file.path(dl_dir, rel_path))
      }
      an_dir <- if (is.function(an_folder)) an_folder() else NULL
      if (!is.null(an_dir) && file.exists(file.path(an_dir, rel_path))) {
        return(file.path(an_dir, rel_path))
      }
      NULL
    }

    raster_choices <- shiny::reactive({
      scan_nonce()
      folder <- if (is.function(global_folder)) global_folder() else NULL
      an_dir <- if (is.function(an_folder)) an_folder() else NULL
      res <- Rwapor:::wapor_visualisation_raster_choices(folder, an_folder = an_dir)
      if (length(res) == 0) return(character(0))
      res
    })

    shiny::observe({
      choices <- raster_choices()
      shiny::updateSelectizeInput(
        session, "raster_left", choices = choices,
        selected = shiny::isolate(input$raster_left), server = FALSE
      )
      shiny::updateSelectizeInput(
        session, "raster_right", choices = choices,
        selected = shiny::isolate(input$raster_right), server = FALSE
      )
    })

    shiny::observeEvent(input$scan_rasters, {
      scan_nonce(scan_nonce() + 1L)
      n <- length(unlist(raster_choices(), use.names = FALSE))
      shiny::showNotification(
        sprintf("Raster list updated (%d file(s) in the project folder).", n),
        type = "message"
      )
    })

    .load_side <- function(file_input_val, band_input_id, store) {
      shiny::req(file_input_val)
      full_path <- .resolve_path(file_input_val)
      if (is.null(full_path) || !file.exists(full_path)) {
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

    output$dual_compat_ui <- shiny::renderUI({
      rl <- loaded_left()
      rr <- loaded_right()
      if (is.null(rl) || is.null(rr)) return(NULL)
      report <- tryCatch(
        suppressWarnings(wapor_validate_compatibility(
          list(left = rl, right = rr),
          operation = "same_period",
          mode = "warn"
        )),
        error = function(e) NULL
      )
      if (is.null(report) || length(report$errors) == 0L) return(NULL)
      shiny::div(
        class = "alert alert-warning py-1 px-2 mb-2",
        style = "font-size: 0.78rem;",
        shiny::icon("triangle-exclamation", class = "me-1"),
        shiny::strong("Comparison note: "),
        paste(report$errors, collapse = " ")
      )
    })

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
        leaflet.extras2::addLeafletsyncDependency() |>
        leaflet::setView(lng = 0, lat = 20, zoom = 2)
    })

    output$map_right <- leaflet::renderLeaflet({
      leaflet::leaflet(options = leaflet::leafletOptions(zoomControl = TRUE)) |>
        leaflet::addProviderTiles(input$basemap %||% "Esri.WorldImagery") |>
        leaflet.extras2::addLeafletsyncDependency() |>
        leaflet::setView(lng = 0, lat = 20, zoom = 2)
    })

    # ── Pan/zoom lock: wait until both maps exist, then attach extras2 sync ──
    map_ids <- Rwapor:::wapor_dual_map_dom_ids(ns)

    .dual_sync_ids <- function() {
      unname(c(map_ids[["left"]], map_ids[["right"]]))
    }

    .attach_dual_sync <- function(no_initial_sync = FALSE) {
      ids <- .dual_sync_ids()
      leaflet::leafletProxy("map_left", session) |>
        leaflet.extras2::addLeafletsync(
          ids = ids,
          options = leaflet.extras2::leafletsyncOptions(
            noInitialSync = isTRUE(no_initial_sync),
            syncCursor = TRUE
          )
        )
    }

    .detach_dual_sync <- function() {
      ids <- .dual_sync_ids()
      leaflet::leafletProxy("map_left", session) |>
        leaflet.extras2::unsync(id = ids[[1]], unsyncids = ids[[2]])
      leaflet::leafletProxy("map_right", session) |>
        leaflet.extras2::unsync(id = ids[[2]], unsyncids = ids[[1]])
    }

    sync_attached <- shiny::reactiveVal(FALSE)

    # Initial lock: attach once when both maps exist and report zoom
    shiny::observe({
      if (isTRUE(sync_attached())) return()
      can_sync <- Rwapor:::wapor_dual_map_can_sync(
        input$sync_maps, input$map_left_zoom, input$map_right_zoom
      )
      if (isTRUE(can_sync)) {
        .attach_dual_sync(no_initial_sync = FALSE)
        sync_attached(TRUE)
      }
    })

    # Responding to user selecting/unselecting "Lock pan & zoom between maps"
    shiny::observeEvent(input$sync_maps, {
      maps_ready <- Rwapor:::wapor_dual_map_can_sync(
        TRUE, input$map_left_zoom, input$map_right_zoom
      )
      if (!isTRUE(maps_ready)) return()

      if (isTRUE(input$sync_maps)) {
        if (!isTRUE(sync_attached())) {
          ctr <- input$map_left_center
          z <- input$map_left_zoom
          if (is.list(ctr) && is.numeric(ctr$lng) && is.numeric(ctr$lat) && is.finite(as.numeric(z)[1L])) {
            leaflet::leafletProxy("map_right", session) |>
              leaflet::setView(lng = ctr$lng, lat = ctr$lat, zoom = z)
          }
          .attach_dual_sync(no_initial_sync = TRUE)
          sync_attached(TRUE)
        }
      } else {
        if (isTRUE(sync_attached())) {
          .detach_dual_sync()
          sync_attached(FALSE)
        }
      }
    }, ignoreInit = TRUE)

    # ── Sync Guide Modal ─────────────────────────────────────────────────────
    shiny::observeEvent(input$sync_guide_btn, {
      shiny::showModal(shiny::modalDialog(
        title = shiny::tagList(shiny::icon("columns"), " Dual Map View & Synchronization Guide"),
        size  = "l",
        easyClose = TRUE,
        footer = shiny::modalButton("Close"),
        shiny::tagList(
          shiny::tags$p(
            "The ", shiny::tags$strong("Side-by-Side (Synced)"), " comparison viewer allows you to inspect ",
            "two independent spatial rasters with linked camera movement."
          ),
          shiny::tags$h6(shiny::icon("lock"), " Lock Pan & Zoom"),
          shiny::tags$ul(
            shiny::tags$li(
              shiny::tags$strong("Locked (Default):"), " Panning or zooming on either the left or right map automatically adjusts the other map to the exact same geographic extent and zoom level in real-time."
            ),
            shiny::tags$li(
              shiny::tags$strong("Unlocked:"), " Uncheck the box to navigate each map independently — useful when comparing different irrigation schemes or zooming in on specific field parcels on one side while keeping a scheme-wide view on the other."
            ),
            shiny::tags$li(
              shiny::tags$strong("Re-Locking:"), " When you re-check the box, the right map immediately snaps to align with the left map's current center and zoom level, and camera movements re-lock."
            )
          ),
          shiny::tags$h6(shiny::icon("arrows-left-right-to-line"), " Common Comparative Use Cases"),
          shiny::tags$ul(
            shiny::tags$li(shiny::tags$strong("Year-over-Year Change:"), " Compare seasonal AETI in 2021 (Left) against 2022 (Right) to pinpoint drought effects."),
            shiny::tags$li(shiny::tags$strong("Actual vs. Potential ET:"), " Load seasonal AETI on the left and seasonal ETc on the right to visually identify areas of crop water stress."),
            shiny::tags$li(shiny::tags$strong("Phenology vs. Mask:"), " Display crop classification masks alongside planting date (SOS) rasters.")
          )
        )
      ))
    })

    .render_side <- function(map_id, r, band_input_id, pal_input_id, fit = TRUE) {
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
      proxy <- leaflet::leafletProxy(map_id, session)
      proxy |> leaflet::clearImages() |> leaflet::clearControls()
      proxy |>
        leaflet::addRasterImage(r_band, colors = pal_fn, opacity = input$raster_opacity %||% 0.8, project = TRUE) |>
        leaflet::addLegend(pal = pal_fn, values = vals, position = "bottomright")
      if (!isTRUE(fit)) return(invisible(NULL))
      e <- terra::ext(r_band)
      proxy |> leaflet::fitBounds(as.numeric(e$xmin), as.numeric(e$ymin), as.numeric(e$xmax), as.numeric(e$ymax))
    }

    shiny::observe({
      .render_side("map_left", loaded_left(), "band_left", "palette_left", fit = TRUE)
    })
    shiny::observe({
      locked <- isTRUE(shiny::isolate(input$sync_maps))
      fit_right <- !locked || is.null(loaded_left())
      .render_side("map_right", loaded_right(), "band_right", "palette_right", fit = fit_right)
    })

    shiny::observeEvent(input$basemap, {
      leaflet::leafletProxy("map_left", session)  |> leaflet::clearTiles() |> leaflet::addProviderTiles(input$basemap)
      leaflet::leafletProxy("map_right", session) |> leaflet::clearTiles() |> leaflet::addProviderTiles(input$basemap)
    })

    invisible(NULL)
  })
}
