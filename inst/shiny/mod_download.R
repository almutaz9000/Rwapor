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
          open = c("Project & Variable", "Area of Interest"),
          bslib::accordion_panel(
            "Project & Variable",
            icon = shiny::icon("database"),
            shiny::fluidRow(
              shiny::column(
                8,
                shiny::div(
                  style = "display: flex; align-items: flex-end; gap: 5px;",
                  shiny::div(
                    style = "flex: 1;",
                    shiny::textInput(
                      ns("folder"),
                      "Project Folder",
                      value = file.path(getwd(), "wapor_project")
                    )
                  ),
                  shiny::uiOutput(ns("favorite_btn_ui"))
                )
              ),
              shiny::column(
                4,
                shinyFiles::shinyDirButton(
                  ns("browse_folder"),
                  "Browse",
                  "Select project directory",
                  width = "100%",
                  class = "mt-4"
                )
              )
            ),
            shiny::uiOutput(ns("favorites_ui")),
            shiny::selectizeInput(
              ns("dn_variables"),
              "Variable(s)",
              choices = all_vars,
              selected = default_var,
              multiple = TRUE,
              options = list(placeholder = "Select one or more variables")
            ),
            shiny::conditionalPanel(
              condition = "input.dn_variables && input.dn_variables.some(v => v.startsWith('L3-'))",
              ns = ns,
              shiny::selectInput(ns("l3_region"), "L3 Region (for L3 variables)", choices = l3_region_choices),
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
            shiny::checkboxInput(ns("seasonal"), "Seasonal Aggregation", FALSE),
            shiny::checkboxInput(ns("separate_files"), "Save Individual Time-Step Files", TRUE),
            shiny::conditionalPanel(
              condition = "input.seasonal && input.separate_files",
              ns = ns,
              shiny::helpText(
                shiny::tags$em("Both selected: Individual files (dekadal/daily) AND a seasonal aggregate.")
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
              condition = "input.dn_variables && input.dn_variables.some(v => v.startsWith('L3-'))",
              ns = ns,
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
      c(shinyFiles::getVolumes()(), Project = getwd())
    } else {
      c(Home = normalizePath("~", winslash = "/"), Root = "/", Project = getwd())
    }

    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::rwapor_get_favorites())
    
    output$favorite_btn_ui <- shiny::renderUI({
      path <- input$folder %||% ""
      is_fav <- Rwapor::rwapor_is_favorite(path)
      
      shiny::actionLink(
        session$ns("favorite_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star-fill", style = "color: #ffc107;") else shiny::icon("star"),
        style = "margin-bottom: 11px; font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$favorite_btn, {
      path <- input$folder %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::rwapor_is_favorite(path)) {
        Rwapor::rwapor_remove_favorite(path)
      } else {
        Rwapor::rwapor_add_favorite(path, type = "directory")
      }
      favs(Rwapor::rwapor_get_favorites())
    })
    
    output$favorites_ui <- shiny::renderUI({
      f <- favs()
      f_dirs <- f[f$type == "directory", "path"]
      if (length(f_dirs) == 0) return(NULL)
      
      shiny::selectizeInput(
        session$ns("quick_fav"),
        NULL, # No label to keep it compact
        choices = c("Quick Access Favorites..." = "", f_dirs),
        options = list(placeholder = "Select a favorite project folder")
      )
    })
    
    shiny::observeEvent(input$quick_fav, {
      path <- input$quick_fav
      if (nzchar(path)) {
        shiny::updateTextInput(session, "folder", value = path)
      }
    })

    current_l3_region <- shiny::reactive({
      vars <- input$dn_variables %||% ""
      if (any(grepl("^L3-", vars))) input$l3_region else NULL
    })

    aoi <- mod_aoi_server(
      "aoi",
      map_id = session$ns("map"),
      map_session = session,
      l3_region = current_l3_region,
      global_folder = shiny::reactive(input$folder),
      l3_regions_meta = l3_regions_meta
    )

    # --- Validation ---
    iv <- shinyvalidate::InputValidator$new()
    iv$add_rule("folder", shinyvalidate::sv_required("Project Folder is required."))
    iv$add_rule("dn_variables", shinyvalidate::sv_required("Select at least one variable."))
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

      var_list_str <- if (length(input$dn_variables) > 1) {
        paste0("c(\"", paste(input$dn_variables, collapse = "\", \""), "\")")
      } else {
        sprintf("\"%s\"", input$dn_variables)
      }

      code_val <- if (input$seasonal && input$separate_files) {
        sprintf(
          paste0(
            "library(Rwapor)\n\n",
            "region   <- %s\n",
            "period   <- %s\n",
            "variable <- %s\n",
            "folder   <- \"%s\"\n\n",
            "# 1. Download individual time-step (dekadal/daily) files\n",
            "file_paths <- wapor_map(\n",
            "  region = region,\n",
            "  variable = variable,\n",
            "  period = period,\n",
            "  folder = folder,\n",
            "  unit_conversion = %s,\n",
            "  seasonal = FALSE,\n",
            "  separate_files = TRUE,\n",
            "  mask = %s\n",
            ")\n\n",
            "# 2. Calculate and save seasonal aggregate\n",
            "seasonal_paths <- wapor_map(\n",
            "  region = region,\n",
            "  variable = variable,\n",
            "  period = period,\n",
            "  folder = folder,\n",
            "  unit_conversion = %s,\n",
            "  seasonal = TRUE,\n",
            "  separate_files = FALSE,\n",
            "  mask = %s\n",
            ")"
          ),
          reg_str,
          period_str,
          var_list_str,
          input$folder,
          unit_conv,
          mask_str,
          unit_conv,
          mask_str
        )
      } else {
        sprintf(
          paste0(
            "library(Rwapor)\n\n",
            "region   <- %s\n",
            "period   <- %s\n",
            "variable <- %s\n",
            "folder   <- \"%s\"\n\n",
            "map_paths <- wapor_map(\n",
            "  region = region,\n",
            "  variable = variable,\n",
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
          var_list_str,
          input$folder,
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
      vars <- input$dn_variables
      
      if (is.null(reg)) {
        shiny::showNotification("Please select an AOI before downloading.", type = "error")
        return()
      }
      if (length(vars) == 0) {
        shiny::showNotification("Please select at least one variable.", type = "error")
        return()
      }
      if (!nzchar(input$folder)) {
        shiny::showNotification("Output folder cannot be empty.", type = "error")
        return()
      }

      shiny::withProgress(message = "Downloading Data", value = 0, {
        tryCatch({
          n_vars <- length(vars)
          unit_conv <- if (input$unit_conversion == "none") NULL else input$unit_conversion
          all_out_paths <- list()

          for (i in seq_along(vars)) {
            v <- vars[i]
            shiny::incProgress(
              1/n_vars * 0.1, 
              detail = sprintf("Initializing %s (%d/%d)...", v, i, n_vars)
            )
            
            # Use the core wapor_map for each variable to provide granular progress
            # Dual-stage if both selected
            if (isTRUE(input$seasonal) && isTRUE(input$separate_files)) {
              shiny::incProgress(0, detail = sprintf("Stage 1 of 2: Individual files for %s...", v))
              out_path_ind <- Rwapor::wapor_map(
                region = reg,
                variable = v,
                period = as.character(input$period),
                folder = input$folder,
                unit_conversion = unit_conv,
                seasonal = FALSE,
                separate_files = TRUE,
                mask = aoi$mask()
              )
              
              shiny::incProgress(0, detail = sprintf("Stage 2 of 2: Seasonal aggregation for %s...", v))
              out_path_sea <- Rwapor::wapor_map(
                region = reg,
                variable = v,
                period = as.character(input$period),
                folder = input$folder,
                unit_conversion = unit_conv,
                seasonal = TRUE,
                separate_files = FALSE,
                mask = aoi$mask()
              )
              out_path <- c(out_path_ind, out_path_sea)
            } else {
              out_path <- Rwapor::wapor_map(
                region = reg,
                variable = v,
                period = as.character(input$period),
                folder = input$folder,
                unit_conversion = unit_conv,
                seasonal = input$seasonal,
                separate_files = input$separate_files,
                mask = aoi$mask()
              )
            }
            
            all_out_paths[[v]] <- out_path
            shiny::incProgress(1/n_vars * 0.9)
          }

          # Check if any files were actually written
          flat_paths <- unlist(all_out_paths)
          if (length(flat_paths) == 0 || !all(file.exists(flat_paths))) {
             stop("Download finished but some expected files were not found on disk.")
          }

          shiny::showNotification(
            sprintf("Download successful. %d file(s) saved for %d variable(s).", length(flat_paths), n_vars),
            type = "message",
            duration = 10
          )
        }, error = function(e) {
          shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
        })
      })
    })

    list(
      region = current_region,
      folder = shiny::reactive(input$folder)
    )
  })
}
