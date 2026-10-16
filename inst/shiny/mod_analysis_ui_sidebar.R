# inst/shiny/mod_analysis_ui_sidebar.R

# First preferred variable present in the catalogue, or NULL (selectInput's
# own default) when none is.
.an_first_available <- function(preferred, all_vars) {
  hit <- preferred[preferred %in% all_vars]
  if (length(hit)) hit[[1]] else NULL
}

mod_analysis_ui_sidebar <- function(ns, all_vars, l3_region_choices) {
  step_title <- function(n, label) {
    shiny::tagList(
      shiny::tags$span(as.character(n), class = "wizard-step-num"),
      label
    )
  }

  bslib::sidebar(
    width = 350,
    open  = TRUE,
    title = "Crop Season Analysis",
    shiny::div(
      class = "sidebar-scroll-area",
      bslib::accordion(
        id = ns("analysis_accordion"),
        open = c("1", "4"),
        multiple = TRUE,
        
        # ── STEP 1: Data & Period ─────────────────────────────────
        bslib::accordion_panel(
          value = "1", title = step_title(1, "Data & Period"), icon = shiny::icon("database"),
          
          # 1. Data Source
          shiny::tags$span("Data Source", class = "ctrl-group-label"),
          shiny::radioButtons(
            ns("an_data_source"), NULL,
            choices = c(
              "Stream from API (online)"      = "api",
              "Use local downloaded files"    = "local"
            ),
            selected = "api"
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s'] == 'api'", ns("an_data_source")),
            shiny::helpText("Reads COGs directly from WaPOR server via GDAL vsicurl.")
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s'] == 'local'", ns("an_data_source")),
            shiny::radioButtons(
              ns("an_project_folder_mode"), NULL,
              choices = c("Use Download tab" = "download", "Manual" = "manual"),
              selected = "download"
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'manual'", ns("an_project_folder_mode")),
              shiny::div(
                class = "inline-row",
                shiny::div(class = "flex-1", shiny::textInput(ns("an_project_folder"), "Project Folder", value = "")),
                shinyFiles::shinyDirButton(ns("an_browse_project_folder"), label = "", title = "Select Project Folder", icon = shiny::icon("folder-open"), class = "btn-outline-secondary btn-sm", style = "margin-top: 25px;")
              )
            ),
            shiny::actionButton(ns("an_scan_local"), "Re-scan Folder", icon = shiny::icon("search"), class = "btn-sm btn-outline-primary w-100 mb-2"),
            shiny::verbatimTextOutput(ns("an_local_vars_info"))
          ),
          
          shiny::tags$hr(class = "ctrl-divider"),
          
          # 2. Season Definition
          shiny::tags$span("Season Definition", class = "ctrl-group-label"),
          shiny::textInput(ns("an_season_label"), "Season Label", value = "Winter 2023"),
          shiny::div(
            class = "d-flex align-items-center justify-content-between mb-1",
            shiny::checkboxInput(ns("an_batch_mode"), "Batch Mode", FALSE),
            shiny::actionLink(ns("an_batch_help"), "Batch Guide", icon = shiny::icon("circle-question"), class = "small text-primary")
          ),
          shiny::conditionalPanel(
            condition = sprintf("!input['%s']", ns("an_batch_mode")),
            shiny::dateRangeInput(ns("an_period"), "Analysis Period", start = "2023-01-01", end = "2023-12-31")
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_batch_mode")),
            shiny::textAreaInput(
              ns("an_batch_list"), NULL,
              placeholder = "Winter_2021, 2021-11-01, 2022-04-30\nSummer_2022, 2022-05-15, 2022-09-30",
              rows = 3
            ),
            shiny::helpText("Format: Label, Start (YYYY-MM-DD), End (YYYY-MM-DD)."),
            shiny::div(
              class = "d-flex gap-1",
              shiny::actionButton(ns("an_copy_from_download"), "Copy DL", icon = shiny::icon("copy"), class = "btn-sm btn-outline-info flex-1"),
              shiny::actionButton(ns("an_detect_seasons"), "Detect", icon = shiny::icon("wand-magic-sparkles"), class = "btn-sm btn-outline-secondary flex-1")
            )
          )
        ),

        # ── STEP 2: Masking & Timing ──────────────────────────────
        bslib::accordion_panel(
          value = "2", title = step_title(2, "Masking & Timing"), icon = shiny::icon("map-location-dot"),
          
          shiny::div(
            class = "d-flex align-items-center justify-content-between mb-1",
            shiny::tags$span("Custom Timing (Optional)", class = "ctrl-group-label mb-0"),
            shiny::actionLink(ns("an_timing_help"), "Timing Guide", icon = shiny::icon("circle-question"), class = "small text-primary")
          ),
          shiny::checkboxInput(ns("an_use_custom_timing"), "Generate from Vector & CSV", value = FALSE),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_use_custom_timing")),
            shiny::fileInput(ns("an_mask_vector"), "Boundaries (.geojson/.shp)", accept = c(".geojson", ".shp", ".zip"), width = "100%"),
            shiny::fileInput(ns("an_mask_csv"), "Plot Dates (.csv)", accept = ".csv", width = "100%"),
            shiny::div(
              class = "inline-row",
              shiny::div(class = "flex-1", shiny::selectInput(ns("an_mask_season_col"), "Season Col", choices = NULL)),
              shiny::div(class = "flex-1", shiny::selectInput(ns("an_mask_crop_col"), "Crop Col", choices = NULL))
            ),
            shiny::actionButton(ns("an_generate_masks"), "Update Masks", icon = shiny::icon("gears"), class = "btn-sm btn-outline-info w-100 mb-2")
          ),
          
          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Optional Inputs", class = "ctrl-group-label"),
          shiny::checkboxInput(ns("an_use_crop_mask"), "Upload crop mask", value = FALSE),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_use_crop_mask")),
            shiny::fileInput(ns("an_crop_mask"), NULL, accept = c(".tif", ".tiff"))
          ),
          shiny::checkboxInput(ns("an_use_season_rasters"), "Upload season rasters", value = FALSE),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_use_season_rasters")),
            shiny::div(
              class = "inline-row",
              shiny::div(class = "flex-1", shiny::fileInput(ns("an_season_start"), "Start (DOY)")),
              shiny::div(class = "flex-1", shiny::fileInput(ns("an_season_end"), "End (DOY)"))
            )
          )
        ),

        # ── STEP 3: Crop Specs ────────────────────────────────────
        bslib::accordion_panel(
          value = "3", title = step_title(3, "Crop Specs"), icon = shiny::icon("seedling"),
          shiny::div(
            class = "d-flex align-items-center justify-content-between mb-1",
            shiny::tags$span("FAO-56 Parameters", class = "ctrl-group-label mb-0"),
            shiny::actionLink(ns("an_crop_params_help"), "Crop Guide", icon = shiny::icon("circle-question"), class = "small text-primary")
          ),
          shiny::helpText("Configure FAO-56 crop parameters (Kc, Lengths, HI) per class or for the entire area (single-crop)."),
          shiny::uiOutput(ns("an_crop_class_ui"))
        ),

        # ── STEP 4: Analysis Targets ──────────────────────────────
        bslib::accordion_panel(
          value = "4", title = step_title(4, "Analysis Targets"), icon = shiny::icon("chart-bar"),
          
          shiny::tags$span("Primary Variables", class = "ctrl-group-label"),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_aeti_var"), "AETI (Actual ET)", choices = grep("AETI-D", all_vars, value = TRUE))),
            shiny::div(class = "flex-1", shiny::selectInput(
              ns("an_ret_var"), "RET (Reference ET)",
              choices = grep("RET|ET0", all_vars, value = TRUE),
              # Default to a dekadal product: the first alphabetical match is annual AgERA5.
              selected = .an_first_available(c("L1-RET-D", "AGERA5-ET0-D", "AGERA5-ET0-E"), all_vars)
            ))
          ),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_t_var"), "Transpiration (T)", choices = c("None" = "", grep("[-](T|ACT-T|TRA)[-]", all_vars, value = TRUE)))),
            shiny::div(class = "flex-1", shiny::selectInput(
              ns("an_precip_var"), "Precipitation",
              choices = grep("PCP|PF", all_vars, value = TRUE),
              selected = .an_first_available(c("L1-PCP-D", "AGERA5-PF-D", "AGERA5-PF-E"), all_vars)
            ))
          ),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_npp_var"), "Biomass (NPP)", choices = grep("NPP|TBP", all_vars, value = TRUE))),
            shiny::div(class = "flex-1", style = "visibility: hidden;")
          ),
          
          shiny::uiOutput(ns("an_l3_policy_ui")),
          shiny::tags$hr(class = "ctrl-divider"),
          shiny::div(
            class = "d-flex align-items-center justify-content-between mb-1",
            shiny::tags$span("Seasonal Indicators", class = "ctrl-group-label mb-0"),
            shiny::actionLink(ns("an_indicators_help"), "Indicators Guide", icon = shiny::icon("circle-question"), class = "small text-primary")
          ),
          shiny::uiOutput(ns("an_indicator_registry_ui"))
        ),

        # ── STEP 5: Output Folder ─────────────────────────────────
        bslib::accordion_panel(
          value = "5", title = step_title(5, "Output Folder"), icon = shiny::icon("folder-open"),
          
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::textInput(ns("an_folder"), NULL, value = file.path(getwd(), "analysis_output"))),
            shiny::uiOutput(ns("an_favorite_btn_ui")),
            shinyFiles::shinyDirButton(ns("an_browse_folder"), label = "", title = "Select Output Folder", icon = shiny::icon("folder-open"), class = "btn-outline-secondary btn-sm")
          ),
          shiny::uiOutput(ns("an_folder_status_ui")),
          shiny::uiOutput(ns("an_favorites_ui")),
          shiny::checkboxInput(ns("an_save_rasters"), "Save rasters", value = TRUE),
          shiny::checkboxInput(ns("an_include_monthly_exports"), "Monthly exports", value = FALSE)
        )
      )
    ),

    shiny::div(
      class = "sidebar-sticky-footer",
      shiny::div(
        style = "display:flex; gap:5px;",
        shiny::actionButton(
          ns("an_validate_btn"), "Validate",
          class = "btn-sm btn-outline-primary flex-fill",
          icon  = shiny::icon("circle-check")
        ),
        shiny::actionButton(
          ns("an_run_btn"), "Run Analysis",
          class = "btn-sm btn-primary flex-fill",
          icon  = shiny::icon("play")
        ),
        shiny::actionButton(
          ns("an_reset_btn"), NULL,
          class = "btn-sm btn-outline-danger",
          icon  = shiny::icon("rotate-left"),
          title = "Reset all inputs"
        )
      )
    )
  )
}
