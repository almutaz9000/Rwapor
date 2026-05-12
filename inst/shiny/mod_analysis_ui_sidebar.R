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
        open = c("Data Source", "Season Definition", "Variables"),

        # ── 1. Data Source ───────────────────────────────────────
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
              " Local mode reads downloaded rasters from a project folder. By default it follows the Download tab, but you can point Analysis to an older project folder directly."
            ),
            shiny::radioButtons(
              ns("an_project_folder_mode"), NULL,
              choices = c(
                "Use Download tab folder" = "download",
                "Choose project folder here" = "manual"
              ),
              selected = "download"
            ),
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'manual'", ns("an_project_folder_mode")),
              shiny::div(
                class = "inline-row",
                shiny::div(
                  class = "flex-1",
                  shiny::textInput(
                    ns("an_project_folder"), "Project Folder",
                    value = "",
                    placeholder = "Path to folder containing downloaded WaPOR variable subfolders"
                  )
                ),
                shinyFiles::shinyDirButton(
                  ns("an_browse_project_folder"), label = "",
                  icon  = shiny::icon("folder-open"),
                  title = "Select project folder for local analysis",
                  class = "btn-outline-secondary btn-sm",
                  style = "margin-top: 25px; padding: 0.37rem 0.6rem;"
                )
              )
            ),
            shiny::actionButton(
              ns("an_scan_local"), "Re-scan Folder",
              icon  = shiny::icon("magnifying-glass"),
              class = "btn-sm btn-outline-primary w-100 mb-2"
            ),
            shiny::verbatimTextOutput(ns("an_local_vars_info"))
          )
        ),

        # ── 2. Season Definition ─────────────────────────────────
        bslib::accordion_panel(
          "Season Definition", icon = shiny::icon("calendar"),

          shiny::textInput(
            ns("an_season_label"), "Season Label",
            value = "Winter 2023", placeholder = "e.g. Winter 2023"
          ),

          shiny::checkboxInput(ns("an_batch_mode"), "Run for multiple seasons (Batch Mode)", FALSE),

          shiny::conditionalPanel(
            condition = sprintf("!input['%s']", ns("an_batch_mode")),
            shiny::div(
              class = "inline-row",
              shiny::div(
                style = "width: 90px;",
                shiny::numericInput(
                  ns("an_ref_year"), "Ref Year",
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

          shiny::conditionalPanel(
            condition = sprintf("input['%s']", ns("an_batch_mode")),
            shiny::tags$p(
              class = "text-muted mb-1",
              style = "font-size:0.78rem;",
              "One season per line: ",
              shiny::tags$code("Label, YYYY-MM-DD, YYYY-MM-DD")
            ),
            shiny::textAreaInput(
              ns("an_batch_list"), NULL,
              placeholder = "Winter2018, 2018-10-01, 2019-05-31\nWinter2019, 2019-10-01, 2020-05-31",
              rows = 5
            ),
            shiny::div(
              class = "d-flex gap-1 mb-1",
              shiny::actionButton(
                ns("an_copy_from_download"), "Copy from Download",
                icon = shiny::icon("copy"),
                class = "btn-sm btn-outline-info flex-1"
              ),
              shiny::actionButton(
                ns("an_detect_seasons"), "Detect from Folder",
                icon = shiny::icon("wand-magic-sparkles"),
                class = "btn-sm btn-outline-secondary flex-1"
              )
            ),
            shiny::actionButton(
              ns("an_load_seasons_json"), "Load seasons from project folder (seasons.json)",
              icon  = shiny::icon("folder-open"),
              class = "btn-sm btn-outline-secondary w-100 mb-2"
            )
          )
        ),

        # ── 2. Custom Timing (Optional) ──────────────────────────
        bslib::accordion_panel(
          "Custom Timing (Optional)", icon = shiny::icon("map-location-dot"),
          shiny::helpText("Upload plot boundaries and specific dates to generate heterogeneous timing masks."),
          
          shiny::fileInput(ns("an_mask_vector"), "Vector File (Plot Boundaries)", 
                           accept = c(".geojson", ".shp", ".zip"), width = "100%"),
          
          shiny::fileInput(ns("an_mask_csv"), "CSV File (Plot Dates)", 
                           accept = ".csv", width = "100%"),
          
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_season_col"), "Grouping Column (Season)", choices = NULL)
            ),
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_crop_col"), "Crop Column", choices = NULL)
            )
          ),
          shiny::helpText("The Grouping Column is required to separate multi-year data into distinct seasonal masks."),
          
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_vector_id_col"), "Vector ID Col", choices = NULL)
            ),
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_csv_id_col"), "CSV ID Col", choices = NULL)
            )
          ),
          
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_start_col"), "Start Date Col", choices = NULL)
            ),
            shiny::div(
              class = "flex-1",
              shiny::selectInput(ns("an_mask_end_col"), "End Date Col", choices = NULL)
            )
          ),
          
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectizeInput(ns("an_mask_template_file"), "Reference Template (Optional)", 
                                   choices = NULL, options = list(placeholder = "Auto-detect from data"))
            ),
            shinyFiles::shinyFilesButton(
              ns("an_browse_template"), label = "",
              icon  = shiny::icon("folder-open"),
              title = "Select reference template raster",
              multiple = FALSE,
              class = "btn-outline-secondary btn-sm",
              style = "margin-top: 25px; padding: 0.37rem 0.6rem;"
            )
          ),
          shiny::helpText("Select a specific raster to use as the spatial grid template."),
          
          shiny::actionButton(
            ns("an_generate_masks"), "Generate/Update Timing Masks",
            icon = shiny::icon("gears"),
            class = "btn-sm btn-outline-info w-100"
          ),
          shiny::tags$hr(class = "ctrl-divider")
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
          shiny::div(
            class = "inline-row",
            shiny::div(
              class = "flex-1",
              shiny::selectInput(
                ns("an_t_var"), "Transpiration (T)",
                choices  = c("None" = "", grep("-T-D", all_vars, value = TRUE)),
                selected = ""
              )
            ),
            shiny::div(class = "flex-1") # Placeholder
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

          shiny::tags$span("Seasonal Aggregation of Specified Variables", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_agg_vars"), NULL,
            choiceNames  = list(
              "PCP \u2013 Total Precipitation",
              "RET \u2013 Reference ET",
              "AETI \u2013 Actual Evapotranspiration",
              "T \u2013 Transpiration",
              "Biomass (kg/ha)",
              "Biomass (t/ha)"
            ),
            choiceValues = list(
              "agg_pcp", "agg_ret", "agg_aeti", "agg_t",
              "agg_biomass_kg", "agg_biomass_t"
            ),
            selected = c("agg_pcp", "agg_ret", "agg_aeti", "agg_biomass_t")
          ),

          shiny::tags$hr(class = "ctrl-divider"),
          shiny::tags$span("Dekadal or Monthly Indicators", class = "ctrl-group-label"),
          shiny::checkboxGroupInput(
            ns("an_derived_vars"), NULL,
            choiceNames  = list(
              "Peff \u2013 Effective Precipitation (USDA)",
              "ETc \u2013 Crop ET (RET \u00d7 Kc)",
              "Water Adequacy \u2013 ETc basis",
              "Water Adequacy \u2013 P95 basis",
              "CWP / BWP \u2013 Water Productivity",
              "Yield \u2013 NPP-based estimate",
              "Beneficial Fraction (T/AETI)",
              "Green Water \u2013 AETI from rainfall (requires Peff)",
              "Blue Water \u2013 AETI from irrigation (requires Peff)"
            ),
            choiceValues = list(
              "peff", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "yield_npp",
              "beneficial_fraction", "green_water", "blue_water"
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

          shiny::tags$span("Analysis Output Folder", class = "ctrl-group-label"),
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
              title = "Browse for folder (Desktop / Downloads / Documents and all drives are available as starting points)",
              class = "btn-outline-secondary btn-sm",
              style = "padding:0.37rem 0.6rem;"
            )
          ),
          shiny::div(
            class = "d-flex align-items-center justify-content-between",
            style = "min-height: 24px; margin-bottom: 4px;",
            shiny::uiOutput(ns("an_folder_status_ui")),
            shinyjs::hidden(
              shiny::actionButton(
                ns("an_create_folder_btn"), "Create",
                icon  = shiny::icon("folder-plus"),
                class = "btn-outline-success btn-sm",
                style = "padding: 0.1rem 0.5rem; font-size: 0.75rem;"
              )
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
