# inst/shiny/mod_analysis_ui_body.R

mod_analysis_ui_body <- function(ns) {
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
              ),
              bslib::value_box(
                title = "Beneficial Frac.",
                value = shiny::textOutput(ns("vbox_beneficial")),
                showcase = shiny::icon("chart-pie", class = "text-secondary"),
                theme = "light",
                class = "border-secondary py-1"
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
      bslib::nav_panel("CWP/BWP", shiny::tableOutput(ns("an_cwp_bwp_table"))),
      bslib::nav_panel("Green/Blue Water", shiny::tableOutput(ns("an_green_blue_table")))
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
        shiny::div(
          class = "mt-2",
          shiny::downloadButton(ns("an_dl_script"), "Download R Script", class = "btn-outline-secondary w-100 btn-sm")
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
}
