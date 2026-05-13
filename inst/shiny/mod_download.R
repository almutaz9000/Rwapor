# mod_download.R
# WaPOR download workflow and shared app state.

mod_download_ui <- function(id, all_vars, default_var, l3_region_choices) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    fillable = TRUE,
    sidebar = bslib::sidebar(
      width = 305,
      open  = TRUE,
      title = "Download Configuration",
      # ── Project Folder — always visible at top of sidebar ─────────────
      shiny::div(
        class = "folder-header-strip",
        shiny::tags$span(
          shiny::icon("folder-open"), " Project Folder",
          class = "ctrl-group-label req-label"
        ),
        shiny::div(
          class = "inline-row",
          shiny::div(
            class = "flex-1",
            shiny::textInput(
              ns("folder"), NULL,
              value       = file.path(getwd(), "wapor_project"),
              placeholder = "Path to output folder"
            )
          ),
          shiny::uiOutput(ns("favorite_btn_ui")),
          shinyFiles::shinyDirButton(
            ns("browse_folder"), label = "",
            icon  = shiny::icon("folder-open"),
            title = "Browse for folder (Desktop / Downloads / Documents and all drives are available as starting points)",
            class = "btn-outline-secondary btn-sm",
            style = "padding:0.37rem 0.6rem;"
          )
        ),
        shiny::div(
          class = "d-flex align-items-center justify-content-between",
          style = "min-height: 24px; margin-bottom: 4px;",
          shiny::uiOutput(ns("folder_status_ui")),
          shinyjs::hidden(
            shiny::actionButton(
              ns("create_folder_btn"), "Create",
              icon  = shiny::icon("folder-plus"),
              class = "btn-outline-success btn-sm",
              style = "padding: 0.1rem 0.5rem; font-size: 0.75rem;"
            )
          )
        ),
        shiny::uiOutput(ns("favorites_ui"))
      ),
      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id     = ns("download_accordion"),
          open   = c("Data Selection"),

          # ── 1. Data Selection ────────────────────────────────────────
          bslib::accordion_panel(
            "Data Selection", icon = shiny::icon("database"),

            shiny::tags$span("Area of Interest", class = "ctrl-group-label req-label"),
            shiny::helpText("Define AOI first to filter L3 regions automatically."),
            mod_aoi_ui(ns("aoi")),
            
            shiny::tags$hr(class = "ctrl-divider"),
            shiny::tags$span("Variables", class = "ctrl-group-label req-label"),
            shiny::selectizeInput(
              ns("dn_variables"), NULL,
              choices  = all_vars,
              selected = default_var,
              multiple = TRUE,
              options  = list(placeholder = "Select one or more WaPOR / AgERA5 variables")
            ),
            shiny::conditionalPanel(
              condition = "input.dn_variables && input.dn_variables.some(v => v.startsWith('L3-'))",
              ns = ns,
              shiny::selectInput(
                ns("l3_region"), "L3 Region",
                choices = l3_region_choices
              ),
              shiny::uiOutput(ns("l3_region_message")),
              shiny::helpText("Required for L3-level variables."),
              shiny::tags$details(
                shiny::tags$summary("📍 Help: Find L3 Regions"),
                shiny::div(
                  style = "font-size: 0.85rem; margin-top: 0.5rem; padding: 0.5rem;",
                  shiny::tags$p(
                    "If auto-detection doesn't work, you can:",
                    shiny::br(),
                    "1. Run in R: ",
                    shiny::tags$code("Filter(function(r) r$country == 'Tunisia', Rwapor::L3_REGIONS)"),
                    shiny::br(),
                    "2. Find the region code (e.g., JEN for Jendouba)",
                    shiny::br(),
                    "3. Select it manually from the dropdown",
                    style = "font-size: 0.8rem; color: #666;"
                  )
                )
              )
            ),

            shiny::tags$hr(class = "ctrl-divider"),
            shiny::div(
              class = "flex-row-center-between",
              shiny::tags$span("Time Period", class = "ctrl-group-label req-label"),
              shiny::div(
                style = "font-size: 0.8rem;",
                shiny::checkboxInput(ns("multi_season"), "Multi-season", FALSE)
              )
            ),
            shiny::conditionalPanel(
              condition = "!input.multi_season",
              ns = ns,
              shiny::dateRangeInput(
                ns("period"), NULL,
                start  = Sys.Date() - 30,
                end    = Sys.Date(),
                format = "yyyy-mm-dd"
              )
            ),
            shiny::conditionalPanel(
              condition = "input.multi_season",
              ns = ns,
              shiny::tags$p(
                class = "text-muted mb-1",
                style = "font-size:0.78rem;",
                "One season per line: ",
                shiny::tags$code("Label, YYYY-MM-DD, YYYY-MM-DD")
              ),
              shiny::textAreaInput(
                ns("seasons_text"), NULL,
                placeholder = "Season1, 2020-10-01, 2021-05-31\nSeason2, 2021-10-01, 2022-05-31",
                rows = 4,
                width = "100%"
              ),
              shiny::div(
                class = "inline-row mb-1",
                shiny::div(class = "flex-1", shiny::textInput(ns("seasons_config_name"), NULL, value = "seasons", placeholder = "Config name")),
                shiny::div(
                  class = "btn-group btn-group-sm",
                  shiny::actionButton(ns("dn_save_seasons"), NULL, icon = shiny::icon("floppy-disk"), class = "btn-outline-secondary", title = "Save config"),
                  shiny::actionButton(ns("dn_load_seasons"), NULL, icon = shiny::icon("folder-open"), class = "btn-outline-secondary", title = "Load config")
                )
              ),
              shiny::uiOutput(ns("seasons_preview"))
            )
          ),

          # ── 2. Output Settings ──────────────────────────────────────
          bslib::accordion_panel(
            "Output Settings", icon = shiny::icon("gear"),

            shiny::tags$span("File options", class = "ctrl-group-label"),
            shiny::div(
              class = "check-row",
              shiny::checkboxInput(ns("seasonal"),       "Seasonal aggregate",       FALSE),
              shiny::checkboxInput(ns("separate_files"), "Save per-timestep files",  TRUE)
            ),
            shiny::conditionalPanel(
              condition = "input.seasonal && input.separate_files",
              ns = ns,
              shiny::helpText("Both checked: dekadal/daily files + one seasonal aggregate.")
            ),

            shiny::tags$hr(class = "ctrl-divider"),
            shiny::tags$span("Unit Conversion", class = "ctrl-group-label"),
            shiny::selectInput(
              ns("unit_conversion"), NULL,
              choices  = c("No conversion" = "none",
                           "Per day"       = "day",
                           "Per dekad"     = "dekad",
                           "Per month"     = "month",
                           "Per year"      = "year"),
              selected = "none"
            ),

            shiny::tags$hr(class = "ctrl-divider")
          )
        )
      ),
      shiny::div(
        class = "sidebar-sticky-footer",
        shiny::actionButton(
          ns("download_btn"), "Download Data",
          class = "btn-primary w-100",
          icon  = shiny::icon("cloud-arrow-down")
        )
      )
    ),
    bslib::navset_card_tab(
      id = ns("download_main_nav"),
      full_screen = TRUE,
      
      # ── Tab 1: Map ──────────────────────────────────────────────────────────
      bslib::nav_panel(
        title = "Area of Interest",
        icon  = shiny::icon("map"),
        bslib::card_body(
          padding = 0,
          class = "main-map-output",
          leaflet::leafletOutput(ns("map"), height = "100%", width = "100%")
        )
      ),
      
      # ── Tab 2: Technical Console ───────────────────────────────────────────
      bslib::nav_panel(
        title = "Technical Console",
        icon  = shiny::icon("terminal"),
        bslib::card_body(
          padding = 0,
          shinyAce::aceEditor(
            ns("code_preview"),
            mode = "r", theme = "monokai", readOnly = TRUE,
            height = "100%", fontSize = 12,
            wordWrap = TRUE, showLineNumbers = TRUE
          )
        ),
        footer = shiny::div(
          class = "d-flex justify-content-between align-items-center p-2 bg-light border-top",
          shiny::div(
            class = "btn-group btn-group-sm",
            shiny::actionButton(ns("dn_copy_code"), "Copy", icon = shiny::icon("copy"), class = "btn-outline-secondary"),
            shiny::actionButton(ns("dn_export_script"), "Export .R", icon = shiny::icon("file-export"), class = "btn-outline-secondary")
          ),
          shiny::div(
            class = "small text-muted",
            shiny::icon("terminal"), " Reproducible R Script"
          )
        )
      )
    )
  )
}

mod_download_server <- function(id, l3_regions_meta) {
  shiny::moduleServer(id, function(input, output, session) {
    roots <- get_shinyfiles_roots()

    # --- Multi-season logic (textarea-based) ---
    # Parse "Label, YYYY-MM-DD, YYYY-MM-DD" lines into a list of named vectors.
    parsed_seasons <- shiny::reactive({
      text <- input$seasons_text %||% ""
      lines <- strsplit(text, "\\r?\\n", perl = TRUE)[[1]]
      lines <- lines[nzchar(trimws(lines))]
      rows <- list()
      for (line in lines) {
        parts <- trimws(strsplit(line, ",", fixed = TRUE)[[1]])
        if (length(parts) < 3L) next
        label   <- parts[1]
        start_d <- tryCatch(as.Date(parts[2]), error = function(e) NA)
        end_d   <- tryCatch(as.Date(parts[3]), error = function(e) NA)
        if (is.na(start_d) || is.na(end_d) || end_d < start_d || !nzchar(label)) next
        rows[[length(rows) + 1L]] <- list(name = label, start = start_d, end = end_d)
      }
      rows
    })

    output$seasons_preview <- shiny::renderUI({
      rows <- parsed_seasons()
      n <- length(rows)
      if (n == 0) {
        return(shiny::tags$p(
          class = "text-muted mt-1",
          style = "font-size:0.75rem;",
          shiny::icon("circle-info"), " No valid seasons yet."
        ))
      }
      shiny::tags$table(
        class = "table table-sm table-bordered mb-0 mt-1",
        style = "font-size:0.75rem;",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Label"), shiny::tags$th("Start"), shiny::tags$th("End")
        )),
        shiny::tags$tbody(lapply(rows, function(r) {
          shiny::tags$tr(
            shiny::tags$td(r$name),
            shiny::tags$td(as.character(r$start)),
            shiny::tags$td(as.character(r$end))
          )
        }))
      )
    })

    # --- Save / Load seasons JSON ---
    seasons_json_path <- shiny::reactive({
      folder <- trimws(input$folder %||% "")
      if (!nzchar(folder)) return(NULL)
      name <- trimws(input$seasons_config_name %||% "seasons")
      if (!nzchar(name)) name <- "seasons"
      if (!grepl("\\.json$", name, ignore.case = TRUE)) name <- paste0(name, ".json")
      file.path(folder, name)
    })

    shiny::observeEvent(input$dn_save_seasons, {
      rows <- parsed_seasons()
      if (length(rows) == 0) {
        shiny::showNotification("No valid seasons to save. Enter seasons first.", type = "warning")
        return()
      }
      path <- seasons_json_path()
      if (is.null(path)) {
        shiny::showNotification("Set a project folder before saving seasons.", type = "warning")
        return()
      }
      folder <- dirname(path)
      if (!dir.exists(folder)) dir.create(folder, recursive = TRUE, showWarnings = FALSE)
      season_list <- lapply(rows, function(r) {
        list(label = r$name, start = as.character(r$start), end = as.character(r$end))
      })
      tryCatch({
        jsonlite::write_json(season_list, path, pretty = TRUE, auto_unbox = TRUE)
        shiny::showNotification(
          sprintf("Saved %d season(s) to %s", length(rows), path),
          type = "message", duration = 8
        )
      }, error = function(e) {
        shiny::showNotification(paste("Failed to save seasons:", e$message), type = "error")
      })
    })

    shiny::observeEvent(input$dn_load_seasons, {
      path <- seasons_json_path()
      if (is.null(path) || !file.exists(path)) {
        shiny::showNotification(
          "seasons.json not found in project folder. Save seasons first or set the correct folder.",
          type = "warning", duration = 8
        )
        return()
      }
      tryCatch({
        season_list <- jsonlite::read_json(path)
        lines <- vapply(season_list, function(s) {
          sprintf("%s, %s, %s", s$label, s$start, s$end)
        }, character(1))
        shiny::updateTextAreaInput(session, "seasons_text", value = paste(lines, collapse = "\n"))
        shiny::showNotification(
          sprintf("Loaded %d season(s) from %s", length(lines), path),
          type = "message", duration = 6
        )
      }, error = function(e) {
        shiny::showNotification(paste("Failed to load seasons:", e$message), type = "error")
      })
    })

    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::wapor_get_favorites())
    
    output$favorite_btn_ui <- shiny::renderUI({
      path <- input$folder %||% ""
      is_fav <- Rwapor::wapor_is_favorite(path)
      
      shiny::actionLink(
        session$ns("favorite_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star", style = "color: #ffc107;") else shiny::icon("star"),
        style = "margin-bottom: 11px; font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$favorite_btn, {
      path <- input$folder %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::wapor_is_favorite(path)) {
        Rwapor::wapor_remove_favorite(path)
      } else {
        Rwapor::wapor_add_favorite(path, type = "directory")
      }
      favs(Rwapor::wapor_get_favorites())
    })
    
    output$favorites_ui <- shiny::renderUI({
      f <- favs()
      f_dirs <- f[f$type == "directory", "path"]
      if (length(f_dirs) == 0) return(NULL)

      display_names <- stats::setNames(f_dirs, paste("\U0001F4C2", basename(f_dirs)))
      shiny::tagList(
        shiny::tags$span("Saved folders", class = "fav-section-label"),
        shiny::selectizeInput(
          session$ns("quick_fav"),
          NULL,
          choices = c("Select a saved folder..." = "", display_names),
          options = list(placeholder = "Select a saved folder...")
        )
      )
    })

    shiny::observeEvent(input$quick_fav, {
      path <- input$quick_fav
      if (nzchar(path)) {
        shiny::updateTextInput(session, "folder", value = path)
        shiny::updateSelectizeInput(session, "quick_fav", selected = "")
      }
    })

    # ── Folder status badge + create-on-demand button ─────────────────────
    folder_exists_status <- shiny::reactive({
      path <- trimws(input$folder %||% "")
      if (!nzchar(path)) return("empty")
      if (dir.exists(path)) "exists" else "missing"
    })

    output$folder_status_ui <- shiny::renderUI({
      switch(folder_exists_status(),
        "exists"  = shiny::span(
          class = "folder-status-badge exists",
          shiny::icon("circle-check"), " Folder exists"
        ),
        "missing" = shiny::span(
          class = "folder-status-badge missing",
          shiny::icon("circle-plus"), " Will be created on download"
        ),
        NULL
      )
    })

    shiny::observe({
      if (folder_exists_status() == "missing") {
        shinyjs::show("create_folder_btn")
      } else {
        shinyjs::hide("create_folder_btn")
      }
    })

    shiny::observeEvent(input$create_folder_btn, {
      path <- trimws(input$folder %||% "")
      if (!nzchar(path)) return()
      tryCatch({
        dir.create(path, recursive = TRUE, showWarnings = FALSE)
        if (dir.exists(path)) {
          shiny::showNotification(
            sprintf("Folder created: %s", path),
            type = "message", duration = 5
          )
        }
      }, error = function(e) {
        shiny::showNotification(paste("Could not create folder:", e$message), type = "error")
      })
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

    # --- L3 Region Auto-Detection ---
    # Reactively detect which L3 regions overlap with the selected AOI
    detected_l3_regions <- shiny::reactive({
      reg <- aoi$region()
      
      # Only attempt detection if AOI is set and it's NOT already an L3 code
      if (is.null(reg) || is_l3_code(reg)) {
        return(list(codes = NULL, status = "no_aoi", message = "No AOI defined"))
      }
      
      # Only detect if L3 variables are selected
      vars <- input$dn_variables %||% ""
      has_l3 <- any(grepl("^L3-", vars))
      if (!has_l3) {
        return(list(codes = NULL, status = "no_l3_vars", message = "No L3 variables selected"))
      }
      
      # Pick a sample L3 variable to use for detection
      l3_vars <- grep("^L3-", vars, value = TRUE)
      sample_var <- l3_vars[1]
      
      # Parse region for wapor_guess_region
      reg_info <- tryCatch({
        if (is.numeric(reg) && length(reg) == 4) {
          # bbox
          list(
            type = "bbox",
            value = sf::st_bbox(c(xmin = reg[1], ymin = reg[2], xmax = reg[3], ymax = reg[4]), crs = 4326)
          )
        } else if (is.character(reg) && file.exists(reg)) {
          # File path  
          Rwapor::wapor_parse_region(reg)
        } else {
          NULL
        }
      }, error = function(e) {
        list(error = e$message)
      })
      
      if (is.null(reg_info)) {
        return(list(codes = NULL, status = "parse_error", message = "Could not parse AOI"))
      }
      
      if (!is.null(reg_info$error)) {
        return(list(codes = NULL, status = "parse_error", message = reg_info$error))
      }
      
      # Use wapor_guess_region to detect overlaps (use first date of period for detection)
      # Convert period to character format as required by wapor_guess_region
      period_dates <- input$period %||% c(Sys.Date() - 30, Sys.Date())
      period <- as.character(period_dates)
      
      overlapping_codes <- tryCatch({
        Rwapor::wapor_guess_region(sample_var, reg_info, period)
      }, error = function(e) {
        # Capture error for diagnostics
        paste0("Detection error: ", e$message)
      })
      
      # Check result
      if (is.character(overlapping_codes) && length(overlapping_codes) == 1 && !grepl("^[A-Z]{3}$", overlapping_codes)) {
        # It's an error message
        return(list(codes = NULL, status = "detection_error", message = overlapping_codes))
      }
      
      if (is.null(overlapping_codes) || length(overlapping_codes) == 0) {
        return(list(codes = NULL, status = "no_overlap", message = "No L3 regions detected"))
      }
      
      list(codes = overlapping_codes, status = "success", message = NULL)
    })
    
    # Update L3 region dropdown based on detected overlaps
    shiny::observe({
      result <- detected_l3_regions()
      codes <- result$codes
      vars <- input$dn_variables %||% ""
      has_l3 <- any(grepl("^L3-", vars))
      
      if (!has_l3) return()  # Only update if L3 variables selected
      
      if (!is.null(codes) && length(codes) > 0) {
        # Update choices to show only overlapping regions
        choices <- stats::setNames(
          codes,
          sapply(codes, function(c) {
            r <- l3_regions_meta[[c]]
            if (!is.null(r)) sprintf("%s - %s (%s)", r$country, r$name, c) else c
          })
        )
        
        # Auto-select if exactly one region overlaps
        selected_val <- if (length(codes) == 1) codes[1] else input$l3_region
        
        shiny::updateSelectInput(
          session, "l3_region",
          choices = choices,
          selected = selected_val
        )
      }
    })
    
    # Display messages about L3 region overlaps
    output$l3_region_message <- shiny::renderUI({
      result <- detected_l3_regions()
      codes <- result$codes
      status <- result$status
      msg <- result$message
      
      vars <- input$dn_variables %||% ""
      has_l3 <- any(grepl("^L3-", vars))
      reg <- aoi$region()
      
      if (!has_l3) return(NULL)
      
      # If no AOI selected
      if (status == "no_aoi") {
        return(shiny::div(
          class = "alert alert-info mt-2",
          style = "font-size: 0.85rem; padding: 0.5rem;",
          shiny::icon("info-circle"),
          " Select an AOI to auto-detect L3 regions"
        ))
      }
      
      # If AOI is already an L3 code
      if (is_l3_code(reg)) {
        return(NULL)
      }
      
      # If detection returned no overlaps
      if (status == "no_overlap") {
        return(shiny::div(
          class = "alert alert-warning mt-2",
          style = "font-size: 0.85rem; padding: 0.5rem;",
          shiny::icon("triangle-exclamation"),
          " No L3 regions overlap with this AOI. You can:",
          shiny::br(),
          shiny::span(style = "font-size: 0.8rem; margin-left: 0.5rem;",
            "• Use L1 or L2 variables instead",
            shiny::br(),
            "• Refine your AOI to cover an existing L3 region"
          )
        ))
      }
      
      # If there was a detection error
      if (status == "detection_error" || status == "parse_error") {
        return(shiny::div(
          class = "alert alert-danger mt-2",
          style = "font-size: 0.85rem; padding: 0.5rem;",
          shiny::icon("exclamation-circle"),
          " L3 Detection Error",
          shiny::br(),
          shiny::span(style = "font-size: 0.75rem; margin-left: 0.5rem; display: block;",
            msg
          ),
          shiny::br(),
          shiny::span(style = "font-size: 0.8rem;",
            "Please select an L3 region manually from the dropdown above"
          )
        ))
      }
      
      # If exactly one region overlaps (success)
      if (!is.null(codes) && length(codes) == 1) {
        r_meta <- l3_regions_meta[[codes[1]]]
        region_name <- if (!is.null(r_meta)) {
          sprintf("%s - %s", r_meta$country, r_meta$name)
        } else {
          codes[1]
        }
        return(shiny::div(
          class = "alert alert-success mt-2",
          style = "font-size: 0.85rem; padding: 0.5rem;",
          shiny::icon("circle-check"),
          sprintf(" Auto-selected: %s", region_name)
        ))
      }
      
      # If multiple regions overlap
      if (!is.null(codes) && length(codes) > 1) {
        return(shiny::div(
          class = "alert alert-warning mt-2",
          style = "font-size: 0.85rem; padding: 0.5rem;",
          shiny::icon("triangle-exclamation"),
          sprintf(" Multiple L3 regions overlap (%s). Please select one.", 
                  paste(codes, collapse = ", "))
        ))
      }
      
      NULL
    })


    # --- Validation ---
    iv <- shinyvalidate::InputValidator$new()
    iv$add_rule("folder", shinyvalidate::sv_required("Project Folder is required."))
    iv$add_rule("dn_variables", function(value) {
      # Filter out empty strings that may occur during selectizeInput transitions
      valid_vars <- value[nzchar(value)]
      if (is.null(value) || length(valid_vars) == 0) {
        return("Select at least one variable.")
      }
    })
    iv$add_rule("period", function(value) {
      if (isTRUE(input$multi_season)) return(NULL) # Skip for multi-season
      if (length(value) != 2 || any(is.na(value))) return("Select a valid date range.")
      if (value[2] < value[1]) return("End date must be after start date.")
    })
    iv$add_rule("add_season_btn", function(value) {
      if (!isTRUE(input$multi_season)) return(NULL)
      s <- parsed_seasons()
      if (length(s) == 0) return("Add at least one season window.")
      for (i in seq_along(s)) {
        if (as.Date(s[[i]]$end) < as.Date(s[[i]]$start)) {
          return(sprintf("Season '%s' has end date before start date.", s[[i]]$name))
        }
      }
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
      
      # Guard: skip code generation if no variables selected
      if (is.null(input$dn_variables) || length(input$dn_variables) == 0) {
        shinyAce::updateAceEditor(
          session, 
          "code_preview", 
          value = "# Please select at least one variable to generate download code"
        )
        return()
      }
      
      if (is.null(reg)) {
        reg_str <- "NULL  # Please select an AOI on the map or upload a file"
      } else if (is_l3_code(reg)) {
        reg_str <- sprintf("\"%s\"", reg)
      } else if (is.character(reg)) {
        reg_str <- sprintf("\"%s\"", normalizePath(reg, winslash = "/", mustWork = FALSE))
      } else {
        reg_str <- sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
      }

      folder_safe <- normalizePath(input$folder %||% "", winslash = "/", mustWork = FALSE)

      period_str <- if (input$multi_season) {
        s <- parsed_seasons()
        if (length(s) == 0) "list()" else {
          s_lines <- sapply(s, function(x) {
            sprintf("    \"%s\" = c(\"%s\", \"%s\")", x$name, x$start, x$end)
          })
          paste0("list(\n", paste(s_lines, collapse = ",\n"), "\n  )")
        }
      } else {
        sprintf("c(\"%s\", \"%s\")", input$period[1], input$period[2])
      }
      
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
          folder_safe,
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
          folder_safe,
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
            # Resolve period
            current_period <- if (input$multi_season) {
              rows <- shiny::isolate(parsed_seasons())
              if (length(rows) == 0) stop("No valid seasons defined. Check format: Label, YYYY-MM-DD, YYYY-MM-DD")
              p_list <- lapply(rows, function(r) as.character(c(r$start, r$end)))
              names(p_list) <- sapply(rows, function(r) r$name)
              p_list
            } else {
              as.character(input$period)
            }

            # Dual-stage if both selected
            if (isTRUE(input$seasonal) && isTRUE(input$separate_files)) {
              shiny::incProgress(0, detail = sprintf("Stage 1 of 2: Individual files for %s...", v))
              out_path_ind <- Rwapor::wapor_map(
                region = reg,
                variable = v,
                period = current_period,
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
                period = current_period,
                folder = input$folder,
                unit_conversion = unit_conv,
                seasonal = TRUE,
                separate_files = FALSE,
                mask = aoi$mask()
              )
              out_path <- c(unlist(out_path_ind), unlist(out_path_sea))
            } else {
              out_path <- Rwapor::wapor_map(
                region = reg,
                variable = v,
                period = current_period,
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



    # --- Console Actions ---
    shiny::observeEvent(input$dn_copy_code, {
      code <- input$code_preview
      if (is.null(code) || !nzchar(code)) return()
      shinyjs::runjs(sprintf("navigator.clipboard.writeText(%s);", jsonlite::toJSON(code, auto_unbox = TRUE)))
      shiny::showNotification("Code copied to clipboard", type = "message", duration = 3)
    })

    shiny::observeEvent(input$dn_export_script, {
      code <- input$code_preview
      if (is.null(code) || !nzchar(code)) return()
      
      folder <- input$folder %||% getwd()
      if (!dir.exists(folder)) dir.create(folder, recursive = TRUE, showWarnings = FALSE)
      
      filename <- sprintf("wapor_download_%s.R", format(Sys.time(), "%Y%m%d_%H%M%S"))
      path <- file.path(folder, filename)
      
      tryCatch({
        writeLines(code, path)
        shiny::showNotification(sprintf("Script exported to: %s", path), type = "message", duration = 8)
      }, error = function(e) {
        shiny::showNotification(paste("Export failed:", e$message), type = "error")
      })
    })

    list(
      region  = current_region,
      folder  = shiny::reactive(input$folder),
      seasons = shiny::reactive({
        if (!isTRUE(input$multi_season)) return(list())
        rows <- parsed_seasons()
        if (length(rows) == 0) return(list())
        stats::setNames(
          lapply(rows, function(r) as.character(c(r$start, r$end))),
          sapply(rows, function(r) r$name)
        )
      })
    )
  })
}
