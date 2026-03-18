# mod_aoi.R
# Area of interest state and controls used by the download workflow.

mod_aoi_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$small(
      class = "text-muted",
      "Draw a rectangle or polygon, or upload a vector file."
    ),
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
    ),
    shiny::tags$div(
      class = "mt-2",
      shinyFiles::shinyFilesButton(
        ns("browse_vector"),
        "Select Vector File (.geojson, .gpkg, .kml)",
        "Select vector file",
        multiple = FALSE,
        class = "w-100 btn-sm btn-outline-secondary",
        icon = shiny::icon("folder-open")
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

    roots <- c(Home = normalizePath("~", winslash = "/"), "C:/" = "C:/")
    shinyFiles::shinyFileChoose(
      input,
      "browse_vector",
      roots = roots,
      session = session,
      filetypes = c("geojson", "gpkg", "kml")
    )

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
      file_info <- shinyFiles::parseFilePaths(roots, input$browse_vector)
      if (nrow(file_info) > 0) {
        path <- normalizePath(file_info$datapath, winslash = "/", mustWork = FALSE)
        handle_vector_file(path)
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
