# mod_analysis.R
# Seasonal analysis workflow.

mod_analysis_ui <- function(id, all_vars, l3_region_choices) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 360,
      open = TRUE,
      title = "Crop Season Analysis",
      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id = ns("analysis_config_accordion"),
          open = c("Season Definition", "Data Inputs"),
          bslib::accordion_panel(
            "Season Definition",
            icon = shiny::icon("calendar"),
            shiny::textInput(
              ns("an_season_label"),
              "Season Label",
              value = "Winter 2023",
              placeholder = "e.g. Winter 2023"
            ),
            shiny::fluidRow(
              shiny::column(
                5,
                shiny::numericInput(
                  ns("an_ref_year"),
                  "Ref. Year",
                  value = 2023,
                  min = 2009,
                  max = 2030,
                  step = 1
                )
              ),
              shiny::column(
                7,
                shiny::dateRangeInput(
                  ns("an_period"),
                  "Analysis Period",
                  start = "2023-01-01",
                  end = "2023-12-31",
                  format = "yyyy-mm-dd"
                )
              )
            )
          ),
          bslib::accordion_panel(
            "Data Source",
            icon = shiny::icon("database"),
            shiny::radioButtons(
              ns("an_data_source"),
              "Get WaPOR data from:",
              choices = c(
                "Stream from API (requires internet)" = "api",
                "Use local downloaded files (offline)" = "local"
              ),
              selected = "api"
            ),
            shiny::helpText(
              class = "text-muted small",
              "Streaming uses GDAL vsicurl to read only the required pixels from Cloud-Optimized GeoTIFFs on the WaPOR server."
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'local'", ns("an_data_source")),
              shiny::tags$div(
                class = "alert alert-info p-2 mb-2",
                shiny::icon("info-circle"),
                " Using local files from the Download folder. Make sure you've downloaded the required variables first."
              ),
              shiny::actionButton(
                ns("an_scan_local"),
                "Scan Local Folder",
                icon = shiny::icon("magnifying-glass"),
                class = "btn-sm btn-outline-primary w-100 mb-2"
              ),
              shiny::verbatimTextOutput(ns("an_local_vars_info"))
            )
          ),
          bslib::accordion_panel(
            "Data Inputs",
            icon = shiny::icon("upload"),
            shiny::checkboxInput(ns("an_use_crop_mask"), "Use a crop mask raster?", value = FALSE),
            shiny::conditionalPanel(
              condition = sprintf("input['%s']", ns("an_use_crop_mask")),
              shiny::fileInput(ns("an_crop_mask"), "Crop Mask", accept = c(".tif", ".tiff")),
              shiny::helpText(
                class = "text-muted small",
                "Upload a GeoTIFF with integer class values (1, 2, 3, etc.)"
              )
            ),
            shiny::checkboxInput(ns("an_use_season_rasters"), "Use pixel-wise season start/end rasters?", value = FALSE),
            shiny::conditionalPanel(
              condition = sprintf("input['%s']", ns("an_use_season_rasters")),
              shiny::fluidRow(
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_season_start"), "Season Start (DOY)", accept = c(".tif", ".tiff"))
                ),
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_season_end"), "Season End (DOY)", accept = c(".tif", ".tiff"))
                )
              ),
              shiny::helpText(
                class = "text-muted small",
                "GeoTIFFs with Julian Day of Year values (1-366). For cross-year seasons, end DOY can exceed 366."
              )
            ),
          shiny::hr(),
            shiny::fluidRow(
              shiny::column(
                6,
                shiny::selectInput(
                  ns("an_aeti_var"),
                  "AETI",
                  choices = grep("AETI-D", all_vars, value = TRUE),
                  selected = if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else NULL
                )
              ),
              shiny::column(
                6,
                shiny::selectInput(
                  ns("an_ret_var"),
                  "RET",
                  choices = grep("RET|ET0", all_vars, value = TRUE),
                  selected = if ("L1-RET-D" %in% all_vars) "L1-RET-D" else NULL
                )
              )
            ),
            shiny::fluidRow(
              shiny::column(
                6,
                shiny::selectInput(
                  ns("an_precip_var"),
                  "Precip",
                  choices = grep("PCP|PF", all_vars, value = TRUE),
                  selected = if ("L1-PCP-D" %in% all_vars) "L1-PCP-D" else NULL
                )
              ),
              shiny::column(
                6,
                shiny::selectInput(
                  ns("an_npp_var"),
                  "NPP",
                  choices = grep("NPP|TBP", all_vars, value = TRUE),
                  selected = if ("L1-NPP-D" %in% all_vars) "L1-NPP-D" else NULL
                )
              )
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && input['%s'].startsWith('L3-')", ns("an_aeti_var"), ns("an_aeti_var")),
              shiny::selectInput(ns("an_l3_region"), "L3 Region", choices = l3_region_choices)
            )
          ),
          bslib::accordion_panel(
            "Crop Classes",
            icon = shiny::icon("seedling"),
            shiny::helpText("Upload crop mask first, then assign profiles per class."),
            shiny::uiOutput(ns("an_crop_class_ui"))
          ),
          bslib::accordion_panel(
            "Indicators",
            icon = shiny::icon("chart-line"),
            shiny::tags$p(
              shiny::tags$strong("Seasonal Aggregation"),
              style = "font-size:0.8rem; color:#2c3e50; margin-bottom:2px;"
            ),
            shiny::tags$small(
              class = "text-muted d-block mb-1",
              "Select which variables to aggregate over the season."
            ),
            shiny::checkboxGroupInput(
              ns("an_agg_vars"),
              NULL,
              choiceNames = list(
                "AETI  (Actual ET)",
                "RET   (Reference ET)",
                "PCP   (Precipitation)",
                "Peff  (Effective Precip, USDA)",
                "Biomass (Total Production)"
              ),
              choiceValues = list("agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "agg_biomass"),
              selected = c("agg_aeti", "agg_ret", "agg_biomass")
            ),
            shiny::hr(style = "margin:4px 0;"),
            shiny::tags$p(
              shiny::tags$strong("Derived Indicators"),
              style = "font-size:0.8rem; color:#2c3e50; margin-bottom:2px;"
            ),
            shiny::checkboxGroupInput(
              ns("an_derived_vars"),
              NULL,
              choiceNames = list(
                "ETc  (RET x Kc)",
                "Adequacy - ETc",
                "Adequacy - P95",
                "CWP / BWP",
                "Yield (NPP-based)"
              ),
              choiceValues = list("etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "yield_npp"),
              selected = c("etc", "adequacy_etc", "yield_npp")
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && (input['%s'].indexOf('cwp_bwp') > -1 || input['%s'].indexOf('agg_biomass') > -1 || input['%s'].indexOf('yield_npp') > -1)", 
                                  ns("an_derived_vars"), ns("an_derived_vars"), ns("an_agg_vars"), ns("an_derived_vars")),
              shiny::fluidRow(
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_yield_file"), "Optional Yield Raster", accept = c(".tif", ".tiff")),
                  shiny::selectInput(ns("an_yield_unit"), "Yield Unit", choices = c("kg/ha", "t/ha"), selected = "t/ha")
                ),
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_biomass_file"), "Optional Biomass Raster", accept = c(".tif", ".tiff")),
                  shiny::selectInput(ns("an_biomass_unit"), "Biomass Unit", choices = c("kg/ha", "t/ha"), selected = "t/ha")
                )
              )
            )
          ),
          bslib::accordion_panel(
            "Output Settings",
            icon = shiny::icon("folder"),
            shiny::fluidRow(
              shiny::column(
                8,
                shiny::div(
                  style = "display: flex; align-items: flex-end; gap: 5px;",
                  shiny::div(
                    style = "flex: 1;",
                    shiny::textInput(
                      ns("an_folder"),
                      "Output Folder",
                      value = file.path(getwd(), "analysis_output")
                    )
                  ),
                  shiny::uiOutput(ns("an_favorite_btn_ui"))
                )
              ),
              shiny::column(
                4,
                shinyFiles::shinyDirButton(
                  ns("an_browse_folder"),
                  "Browse",
                  "Select output directory",
                  width = "100%",
                  class = "mt-4"
                )
              )
            ),
            shiny::uiOutput(ns("an_favorites_ui")),
            shiny::checkboxInput(ns("an_save_rasters"), "Save Analysis Rasters to Folder", value = TRUE)
          )
        )
        ),
      shiny::div(
        class = "sidebar-sticky-footer",
        shiny::fluidRow(
          shiny::column(
            4,
            shiny::actionButton(
              ns("an_validate_btn"),
              "Validate",
              class = "btn-sm btn-outline-primary w-100",
              icon = shiny::icon("check-circle")
            )
          ),
          shiny::column(
            4,
            shiny::actionButton(
              ns("an_run_btn"),
              "Run",
              class = "btn-sm btn-primary w-100",
              icon = shiny::icon("play")
            )
          ),
          shiny::column(
            4,
            shiny::actionButton(
              ns("an_reset_btn"),
              "Reset",
              class = "btn-sm btn-outline-danger w-100",
              icon = shiny::icon("rotate-left")
            )
          )
        )
      )
    ),
    bslib::layout_column_wrap(
      width = 1,
      gap = "1rem",
      bslib::card(
        full_screen = TRUE,
        bslib::card_header(
          shiny::icon("circle-info"), " Season & Data Summary"
        ),
        bslib::card_body(
          padding = 0,
          bslib::layout_column_wrap(
            width = "300px",
            fixed_height = TRUE,
            shiny::div(
              style = "padding: 0.5rem; font-size: 0.85rem; border-right: 1px solid #eee;",
              shiny::verbatimTextOutput(ns("an_season_summary"))
            ),
            shiny::div(
              style = "padding: 0.5rem;",
              bslib::layout_column_wrap(
                width = "180px",
                fill = FALSE,
                bslib::value_box(
                  title = "AETI",
                  value = shiny::textOutput(ns("vbox_aeti")),
                  showcase = shiny::icon("droplet", class = "text-primary"),
                  theme = "light",
                  class = "border-primary py-1"
                ),
                bslib::value_box(
                  title = "ETc",
                  value = shiny::textOutput(ns("vbox_etc")),
                  showcase = shiny::icon("sun", class = "text-info"),
                  theme = "light",
                  class = "border-info py-1"
                ),
                bslib::value_box(
                  title = "Adequacy",
                  value = shiny::textOutput(ns("vbox_adequacy")),
                  showcase = shiny::icon("percent", class = "text-success"),
                  theme = "light",
                  class = "border-success py-1"
                ),
                bslib::value_box(
                  title = "Biomass",
                  value = shiny::textOutput(ns("vbox_biomass")),
                  showcase = shiny::icon("leaf", class = "text-warning"),
                  theme = "light",
                  class = "border-warning py-1"
                )
              )
            )
          )
        )
      ),
      bslib::layout_column_wrap(
        width = "400px",
        bslib::navset_card_tab(
          title = "Spatial Data",
          bslib::nav_panel("Crop Mask", shiny::plotOutput(ns("an_crop_mask_plot"), height = "300px")),
          bslib::nav_panel("Season", shiny::verbatimTextOutput(ns("an_season_raster_info"))),
          bslib::nav_panel("Classes", shiny::tableOutput(ns("an_crop_class_table")))
        ),
        bslib::card(
          bslib::card_header(shiny::icon("chart-area"), " Kc Curves by Class"),
          bslib::card_body(
            padding = 1,
            shiny::plotOutput(ns("an_kc_plot"), height = "300px")
          )
        )
      ),
      bslib::navset_card_tab(
        title = "Detailed Analysis Results",
        bslib::nav_panel("Main Results", shiny::tableOutput(ns("an_etc_aeti_table"))),
        bslib::nav_panel("Adequacy", shiny::tableOutput(ns("an_adequacy_table"))),
        bslib::nav_panel("Eff. Precip", shiny::tableOutput(ns("an_peff_table"))),
        bslib::nav_panel("CWP/BWP", shiny::tableOutput(ns("an_cwp_bwp_table")))
      ),
      bslib::card(
        bslib::card_header(shiny::icon("download"), " Export & Reproducibility"),
        bslib::card_body(
          shiny::fluidRow(
            shiny::column(
              4,
              shiny::downloadButton(ns("an_dl_crop_params"), "Params CSV", class = "btn-outline-primary w-100 btn-sm")
            ),
            shiny::column(
              4,
              shiny::downloadButton(ns("an_dl_results"), "Results CSV", class = "btn-outline-primary w-100 btn-sm")
            ),
            shiny::column(
              4,
              shiny::downloadButton(ns("an_dl_peff"), "Peff CSV", class = "btn-outline-primary w-100 btn-sm")
            )
          ),
          shiny::hr(),
          shiny::checkboxInput(ns("an_incremental"), "Memory Optimization (Incremental Sum)", value = FALSE),
          shiny::helpText("Recommended for very long seasons or low-RAM systems (e.g. 8GB)."),
          shiny::hr(),
          shiny::fluidRow(
            shiny::column(
              6,
              shiny::actionButton(ns("an_validate_btn"), "Validate Inputs", class = "btn-outline-secondary w-100 mb-1")
            ),
            shiny::column(
              6,
              shiny::tags$button(
                class = "btn btn-sm btn-outline-secondary w-100",
                `data-bs-toggle` = "collapse",
                `data-bs-target` = sprintf("#%s", ns("anCodePreviewCollapse")),
                shiny::icon("code"), " Toggle R Code Preview"
              )
            )
          ),
          shiny::div(
            id = ns("anCodePreviewCollapse"),
            class = "collapse mt-2",
            shinyAce::aceEditor(
              ns("an_code_preview"),
              mode = "r", theme = "monokai", readOnly = TRUE,
              height = "200px", fontSize = 11
            )
          )
        )
      )
    )
  )
}

mod_analysis_server <- function(id, global_folder, aoi_region) {
  shiny::moduleServer(id, function(input, output, session) {
    # Phase 2: Missing data state
    temp_missing_info <- shiny::reactiveVal(NULL)
    
    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::rwapor_get_favorites())
    
    output$an_favorite_btn_ui <- shiny::renderUI({
      path <- input$an_folder %||% ""
      is_fav <- Rwapor::rwapor_is_favorite(path)
      
      shiny::actionLink(
        session$ns("an_favorite_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star-fill", style = "color: #ffc107;") else shiny::icon("star"),
        style = "margin-bottom: 11px; font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$an_favorite_btn, {
      path <- input$an_folder %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::rwapor_is_favorite(path)) {
        Rwapor::rwapor_remove_favorite(path)
      } else {
        Rwapor::rwapor_add_favorite(path, type = "directory")
      }
      favs(Rwapor::rwapor_get_favorites())
    })
    
    output$an_favorites_ui <- shiny::renderUI({
      f <- favs()
      f_dirs <- f[f$type == "directory", "path"]
      if (length(f_dirs) == 0) return(NULL)
      
      shiny::selectizeInput(
        session$ns("an_quick_fav"),
        NULL,
        choices = c("Quick Access Favorites..." = "", f_dirs),
        options = list(placeholder = "Select a favorite analysis folder")
      )
    })
    
    shiny::observeEvent(input$an_quick_fav, {
      path <- input$an_quick_fav
      if (nzchar(path)) {
        shiny::updateTextInput(session, "an_folder", value = path)
      }
    })
    
    # --- NEW: Observer for Missing Data Download Button ---
    shiny::observeEvent(input$an_download_missing_btn, {
      missing_info <- temp_missing_info()
      folder <- global_folder()
      shiny::removeModal()
      
      if (is.null(missing_info) || length(missing_info) == 0) return()
      
      # Determine if we should mask based on analysis setting
      do_mask <- isTRUE(input$an_use_crop_mask)
      
      shiny::withProgress(message = "Downloading Missing Data", value = 0, {
        tryCatch({
          # Resolve extent: AOI > Crop Mask
          reg <- aoi_region()
          if (is.null(reg)) {
            cm <- an_crop_mask_rast()
            if (!is.null(cm)) {
              shiny::incProgress(0.05, detail = "Resolving extent from crop mask...")
              cm_ext <- terra::ext(cm)
              cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(cm))
              cm_poly_4326 <- Rwapor::safe_project(cm_poly, "EPSG:4326")
              e <- terra::ext(cm_poly_4326)
              reg <- c(e$xmin, e$ymin, e$xmax, e$ymax)
            }
          }
          
          if (is.null(reg)) {
            stop("Could not resolve an AOI or Crop Mask extent for the download.")
          }
          
          vars <- names(missing_info)
          for (i in seq_along(vars)) {
            v <- vars[i]
            dates <- missing_info[[v]]
            period_v <- c(as.character(dates[1]), as.character(dates[length(dates)]))
            
            shiny::incProgress(0.1 + (0.8 * i/length(vars)), detail = sprintf("Downloading %s...", v))
            
            Rwapor::wapor_map(
                variable = v,
                period = period_v,
                region = reg,
                mask = do_mask,
                folder = folder,
                separate_files = TRUE
            )
          }
          
          # Refresh local variables list automatically
          shiny::incProgress(0.95, detail = "Refreshing local database...")
          new_vars <- Rwapor::rwapor_scan_local_variables(folder)
          an_local_vars(new_vars)
          
          shiny::showNotification(
            sprintf("Download complete! Files saved in their respective subfolders within: %s. Project folder re-scanned.", folder), 
            type = "message", 
            duration = 20
          )
        }, error = function(e) {
          shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
        })
      })
    })

    ns <- session$ns
    # Cross-platform roots for shinyFiles
    roots <- if (.Platform$OS.type == "windows") {
      c(shinyFiles::getVolumes()(), Project = getwd())
    } else {
      c(Home = normalizePath("~", winslash = "/"), Root = "/", Project = getwd())
    }
    
    shinyFiles::shinyDirChoose(input, "an_browse_folder", roots = roots, session = session)
    shiny::observeEvent(input$an_browse_folder, {
      dir_path <- shinyFiles::parseDirPath(roots, input$an_browse_folder)
      if (length(dir_path) == 1 && nzchar(dir_path)) {
        shiny::updateTextInput(session, "an_folder", value = dir_path)
      }
    })

    # Sync with global folder from Download tab
    shiny::observe({
      folder <- global_folder()
      if (!is.null(folder) && nzchar(folder) && !nzchar(input$an_folder)) {
        shiny::updateTextInput(session, "an_folder", value = folder)
      }
    })
    an_crop_mask_rast <- shiny::reactiveVal(NULL)
    an_start_rast <- shiny::reactiveVal(NULL)
    an_end_rast <- shiny::reactiveVal(NULL)
    an_crop_classes <- shiny::reactiveVal(NULL)
    an_crop_params <- shiny::reactiveVal(NULL)
    an_results <- shiny::reactiveVal(NULL)
    an_peff_monthly <- shiny::reactiveVal(NULL)
    an_local_vars <- shiny::reactiveVal(NULL)

    # --- File Upload Observers ---
    shiny::observeEvent(input$an_crop_mask, {
      f <- input$an_crop_mask
      shiny::req(f)
      tryCatch({
        r <- terra::rast(f$datapath)
        an_crop_mask_rast(r)
        
        # Auto-detect L3 region if an L3 variable is selected or potentially selected
        aeti_v <- input$an_aeti_var
        if (!is.null(aeti_v) && startsWith(aeti_v, "L3-")) {
          shiny::withProgress(message = "Detecting Level 3 region...", value = 0.5, {
            reg_info <- Rwapor::parse_region(f$datapath)
            period <- as.character(input$an_period)
            intersecting <- Rwapor::guess_l3_region(aeti_v, reg_info, period)
            
            if (length(intersecting) > 0) {
              shiny::updateSelectInput(session, "an_l3_region", selected = intersecting[1])
              shiny::showNotification(
                sprintf("Automatically matched crop mask to L3 region: %s", intersecting[1]),
                type = "message"
              )
            }
          })
        }
      }, error = function(e) shiny::showNotification(paste("Error loading crop mask:", e$message), type = "error"))
    })

    shiny::observeEvent(input$an_season_start, {
      f <- input$an_season_start
      shiny::req(f)
      tryCatch({
        r <- terra::rast(f$datapath)
        an_start_rast(r)
      }, error = function(e) shiny::showNotification(paste("Error loading season start:", e$message), type = "error"))
    })

    shiny::observeEvent(input$an_season_end, {
      f <- input$an_season_end
      shiny::req(f)
      tryCatch({
        r <- terra::rast(f$datapath)
        an_end_rast(r)
      }, error = function(e) shiny::showNotification(paste("Error loading season end:", e$message), type = "error"))
    })

    # --- Local Data Source Logic ---
    shiny::observeEvent(input$an_scan_local, {
      folder <- global_folder()
      if (is.null(folder) || !nzchar(folder)) {
        shiny::showNotification(
          "No download folder set. Please configure the output folder in the Download tab first.",
          type = "error"
        )
        return()
      }

      if (!dir.exists(folder)) {
        shiny::showNotification(
          sprintf("Folder does not exist: %s", folder),
          type = "error"
        )
        return()
      }

      tryCatch({
        local_vars <- Rwapor::rwapor_scan_local_variables(folder)
        an_local_vars(local_vars)

        if (nrow(local_vars) == 0) {
          shiny::showNotification(
            "No WaPOR variable folders found. Download data first using the Download tab.",
            type = "warning"
          )
        } else {
          shiny::showNotification(
            sprintf("Found %d variable(s) with local data.", nrow(local_vars)),
            type = "message"
          )

          # Update variable dropdowns with available local variables
          aeti_vars <- local_vars$variable[grepl("AETI", local_vars$variable)]
          ret_vars <- local_vars$variable[grepl("RET|ET0", local_vars$variable)]
          precip_vars <- local_vars$variable[grepl("PCP|PF", local_vars$variable)]
          npp_vars <- local_vars$variable[grepl("NPP|TBP", local_vars$variable)]

          if (length(aeti_vars) > 0) {
            shiny::updateSelectInput(session, "an_aeti_var",
              choices = aeti_vars,
              selected = aeti_vars[1]
            )
          }
          if (length(ret_vars) > 0) {
            shiny::updateSelectInput(session, "an_ret_var",
              choices = ret_vars,
              selected = ret_vars[1]
            )
          }
          if (length(precip_vars) > 0) {
            shiny::updateSelectInput(session, "an_precip_var",
              choices = precip_vars,
              selected = precip_vars[1]
            )
          }
          if (length(npp_vars) > 0) {
            shiny::updateSelectInput(session, "an_npp_var",
              choices = npp_vars,
              selected = npp_vars[1]
            )
          }

          # Auto-update date range based on available data
          if (nrow(local_vars) > 0) {
            all_min <- min(as.Date(local_vars$min_date[!is.na(local_vars$min_date)]), na.rm = TRUE)
            all_max <- max(as.Date(local_vars$max_date[!is.na(local_vars$max_date)]), na.rm = TRUE)
            if (!is.na(all_min) && !is.na(all_max)) {
              shiny::updateDateRangeInput(session, "an_period",
                start = all_min,
                end = all_max
              )
            }
          }
        }
      }, error = function(e) {
        shiny::showNotification(
          paste("Error scanning folder:", e$message),
          type = "error"
        )
      })
    })

    output$an_local_vars_info <- shiny::renderPrint({
      local_vars <- an_local_vars()
      folder <- global_folder()

      if (is.null(folder) || !nzchar(folder)) {
        cat("Download folder not set.\n")
        cat("Configure it in the Download tab.\n")
        return()
      }

      cat("Folder:", folder, "\n\n")

      if (is.null(local_vars)) {
        cat("Click 'Scan Local Folder' to detect available variables.\n")
        return()
      }

      if (nrow(local_vars) == 0) {
        cat("No WaPOR variables found.\n")
        cat("Download data first using the Download tab.\n")
        return()
      }

      cat("=== Available Local Variables ===\n\n")
      for (i in seq_len(nrow(local_vars))) {
        v <- local_vars[i, ]
        cat(sprintf("%s:\n", v$variable))
        cat(sprintf("  Files: %d\n", v$file_count))
        if (!is.na(v$min_date) && !is.na(v$max_date)) {
          cat(sprintf("  Date range: %s to %s\n", v$min_date, v$max_date))
        }
        cat("\n")
      }
    })

    # --- Validation ---
    iv <- shinyvalidate::InputValidator$new()
    iv$add_rule("an_ref_year", shinyvalidate::sv_required())
    iv$add_rule("an_ref_year", shinyvalidate::sv_between(2000, 2030))
    iv$add_rule("an_period", function(value) {
      if (length(value) != 2 || any(is.na(value))) return("Select a valid date range.")
      if (value[2] < value[1]) return("End date must be after start date.")
    })
    iv$add_rule("an_aeti_var", shinyvalidate::sv_required())
    iv$add_rule("an_ret_var", shinyvalidate::sv_required())
    iv$add_rule("an_crop_mask", function(value) {
      if (isTRUE(input$an_use_crop_mask) && is.null(value)) "Crop mask is required when enabled."
    })
    iv$add_rule("an_season_start", function(value) {
      if (isTRUE(input$an_use_season_rasters) && is.null(value)) "Season start raster is required when enabled."
    })
    iv$add_rule("an_season_end", function(value) {
      if (isTRUE(input$an_use_season_rasters) && is.null(value)) "Season end raster is required when enabled."
    })
    iv$enable()

    # Control run button state
    shiny::observe({
      shinyjs::toggleState("an_run_btn", condition = iv$is_valid())
    })

    # --- Value Box Renderers ---
    output$vbox_aeti <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || is.null(res$seasonal_aeti)) return("--")
      # Extract mean value from raster
      val <- terra::global(res$seasonal_aeti$raster, fun = "mean", na.rm = TRUE)$mean
      sprintf("%.1f mm", val)
    })

    output$vbox_etc <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || is.null(res$etc_by_class)) return("--")
      # Simplified: Mean of first available class or overall mean if possible
      all_etc <- lapply(res$etc_by_class, function(x) terra::global(x$etc_seasonal, "mean", na.rm = TRUE)$mean)
      val <- mean(unlist(all_etc), na.rm = TRUE)
      sprintf("%.1f mm", val)
    })

    output$vbox_adequacy <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || (is.null(res$adequacy_etc) && is.null(res$adequacy_p95))) return("--")
      adq_rast <- res$adequacy_etc %||% res$adequacy_p95
      val <- terra::global(adq_rast, "mean", na.rm = TRUE)$mean
      sprintf("%.0f%%", val * 100)
    })

    output$vbox_biomass <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || (is.null(res$biomass) && is.null(res$seasonal_biomass))) return("--")
      # Use seasonal_biomass if available (it's the raster), otherwise fallback to biomass component
      bio_rast <- res$seasonal_biomass %||% res$biomass
      val <- terra::global(bio_rast, "mean", na.rm = TRUE)$mean
      unit <- input$an_biomass_unit %||% "kg/ha"
      if (unit == "t/ha") val <- val / 1000
      sprintf("%.1f %s", val, unit)
    })

    current_region <- shiny::reactive(aoi_region())

    shiny::observeEvent(input$an_crop_mask, {
      shiny::req(input$an_crop_mask)
      file_path <- input$an_crop_mask$datapath
      file_name <- input$an_crop_mask$name

      # Validate file exists
      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Uploaded file not found: %s", file_name),
          type = "error"
        )
        an_crop_mask_rast(NULL)
        an_crop_classes(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::rwapor_load_crop_mask(file_path)

        # Validate raster is not empty
        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Crop mask raster is empty or invalid.", type = "error")
          an_crop_mask_rast(NULL)
          an_crop_classes(NULL)
          return()
        }

        an_crop_mask_rast(r)
        classes <- Rwapor::rwapor_extract_crop_classes(r)

        # Check if any valid classes were found
        if (is.null(classes) || nrow(classes) == 0) {
          shiny::showNotification(
            "No valid crop classes found in mask. Check if your raster contains valid class values (not just 0, 255, or nodata).",
            type = "warning",
            duration = 10
          )
          # Create a default single class
          classes <- data.frame(class_value = 1L, pixel_count = NA_integer_, area_ha = NA_real_)
        }

        an_crop_classes(classes)
        an_crop_params(Rwapor::rwapor_build_crop_assignment_table(classes$class_value))
        shiny::showNotification(
          sprintf("Crop mask loaded: %d class(es) found. File: %s", nrow(classes), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading crop mask:", e$message), type = "error")
        an_crop_mask_rast(NULL)
        an_crop_classes(NULL)
      })
    })

    shiny::observeEvent(input$an_season_start, {
      shiny::req(input$an_season_start)
      file_path <- input$an_season_start$datapath
      file_name <- input$an_season_start$name

      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Season start file not found: %s", file_name),
          type = "error"
        )
        an_start_rast(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::rwapor_load_season_raster(file_path)

        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Season start raster is empty or invalid.", type = "error")
          an_start_rast(NULL)
          return()
        }

        # Validate DOY values are reasonable
        vals <- terra::values(r, na.rm = TRUE)
        if (length(vals) == 0) {
          shiny::showNotification("Season start raster contains no valid data.", type = "error")
          an_start_rast(NULL)
          return()
        }

        min_val <- min(vals)
        max_val <- max(vals)

        if (min_val < 1 || max_val > 730) {
          shiny::showNotification(
            sprintf("Season start DOY values (%d-%d) seem unusual. Expected 1-366 (or up to 730 for cross-year).",
                    as.integer(min_val), as.integer(max_val)),
            type = "warning",
            duration = 8
          )
        }

        an_start_rast(r)
        shiny::showNotification(
          sprintf("Season start loaded: DOY range %d-%d. File: %s",
                  as.integer(min_val), as.integer(max_val), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading season start:", e$message), type = "error")
        an_start_rast(NULL)
      })
    })

    shiny::observeEvent(input$an_season_end, {
      shiny::req(input$an_season_end)
      file_path <- input$an_season_end$datapath
      file_name <- input$an_season_end$name

      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Season end file not found: %s", file_name),
          type = "error"
        )
        an_end_rast(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::rwapor_load_season_raster(file_path)

        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Season end raster is empty or invalid.", type = "error")
          an_end_rast(NULL)
          return()
        }

        # Validate DOY values are reasonable
        vals <- terra::values(r, na.rm = TRUE)
        if (length(vals) == 0) {
          shiny::showNotification("Season end raster contains no valid data.", type = "error")
          an_end_rast(NULL)
          return()
        }

        min_val <- min(vals)
        max_val <- max(vals)

        if (min_val < 1 || max_val > 730) {
          shiny::showNotification(
            sprintf("Season end DOY values (%d-%d) seem unusual. Expected 1-366 (or up to 730 for cross-year).",
                    as.integer(min_val), as.integer(max_val)),
            type = "warning",
            duration = 8
          )
        }

        an_end_rast(r)
        shiny::showNotification(
          sprintf("Season end loaded: DOY range %d-%d. File: %s",
                  as.integer(min_val), as.integer(max_val), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading season end:", e$message), type = "error")
        an_end_rast(NULL)
      })
    })

    # Auto-update analysis period from season rasters
    shiny::observe({
      shiny::req(isTRUE(input$an_use_season_rasters))
      s_start <- an_start_rast()
      s_end <- an_end_rast()
      shiny::req(s_start, s_end)
      shiny::req(input$an_ref_year)

      tryCatch({
        vals_start <- terra::values(s_start, na.rm = TRUE)
        vals_end <- terra::values(s_end, na.rm = TRUE)
        if (length(vals_start) > 0 && length(vals_end) > 0) {
          min_doy <- min(vals_start)
          max_doy <- max(vals_end)

          ref_year <- input$an_ref_year
          year_length <- ifelse(lubridate::leap_year(ref_year), 366L, 365L)

          # Handle cross-year seasons properly
          # If max_doy > year_length, it's already in continuous Julian format
          # If min_doy > max_doy, the season crosses the year boundary
          is_cross_year <- (min_doy > max_doy) && (max_doy <= year_length)

          if (is_cross_year) {
            # Season crosses year boundary (e.g., Oct-Jan: start=280, end=30)
            # Convert end DOY to continuous format
            max_doy <- max_doy + year_length
            shiny::showNotification(
              sprintf("Cross-year season detected: DOY %d (year %d) to DOY %d (year %d).",
                      as.integer(min_doy), ref_year, as.integer(max_doy - year_length), ref_year + 1),
              type = "message",
              duration = 6
            )
          }

          date_start <- as.Date(sprintf("%04d-01-01", ref_year)) + (min_doy - 1)
          date_end <- as.Date(sprintf("%04d-01-01", ref_year)) + (max_doy - 1)

          # Validate dates are reasonable
          if (date_end > as.Date(sprintf("%04d-12-31", ref_year + 1))) {
            shiny::showNotification(
              "Season end date exceeds reasonable range. Please check your season raster values.",
              type = "warning"
            )
          }

          # Only update if different to avoid circularity
          current_period <- as.character(input$an_period)
          new_period <- as.character(c(date_start, date_end))
          if (!identical(current_period, new_period)) {
            shiny::updateDateRangeInput(session, "an_period", start = date_start, end = date_end)
          }
        }
      }, error = function(e) {
        # Silently handle errors to avoid interrupting the user
        message("Auto-update of analysis period failed: ", e$message)
      })
    })

    # Validate spatial overlap between crop mask and season rasters
    shiny::observe({
      cm <- an_crop_mask_rast()
      ss <- an_start_rast()
      se <- an_end_rast()

      # Only validate when we have both crop mask and at least one season raster
      if (is.null(cm) || (is.null(ss) && is.null(se))) return()

      tryCatch({
        cm_ext <- terra::ext(cm)
        check_rast <- ss %||% se

        if (!is.null(check_rast)) {
          check_ext <- terra::ext(check_rast)

          # Check for overlap
          has_overlap <- !(cm_ext$xmax <= check_ext$xmin || cm_ext$xmin >= check_ext$xmax ||
                          cm_ext$ymax <= check_ext$ymin || cm_ext$ymin >= check_ext$ymax)

          if (!has_overlap) {
            shiny::showNotification(
              "Warning: Crop mask and season rasters don't appear to overlap spatially. Please ensure all input rasters cover the same geographic area.",
              type = "warning",
              duration = 10
            )
          }
        }
      }, error = function(e) {
        # Silently ignore validation errors
      })
    })

    # Handle optional crop mask defaults and state transitions
    shiny::observe({
      use_mask <- isTRUE(input$an_use_crop_mask)

      if (!use_mask) {
        # Create a dummy class if no mask is used - treat entire area as single class
        an_crop_classes(data.frame(class_value = 1L, pixel_count = NA_integer_, area_ha = NA_real_))
        an_crop_mask_rast(NULL)
        an_crop_params(Rwapor::rwapor_build_crop_assignment_table(1L))
      } else if (is.null(an_crop_mask_rast())) {
        # Checkbox is checked but no mask uploaded yet - clear classes to force upload
        an_crop_classes(NULL)
        an_crop_params(NULL)
      }
    })

    # Handle optional season rasters defaults - clear when unchecked
    shiny::observe({
      if (!isTRUE(input$an_use_season_rasters)) {
        an_start_rast(NULL)
        an_end_rast(NULL)
      }
    })

    output$an_crop_class_ui <- shiny::renderUI({
      classes <- an_crop_classes()

      # Show different messages based on state
      if (is.null(classes)) {
        if (isTRUE(input$an_use_crop_mask)) {
          return(shiny::tagList(
            shiny::tags$div(
              class = "alert alert-info",
              shiny::icon("info-circle"),
              " Please upload a crop mask raster to define crop classes."
            )
          ))
        } else {
          return(shiny::p("Crop mask disabled - using entire area as single class."))
        }
      }

      if (nrow(classes) == 0) {
        return(shiny::tagList(
          shiny::tags$div(
            class = "alert alert-warning",
            shiny::icon("exclamation-triangle"),
            " No valid classes found in the crop mask. Check your raster values."
          )
        ))
      }

      crop_choices <- c("(Custom)" = "custom", Rwapor::rwapor_list_crops())
      names(crop_choices) <- c("(Custom)", Rwapor::rwapor_list_crops())

      shiny::tagList(lapply(seq_len(nrow(classes)), function(i) {
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
        shiny::tagList(
          shiny::div(
            class = "card p-2 mb-2 bg-light",
            shiny::tags$div(
              style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;",
              shiny::tags$strong(
                if (is.na(classes$pixel_count[i])) {
                  sprintf("Class %d (Default)", cls)
                } else {
                  sprintf("Class %d (%d px, %.1f ha)", cls, classes$pixel_count[i], classes$area_ha[i])
                }
              )
            ),
            shiny::fluidRow(
              shiny::column(
                6,
                shiny::selectInput(ns(paste0(prefix, "profile")), "Profile", choices = crop_choices, width = "100%")
              ),
              shiny::column(
                6,
                shiny::textInput(ns(paste0(prefix, "label")), "Label", value = paste("Class", cls), width = "100%")
              )
            ),
            # FAO-56 Kc Parameters
            shiny::tags$small(class = "text-primary d-block mb-1", "Kc & Stage Lengths"),
            shiny::fluidRow(
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_ini")), "Kc ini", value = 0.3, step = 0.05, width = "100%")),
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_mid")), "Kc mid", value = 1.15, step = 0.05, width = "100%")),
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_end")), "Kc end", value = 0.3, step = 0.05, width = "100%"))
            ),
            shiny::fluidRow(
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_ini")), "Ini(d)", value = 30, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_mid")), "Mid(d)", value = 40, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_late")), "End(d)", value = 30, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "height")), "H(m)", value = 1.0, step = 0.1, width = "100%"))
            ),
            # Production Parameters (NEW)
            shiny::tags$small(class = "text-success d-block mb-1 mt-1", "Production Parameters (Yield/Biomass)"),
            shiny::fluidRow(
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "hi")), "HI", value = 0.45, min = 0, max = 1, step = 0.05, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "mc")), "MC", value = 0.12, min = 0, max = 1, step = 0.05, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "fc")), "fc", value = 1.0, min = 0, step = 0.1, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "aot")), "AOT", value = 0.8, min = 0, max = 1, step = 0.05, width = "100%"))
            )
          )
        )
      }))
    })

    shiny::observe({
      classes <- an_crop_classes()
      shiny::req(classes)

      for (i in seq_len(nrow(classes))) {
        local({
          cls <- classes$class_value[i]
          prefix <- paste0("an_cls_", cls, "_")
          profile_id <- paste0(prefix, "profile")

          shiny::observeEvent(input[[profile_id]], {
            profile_name <- input[[profile_id]]
            if (!is.null(profile_name) && profile_name != "custom") {
              defaults <- Rwapor::rwapor_get_crop_defaults(profile_name)
              if (!is.null(defaults)) {
                shiny::updateTextInput(session, paste0(prefix, "label"), value = defaults$crop_name)
                shiny::updateNumericInput(session, paste0(prefix, "kc_ini"), value = defaults$Kc_ini)
                shiny::updateNumericInput(session, paste0(prefix, "kc_mid"), value = defaults$Kc_mid)
                shiny::updateNumericInput(session, paste0(prefix, "kc_end"), value = defaults$Kc_end)
                shiny::updateNumericInput(session, paste0(prefix, "l_ini"), value = defaults$L_ini_days)
                shiny::updateNumericInput(session, paste0(prefix, "l_mid"), value = defaults$L_mid_days)
                shiny::updateNumericInput(session, paste0(prefix, "l_late"), value = defaults$L_late_days)
                shiny::updateNumericInput(session, paste0(prefix, "height"), value = defaults$max_height_m)
                shiny::updateNumericInput(session, paste0(prefix, "hi"), value = defaults$HI)
                shiny::updateNumericInput(session, paste0(prefix, "mc"), value = defaults$MC)
                shiny::updateNumericInput(session, paste0(prefix, "fc"), value = defaults$fc)
                shiny::updateNumericInput(session, paste0(prefix, "aot"), value = defaults$AOT)
              }
            }
          }, ignoreInit = TRUE)
        })
      }
    })

    collect_crop_params <- function() {
      classes <- an_crop_classes()
      if (is.null(classes)) return(NULL)

      rows <- lapply(seq_len(nrow(classes)), function(i) {
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
          data.frame(
            class_value = cls,
            crop_label = null_default(input[[paste0(prefix, "label")]], paste("Class", cls)),
            Kc_ini = null_default(input[[paste0(prefix, "kc_ini")]], 0.3),
            Kc_mid = null_default(input[[paste0(prefix, "kc_mid")]], 1.15),
            Kc_end = null_default(input[[paste0(prefix, "kc_end")]], 0.3),
            L_ini_days = as.integer(null_default(input[[paste0(prefix, "l_ini")]], 30)),
            L_mid_days = as.integer(null_default(input[[paste0(prefix, "l_mid")]], 40)),
            L_late_days = as.integer(null_default(input[[paste0(prefix, "l_late")]], 30)),
            max_height_m = null_default(input[[paste0(prefix, "height")]], 1.0),
            HI = null_default(input[[paste0(prefix, "hi")]], 0.45),
            MC = null_default(input[[paste0(prefix, "mc")]], 0.12),
            fc = null_default(input[[paste0(prefix, "fc")]], 1.0),
            AOT = null_default(input[[paste0(prefix, "aot")]], 0.8),
            stringsAsFactors = FALSE
          )
      })

      do.call(rbind, rows)
    }

    active_kc_data <- shiny::reactive({
      params <- collect_crop_params()
      shiny::req(params)
      # Dynamic total days for preview to ensure L_dev is at least 30
      fixed_sums <- params$L_ini_days + params$L_mid_days + params$L_late_days
      total_days_vec <- stats::setNames(fixed_sums + 30, as.character(params$class_value))
      tryCatch(Rwapor::rwapor_build_kc_by_class(params, total_days_vec), error = function(e) NULL)
    })

    output$an_season_summary <- shiny::renderPrint({
      cat("Season:", input$an_season_label, "\n")
      cat("Reference Year:", input$an_ref_year, "\n")
      cat("Analysis Period:", as.character(input$an_period[1]), "to", as.character(input$an_period[2]), "\n")

      # Data source mode
      data_source <- input$an_data_source
      if (data_source == "local") {
        cat("Data Source: LOCAL FILES (offline mode)\n")
      } else {
        cat("Data Source: API STREAMING (online mode)\n")
      }

      cat("\n--- Variables ---\n")
      cat("AETI:", input$an_aeti_var, "\n")
      cat("RET:", input$an_ret_var, "\n")
      cat("Precip:", input$an_precip_var, "\n")
      cat("Shared Output Folder:", global_folder() %||% "Not set", "\n")

      cat("\n--- Raster Status ---\n")
      cat("Crop Mask:", if (!is.null(an_crop_mask_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season Start:", if (!is.null(an_start_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season End:", if (!is.null(an_end_rast())) "Loaded" else "Not loaded", "\n")

      # Show local data availability if in local mode
      if (data_source == "local") {
        local_vars <- an_local_vars()
        if (!is.null(local_vars) && nrow(local_vars) > 0) {
          cat("\n--- Local Data Available ---\n")
          for (i in seq_len(nrow(local_vars))) {
            v <- local_vars[i, ]
            status <- if (v$variable %in% c(input$an_aeti_var, input$an_ret_var, input$an_precip_var)) "[SELECTED]" else ""
            cat(sprintf("%s: %d files %s\n", v$variable, v$file_count, status))
          }
        } else {
          cat("\n[!] Click 'Scan Local Folder' to detect available data.\n")
        }
      }
    })

    shiny::observe({
      # Dynamically update Ace Editor with code preview
      ref_year <- input$an_ref_year
      period <- input$an_period
      aeti_var <- input$an_aeti_var
      ret_var <- input$an_ret_var
      precip_var <- input$an_precip_var
      
      # Generate a representative snippet
      code_val <- sprintf(
        "library(Rwapor)\n\n# Seasonal Analysis Workflow\nref_year <- %d\nperiod <- c(\"%s\", \"%s\")\n\n# Load Rasters\ncrop_mask <- rwapor_load_crop_mask(\"path/to/crop_mask.tif\")\n\n# Calculate Seasonal Indicators\n# (Full code updates upon successful run)",
        ref_year %||% 2023,
        as.character(period[1] %||% Sys.Date()),
        as.character(period[2] %||% Sys.Date())
      )
      
      shinyAce::updateAceEditor(session, "an_code_preview", value = code_val)
    })

    output$an_crop_mask_plot <- shiny::renderPlot({
      r <- an_crop_mask_rast()
      shiny::req(r)
      graphics::par(mar = c(0.1, 0.1, 1.5, 0.1))
      terra::plot(r, main = "Crop Mask Classes", col = grDevices::hcl.colors(20, "Set2"), axes = FALSE)
    })

    output$an_season_raster_info <- shiny::renderPrint({
      use_season <- isTRUE(input$an_use_season_rasters)
      s_start <- an_start_rast()
      s_end <- an_end_rast()

      if (!use_season) {
        cat("Season rasters disabled.\n")
        cat("Analysis will use the date range from the Analysis Period input.\n")
        return()
      }

      if (is.null(s_start) && is.null(s_end)) {
        cat("Waiting for season rasters to be uploaded...\n")
        cat("\nExpected format:\n")
        cat("  - Single-band GeoTIFF with Julian Day of Year (DOY) values\n")
        cat("  - Values should be 1-366 (or up to 730 for cross-year seasons)\n")
        return()
      }

      cat("=== Season Rasters Status ===\n\n")

      if (!is.null(s_start)) {
        cat("[OK] Season Start Raster:\n")
        vals <- terra::values(s_start, na.rm = TRUE)
        cat(sprintf("     Dimensions: %d x %d\n", nrow(s_start), ncol(s_start)))
        cat(sprintf("     DOY range: %d - %d\n", as.integer(min(vals)), as.integer(max(vals))))
        cat(sprintf("     Valid pixels: %d\n", length(vals)))
      } else {
        cat("[MISSING] Season Start Raster: Not uploaded\n")
      }

      cat("\n")

      if (!is.null(s_end)) {
        cat("[OK] Season End Raster:\n")
        vals <- terra::values(s_end, na.rm = TRUE)
        cat(sprintf("     Dimensions: %d x %d\n", nrow(s_end), ncol(s_end)))
        cat(sprintf("     DOY range: %d - %d\n", as.integer(min(vals)), as.integer(max(vals))))
        cat(sprintf("     Valid pixels: %d\n", length(vals)))
      } else {
        cat("[MISSING] Season End Raster: Not uploaded\n")
      }

      # Additional validation feedback
      if (!is.null(s_start) && !is.null(s_end)) {
        cat("\n=== Validation ===\n")
        vals_start <- terra::values(s_start, na.rm = TRUE)
        vals_end <- terra::values(s_end, na.rm = TRUE)
        mean_start <- mean(vals_start)
        mean_end <- mean(vals_end)
        mean_duration <- mean_end - mean_start + 1

        if (mean_start > mean_end && mean_end < 366) {
          cat("Cross-year season detected.\n")
          mean_duration <- (366 - mean_start) + mean_end + 1
        }
        cat(sprintf("Mean season duration: ~%.0f days\n", mean_duration))
      }
    })

    output$an_crop_class_table <- shiny::renderTable({
      classes <- an_crop_classes()
      shiny::req(classes)
      classes
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    shiny::observeEvent(input$an_validate_btn, {
      errors <- character()
      if (isTRUE(input$an_use_crop_mask) && is.null(an_crop_mask_rast())) errors <- c(errors, "Crop mask raster not uploaded.")
      if (isTRUE(input$an_use_season_rasters) && (is.null(an_start_rast()) || is.null(an_end_rast()))) errors <- c(errors, "Season start/end rasters not uploaded.")
      if (is.null(an_crop_classes())) errors <- c(errors, "No crop classes found.")

      params <- collect_crop_params()
      if (!is.null(params)) {
        if (any(is.na(params$Kc_ini) | is.na(params$Kc_mid) | is.na(params$Kc_end))) {
          errors <- c(errors, "Some Kc values are missing.")
        }
        if (any(is.na(params$L_ini_days) | is.na(params$L_mid_days) | is.na(params$L_late_days))) {
          errors <- c(errors, "Some stage length values are missing.")
        }
      }
      if (length(unique(c(input$an_agg_vars, input$an_derived_vars))) == 0) {
        errors <- c(errors, "Select at least one indicator.")
      }

      if (length(errors) > 0) {
        shiny::showNotification(
          shiny::HTML(paste("<b>Validation errors:</b><br>", paste("-", errors, collapse = "<br>"))),
          type = "error",
          duration = 10
        )
      } else {
        shiny::showNotification("All inputs validated successfully.", type = "message")
      }
    })

    shiny::observeEvent(input$an_reset_btn, {
      an_crop_mask_rast(NULL)
      an_start_rast(NULL)
      an_end_rast(NULL)
      an_crop_classes(NULL)
      an_crop_params(NULL)
      an_results(NULL)
      an_peff_monthly(NULL)
      an_local_vars(NULL)
      shiny::showNotification("Analysis state reset.", type = "message")
    })

    shiny::observeEvent(input$an_run_btn, {
      # 1. Immediate validation and input resolution
      if (isTRUE(input$an_use_crop_mask) && is.null(an_crop_mask_rast())) {
        shiny::showNotification("Please upload a crop mask raster or uncheck the 'Use a crop mask raster?' option.", type = "error")
        return()
      }
      if (isTRUE(input$an_use_season_rasters) && (is.null(an_start_rast()) || is.null(an_end_rast()))) {
        shiny::showNotification("Please upload season start and end rasters or uncheck the 'Use pixel-wise season start/end rasters?' option.", type = "error")
        return()
      }

      indicators <- unique(c(input$an_agg_vars, input$an_derived_vars))
      if (length(indicators) == 0) {
        shiny::showNotification("Select at least one indicator.", type = "error")
        return()
      }

      crop_params <- collect_crop_params()
      if (is.null(crop_params) || nrow(crop_params) == 0) {
        shiny::showNotification("No crop class parameters defined.", type = "error")
        return()
      }

      # 2. Resolve metadata for check and analysis
      ref_year <- input$an_ref_year
      period   <- as.character(input$an_period)
      reg      <- current_region()
      aeti_var <- input$an_aeti_var
      ret_var  <- input$an_ret_var
      precip_var <- input$an_precip_var
      npp_var    <- input$an_npp_var
      folder     <- global_folder()
      
      # Resolve L3 code if needed (check all required variables)
      any_l3 <- any(grepl("^L3-", c(aeti_var, ret_var, precip_var, npp_var) %||% ""))
      l3_code <- if (any_l3) input$an_l3_region else NULL
      
      if (is.null(l3_code) && any_l3) {
         # Attempt to auto-resolve L3 region from AOI or Mask for URL generation
         cand_reg <- reg
         if (is.null(cand_reg) && isTRUE(input$an_use_crop_mask) && !is.null(an_crop_mask_rast())) {
            cm_rast <- an_crop_mask_rast()
            tryCatch({
              cm_ext <- terra::ext(cm_rast)
              cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(cm_rast))
              cm_poly_4326 <- Rwapor::safe_project(cm_poly, "EPSG:4326")
              e_4326 <- terra::ext(cm_poly_4326)
              cand_reg <- c(e_4326$xmin, e_4326$ymin, e_4326$xmax, e_4326$ymax)
            }, error = function(e) NULL)
         }
         
         if (!is.null(cand_reg)) {
            guess <- tryCatch({
              reg_info_guess <- Rwapor::parse_region(cand_reg)
              Rwapor::guess_l3_region(aeti_var, reg_info_guess, period)
            }, error = function(e) NULL)
            if (length(guess) > 0) l3_code <- guess[1]
         }
      }

      # 3. Check data availability if in Local Mode
      if (isTRUE(input$an_data_source == "local")) {
        if (is.null(folder) || !nzchar(folder) || !dir.exists(folder)) {
          shiny::showNotification("Local data mode selected but download folder is not set. Configure it in the Download tab first.", type = "error")
          return()
        }

        local_vars <- an_local_vars()
        if (is.null(local_vars) || nrow(local_vars) == 0) {
          shiny::showNotification("Please click 'Scan Local Folder' first to detect available variables.", type = "error")
          return()
        }

        # Check if required variables are available locally
        required_vars <- aeti_var
        if (any(c("agg_ret", "etc", "adequacy_etc") %in% indicators)) {
          required_vars <- c(required_vars, ret_var)
        }
        if (any(c("agg_pcp", "agg_peff") %in% indicators)) {
          required_vars <- c(required_vars, precip_var)
        }
        if (any(c("agg_biomass", "yield_npp", "cwp_bwp") %in% indicators)) {
          required_vars <- c(required_vars, npp_var)
        }

        missing_vars <- required_vars[!required_vars %in% local_vars$variable]
        if (length(missing_vars) > 0) {
          shiny::showNotification(
            sprintf("Required variable(s) not found locally: %s. Download them first or switch to API streaming.",
                    paste(missing_vars, collapse = ", ")),
            type = "error",
            duration = 10
          )
          return()
        }

        # Check for specific missing dekads
        all_missing_info <- list()
        for (v in required_vars) {
          urls <- Rwapor::wapor_generate_urls(v, l3_region = l3_code, period = period)
          check <- Rwapor::rwapor_check_local_files(urls, v, folder)
          if (length(check$missing_dates) > 0) {
            all_missing_info[[v]] <- check$missing_dates
          }
        }

        if (length(all_missing_info) > 0) {
          temp_missing_info(all_missing_info)
          missing_lines <- lapply(names(all_missing_info), function(v) {
            dates <- all_missing_info[[v]]
            sprintf("<b>%s</b>: %d dekads missing (%s...%s)", 
                    v, length(dates), dates[1], dates[length(dates)])
          })
          
          shiny::showModal(shiny::modalDialog(
            title = "Missing Data Detected",
            shiny::HTML(paste0(
              sprintf("<p>The following data is required for your analysis but was not found in the project folder (<b>%s</b>):</p>", folder),
              "<ul><li>", paste(missing_lines, collapse = "</li><li>"), "</li></ul>",
              "<p>Would you like to download the missing dekadal rasters now?</p>",
              sprintf("<p><small><i>Note: The download will use your selected AOI or the crop mask bounding box. Files will be saved in subfolders within <b>%s</b>.</i></small></p>", folder)
            )),
            footer = shiny::tagList(
              shiny::modalButton("Cancel"),
              shiny::actionButton(ns("an_download_missing_btn"), "Download Missing Data", class = "btn-success")
            ),
            easyClose = FALSE
          ))
          return()
        }
      }

      # 4. Run Analysis
      an_peff_monthly(NULL)
      shiny::withProgress(message = "Running analysis...", value = 0, {
        tryCatch({
          use_local <- isTRUE(input$an_data_source == "local")
          shiny::incProgress(0.05, detail = if (use_local) "Loading local reference AETI raster..." else "Fetching reference AETI raster...")

          # Get template raster based on data source
          template_r <- NULL
          reg_info <- NULL
          
          # Use AOI from map or fallback to crop mask
          final_reg <- reg
          if (is.null(final_reg) && isTRUE(input$an_use_crop_mask) && !is.null(an_crop_mask_rast())) {
             cm_rast <- an_crop_mask_rast()
             cm_ext <- tryCatch(terra::ext(cm_rast), error = function(e) NULL)
             
             if (!is.null(cm_ext)) {
                # Convert extent to WGS84 bbox
                cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(cm_rast))
                cm_poly_4326 <- Rwapor::safe_project(cm_poly, "EPSG:4326")
                cm_ext_4326 <- tryCatch(terra::ext(cm_poly_4326), error = function(e) NULL)
               
               if (!is.null(cm_ext_4326)) {
                 final_reg <- c(as.numeric(cm_ext_4326$xmin), as.numeric(cm_ext_4326$ymin), 
                               as.numeric(cm_ext_4326$xmax), as.numeric(cm_ext_4326$ymax))
                 shiny::showNotification("Using crop mask extent as analysis bounding box.", type = "message")
               }
             }
          }

          if (use_local) {
            local_aeti_paths <- Rwapor::rwapor_get_local_rasters(folder, aeti_var, period[1], period[2])
            if (length(local_aeti_paths) == 0) {
              stop(sprintf("No local AETI files found for %s in date range %s to %s.", aeti_var, period[1], period[2]))
            }
            template_r <- terra::rast(local_aeti_paths[1])
            if (!is.null(final_reg)) {
              reg_info <- Rwapor::parse_region(final_reg)
              template_r <- crop_to_region_shiny(template_r, reg_info, do_mask = FALSE)
            }
          } else {
            ref_urls <- Rwapor::wapor_generate_urls(aeti_var, l3_region = l3_code, period = period)
            if (length(ref_urls) == 0) stop("No AETI data found for the specified period.")
            
            # Safely load template
            template_r <- tryCatch({
              r <- terra::rast(paste0("/vsicurl/", ref_urls[1]))
              if (terra::nlyr(r) == 0) stop("Fetched template raster has no layers.")
              r
            }, error = function(e) {
              stop(sprintf("Failed to load reference AETI raster from WaPOR: %s. Check your internet connection or L3 region selection.", e$message))
            })

            if (!is.null(final_reg)) {
              reg_info <- Rwapor::parse_region(final_reg)
              template_r <- crop_to_region_shiny(template_r, reg_info, do_mask = FALSE)
            }
          }

          shiny::incProgress(0.10, detail = "Harmonizing rasters...")
          
          # Handle optional crop mask
          h_mask <- if (isTRUE(input$an_use_crop_mask)) {
            Rwapor::rwapor_harmonize_crop_mask(an_crop_mask_rast(), template_r)
          } else {
            # Constant 1 raster with template's geometry
            terra::classify(template_r * 0 + 1, cbind(NA, NA))
          }

          # Handle optional season rasters
          h_start <- if (isTRUE(input$an_use_season_rasters)) {
            Rwapor::rwapor_harmonize_to_template(an_start_rast(), template_r, method = "near")
          } else {
            doy_start <- as.integer(strftime(input$an_period[1], "%j"))
            template_r * 0 + doy_start
          }

          h_end <- if (isTRUE(input$an_use_season_rasters)) {
            Rwapor::rwapor_harmonize_to_template(an_end_rast(), template_r, method = "near")
          } else {
            doy_end <- as.integer(strftime(input$an_period[2], "%j"))
            template_r * 0 + doy_end
          }

          s_start_vals <- tryCatch({
            terra::global(h_start, "mean", na.rm = TRUE)$mean
          }, error = function(e) NaN)

          if (is.nan(s_start_vals) || is.na(s_start_vals)) {
            stop("Season start raster contains no valid data in the selected area.")
          }

          mean_s_start <- round(s_start_vals)

          s_end_vals <- tryCatch({
            terra::global(h_end, "mean", na.rm = TRUE)$mean
          }, error = function(e) NaN)

          if (is.nan(s_end_vals) || is.na(s_end_vals)) {
            stop("Season end raster contains no valid data.")
          }

          mean_s_end <- round(s_end_vals)

          shiny::incProgress(0.10, detail = "Computing season duration...")
          total_days_r <- Rwapor::rwapor_compute_total_days_raster(h_start, h_end)
          mean_total_days <- round(mean(terra::values(total_days_r, na.rm = TRUE)))

          for (j in seq_len(nrow(crop_params))) {
            fixed_sum <- crop_params$L_ini_days[j] + crop_params$L_mid_days[j] + crop_params$L_late_days[j]
            if (fixed_sum >= mean_total_days) {
              warning(
                sprintf(
                  "Class %s: ini+mid+late=%d >= mean total days=%d. L_dev will be <=0.",
                  crop_params$crop_label[j],
                  fixed_sum,
                  mean_total_days
                )
              )
            }
          }

          shiny::incProgress(0.10, detail = "Building Kc curves...")
          total_days_vec <- stats::setNames(rep(mean_total_days, nrow(crop_params)), as.character(crop_params$class_value))
          kc_by_class <- Rwapor::rwapor_build_kc_by_class(crop_params, total_days_vec)

          shiny::incProgress(0.10, detail = "Building season weights...")
          sw <- Rwapor::rwapor_build_season_weights_dekad(period[1], period[2], h_start, h_end, ref_year)
          season_weights <- sw$weights
          dekad_table <- sw$dekad_table

          need_aeti_stack <- any(c("agg_aeti", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp") %in% indicators)
          need_ret_stack <- any(c("agg_ret", "etc", "adequacy_etc") %in% indicators)
          need_precip_stack <- any(c("agg_pcp", "agg_peff") %in% indicators)
          need_npp_stack <- any(c("agg_biomass", "yield_npp", "cwp_bwp") %in% indicators) && is.null(input$an_biomass_file)

          shiny::incProgress(0.15, detail = if (use_local) "Loading local data..." else "Fetching remote data...")
          aeti_stack <- ret_stack <- precip_stack <- npp_stack <- NULL

          # Helper function to load raster stack from local or remote
          load_var_stack <- function(var, use_local, folder, period, l3_code, reg_info) {
            if (use_local) {
              local_paths <- Rwapor::rwapor_get_local_rasters(folder, var, period[1], period[2])
              if (length(local_paths) == 0) {
                warning(sprintf("No local files found for %s", var))
                return(NULL)
              }
              stack <- terra::rast(local_paths)
            } else {
              urls <- Rwapor::wapor_generate_urls(var, l3_region = l3_code, period = period)
              if (length(urls) == 0) return(NULL)
              stack <- terra::rast(paste0("/vsicurl/", urls))
            }

            if (!is.null(reg_info)) {
              stack <- crop_to_region_shiny(stack, reg_info, do_mask = FALSE)
            }

            # Apply scale factor
            meta <- Rwapor::get_variable_metadata(var)
            if (!is.null(meta) && !is.null(meta$scale)) {
              stack <- stack * meta$scale
            }

            stack
          }

          if (need_aeti_stack) {
            aeti_stack <- load_var_stack(aeti_var, use_local, folder, period, l3_code, reg_info)
            if (is.null(aeti_stack)) {
              stop(sprintf("Failed to load AETI data for %s. %s",
                           aeti_var,
                           if (use_local) "Check that the variable is downloaded." else "Check your internet connection."))
            }
            # Harmonize AETI stack to template to ensure exact extent/resolution alignment
            shiny::incProgress(0.02, detail = "Harmonizing AETI to template...")
            aeti_stack <- Rwapor::rwapor_harmonize_to_template(aeti_stack, template_r, method = "bilinear")
          }

          if (need_ret_stack) {
            ret_stack <- load_var_stack(ret_var, use_local, folder, period, l3_code, reg_info)
            if (is.null(ret_stack)) {
              stop(sprintf("Failed to load RET data for %s. %s",
                           ret_var,
                           if (use_local) "Check that the variable is downloaded." else "Check your internet connection."))
            }
            shiny::incProgress(0.05, detail = "Harmonizing RET to AETI...")
            ret_stack <- Rwapor::rwapor_harmonize_to_template(ret_stack, template_r)
          }

          if (need_precip_stack) {
            precip_stack <- load_var_stack(precip_var, use_local, folder, period, l3_code, reg_info)
            if (!is.null(precip_stack)) {
               shiny::incProgress(0.05, detail = "Harmonizing Precipitation to AETI...")
               precip_stack <- Rwapor::rwapor_harmonize_to_template(precip_stack, template_r)
            }
          }

          if (need_npp_stack) {
            npp_var <- "L1-NPP-D"
            npp_stack <- load_var_stack(npp_var, use_local, folder, period, l3_code, reg_info)
            if (!is.null(npp_stack)) {
               shiny::incProgress(0.05, detail = "Harmonizing NPP to AETI...")
               npp_stack <- Rwapor::rwapor_harmonize_to_template(npp_stack, template_r)
            }
          }


          # Helper function to align raster stacks to the same dates as the season weights
          align_stack_to_weights <- function(s, target_dates) {
            if (is.null(s)) return(NULL)
            nms <- names(s)
            
            # Simple extractor for dates from layer names (handles YYYY-MM-DD and YYYYMMDD)
            # terra names often strip hyphens or prefix with variable names
            found_dates <- nms
            if (any(grepl("\\d{4}-\\d{2}-\\d{2}", nms))) {
              found_dates <- gsub(".*(\\d{4}-\\d{2}-\\d{2}).*", "\\1", nms)
            } else if (any(grepl("\\d{8}", nms))) {
              found_dates <- gsub(".*(\\d{4})(\\d{2})(\\d{2}).*", "\\1-\\2-\\3", nms)
            }
            
            indices <- match(as.character(target_dates), found_dates)
            if (any(is.na(indices))) {
              missing_idx <- which(is.na(indices))
              stop(sprintf("Missing data for dekad starting %s. Alignment failed.", 
                           target_dates[missing_idx[1]]), call. = FALSE)
            }
            s[[indices]]
          }

          target_dates <- dekad_table$dekad_start
          
          if (!is.null(aeti_stack)) aeti_stack <- align_stack_to_weights(aeti_stack, target_dates)
          if (!is.null(ret_stack)) ret_stack <- align_stack_to_weights(ret_stack, target_dates)
          if (!is.null(precip_stack)) precip_stack <- align_stack_to_weights(precip_stack, target_dates)
          if (!is.null(npp_stack)) npp_stack <- align_stack_to_weights(npp_stack, target_dates)

          n_layers <- terra::nlyr(season_weights)

          shiny::incProgress(0.10, detail = "Computing seasonal aggregations...")
          results <- list()

          # Compute seasonal aggregates with optional incremental mode
          use_incremental <- isTRUE(input$an_incremental)
          
          if (need_aeti_stack && !is.null(aeti_stack)) {
            results$seasonal_aeti <- Rwapor::rwapor_calc_seasonal_aeti_masked(
              aeti_stack, season_weights, h_mask, incremental = use_incremental
            )
          }

          if (need_ret_stack && !is.null(ret_stack)) {
            results$seasonal_ret <- Rwapor::rwapor_calc_seasonal_ret_masked(
              ret_stack, season_weights, h_mask, incremental = use_incremental
            )
          }

          if ("agg_pcp" %in% indicators && !is.null(precip_stack)) {
            results$seasonal_pcp <- Rwapor::rwapor_apply_masked_sum(
              precip_stack, season_weights, incremental = use_incremental
            )
          }

          if (("agg_biomass" %in% indicators || "yield_npp" %in% indicators) && !is.null(npp_stack)) {
            shiny::incProgress(0.05, detail = "Computing Biomass...")
            # Biomass is weighted sum of NPP * 22.222
            results$seasonal_biomass <- Rwapor::rwapor_apply_masked_sum(
              npp_stack, season_weights, incremental = use_incremental
            ) * 22.222
            # NPP stack no longer needed after biomass is computed
            rm(npp_stack); gc()
          }

          if ("etc" %in% indicators || "adequacy_etc" %in% indicators) {
            shiny::incProgress(0.05, detail = "Computing ETc...")
            
            # Step 1: Precompute dekadal Kc for each class
            # This is fast (numeric operations on small vectors)
            kc_list <- list()
            for (j in seq_len(nrow(crop_params))) {
              cls <- as.character(crop_params$class_value[j])
              kc_daily <- kc_by_class[[cls]]
              # Period[1] is the season start date
              kc_list[[cls]] <- Rwapor::rwapor_aggregate_kc_dekad(
                kc_daily, dekad_table, period[1]
              )
            }
            
            # Step 2: Group classes by identical Kc profiles to avoid redundant raster math
            kc_keys <- vapply(kc_list, function(x) paste(round(x, 4), collapse = ","), character(1))
            unique_kc_keys <- unique(kc_keys)
            
            unique_etc_rasters <- list()
            for (key in unique_kc_keys) {
              # Find the first class that has this Kc profile
              cls_example <- names(kc_keys)[kc_keys == key][1]
              kc_vec <- kc_list[[cls_example]]
              
              # Compute seasonal ETc once for this profile (incremental = memory safe)
              unique_etc_rasters[[key]] <- Rwapor::rwapor_calc_seasonal_etc_incremental(
                ret_stack, season_weights, kc_vec
              )
            }
            
            # Step 3: Map back to etc_by_class and apply class mask
            # This ensures each class gets its specific spatial extent results
            etc_by_class <- list()
            for (j in seq_len(nrow(crop_params))) {
              cls <- as.character(crop_params$class_value[j])
              key <- kc_keys[cls]
              
              # Get the seasonal ETc for this profile
              etc_seasonal_global <- unique_etc_rasters[[key]]
              
              # Mask to the specific crop class
              class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
              etc_seasonal_masked <- etc_seasonal_global * class_mask
              
              # mod_analysis.R expects a list with kc_dekad and etc_seasonal
              etc_by_class[[cls]] <- list(
                kc_dekad = kc_list[[cls]],
                etc_seasonal = etc_seasonal_masked
              )
            }
            results$etc_by_class <- etc_by_class
            
            # RET stack no longer needed after ETc is computed
            rm(ret_stack); gc()
          }

          if ("adequacy_etc" %in% indicators && !is.null(results$seasonal_aeti) && !is.null(results$etc_by_class)) {
            shiny::incProgress(0.05, detail = "Computing adequacy (ETc)...")
            all_etc <- lapply(results$etc_by_class, function(x) x$etc_seasonal)
            if (length(all_etc) > 0) {
              combined_etc <- all_etc[[1]]
              if (length(all_etc) > 1) {
                for (k in seq_along(all_etc)[-1]) {
                  combined_etc <- terra::cover(combined_etc, all_etc[[k]])
                }
              }
              results$adequacy_etc <- Rwapor::rwapor_calc_adequacy_etc(results$seasonal_aeti$raster, combined_etc)
            }
          }

          if ("adequacy_p95" %in% indicators && !is.null(results$seasonal_aeti)) {
            shiny::incProgress(0.05, detail = "Computing adequacy (P95)...")
            p95_table <- Rwapor::rwapor_calc_class_p95_aeti(results$seasonal_aeti$raster, h_mask)
            results$p95_table <- p95_table
            results$adequacy_p95 <- Rwapor::rwapor_calc_adequacy_p95(results$seasonal_aeti$raster, h_mask, p95_table)
          }

          if ("agg_peff" %in% indicators && !is.null(precip_stack)) {
            shiny::incProgress(0.05, detail = "Computing effective precipitation...")
            tryCatch({
              precip_means <- terra::global(precip_stack[[seq_len(n_layers)]], fun = "mean", na.rm = TRUE)$mean
              tres <- utils::tail(strsplit(precip_var, "-")[[1]], 1)
              precip_urls <- Rwapor::wapor_generate_urls(precip_var, l3_region = l3_code, period = period)
              precip_dates <- lapply(precip_urls, function(u) Rwapor::get_date_info(u, tres))
              precip_ts <- data.frame(
                date = as.Date(vapply(precip_dates, function(x) x$start_date, character(1))),
                value = precip_means,
                stringsAsFactors = FALSE
              )
              monthly_p <- Rwapor::rwapor_aggregate_precip_monthly(precip_ts)
              monthly_p$peff_mm <- Rwapor::rwapor_calc_peff_usda_monthly(monthly_p$p_monthly_mm)
              an_peff_monthly(monthly_p)
              results$peff_seasonal <- sum(monthly_p$peff_mm, na.rm = TRUE)
              results$peff_monthly <- monthly_p
            }, error = function(e) {
              warning("Peff computation failed: ", e$message)
            })
          }

          if ("yield_npp" %in% indicators && !is.null(results$seasonal_biomass)) {
            shiny::incProgress(0.05, detail = "Computing Yield (NPP-based)...")
            yield_layers <- list()
            for (j in seq_len(nrow(crop_params))) {
              cls <- as.character(crop_params$class_value[j])
              cp <- crop_params[j, ]
              class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
              # Yield = (HI * AOT * fc * (Biomass / (1 - MC))) / 1000  [t/ha]
              # Note: results$seasonal_biomass is already in kgDM/ha (NPP * 22.222)
              yield_rast <- (cp$HI * cp$AOT * cp$fc * (results$seasonal_biomass / (1 - cp$MC))) / 1000
              yield_layers[[cls]] <- yield_rast * class_mask
            }
            results$yield_by_class <- yield_layers
          }

          if ("cwp_bwp" %in% indicators && !is.null(results$seasonal_aeti)) {
            shiny::incProgress(0.05, detail = "Computing CWP/BWP...")
            mean_aeti <- mean(terra::values(results$seasonal_aeti$raster, na.rm = TRUE))
            cwp_val <- NULL
            bwp_val <- NULL

            if (!is.null(input$an_yield_file)) {
              tryCatch({
                yield_r <- terra::rast(input$an_yield_file$datapath)
                yield_h <- Rwapor::rwapor_harmonize_to_template(yield_r, template_r)
                mean_yield <- mean(terra::values(yield_h, na.rm = TRUE))
                cwp_val <- Rwapor::rwapor_calc_cwp(mean_yield, mean_aeti, input$an_yield_unit)
              }, error = function(e) {
                warning("CWP computation failed: ", e$message)
              })
            }

            bio_h <- results$seasonal_biomass
            if (!is.null(input$an_biomass_file)) {
              tryCatch({
                bio_r <- terra::rast(input$an_biomass_file$datapath)
                bio_h <- Rwapor::rwapor_harmonize_to_template(bio_r, template_r)
              }, error = function(e) warning("Local biomass load failed: ", e$message))
            }

            if (!is.null(bio_h)) {
              tryCatch({
                mean_bio <- mean(terra::values(bio_h, na.rm = TRUE))
                bwp_val <- Rwapor::rwapor_calc_bwp(mean_bio, mean_aeti, input$an_biomass_unit)
              }, error = function(e) {
                warning("BWP computation failed: ", e$message)
              })
            }

            results$cwp <- cwp_val
            results$bwp <- bwp_val
            results$biomass <- bio_h
          }
          
          # Final memory cleanup
          rm(aeti_stack, precip_stack); gc()

          shiny::incProgress(0.10, detail = "Finalizing results...")
          results$crop_params <- crop_params
          results$kc_by_class <- kc_by_class
          results$dekad_table <- dekad_table[seq_len(n_layers), , drop = FALSE]

          an_results(results)
          an_crop_params(crop_params)

          # --- Automatic Raster Saving ---
          if (isTRUE(input$an_save_rasters) && nzchar(input$an_folder)) {
            shiny::showNotification(sprintf("Saving analysis rasters to: %s", input$an_folder), type = "message")
            tryCatch({
              if (!dir.exists(input$an_folder)) dir.create(input$an_folder, recursive = TRUE)
              
              prefix <- if (nzchar(input$an_season_label)) {
                gsub("[^a-zA-Z0-9_-]", "_", input$an_season_label)
              } else "analysis"
              
              # AETI
              if (!is.null(results$seasonal_aeti)) {
                terra::writeRaster(results$seasonal_aeti$raster, 
                                  file.path(input$an_folder, paste0(prefix, "_seasonal_aeti.tif")), 
                                  overwrite = TRUE)
              }
              # RET
              if (!is.null(results$seasonal_ret)) {
                terra::writeRaster(results$seasonal_ret$raster, 
                                  file.path(input$an_folder, paste0(prefix, "_seasonal_ret.tif")), 
                                  overwrite = TRUE)
              }
              # PCP
              if (!is.null(results$seasonal_pcp)) {
                terra::writeRaster(results$seasonal_pcp, 
                                  file.path(input$an_folder, paste0(prefix, "_seasonal_pcp.tif")), 
                                  overwrite = TRUE)
              }
              # Adequacy ETc
              if (!is.null(results$adequacy_etc)) {
                terra::writeRaster(results$adequacy_etc, 
                                  file.path(input$an_folder, paste0(prefix, "_adequacy_etc.tif")), 
                                  overwrite = TRUE)
              }
              # Adequacy P95
              if (!is.null(results$adequacy_p95)) {
                terra::writeRaster(results$adequacy_p95, 
                                  file.path(input$an_folder, paste0(prefix, "_adequacy_p95.tif")), 
                                  overwrite = TRUE)
              }
              # ETc by class
              if (!is.null(results$etc_by_class)) {
                for (cls in names(results$etc_by_class)) {
                  terra::writeRaster(results$etc_by_class[[cls]]$etc_seasonal, 
                                    file.path(input$an_folder, paste0(prefix, "_etc_class_", cls, ".tif")), 
                                    overwrite = TRUE)
                }
              }
              shiny::showNotification("Rasters saved successfully.", type = "message")
            }, error = function(e) {
              shiny::showNotification(paste("Raster saving failed:", e$message), type = "warning")
            })
          }

          shiny::showNotification("Analysis complete!", type = "message", duration = 8)
        }, error = function(e) {
          shiny::showNotification(paste("Analysis failed:", e$message), type = "error", duration = 15)
        })
      })
    })

    output$an_kc_plot <- shiny::renderPlot({
      kc_list <- active_kc_data()
      params <- collect_crop_params()
      shiny::req(kc_list, params)

      if (length(kc_list) == 0) return()
      max_len <- max(vapply(kc_list, length, integer(1)))
      if (max_len == 0) return()

      graphics::par(mar = c(3, 3, 2, 1), mgp = c(2, 0.7, 0))

      cols <- grDevices::hcl.colors(length(kc_list), "Set2")
      graphics::plot(
        NULL,
        xlim = c(1, max_len),
        ylim = c(0, 1.5),
        xlab = "Day of Season",
        ylab = "Kc",
        main = "Crop Coefficient Curves (Preview)",
        axes = FALSE
      )
      graphics::axis(1)
      graphics::axis(2)
      graphics::box()
      
      for (i in seq_along(kc_list)) {
        kc <- kc_list[[i]]
        if (length(kc) > 0) {
          graphics::lines(seq_along(kc), kc, col = cols[i], lwd = 3)
        }
      }
      graphics::legend("topright", legend = params$crop_label, col = cols, lwd = 3, cex = 0.9, bty = "n")
    })

    output$an_etc_aeti_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      if (!is.null(res$seasonal_aeti$by_class)) {
        aeti_tbl <- res$seasonal_aeti$by_class
        ret_tbl <- res$seasonal_ret$by_class
        etc_means <- if (!is.null(res$etc_by_class)) {
          vapply(names(res$etc_by_class), function(cls) {
            etc_r <- res$etc_by_class[[cls]]$etc_seasonal
            if (!is.null(etc_r)) mean(terra::values(etc_r, na.rm = TRUE)) else NA_real_
          }, numeric(1))
        } else {
          numeric()
        }

        for (i in seq_len(nrow(aeti_tbl))) {
          cls_str <- as.character(aeti_tbl$class_value[i])
          label <- if (!is.null(res$crop_params)) {
            idx <- which(res$crop_params$class_value == aeti_tbl$class_value[i])
            if (length(idx) > 0) res$crop_params$crop_label[idx[1]] else cls_str
          } else {
            cls_str
          }

          # Get Yield if available
          yield_val <- if (!is.null(res$yield_by_class) && cls_str %in% names(res$yield_by_class)) {
            terra::global(res$yield_by_class[[cls_str]], "mean", na.rm = TRUE)$mean
          } else NA_real_

          rows[[i]] <- data.frame(
            Class = label,
            `AETI (mm)` = round(aeti_tbl$mean_seasonal_aeti[i], 1),
            `RET (mm)` = round(ret_tbl$mean_seasonal_ret[i], 1),
            `ETc (mm)` = if (cls_str %in% names(etc_means)) round(etc_means[cls_str], 1) else NA,
            `Yield (t/ha)` = if (!is.na(yield_val)) round(yield_val, 2) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Run analysis first.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_adequacy_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      params <- res$crop_params

      if (!is.null(res$adequacy_etc)) {
        classes <- terra::freq(an_crop_mask_rast())
        classes <- classes[!is.na(classes$value), ]
        for (i in seq_len(nrow(classes))) {
          cls <- classes$value[i]
          cls_mask <- terra::ifel(an_crop_mask_rast() == cls, 1L, NA)
          adq_vals <- terra::values(res$adequacy_etc * cls_mask, na.rm = TRUE)
          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Adequacy_ETc",
            Mean = if (length(adq_vals) > 0) round(mean(adq_vals), 3) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (!is.null(res$adequacy_p95)) {
        p95_tbl <- res$p95_table
        for (i in seq_len(nrow(p95_tbl))) {
          cls <- p95_tbl$class_value[i]
          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Adequacy_P95",
            Mean = if (p95_tbl$valid[i]) round(p95_tbl$p95_aeti[i], 1) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Run analysis with adequacy indicators selected.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_peff_table <- shiny::renderTable({
      peff_m <- an_peff_monthly()
      if (!is.null(peff_m)) {
        peff_m$month_name <- month.abb[peff_m$month]
        out <- peff_m[, c("year", "month_name", "p_monthly_mm", "peff_mm")]
        names(out) <- c("Year", "Month", "Precip (mm)", "Peff (mm)")
        total_row <- data.frame(
          Year = "",
          Month = "TOTAL",
          `Precip (mm)` = round(sum(peff_m$p_monthly_mm, na.rm = TRUE), 1),
          `Peff (mm)` = round(sum(peff_m$peff_mm, na.rm = TRUE), 1),
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
        rbind(out, total_row)
      } else {
        data.frame(Message = "Run analysis with Peff indicator selected.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_cwp_bwp_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      if (!is.null(res$cwp)) {
        rows[[length(rows) + 1]] <- data.frame(
          Metric = "CWP",
          Value = round(res$cwp, 3),
          Unit = "kg/m3",
          stringsAsFactors = FALSE
        )
      }
      if (!is.null(res$bwp)) {
        rows[[length(rows) + 1]] <- data.frame(
          Metric = "BWP",
          Value = round(res$bwp, 3),
          Unit = "kg/m3",
          stringsAsFactors = FALSE
        )
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Upload yield/biomass rasters and run analysis.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_dl_crop_params <- shiny::downloadHandler(
      filename = function() paste0("crop_parameters_", Sys.Date(), ".csv"),
      content = function(file) {
        params <- an_crop_params()
        if (!is.null(params)) utils::write.csv(params, file, row.names = FALSE)
      }
    )

    output$an_dl_results <- shiny::downloadHandler(
      filename = function() paste0("seasonal_results_", Sys.Date(), ".csv"),
      content = function(file) {
        res <- an_results()
        if (!is.null(res) && !is.null(res$seasonal_aeti$by_class)) {
          out <- res$seasonal_aeti$by_class
          if (!is.null(res$seasonal_ret$by_class)) {
            out <- merge(out, res$seasonal_ret$by_class, by = "class_value", all = TRUE)
          }
          out$season <- input$an_season_label
          out$ref_year <- input$an_ref_year
          utils::write.csv(out, file, row.names = FALSE)
        }
      }
    )

    output$an_dl_peff <- shiny::downloadHandler(
      filename = function() paste0("monthly_peff_", Sys.Date(), ".csv"),
      content = function(file) {
        peff_m <- an_peff_monthly()
        if (!is.null(peff_m)) {
          peff_m$method <- "USDA_SCS"
          utils::write.csv(peff_m, file, row.names = FALSE)
        }
      }
    )

    output$an_code_preview <- shiny::renderText({
      reg <- current_region()
      reg_str <- if (is.null(reg)) {
        "NULL"
      } else if (is.character(reg)) {
        sprintf("\"%s\"", reg)
      } else {
        sprintf("c(%f, %f, %f, %f)", reg[1], reg[2], reg[3], reg[4])
      }

      sprintf(
        paste0(
          "library(Rwapor)\n\n",
          "# 0. Setup output folder\n",
          "output_folder <- \"%s\"\n",
          "if (!dir.exists(output_folder)) dir.create(output_folder, recursive = TRUE)\n\n",
          "# 1. Load rasters\n",
          "crop_mask <- rwapor_load_crop_mask(\"crop_mask.tif\")\n",
          "season_start <- rwapor_load_season_raster(\"season_start.tif\")\n",
          "season_end <- rwapor_load_season_raster(\"season_end.tif\")\n\n",
          "# 2. Harmonize to AETI grid\n",
          "template <- terra::rast(\"aeti_reference.tif\")\n",
          "crop_mask_h <- rwapor_harmonize_crop_mask(crop_mask, template)\n",
          "start_h <- rwapor_harmonize_to_template(season_start, template)\n",
          "end_h <- rwapor_harmonize_to_template(season_end, template)\n\n",
          "# 3. Build season weights\n",
          "sw <- rwapor_build_season_weights_dekad(\n",
          "  \"%s\", \"%s\", start_h, end_h, %d\n",
          ")\n\n",
          "# 4. Fetch data and compute indicators\n",
          "# aeti_ts <- wapor_ts(region = %s, variable = \"%s\", ...)\n",
          "# See package documentation for full workflow"
        ),
        input$an_folder,
        input$an_period[1],
        input$an_period[2],
        input$an_ref_year,
        reg_str,
        input$an_aeti_var
      )
    })

    list(
      mask_rast = an_crop_mask_rast,
      start_rast = an_start_rast,
      end_rast = an_end_rast,
      crop_params = an_crop_params
    )
  })
}
