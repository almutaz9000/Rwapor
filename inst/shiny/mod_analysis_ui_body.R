# inst/shiny/mod_analysis_ui_body.R

mod_analysis_ui_body <- function(ns) {
  bslib::navset_card_tab(
    id = ns("analysis_main_nav"),
    full_screen = TRUE,
    
    # ── TAB 1: Analysis Hub (Workspace) ──────────────────────────────────
    bslib::nav_panel(
      title = "Analysis Hub",
      icon = shiny::icon("gauge-high"),
      
      bslib::layout_column_wrap(
        width = 1,
        fill = TRUE,
        gap = "0.75rem",
        
        # Row 1: Compact Summary (Fixed height)
        bslib::card(
          id = ns("an_card_summary"),
          max_height = "165px",
          bslib::card_body(
            padding = 0,
            bslib::layout_column_wrap(
              width = "250px",
              fill = TRUE,
              shiny::div(
                style = "padding: 0.5rem; font-size: 0.78rem; border-right: 1px solid #eee; background: #fcfcfc; height: 100%;",
                shiny::verbatimTextOutput(ns("an_season_summary"))
              ),
              shiny::div(
                style = "padding: 0.4rem;",
                bslib::layout_column_wrap(
                  width = "140px",
                  fill = FALSE,
                  gap = "0.4rem",
                  bslib::value_box(
                    title = "AETI", value = shiny::textOutput(ns("vbox_aeti")),
                    showcase = shiny::icon("droplet", class = "text-primary"),
                    theme = "light", class = "border-primary py-0 shadow-none"
                  ),
                  bslib::value_box(
                    title = "ETc", value = shiny::textOutput(ns("vbox_etc")),
                    showcase = shiny::icon("sun", class = "text-info"),
                    theme = "light", class = "border-info py-0 shadow-none"
                  ),
                  bslib::value_box(
                    title = "Adequacy", value = shiny::textOutput(ns("vbox_adequacy")),
                    showcase = shiny::icon("percent", class = "text-success"),
                    theme = "light", class = "border-success py-0 shadow-none"
                  ),
                  bslib::value_box(
                    title = "Biomass", value = shiny::textOutput(ns("vbox_biomass")),
                    showcase = shiny::icon("leaf", class = "text-warning"),
                    theme = "light", class = "border-warning py-0 shadow-none"
                  )
                )
              )
            )
          )
        ),
        
        # Row 2: Spatial & Profiles (Fills remaining space)
        bslib::layout_column_wrap(
          id = ns("an_card_spatial_group"),
          width = "400px",
          fill = TRUE,
          gap = "0.75rem",
          bslib::navset_card_tab(
            title = "Spatial Data",
            bslib::nav_panel("Crop Mask", bslib::card_body(fillable = TRUE, padding = 0, shiny::plotOutput(ns("an_crop_mask_plot"), height = "100%"))),
            bslib::nav_panel("Season", bslib::card_body(fillable = TRUE, shiny::verbatimTextOutput(ns("an_season_raster_info")))),
            bslib::nav_panel("Classes", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_crop_class_table"))))
          ),
          bslib::card(
            bslib::card_header(shiny::icon("chart-line"), " Kc Profiles"),
            bslib::card_body(padding = 0, fillable = TRUE, shiny::plotOutput(ns("an_kc_plot"), height = "100%"))
          )
        )
      )
    ),
    
    # ── TAB 2: Indicator Results ─────────────────────────────────────────
    bslib::nav_panel(
      title = "Indicator Results",
      icon = shiny::icon("table"),
      bslib::card(
        id = ns("an_card_results_container"),
        full_screen = TRUE,
        bslib::navset_card_pill(
          id = ns("an_card_results"),
          placement = "above",
          bslib::nav_panel("Main", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_etc_aeti_table")))),
          bslib::nav_panel("Adequacy", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_adequacy_table")))),
          bslib::nav_panel("Eff. Precip", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_peff_table")))),
          bslib::nav_panel("CWP/BWP", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_cwp_bwp_table")))),
          bslib::nav_panel("Water Sources", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_green_blue_table")))),
          bslib::nav_panel("Beneficial", bslib::card_body(fillable = TRUE, shiny::tableOutput(ns("an_beneficial_table")))),
          
          footer = shiny::div(
            class = "d-flex gap-2 p-2 border-top bg-light",
            shiny::downloadButton(ns("an_dl_results"), "Results CSV", class = "btn-sm btn-outline-primary"),
            shiny::downloadButton(ns("an_dl_params"), "Params CSV", class = "btn-sm btn-outline-secondary")
          )
        )
      )
    ),
    
    # ── TAB 3: Technical Console ─────────────────────────────────────────
    bslib::nav_panel(
      title = "Technical Console",
      icon = shiny::icon("code"),
      bslib::card(
        id = ns("an_card_console"),
        class = "console-card",
        full_screen = TRUE,
        bslib::card_header(
          class = "console-header",
          shiny::div(
            class = "d-flex align-items-center justify-content-between",
            shiny::div(shiny::icon("code"), " R Script Console"),
            shiny::downloadLink(ns("an_dl_script"), shiny::icon("download"), class = "text-white")
          )
        ),
        bslib::card_body(
          class = "console-body",
          padding = 0,
          shinyAce::aceEditor(
            ns("an_code_preview"),
            mode = "r", theme = "monokai", readOnly = TRUE,
            height = "100%", fontSize = 12,
            wordWrap = TRUE, showLineNumbers = TRUE
          )
        ),
        bslib::card_footer(
          class = "console-footer",
          shiny::div(
            class = "d-flex align-items-center justify-content-between small opacity-75",
            shiny::div(shiny::icon("terminal"), " Reproducible Extraction Script"),
            shiny::checkboxInput(ns("an_incremental"), "Optimize Memory", value = FALSE)
          )
        )
      )
    )
  )
}
