# inst/shiny/mod_analysis_ui_sidebar.R

mod_analysis_ui_sidebar <- function(ns, all_vars, l3_region_choices) {
  bslib::sidebar(
    width = 350,
    open  = TRUE,
    title = "Crop Season Analysis",
    shiny::div(
      class = "sidebar-scroll-area",
      bslib::accordion(
        id   = ns("analysis_config_accordion"),
        open = c("Season Definition", "Variables"),

        # ── 1. Season Definition ─────────────────────────────────
        bslib::accordion_panel(
          "Season Definition", icon = shiny::icon("calendar"),

          shiny::textInput(
            ns("an_season_label"), "Season Label",
            value = "Winter 2023", placeholder = "e.g. Winter 2023"
          ),

          shiny::div(
            class = "inline-row",
            shiny::div(
              style = "width: 90px;",
              shiny::numericInput(
                ns("an_ref_year"), "Reference Year",
                value = 2023, min = 2009, max = 2030, step = 1
              )
            ),
            shiny::div(
              class = "flex-1",
              shiny::dateRangeInput(
                ns("an_period"), "Analysis Period",
                start = "2023-01-01", end = "2023-12-31",
                format = "yyyy-mm-dd"
              )
            )
          )
        ),

        # ── 2. Data Source ───────────────────────────────────────
        bslib::accordion_panel(
          "Data Source", icon = shiny::icon("database"),

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
            shiny::helpText(
              "Reads Cloud-Optimized GeoTIFFs directly from the WaPOR server via GDAL vsicurl. Internet required."
            )
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s'] == 'local'", ns("an_data_source")),
            shiny::tags$div(
              class = "alert alert-info p-2 mb-2 small",
              shiny::icon("circle-info"),
              " Uses files from the project folder (set in Download tab). Folder is scanned automatically when switching to local mode."
            ),
            shiny::actionButton(
              ns("an_scan_local"), "Re-scan Folder",
              icon  = shiny::icon("magnifying-glass"),
              class = "btn-sm btn-outline-primary w-100 mb-2"
            ),
            shiny::verbatimTextOutput(ns("an_local_vars_info"))
          )
        ),

        # ── 3. Variables ─────────────────────────────────────────
        bslib::accordion_panel(
          "Variables", icon = shiny::icon("layer-group"),

          shiny::tags$span("Primary variables", class = "ctrl-group-label"),
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(
                ns("an_aeti_var"), "AETI (Actual ET)",
                choices  = grep("AETI-D", all_vars, value = TRUE),
                selected = if ("L1-AETI-D" %in% all_vars) "L1-AETI-D" else NULL
              )
            ),
            shiny::div(
              class = "flex-1",
              shiny::selectInput(
                ns("an_ret_var"), "RET (Reference ET)",
                choices  = grep("RET|ET0", all_vars, value = TRUE),
                selected = if ("L1-RET-D" %in% all_vars) "L1-RET-D" else NULL
              )
            )
          ),
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(
                ns("an_precip_var"), "Precipitation",
                choices  = grep("PCP|PF", all_vars, value = TRUE),
                selected = if ("L1-PCP-D" %in% all_vars) "L1-PCP-D" else NULL
              )
            ),
            shiny::div(
              class = "flex-1",
              shiny::selectInput(
                ns("an_npp_var"), "Biomass (NPP)",
                choices  = grep("NPP|TBP", all_vars, value = TRUE),
                selected = if ("L1-NPP-D" %in% all_vars) "L1-NPP-D" else NULL
              )
            )
          ),
          shiny::conditionalPanel(
            condition = sprintf(
                "input['%s'] && input['%s'].startsWith('L3-')",
                ns("an_aeti_var"), ns("an_aeti_var")
            ),
            shiny::selectInput(ns("an_l3_region"), "L3 Region", choices = l3_region_choices)
          )
        ),

        # ── 4. Optional Inputs ───────────────────────────────────
        bslib::accordion_panel(
          "Optional Inputs", icon = shiny::icon("upload"),

          shiny::tags$span("Crop Mask", class = "ctrl-group-label"),
          shiny::checkboxInput(
            ns("an_use_crop_mask"),
            "Upload a crop mask raster",
            value = FALSE
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_use_crop_mask")),
            shiny::fileInput(
              ns("an_crop_mask"), NULL,
              accept      = c(".tif", ".tiff"),
              placeholder = "GeoTIFF with integer class values"
            )
          ),

          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Pixel-wise Season Boundaries", class = "ctrl-group-label"),
          shiny::checkboxInput(
            ns("an_use_season_rasters"),
            "Upload season start / end rasters",
            value = FALSE
          ),
          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_use_season_rasters")),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::fileInput(
                  ns("an_season_start"), "Start (DOY)",
                  accept = c(".tif", ".tiff")
                )
              ),
              shiny::div(
                class = "flex-1",
                shiny::fileInput(
                  ns("an_season_end"), "End (DOY)",
                  accept = c(".tif", ".tiff")
                )
              )
            ),
            shiny::helpText(
              "Julian Day-of-Year rasters (1-366). End DOY may exceed 366 for cross-year seasons."
            )
          )
        ),

        # ── 5. Crop Classes ──────────────────────────────────────
        bslib::accordion_panel(
          "Crop Classes", icon = shiny::icon("seedling"),
          shiny::helpText("Upload a crop mask (Optional Inputs) first, then assign Kc profiles per class."),
          shiny::uiOutput(ns("an_crop_class_ui"))
        ),

        # ── 6. Indicators ────────────────────────────────────────
        bslib::accordion_panel(
          "Indicators", icon = shiny::icon("chart-bar"),

          shiny::tags$span("Seasonal Aggregations", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_agg_vars"), NULL,
            choiceNames  = list(
              "AETI \u2013 Actual Evapotranspiration",
              "RET \u2013 Reference ET",
              "PCP \u2013 Total Precipitation",
              "Peff \u2013 Effective Precipitation (USDA)",
              "Biomass (kg/ha)",
              "Biomass (t/ha)"
            ),
            choiceValues = list(
              "agg_aeti", "agg_ret", "agg_pcp", "agg_peff",
              "agg_biomass_kg", "agg_biomass_t"
            ),
            selected = c("agg_aeti", "agg_ret", "agg_biomass_t")
          ),

          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Derived Indicators", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_derived_vars"), NULL,
            choiceNames  = list(
              "ETc \u2013 Crop ET (RET \u00d7 Kc)",
              "Water Adequacy \u2013 ETc basis",
              "Water Adequacy \u2013 P95 basis",
              "CWP / BWP \u2013 Water Productivity",
              "Yield \u2013 NPP-based estimate",
              "Green Water \u2013 AETI from rainfall (requires Peff)",
              "Blue Water \u2013 AETI from irrigation (requires Peff)"
            ),
            choiceValues = list(
              "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "yield_npp",
              "green_water", "blue_water"
            ),
            selected = c("etc", "adequacy_etc", "yield_npp")
          ),

          shiny::conditionalPanel(
            condition = sprintf(
              "input['%s'] && (input['%s'].indexOf('cwp_bwp') > -1 || input['%s'].indexOf('agg_biomass_kg') > -1 || input['%s'].indexOf('agg_biomass_t') > -1 || input['%s'].indexOf('yield_npp') > -1)",
              ns("an_derived_vars"),
              ns("an_derived_vars"), ns("an_agg_vars"), ns("an_agg_vars"), ns("an_derived_vars")
            ),
            shiny::tags$hr(class = "ctrl-divider"),
            shiny::tags$span("Optional Reference Rasters", class = "ctrl-group-label"),
            shiny::div(
              class = "inline-row",
              shiny::div(
                class = "flex-1",
                shiny::fileInput(
                  ns("an_yield_file"), "Yield raster",
                  accept = c(".tif", ".tiff")
                ),
                shiny::selectInput(
                  ns("an_yield_unit"), "Yield unit",
                  choices = c("kg/ha", "t/ha"), selected = "t/ha"
                )
              ),
              shiny::div(
                class = "flex-1",
                shiny::fileInput(
                  ns("an_biomass_file"), "Biomass raster",
                  accept = c(".tif", ".tiff")
                ),
                shiny::selectInput(
                  ns("an_biomass_unit"), "Biomass unit",
                  choices = c("kg/ha", "t/ha"), selected = "t/ha"
                )
              )
            )
          )
        ),

        # ── 7. Output Settings ───────────────────────────────────
        bslib::accordion_panel(
          "Output Settings", icon = shiny::icon("folder-open"),

          shiny::tags$span("Output Folder", class = "ctrl-group-label"),
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::textInput(
                ns("an_folder"), NULL,
                value       = file.path(getwd(), "analysis_output"),
                placeholder = "Path to output folder"
              )
            ),
            shiny::uiOutput(ns("an_favorite_btn_ui")),
            shinyFiles::shinyDirButton(
              ns("an_browse_folder"), label = "",
              icon  = shiny::icon("folder-open"),
              title = "Select output folder",
              class = "btn-outline-secondary btn-sm",
              style = "padding:0.37rem 0.6rem;"
            )
          ),
          shiny::uiOutput(ns("an_favorites_ui")),
          shiny::checkboxInput(
            ns("an_save_rasters"),
            "Save analysis rasters to folder",
            value = TRUE
          )
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
