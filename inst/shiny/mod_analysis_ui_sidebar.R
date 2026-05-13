# inst/shiny/mod_analysis_ui_sidebar.R

mod_analysis_ui_sidebar <- function(ns, all_vars, l3_region_choices) {
  bslib::sidebar(
    width = 350,
    open  = TRUE,
    title = "Crop Season Analysis",
    shiny::div(
      class = "sidebar-scroll-area analysis-sidebar-pills",
      bslib::navset_pill_list(
        id = ns("analysis_config_nav"),
        widths = c(12, 12), # Stacked layout within sidebar
        well = FALSE,
        
        # ── TAB 1: Data & Period ─────────────────────────────────
        bslib::nav_panel(
          shiny::span(shiny::icon("database"), " Data & Period"),
          
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
          shiny::checkboxInput(ns("an_batch_mode"), "Batch Mode", FALSE),
          shiny::conditionalPanel(
            condition = sprintf("!input['%s']", ns("an_batch_mode")),
            shiny::div(
              class = "inline-row",
              shiny::div(style = "width: 80px;", shiny::numericInput(ns("an_ref_year"), "Ref Year", value = 2023, min = 2009, max = 2030)),
              shiny::div(class = "flex-1", shiny::dateRangeInput(ns("an_period"), "Analysis Period", start = "2023-01-01", end = "2023-12-31"))
            )
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_batch_mode")),
            shiny::textAreaInput(ns("an_batch_list"), NULL, placeholder = "Label, Start, End", rows = 4),
            shiny::div(
              class = "d-flex gap-1",
              shiny::actionButton(ns("an_copy_from_download"), "Copy DL", icon = shiny::icon("copy"), class = "btn-sm btn-outline-info flex-1"),
              shiny::actionButton(ns("an_detect_seasons"), "Detect", icon = shiny::icon("wand-magic-sparkles"), class = "btn-sm btn-outline-secondary flex-1")
            )
          )
        ),

        # ── TAB 2: Masking & Timing ──────────────────────────────
        bslib::nav_panel(
          shiny::span(shiny::icon("map-location-dot"), " Masking & Timing"),
          
          shiny::tags$span("Custom Timing (Optional)", class = "ctrl-group-label"),
          shiny::fileInput(ns("an_mask_vector"), "Boundaries (.geojson/.shp)", accept = c(".geojson", ".shp", ".zip"), width = "100%"),
          shiny::fileInput(ns("an_mask_csv"), "Plot Dates (.csv)", accept = ".csv", width = "100%"),
          
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_mask_season_col"), "Season Col", choices = NULL)),
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_mask_crop_col"), "Crop Col", choices = NULL))
          ),
          
          shiny::actionButton(ns("an_generate_masks"), "Update Masks", icon = shiny::icon("gears"), class = "btn-sm btn-outline-info w-100"),
          
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

        # ── TAB 3: Crop Specs ────────────────────────────────────
        bslib::nav_panel(
          shiny::span(shiny::icon("seedling"), " Crop Specs"),
          shiny::helpText("Assign Kc profiles per class. Requires a crop mask."),
          shiny::uiOutput(ns("an_crop_class_ui"))
        ),

        # ── TAB 4: Analysis Targets ──────────────────────────────
        bslib::nav_panel(
          shiny::span(shiny::icon("chart-bar"), " Analysis Targets"),
          
          shiny::tags$span("Primary Variables", class = "ctrl-group-label"),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_aeti_var"), "AETI (Actual ET)", choices = grep("AETI-D", all_vars, value = TRUE))),
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_ret_var"), "RET (Reference ET)", choices = grep("RET|ET0", all_vars, value = TRUE)))
          ),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_t_var"), "Transpiration (T)", choices = c("None" = "", grep("[-](T|ACT-T|TRA)[-]", all_vars, value = TRUE)))),
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_precip_var"), "Precipitation", choices = grep("PCP|PF", all_vars, value = TRUE)))
          ),
          shiny::div(
            class = "inline-row",
            shiny::div(class = "flex-1", shiny::selectInput(ns("an_npp_var"), "Biomass (NPP)", choices = grep("NPP|TBP", all_vars, value = TRUE))),
            shiny::div(class = "flex-1", style = "visibility: hidden;")
          ),
          
          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Seasonal Aggregation", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_agg_vars"), NULL,
            choiceNames = list("PCP Total", "RET Total", "AETI Total", "Biomass (t/ha)"),
            choiceValues = list("agg_pcp", "agg_ret", "agg_aeti", "agg_biomass_t"),
            selected = c("agg_pcp", "agg_ret", "agg_aeti", "agg_biomass_t"),
            inline = TRUE
          ),

          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Calculated Indicators", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_derived_vars"), NULL,
            choiceNames = list(
              "Peff (Effective Precip)", "ETc (Crop ET)", "Adequacy (ETc based)", 
              "CWP/BWP (Water Prod.)", "Yield (NPP based)", "Beneficial Fraction"
            ),
            choiceValues = list(
              "peff", "etc", "adequacy_etc", "cwp_bwp", "yield_npp", "beneficial_fraction"
            ),
            selected = c("etc", "adequacy_etc", "yield_npp")
          )
        ),

        # ── TAB 5: Output Folder ─────────────────────────────────
        bslib::nav_panel(
          shiny::span(shiny::icon("folder-open"), " Output Folder"),
          
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
