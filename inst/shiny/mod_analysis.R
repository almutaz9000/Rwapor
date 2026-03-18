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
            "Data Inputs",
            icon = shiny::icon("upload"),
            shiny::fluidRow(
              shiny::column(
                12,
                shiny::fileInput(ns("an_crop_mask"), "Crop Mask", accept = c(".tif", ".tiff"))
              ),
              shiny::column(
                6,
                shiny::fileInput(ns("an_season_start"), "Season Start (DOY)", accept = c(".tif", ".tiff"))
              ),
              shiny::column(
                6,
                shiny::fileInput(ns("an_season_end"), "Season End (DOY)", accept = c(".tif", ".tiff"))
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
                "Peff  (Effective Precip, USDA)"
              ),
              choiceValues = list("agg_aeti", "agg_ret", "agg_pcp", "agg_peff"),
              selected = c("agg_aeti", "agg_ret")
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
                "CWP / BWP"
              ),
              choiceValues = list("etc", "adequacy_etc", "adequacy_p95", "cwp_bwp"),
              selected = c("etc", "adequacy_etc")
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] && input['%s'].indexOf('cwp_bwp') > -1", ns("an_derived_vars"), ns("an_derived_vars")),
              shiny::fluidRow(
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_yield_file"), "Yield Raster", accept = c(".tif", ".tiff")),
                  shiny::selectInput(ns("an_yield_unit"), "Unit", choices = c("kg/ha", "t/ha"), selected = "kg/ha")
                ),
                shiny::column(
                  6,
                  shiny::fileInput(ns("an_biomass_file"), "Biomass Raster", accept = c(".tif", ".tiff")),
                  shiny::selectInput(ns("an_biomass_unit"), "Unit", choices = c("kg/ha", "t/ha"), selected = "kg/ha")
                )
              )
            )
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
      bslib::card(
        bslib::card_header("Season Summary"),
        bslib::card_body(class = "compact", shiny::verbatimTextOutput(ns("an_season_summary")))
      ),
      bslib::navset_card_tab(
        title = "Crop Data",
        bslib::nav_panel("Crop Mask Preview", shiny::plotOutput(ns("an_crop_mask_plot"), height = "300px")),
        bslib::nav_panel("Season Rasters", shiny::verbatimTextOutput(ns("an_season_raster_info"))),
        bslib::nav_panel("Crop Class Table", shiny::tableOutput(ns("an_crop_class_table")))
      ),
      bslib::card(
        bslib::card_header("Kc Curves by Class"),
        bslib::card_body(shiny::plotOutput(ns("an_kc_plot"), height = "300px"))
      ),
      bslib::card(
        bslib::card_header("Analysis Results Summary"),
        bslib::card_body(
          bslib::layout_column_wrap(
            width = "250px",
            bslib::value_box(
              title = "Mean Seasonal AETI",
              value = shiny::textOutput(ns("vbox_aeti")),
              showcase = shiny::icon("tint"),
              theme = "primary"
            ),
            bslib::value_box(
              title = "Mean Seasonal ETc",
              value = shiny::textOutput(ns("vbox_etc")),
              showcase = shiny::icon("sun"),
              theme = "info"
            ),
            bslib::value_box(
              title = "Water Adequacy",
              value = shiny::textOutput(ns("vbox_adequacy")),
              showcase = shiny::icon("percentage"),
              theme = "success"
            )
          )
        )
      ),
      bslib::navset_card_tab(
        title = "Detailed Tables",
        bslib::nav_panel("ETc & AETI", shiny::tableOutput(ns("an_etc_aeti_table"))),
        bslib::nav_panel("Adequacy", shiny::tableOutput(ns("an_adequacy_table"))),
        bslib::nav_panel("Effective Precip", shiny::tableOutput(ns("an_peff_table"))),
        bslib::nav_panel("CWP / BWP", shiny::tableOutput(ns("an_cwp_bwp_table")))
      ),
      bslib::card(
        bslib::card_header("Export"),
        bslib::card_body(
          shiny::fluidRow(
            shiny::column(
              4,
              shiny::downloadButton(
                ns("an_dl_crop_params"),
                "Crop Parameters CSV",
                class = "btn-outline-primary w-100 btn-sm mb-1"
              )
            ),
            shiny::column(
              4,
              shiny::downloadButton(
                ns("an_dl_results"),
                "Seasonal Results CSV",
                class = "btn-outline-primary w-100 btn-sm mb-1"
              )
            ),
            shiny::column(
              4,
              shiny::downloadButton(
                ns("an_dl_peff"),
                "Monthly Peff CSV",
                class = "btn-outline-primary w-100 btn-sm mb-1"
              )
            )
          )
        )
      ),
      shiny::tags$button(
        class = "btn btn-sm btn-outline-secondary code-preview-toggle",
        `data-bs-toggle` = "collapse",
        `data-bs-target` = sprintf("#%s", ns("anCodePreviewCollapse")),
        `aria-expanded` = "false",
        shiny::icon("code"),
        " R Code Preview"
      ),
      shiny::div(
        id = ns("anCodePreviewCollapse"),
        class = "collapse code-preview-body",
        shinyAce::aceEditor(
          ns("an_code_preview"),
          mode = "r",
          theme = "monokai",
          readOnly = TRUE,
          height = "300px",
          fontSize = 12,
          wordWrap = TRUE
        )
      )
    )
  )
}

mod_analysis_server <- function(id, global_folder, aoi_region) {
  shiny::moduleServer(id, function(input, output, session) {
    an_crop_mask_rast <- shiny::reactiveVal(NULL)
    an_start_rast <- shiny::reactiveVal(NULL)
    an_end_rast <- shiny::reactiveVal(NULL)
    an_crop_classes <- shiny::reactiveVal(NULL)
    an_crop_params <- shiny::reactiveVal(NULL)
    an_results <- shiny::reactiveVal(NULL)
    an_peff_monthly <- shiny::reactiveVal(NULL)

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
    iv$add_rule("an_crop_mask", shinyvalidate::sv_required(message = "Crop mask is mandatory."))
    iv$add_rule("an_season_start", shinyvalidate::sv_required(message = "Season start is mandatory."))
    iv$add_rule("an_season_end", shinyvalidate::sv_required(message = "Season end is mandatory."))
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

    current_region <- shiny::reactive(aoi_region())

    shiny::observeEvent(input$an_crop_mask, {
      shiny::req(input$an_crop_mask)
      tryCatch({
        r <- Rwapor::rwapor_load_crop_mask(input$an_crop_mask$datapath)
        an_crop_mask_rast(r)
        classes <- Rwapor::rwapor_extract_crop_classes(r)
        an_crop_classes(classes)
        an_crop_params(Rwapor::rwapor_build_crop_assignment_table(classes$class_value))
        shiny::showNotification(
          sprintf("Crop mask loaded: %d classes found.", nrow(classes)),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading crop mask:", e$message), type = "error")
      })
    })

    shiny::observeEvent(input$an_season_start, {
      shiny::req(input$an_season_start)
      tryCatch({
        an_start_rast(Rwapor::rwapor_load_season_raster(input$an_season_start$datapath))
        shiny::showNotification("Season start raster loaded.", type = "message")
      }, error = function(e) {
        shiny::showNotification(paste("Error:", e$message), type = "error")
      })
    })

    shiny::observeEvent(input$an_season_end, {
      shiny::req(input$an_season_end)
      tryCatch({
        an_end_rast(Rwapor::rwapor_load_season_raster(input$an_season_end$datapath))
        shiny::showNotification("Season end raster loaded.", type = "message")
      }, error = function(e) {
        shiny::showNotification(paste("Error:", e$message), type = "error")
      })
    })

    output$an_crop_class_ui <- shiny::renderUI({
      classes <- an_crop_classes()
      if (is.null(classes)) {
        return(shiny::p("No crop mask loaded yet."))
      }

      crop_choices <- c("(Custom)" = "custom", Rwapor::rwapor_list_crops())
      names(crop_choices) <- c("(Custom)", Rwapor::rwapor_list_crops())

      shiny::tagList(lapply(seq_len(nrow(classes)), function(i) {
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
        shiny::tagList(
          shiny::tags$strong(sprintf("Class %d (%d px, %.1f ha)", cls, classes$pixel_count[i], classes$area_ha[i])),
          shiny::fluidRow(
            shiny::column(
              6,
              shiny::selectInput(ns(paste0(prefix, "profile")), "Profile", choices = crop_choices)
            ),
            shiny::column(
              6,
              shiny::textInput(ns(paste0(prefix, "label")), "Label", value = paste("Class", cls))
            )
          ),
          shiny::fluidRow(
            shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_ini")), "Kc ini", value = 0.3, step = 0.05)),
            shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_mid")), "Kc mid", value = 1.15, step = 0.05)),
            shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_end")), "Kc end", value = 0.3, step = 0.05))
          ),
          shiny::fluidRow(
            shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_ini")), "L ini (d)", value = 30, min = 0)),
            shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_mid")), "L mid (d)", value = 40, min = 0)),
            shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_late")), "L late (d)", value = 30, min = 0)),
            shiny::column(3, shiny::numericInput(ns(paste0(prefix, "height")), "H (m)", value = 1.0, step = 0.1))
          ),
          shiny::hr()
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
          stringsAsFactors = FALSE
        )
      })

      do.call(rbind, rows)
    }

    active_kc_data <- shiny::reactive({
      params <- collect_crop_params()
      shiny::req(params)
      total_days_vec <- stats::setNames(rep(150, nrow(params)), as.character(params$class_value))
      tryCatch(Rwapor::rwapor_build_kc_by_class(params, total_days_vec), error = function(e) NULL)
    })

    output$an_season_summary <- shiny::renderPrint({
      cat("Season:", input$an_season_label, "\n")
      cat("Reference Year:", input$an_ref_year, "\n")
      cat("Analysis Period:", as.character(input$an_period[1]), "to", as.character(input$an_period[2]), "\n")
      cat("AETI:", input$an_aeti_var, "\n")
      cat("RET:", input$an_ret_var, "\n")
      cat("Precip:", input$an_precip_var, "\n")
      cat("Shared Output Folder:", global_folder() %||% "Not set", "\n")
      cat("\n--- Raster Status ---\n")
      cat("Crop Mask:", if (!is.null(an_crop_mask_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season Start:", if (!is.null(an_start_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season End:", if (!is.null(an_end_rast())) "Loaded" else "Not loaded", "\n")
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
      terra::plot(r, main = "Crop Mask Classes", col = grDevices::hcl.colors(20, "Set2"))
    })

    output$an_season_raster_info <- shiny::renderPrint({
      s_start <- an_start_rast()
      s_end <- an_end_rast()
      if (is.null(s_start) && is.null(s_end)) {
        cat("No season rasters loaded yet.")
        return()
      }

      if (!is.null(s_start)) {
        cat("--- Season Start Raster ---\n")
        vals <- terra::values(s_start, na.rm = TRUE)
        cat(sprintf("  Dimensions: %d x %d\n", nrow(s_start), ncol(s_start)))
        cat(sprintf("  Value range: %d - %d (Julian DOY)\n", min(vals), max(vals)))
        cat(sprintf("  Non-NA pixels: %d\n", length(vals)))
      }

      if (!is.null(s_end)) {
        cat("\n--- Season End Raster ---\n")
        vals <- terra::values(s_end, na.rm = TRUE)
        cat(sprintf("  Dimensions: %d x %d\n", nrow(s_end), ncol(s_end)))
        cat(sprintf("  Value range: %d - %d (Julian DOY)\n", min(vals), max(vals)))
        cat(sprintf("  Non-NA pixels: %d\n", length(vals)))
      }
    })

    output$an_crop_class_table <- shiny::renderTable({
      classes <- an_crop_classes()
      shiny::req(classes)
      classes
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    shiny::observeEvent(input$an_validate_btn, {
      errors <- character()
      if (is.null(an_crop_mask_rast())) errors <- c(errors, "Crop mask raster not uploaded.")
      if (is.null(an_start_rast())) errors <- c(errors, "Season start raster not uploaded.")
      if (is.null(an_end_rast())) errors <- c(errors, "Season end raster not uploaded.")
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
      shiny::showNotification("Analysis state reset.", type = "message")
    })

    shiny::observeEvent(input$an_run_btn, {
      if (is.null(an_crop_mask_rast()) || is.null(an_start_rast()) || is.null(an_end_rast())) {
        shiny::showNotification(
          "Please upload crop mask, season start, and season end rasters first.",
          type = "error"
        )
        return()
      }

      crop_params <- collect_crop_params()
      if (is.null(crop_params) || nrow(crop_params) == 0) {
        shiny::showNotification("No crop class parameters defined.", type = "error")
        return()
      }

      indicators <- unique(c(input$an_agg_vars, input$an_derived_vars))
      if (length(indicators) == 0) {
        shiny::showNotification("Select at least one indicator.", type = "error")
        return()
      }

      an_peff_monthly(NULL)

      shiny::withProgress(message = "Running analysis...", value = 0, {
        tryCatch({
          ref_year <- input$an_ref_year
          period <- as.character(input$an_period)
          reg <- current_region()
          aeti_var <- input$an_aeti_var
          ret_var <- input$an_ret_var
          precip_var <- input$an_precip_var
          l3_code <- if (grepl("^L3-", aeti_var %||% "")) input$an_l3_region else NULL

          shiny::incProgress(0.05, detail = "Fetching reference AETI raster...")
          ref_urls <- Rwapor::wapor_generate_urls(aeti_var, l3_region = l3_code, period = period)
          if (length(ref_urls) == 0) stop("No AETI data found for the specified period.")

          template_r <- terra::rast(paste0("/vsicurl/", ref_urls[1]))
          reg_info <- NULL
          if (!is.null(reg)) {
            reg_info <- Rwapor::parse_region(reg)
            template_r <- crop_to_region_shiny(template_r, reg_info, do_mask = FALSE)
          }

          shiny::incProgress(0.10, detail = "Harmonizing rasters...")
          h_mask <- Rwapor::rwapor_harmonize_crop_mask(an_crop_mask_rast(), template_r)
          h_start <- Rwapor::rwapor_harmonize_to_template(an_start_rast(), template_r, method = "near")
          h_end <- Rwapor::rwapor_harmonize_to_template(an_end_rast(), template_r, method = "near")

          s_start_vals <- terra::values(h_start, na.rm = TRUE)
          s_end_vals <- terra::values(h_end, na.rm = TRUE)
          if (length(s_start_vals) == 0 || length(s_end_vals) == 0) {
            stop("Season rasters have no valid pixels after harmonization.")
          }

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
          need_npp_stack <- "cwp_bwp" %in% indicators && is.null(input$an_biomass_file)

          shiny::incProgress(0.15, detail = "Fetching remote data...")
          aeti_stack <- ret_stack <- precip_stack <- npp_stack <- NULL

          if (need_aeti_stack) {
            aeti_urls <- Rwapor::wapor_generate_urls(aeti_var, l3_region = l3_code, period = period)
            aeti_stack <- terra::rast(paste0("/vsicurl/", aeti_urls))
            if (!is.null(reg_info)) aeti_stack <- crop_to_region_shiny(aeti_stack, reg_info, do_mask = FALSE)
            aeti_meta <- Rwapor::get_variable_metadata(aeti_var)
            if (!is.null(aeti_meta)) aeti_stack <- aeti_stack * aeti_meta$scale
          }

          if (need_ret_stack) {
            ret_urls <- Rwapor::wapor_generate_urls(ret_var, l3_region = l3_code, period = period)
            ret_stack <- terra::rast(paste0("/vsicurl/", ret_urls))
            if (!is.null(reg_info)) ret_stack <- crop_to_region_shiny(ret_stack, reg_info, do_mask = FALSE)
            ret_meta <- Rwapor::get_variable_metadata(ret_var)
            if (!is.null(ret_meta)) ret_stack <- ret_stack * ret_meta$scale
          }

          if (need_precip_stack) {
            precip_urls <- Rwapor::wapor_generate_urls(precip_var, l3_region = l3_code, period = period)
            if (length(precip_urls) > 0) {
              precip_stack <- terra::rast(paste0("/vsicurl/", precip_urls))
              if (!is.null(reg_info)) precip_stack <- crop_to_region_shiny(precip_stack, reg_info, do_mask = FALSE)
              precip_meta <- Rwapor::get_variable_metadata(precip_var)
              if (!is.null(precip_meta)) precip_stack <- precip_stack * precip_meta$scale
            }
          }

          if (need_npp_stack) {
            npp_urls <- Rwapor::wapor_generate_urls(input$an_npp_var, l3_region = l3_code, period = period)
            if (length(npp_urls) > 0) {
              npp_stack <- terra::rast(paste0("/vsicurl/", npp_urls))
              if (!is.null(reg_info)) npp_stack <- crop_to_region_shiny(npp_stack, reg_info, do_mask = FALSE)
              npp_meta <- Rwapor::get_variable_metadata(input$an_npp_var)
              if (!is.null(npp_meta)) npp_stack <- npp_stack * npp_meta$scale
            }
          }

          n_wt <- terra::nlyr(season_weights)
          trim_stack <- function(s, n) {
            if (is.null(s)) return(NULL)
            s[[seq_len(min(terra::nlyr(s), n))]]
          }
          aeti_stack <- trim_stack(aeti_stack, n_wt)
          ret_stack <- trim_stack(ret_stack, n_wt)
          precip_stack <- trim_stack(precip_stack, n_wt)
          npp_stack <- trim_stack(npp_stack, n_wt)

          n_layers <- n_wt
          if (!is.null(aeti_stack)) n_layers <- min(n_layers, terra::nlyr(aeti_stack))
          if (!is.null(ret_stack)) n_layers <- min(n_layers, terra::nlyr(ret_stack))
          if (!is.null(precip_stack)) n_layers <- min(n_layers, terra::nlyr(precip_stack))
          if (!is.null(npp_stack)) n_layers <- min(n_layers, terra::nlyr(npp_stack))

          season_weights <- season_weights[[seq_len(n_layers)]]
          if (!is.null(aeti_stack)) aeti_stack <- aeti_stack[[seq_len(n_layers)]]
          if (!is.null(ret_stack)) ret_stack <- ret_stack[[seq_len(n_layers)]]
          if (!is.null(precip_stack)) precip_stack <- precip_stack[[seq_len(n_layers)]]
          if (!is.null(npp_stack)) npp_stack <- npp_stack[[seq_len(n_layers)]]

          shiny::incProgress(0.10, detail = "Computing seasonal aggregations...")
          results <- list()

          if (need_aeti_stack && !is.null(aeti_stack)) {
            results$seasonal_aeti <- Rwapor::rwapor_calc_seasonal_aeti_masked(aeti_stack, season_weights, h_mask)
          }
          if (need_ret_stack && !is.null(ret_stack)) {
            results$seasonal_ret <- Rwapor::rwapor_calc_seasonal_ret_masked(ret_stack, season_weights, h_mask)
          }
          if ("agg_pcp" %in% indicators && !is.null(precip_stack)) {
            results$seasonal_pcp <- terra::app(precip_stack * season_weights, fun = "sum", na.rm = TRUE)
          }

          if ("etc" %in% indicators || "adequacy_etc" %in% indicators) {
            shiny::incProgress(0.05, detail = "Computing ETc...")
            etc_by_class <- list()
            for (j in seq_len(nrow(crop_params))) {
              cls <- as.character(crop_params$class_value[j])
              kc_daily <- kc_by_class[[cls]]
              if (length(kc_daily) == 0) next

              dk_tbl <- dekad_table[seq_len(n_layers), , drop = FALSE]
              season_start_date <- as.Date(sprintf("%04d-01-01", ref_year)) + (round(mean(s_start_vals)) - 1)
              kc_dekad <- Rwapor::rwapor_aggregate_kc_dekad(kc_daily, dk_tbl, season_start_date)
              kc_dekad <- kc_dekad[seq_len(n_layers)]
              etc_class <- Rwapor::rwapor_calc_etc_dekad(ret_stack, kc_dekad)
              class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
              etc_class_masked <- etc_class * class_mask
              etc_seasonal <- terra::app(etc_class_masked * season_weights, fun = "sum", na.rm = TRUE)
              etc_by_class[[cls]] <- list(kc_dekad = kc_dekad, etc_seasonal = etc_seasonal)
            }
            results$etc_by_class <- etc_by_class
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

            bio_h <- NULL
            if (!is.null(input$an_biomass_file)) {
              tryCatch({
                bio_r <- terra::rast(input$an_biomass_file$datapath)
                bio_h <- Rwapor::rwapor_harmonize_to_template(bio_r, template_r)
              }, error = function(e) warning("Local biomass load failed: ", e$message))
            } else if (!is.null(npp_stack)) {
              bio_rast <- terra::app(npp_stack * season_weights, fun = "sum", na.rm = TRUE)
              bio_h <- if (grepl("-NPP-", input$an_npp_var %||% "")) bio_rast * 22.22 else bio_rast
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
          }

          shiny::incProgress(0.05, detail = "Done!")
          results$crop_params <- crop_params
          results$kc_by_class <- kc_by_class
          results$dekad_table <- dekad_table[seq_len(n_layers), , drop = FALSE]

          an_results(results)
          an_crop_params(crop_params)
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

      cols <- grDevices::hcl.colors(length(kc_list), "Set2")
      graphics::plot(
        NULL,
        xlim = c(1, max_len),
        ylim = c(0, 1.5),
        xlab = "Day of Season",
        ylab = "Kc",
        main = "Crop Coefficient Curves (Preview)"
      )
      for (i in seq_along(kc_list)) {
        kc <- kc_list[[i]]
        if (length(kc) > 0) {
          graphics::lines(seq_along(kc), kc, col = cols[i], lwd = 2)
        }
      }
      graphics::legend("topright", legend = params$crop_label, col = cols, lwd = 2, cex = 0.8, bg = "white")
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

          rows[[i]] <- data.frame(
            Class = label,
            `AETI (mm)` = round(aeti_tbl$mean_seasonal_aeti[i], 1),
            `RET (mm)` = round(ret_tbl$mean_seasonal_ret[i], 1),
            `ETc (mm)` = if (cls_str %in% names(etc_means)) round(etc_means[cls_str], 1) else NA,
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
