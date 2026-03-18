# mod_download.R
# WaPOR download workflow and shared app state.

mod_download_ui <- function(id, all_vars, default_var, l3_region_choices) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      open = TRUE,
      title = "Download Configuration",
      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id = ns("download_accordion"),
          open = c("Variable & Period", "Area of Interest"),
          bslib::accordion_panel(
            "Variable & Period",
            icon = shiny::icon("database"),
            shiny::selectInput(
              ns("variable"),
              "Variable",
              choices = all_vars,
              selected = default_var
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && input['%s'].startsWith('L3-')", ns("variable"), ns("variable")),
              shiny::selectInput(ns("l3_region"), "L3 Region", choices = l3_region_choices),
              shiny::helpText("L3 variables require a specific region.")
            ),
            shiny::dateRangeInput(
              ns("period"),
              "Period",
              start = Sys.Date() - 30,
              end = Sys.Date(),
              format = "yyyy-mm-dd"
            )
          ),
          bslib::accordion_panel(
            "Output Settings",
            icon = shiny::icon("folder"),
            shiny::fluidRow(
              shiny::column(
                8,
                shiny::textInput(
                  ns("folder"),
                  "Output Folder",
                  value = file.path(getwd(), "wapor_output")
                )
              ),
              shiny::column(
                4,
                shinyFiles::shinyDirButton(
                  ns("browse_folder"),
                  "Browse",
                  "Select output directory",
                  width = "100%"
                )
              )
            ),
            shiny::checkboxInput(ns("seasonal"), "Seasonal Aggregation", FALSE),
            shiny::checkboxInput(ns("separate_files"), "Save as Separate Files", FALSE),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && input['%s']", ns("seasonal"), ns("separate_files")),
              shiny::helpText(
                shiny::tags$em("Both selected: seasonal + individual time-step files.")
              )
            ),
            shiny::selectInput(
              ns("unit_conversion"),
              "Unit Conversion",
              choices = c("none", "day", "dekad", "month", "year"),
              selected = "none"
            )
          ),
          bslib::accordion_panel(
            "Area of Interest",
            icon = shiny::icon("map"),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && input['%s'].startsWith('L3-')", ns("variable"), ns("variable")),
              shiny::helpText(
                shiny::tags$em("AOI clips data; leave empty to download the whole L3 region.")
              )
            ),
            mod_aoi_ui(ns("aoi"))
          )
        )
      ),
      shiny::div(
        class = "sidebar-sticky-footer",
        shiny::actionButton(
          ns("download_btn"),
          "Download Data",
          class = "btn-primary w-100",
          icon = shiny::icon("cloud-download")
        )
      )
    ),
    shiny::div(
      bslib::card(
        id = ns("download_map_card"),
        full_screen = TRUE,
        bslib::card_header("Map"),
        bslib::card_body(
          class = "p-0 main-map-output",
          leaflet::leafletOutput(ns("map"), height = "100%", width = "100%")
        )
      ),
      shiny::tags$button(
        class = "btn btn-sm btn-outline-secondary code-preview-toggle mt-1",
        `data-bs-toggle` = "collapse",
        `data-bs-target` = sprintf("#%s", ns("codePreviewCollapse")),
        `aria-expanded` = "false",
        shiny::icon("code"),
        " R Code Preview"
      ),
      shiny::div(
        id = ns("codePreviewCollapse"),
        class = "collapse code-preview-body",
        shinyAce::aceEditor(
          ns("code_preview"),
          mode = "r",
          theme = "monokai",
          readOnly = TRUE,
          height = "250px",
          fontSize = 12,
          wordWrap = TRUE
        )
      )
    )
  )
}

mod_download_server <- function(id, l3_regions_meta) {
  shiny::moduleServer(id, function(input, output, session) {
    # Cross-platform roots for shinyFiles
    roots <- if (.Platform$OS.type == "windows") {
      c(Home = normalizePath("~", winslash = "/"), "C:/" = "C:/")
    } else {
      c(Home = normalizePath("~", winslash = "/"), Root = "/")
    }

    current_l3_region <- shiny::reactive({
      if (grepl("^L3-", input$variable %||% "")) input$l3_region else NULL
    })

    aoi <- mod_aoi_server(
      "aoi",
      map_id = "map",
      map_session = session,
      l3_region = current_l3_region,
      l3_regions_meta = l3_regions_meta
    )

    # --- Validation ---
    iv <- shinyvalidate::InputValidator$new()
    iv$add_rule("folder", shinyvalidate::sv_required())
    iv$add_rule("variable", shinyvalidate::sv_required())
    iv$add_rule("period", function(value) {
      if (length(value) != 2 || any(is.na(value))) return("Select a valid date range.")
      if (value[2] < value[1]) return("End date must be after start date.")
    })
    iv$enable()

    # Control download button state
    shiny::observe({
      shinyjs::toggleState("download_btn", condition = iv$is_valid())
    })

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
            editOptions = edit_toolbar_options(
              selectedPathOptions = selected_path_options()
            )
          )
      }
      m |> leaflet::setView(lng = 18, lat = 2, zoom = 3)
    })

    shiny::observeEvent(input$map_click, {
      if (!aoi$manual_active()) return()

      click <- input$map_click
      current <- aoi$manual_clicks()
      current <- rbind(current, c(click$lng, click$lat))
      aoi$manual_clicks(current)

      leaflet::leafletProxy("map", session = session) |>
        leaflet::addCircleMarkers(
          lng = click$lng,
          lat = click$lat,
          radius = 4,
          group = "manual_draw",
          fillOpacity = 1
        )

      if (aoi$manual_mode() == "bbox" && nrow(current) >= 2) {
        bbox <- c(
          min(current[, 1]),
          min(current[, 2]),
          max(current[, 1]),
          max(current[, 2])
        )
        aoi$user_roi(bbox)
        aoi$upload_roi(NULL)
        aoi$manual_active(FALSE)

        leaflet::leafletProxy("map", session = session) |>
          leaflet::clearGroup("manual_draw") |>
          leaflet::addRectangles(
            lng1 = bbox[1],
            lat1 = bbox[2],
            lng2 = bbox[3],
            lat2 = bbox[4],
            color = "yellow",
            fill = FALSE,
            weight = 2,
            group = "manual_draw"
          ) |>
          leaflet::fitBounds(
            lng1 = bbox[1],
            lat1 = bbox[2],
            lng2 = bbox[3],
            lat2 = bbox[4]
          )
      } else if (aoi$manual_mode() == "poly" && nrow(current) >= 2) {
        leaflet::leafletProxy("map", session = session) |>
          leaflet::clearGroup("manual_preview") |>
          leaflet::addPolylines(
            lng = current[, 1],
            lat = current[, 2],
            color = "yellow",
            weight = 2,
            group = "manual_preview"
          )
      }
    })

    shiny::observeEvent(input$map_draw_new_feature, {
      bbox <- extract_bbox_from_feature(input$map_draw_new_feature)
      if (!is.null(bbox)) {
        aoi$user_roi(bbox)
        aoi$upload_roi(NULL)
        aoi$manual_active(FALSE)
      }
    })

    shiny::observeEvent(input$map_draw_edited_features, {
      edited <- input$map_draw_edited_features$features
      if (length(edited) > 0) {
        bbox <- extract_bbox_from_feature(edited[[1]])
        if (!is.null(bbox)) {
          aoi$user_roi(bbox)
          aoi$upload_roi(NULL)
        }
      }
    })

    shiny::observeEvent(input$map_draw_deleted_features, {
      aoi$user_roi(NULL)
      aoi$upload_roi(NULL)
    })

    current_region <- shiny::reactive(aoi$region())

    shiny::observe({
      reg <- current_region()
      if (is.null(reg)) {
        reg_str <- "NULL  # Please select an AOI on the map or upload a file"
      } else if (is_l3_code(reg)) {
        reg_str <- sprintf("\"%s\"", reg)
      } else if (is.character(reg)) {
        reg_str <- sprintf("\"%s\"", normalizePath(reg, winslash = "/", mustWork = FALSE))
      } else {
        reg_str <- sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
      }

      period_str <- sprintf("c(\"%s\", \"%s\")", input$period[1], input$period[2])
      unit_conv <- if (input$unit_conversion == "none") "NULL" else sprintf("\"%s\"", input$unit_conversion)
      mask_str <- if (isTRUE(aoi$mask())) "TRUE" else "FALSE"

      code_val <- if (input$seasonal && input$separate_files) {
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
          reg_str,
          period_str,
          input$folder,
          input$variable,
          unit_conv,
          mask_str,
          input$variable,
          unit_conv,
          mask_str
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
          reg_str,
          period_str,
          input$folder,
          input$variable,
          unit_conv,
          input$seasonal,
          input$separate_files,
          mask_str
        )
      }
      
      shinyAce::updateAceEditor(session, "code_preview", value = code_val)
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

      if (input$seasonal && input$separate_files) {
        shiny::withProgress(message = "Downloading data...", value = 0, {
          tryCatch({
            unit_conv <- if (input$unit_conversion == "none") NULL else input$unit_conversion

            shiny::incProgress(0.05, detail = "Downloading seasonal aggregate...")
            seasonal_path <- Rwapor::wapor_map(
              region = reg,
              variable = input$variable,
              period = as.character(input$period),
              folder = input$folder,
              unit_conversion = unit_conv,
              seasonal = TRUE,
              separate_files = FALSE,
              mask = aoi$mask()
            )

            shiny::incProgress(0.50, detail = "Downloading individual time steps...")
            ind_paths <- Rwapor::wapor_map(
              region = reg,
              variable = input$variable,
              period = as.character(input$period),
              folder = input$folder,
              unit_conversion = unit_conv,
              seasonal = FALSE,
              separate_files = TRUE,
              mask = aoi$mask()
            )

            all_paths <- c(seasonal_path, ind_paths)
            shiny::incProgress(0.45, detail = "Complete!")
            shiny::showNotification(
              sprintf(
                "Download successful. %d files written (1 seasonal + %d individual).",
                length(all_paths),
                length(all_paths) - 1
              ),
              type = "message",
              duration = 10
            )
          }, error = function(e) {
            shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
          })
        })
      } else {
        shiny::withProgress(message = "Downloading data...", value = 0, {
          tryCatch({
            shiny::incProgress(0.10, detail = "Initializing download...")
            unit_conv <- if (input$unit_conversion == "none") NULL else input$unit_conversion
            out_path <- Rwapor::wapor_map(
              region = reg,
              variable = input$variable,
              period = as.character(input$period),
              folder = input$folder,
              unit_conversion = unit_conv,
              seasonal = input$seasonal,
              separate_files = input$separate_files,
              mask = aoi$mask()
            )
            shiny::incProgress(0.90, detail = "Finalizing...")
            if (length(out_path) == 0 || !all(file.exists(out_path))) {
              stop("Download completed but output file(s) were not found on disk.")
            }
            shiny::showNotification(
              if (length(out_path) > 1) {
                sprintf("Download successful. %d files written in %s", length(out_path), dirname(out_path[1]))
              } else {
                sprintf("Download successful. Saved to: %s", out_path)
              },
              type = "message",
              duration = 10
            )
          }, error = function(e) {
            shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
          })
        })
      }
    })

    list(
      region = current_region,
      folder = shiny::reactive(input$folder)
    )
  })
}
