# mod_timeseries.R ── Vector-based time series, seasonal values, and regression
# Requires: shiny, bslib, ggplot2, dplyr, DT, sf, Rwapor, shinycssloaders

# ── Palette & theme helpers ────────────────────────────────────────────────────

.ts_pal <- function(n, name) {
  switch(name,
    viridis  = viridisLite::viridis(n, option = "D"),
    plasma   = viridisLite::viridis(n, option = "C"),
    magma    = viridisLite::viridis(n, option = "A"),
    Set1     = grDevices::colorRampPalette(RColorBrewer::brewer.pal(min(9,  max(3, n)), "Set1"))(n),
    Set2     = grDevices::colorRampPalette(RColorBrewer::brewer.pal(min(8,  max(3, n)), "Set2"))(n),
    Dark2    = grDevices::colorRampPalette(RColorBrewer::brewer.pal(min(8,  max(3, n)), "Dark2"))(n),
    Paired   = grDevices::colorRampPalette(RColorBrewer::brewer.pal(min(12, max(3, n)), "Paired"))(n),
    grDevices::colorRampPalette(c("#1a5276","#1e8449","#b7950b","#922b21","#6c3483"))(n)
  )
}

.ts_theme <- function(name, base_size = 13) {
  base <- switch(name,
    classic  = ggplot2::theme_classic(base_size  = base_size),
    bw       = ggplot2::theme_bw(base_size        = base_size),
    light    = ggplot2::theme_light(base_size      = base_size),
    linedraw = ggplot2::theme_linedraw(base_size   = base_size),
    ggplot2::theme_minimal(base_size = base_size)   # default: minimal
  )
  base + ggplot2::theme(
    plot.title       = ggplot2::element_text(face = "bold", size = base_size + 2,
                                             margin = ggplot2::margin(b = 4)),
    plot.subtitle    = ggplot2::element_text(colour = "grey45", size = base_size - 1,
                                             margin = ggplot2::margin(b = 8)),
    plot.caption     = ggplot2::element_text(colour = "grey55", size = base_size - 3,
                                             margin = ggplot2::margin(t = 6)),
    strip.text       = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.key.size  = ggplot2::unit(0.45, "cm")
  )
}


# ── UI ─────────────────────────────────────────────────────────────────────────
#' Timeseries Module UI
#' @param id Module namespace ID
#' @export
mod_timeseries_ui <- function(id) {
  ns <- NS(id)

  bslib::page_fillable(
    padding = 0,
    # Compact sidebar accordion styling
    shiny::tags$head(shiny::tags$style(shiny::HTML(
      sprintf("
        #%s .accordion-button { font-size: 0.82rem; padding: 0.45rem 0.8rem; font-weight: 600; }
        #%s .accordion-body   { padding: 0.5rem 0.8rem 0.6rem; }
        #%s .form-label, #%s label { font-size: 0.82rem; margin-bottom: 2px; }
        #%s .form-control, #%s .form-select { font-size: 0.82rem; }
        #%s .help-block { font-size: 0.78rem; color: #6c757d; margin-top: 2px; }
      ", ns(""), ns(""), ns(""), ns(""), ns(""), ns(""), ns(""))
    ))),

    bslib::layout_sidebar(
      fillable = TRUE,

      # ── SIDEBAR ────────────────────────────────────────────────────────────
      sidebar = bslib::sidebar(
        width = 300,
        open  = TRUE,
        gap   = "0.3rem",
        padding = "0.5rem",

        # 1 · Vector File ─────────────────────────────────────────────────────
        bslib::accordion(
          open = TRUE, multiple = TRUE,
          bslib::accordion_panel(
            "Vector File", icon = shiny::icon("map"),
            shiny::fileInput(
              ns("vec_file"), NULL,
              accept      = c(".shp", ".geojson", ".gpkg", ".kml", ".json"),
              buttonLabel = shiny::icon("folder-open"),
              placeholder = "GeoJSON / SHP / GPKG / KML"
            ),
            shiny::uiOutput(ns("vec_info_ui")),
            shiny::uiOutput(ns("vec_id_col_ui"))
          ),

          # 2 · Variables ───────────────────────────────────────────────────
          bslib::accordion_panel(
            "Variables", icon = shiny::icon("layer-group"),
            shiny::selectInput(
              ns("vars_ts"), "Time Series Variables",
              choices = NULL, multiple = TRUE
            ),
            shiny::div(
              style = "border-top: 1px dashed #dee2e6; margin: 6px 0 4px;",
              shiny::helpText("Regression axes (seasonal)", style = "font-size:0.78rem; color:#888;")
            ),
            shiny::selectInput(ns("vars_reg_x"), "X variable", choices = NULL),
            shiny::selectInput(ns("vars_reg_y"), "Y variable", choices = NULL)
          ),

          # 3 · Period ──────────────────────────────────────────────────────
          bslib::accordion_panel(
            "Period", icon = shiny::icon("calendar"),
            shiny::dateRangeInput(
              ns("period"), NULL,
              start  = Sys.Date() - 730,
              end    = Sys.Date(),
              format = "yyyy-mm-dd"
            )
          ),

          # 4 · Plot Style ──────────────────────────────────────────────────
          bslib::accordion_panel(
            "Plot Style", icon = shiny::icon("palette"),
            shiny::selectInput(
              ns("gg_theme"), "Theme",
              choices  = c("Minimal"  = "minimal", "Classic"  = "classic",
                           "B&W"      = "bw",      "Light"    = "light",
                           "Linedraw" = "linedraw"),
              selected = "minimal"
            ),
            shiny::selectInput(
              ns("color_pal"), "Colour palette",
              choices  = c("viridis", "plasma", "magma",
                           "Set1", "Set2", "Dark2", "Paired"),
              selected = "Set2"
            ),
            shiny::selectInput(
              ns("ts_geom"), "Time series geom",
              choices  = c("Lines"          = "line",
                           "Points"         = "point",
                           "Lines + Points" = "both",
                           "Smoothed trend" = "smooth"),
              selected = "both"
            ),
            shiny::div(
              style = "display: flex; gap: 8px; flex-wrap: wrap;",
              shiny::checkboxInput(ns("show_ribbon"), "Min–Max ribbon", FALSE),
              shiny::checkboxInput(ns("show_mean"),   "Ensemble mean",  FALSE),
              shiny::checkboxInput(ns("facet_var"),   "Facet by variable", TRUE)
            ),
            shiny::sliderInput(ns("base_size"), "Font size", 10, 20, 13,
                               step = 1, ticks = FALSE),
            shiny::textInput(ns("plot_title"), "Title",       placeholder = "(auto-fill)"),
            shiny::textInput(ns("plot_ylab"),  "Y-axis label",placeholder = "(auto-fill)")
          )
        ), # /accordion

        # 5 · Action buttons ───────────────────────────────────────────────
        shiny::div(
          style = "padding-top: 0.5rem;",
          shiny::actionButton(
            ns("btn_run"), "Extract & Plot",
            icon  = shiny::icon("chart-line"),
            class = "btn-primary w-100 mb-2",
            style = "font-weight: 600;"
          ),
          shiny::actionButton(
            ns("btn_reset"), "Clear",
            icon  = shiny::icon("trash"),
            class = "btn-outline-secondary w-100"
          )
        )
      ), # /sidebar

      # ── MAIN PANEL ─────────────────────────────────────────────────────────
      bslib::navset_card_tab(
        id = ns("main_tabs"),

        # Tab 1 · Time Series ─────────────────────────────────────────────────
        bslib::nav_panel(
          "Time Series", icon = shiny::icon("chart-line"),
          bslib::card_body(
            fillable = TRUE,
            shiny::plotOutput(ns("plot_ts"), height = "520px") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50"),
            shiny::hr(style = "margin: 6px 0;"),
            shiny::div(
              style = "display: flex; gap: 8px;",
              shiny::downloadButton(ns("dl_ts_png"), "PNG", class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_ts_pdf"), "PDF", class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_ts_svg"), "SVG", class = "btn-sm btn-outline-secondary")
            )
          )
        ),

        # Tab 2 · Seasonal Values ─────────────────────────────────────────────
        bslib::nav_panel(
          "Seasonal Values", icon = shiny::icon("seedling"),
          bslib::card_body(
            fillable = TRUE,
            shiny::fluidRow(
              shiny::column(5,
                shiny::selectInput(
                  ns("seas_plot_type"), "Display as",
                  choices  = c("Bar chart" = "bar", "Box plot" = "box", "Dot plot" = "dot"),
                  selected = "bar"
                )
              ),
              shiny::column(7,
                shiny::selectInput(ns("seas_var_sel"), "Variable", choices = NULL)
              )
            ),
            shiny::plotOutput(ns("plot_seasonal"), height = "480px") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50"),
            shiny::hr(style = "margin: 6px 0;"),
            shiny::div(
              style = "display: flex; gap: 8px;",
              shiny::downloadButton(ns("dl_seas_png"), "PNG", class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_seas_pdf"), "PDF", class = "btn-sm btn-outline-secondary")
            )
          )
        ),

        # Tab 3 · Regression ──────────────────────────────────────────────────
        bslib::nav_panel(
          "Regression", icon = shiny::icon("braille"),
          bslib::card_body(
            fillable = TRUE,
            shiny::fluidRow(
              shiny::column(4,
                shiny::checkboxInput(ns("reg_by_geom"),  "Colour by geometry", TRUE)),
              shiny::column(4,
                shiny::checkboxInput(ns("reg_fit_line"), "Fit OLS line + CI",  TRUE)),
              shiny::column(4,
                shiny::checkboxInput(ns("reg_show_eq"),  "Equation + R²",      TRUE))
            ),
            shiny::plotOutput(ns("plot_reg"), height = "460px") |>
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50"),
            shiny::hr(style = "margin: 6px 0;"),
            shiny::verbatimTextOutput(ns("reg_lm_text")),
            shiny::div(
              style = "display: flex; gap: 8px; margin-top: 6px;",
              shiny::downloadButton(ns("dl_reg_png"), "PNG", class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_reg_pdf"), "PDF", class = "btn-sm btn-outline-secondary")
            )
          )
        ),

        # Tab 4 · Data Table ──────────────────────────────────────────────────
        bslib::nav_panel(
          "Data Table", icon = shiny::icon("table"),
          bslib::card_body(
            shiny::div(
              style = "display: flex; gap: 8px; margin-bottom: 8px;",
              shiny::downloadButton(ns("dl_csv"),     "CSV",     class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_parquet"), "Parquet", class = "btn-sm btn-outline-secondary"),
              shiny::downloadButton(ns("dl_rds"),     "RDS",     class = "btn-sm btn-outline-secondary")
            ),
            DT::DTOutput(ns("tbl_ts"))
          )
        ),

        # Tab 5 · Summary ─────────────────────────────────────────────────────
        bslib::nav_panel(
          "Summary", icon = shiny::icon("info-circle"),
          bslib::card_body(shiny::verbatimTextOutput(ns("txt_summary")))
        )
      ) # /navset_card_tab
    ) # /layout_sidebar
  )
}


# ── SERVER ─────────────────────────────────────────────────────────────────────
#' Timeseries Module Server
#'
#' @param id Module namespace ID
#' @param global_folder Reactive returning the current working folder path
#' @param aoi_region Reactive returning the AOI region (from Download module)
#' @export
mod_timeseries_server <- function(id, global_folder, aoi_region) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      vec_sf        = NULL,   # sf object (uploaded vector)
      ts_data       = NULL,   # data.frame: multi-var time series (long format)
      seasonal_data = NULL,   # data.frame: seasonal aggregates for X/Y vars
      avail_vars    = character(0)
    )

    ## ── 1. Scan folder for available variables ──────────────────────────────
    observe({
      folder <- global_folder()
      req(!is.null(folder), nzchar(folder), dir.exists(folder))
      tryCatch({
        tifs <- list.files(folder, pattern = "\\.tif$", recursive = FALSE)
        pat  <- "^((?:L[1-3]|AGERA5)-[A-Z0-9]+-[ADEMS])"
        vars <- sort(unique(regmatches(tifs, regexpr(pat, tifs, perl = TRUE))))
        vars <- vars[nzchar(vars)]
        rv$avail_vars <- vars
        updateSelectInput(session, "vars_ts",    choices = vars, selected = vars[1])
        updateSelectInput(session, "vars_reg_x", choices = vars, selected = vars[1])
        updateSelectInput(session, "vars_reg_y", choices = vars,
                          selected = if (length(vars) > 1) vars[2] else vars[1])
      }, error = function(e) NULL)
    })

    ## ── 2. Load vector file ─────────────────────────────────────────────────
    observeEvent(input$vec_file, {
      req(input$vec_file)
      tryCatch({
        rv$vec_sf <- sf::st_read(input$vec_file$datapath, quiet = TRUE)
        showNotification(
          sprintf("\u2714 Loaded %d features  (%s)",
                  nrow(rv$vec_sf), as.character(sf::st_geometry_type(rv$vec_sf)[1])),
          type = "message", duration = 5
        )
      }, error = function(e) {
        showNotification(paste("Vector load error:", e$message), type = "error")
        rv$vec_sf <- NULL
      })
    })

    output$vec_info_ui <- renderUI({
      req(rv$vec_sf)
      shiny::helpText(
        sprintf("%d features \u00b7 %d attributes \u00b7 %s",
                nrow(rv$vec_sf),
                max(0L, ncol(rv$vec_sf) - 1L),
                as.character(sf::st_geometry_type(rv$vec_sf)[1])),
        style = "color: #27ae60; font-size: 0.8rem; margin-top: -4px;"
      )
    })

    output$vec_id_col_ui <- renderUI({
      req(rv$vec_sf)
      cols <- setdiff(names(rv$vec_sf), c("geometry", "geom"))
      shiny::selectInput(ns("vec_id_col"), "Identifier column",
                         choices = cols, selected = cols[1])
    })

    ## ── 3. Populate seasonal-variable selector once ts_data is ready ────────
    observe({
      req(rv$ts_data)
      vars <- unique(rv$ts_data$variable)
      updateSelectInput(session, "seas_var_sel", choices = vars, selected = vars[1])
    })

    ## ── 4. Extract on button click ──────────────────────────────────────────
    observeEvent(input$btn_run, {

      vec_sf  <- rv$vec_sf
      id_col  <- input$vec_id_col
      vars_ts <- input$vars_ts
      x_var   <- input$vars_reg_x
      y_var   <- input$vars_reg_y
      folder  <- global_folder()
      period  <- c(as.character(input$period[1]), as.character(input$period[2]))

      # ·· Input validation ··················································
      if (is.null(vec_sf)) {
        showNotification("Upload a vector file first.", type = "warning"); return()
      }
      if (length(vars_ts) == 0) {
        showNotification("Select at least one time-series variable.", type = "warning"); return()
      }
      if (is.null(folder) || !dir.exists(folder)) {
        showNotification("Set a project folder in the Download tab.", type = "warning"); return()
      }

      all_vars_needed <- unique(c(vars_ts, x_var, y_var))

      withProgress(message = "Extracting time series \u2026", value = 0, {

        # ·· Time series (all selected vars) ·································
        n_ts <- length(vars_ts)
        ts_list <- lapply(seq_along(vars_ts), function(i) {
          setProgress(i / (n_ts + 2), detail = vars_ts[i])
          tryCatch({
            df <- Rwapor::wapor_ts(
              region     = vec_sf,
              variable   = vars_ts[i],
              period     = period,
              identifier = id_col
            )
            df$variable <- vars_ts[i]
            # Ensure start_date is Date
            df$start_date <- as.Date(df$start_date)
            df
          }, error = function(e) {
            showNotification(
              sprintf("TS extraction failed for %s: %s", vars_ts[i], e$message),
              type = "warning", duration = 8
            )
            NULL
          })
        })
        rv$ts_data <- do.call(rbind, Filter(Negate(is.null), ts_list))

        # ·· Seasonal aggregates for regression X and Y ······················
        seas_vars <- unique(c(x_var, y_var))
        seas_list <- lapply(seq_along(seas_vars), function(i) {
          setProgress((n_ts + i) / (n_ts + 2), detail = paste("Seasonal:", seas_vars[i]))
          tryCatch({
            df <- Rwapor::wapor_ts(
              region     = vec_sf,
              variable   = seas_vars[i],
              period     = period,
              identifier = id_col,
              seasonal   = TRUE
            )
            df$variable <- seas_vars[i]
            df
          }, error = function(e) {
            showNotification(
              sprintf("Seasonal extraction failed for %s: %s", seas_vars[i], e$message),
              type = "warning", duration = 8
            )
            NULL
          })
        })
        rv$seasonal_data <- do.call(rbind, Filter(Negate(is.null), seas_list))

        setProgress(1, detail = "Done")
      })

      if (!is.null(rv$ts_data) && nrow(rv$ts_data) > 0) {
        showNotification(
          sprintf("\u2714 %d obs \u00b7 %d variables \u00b7 %d geometries",
                  nrow(rv$ts_data),
                  length(unique(rv$ts_data$variable)),
                  .n_geoms(rv$ts_data, id_col)),
          type = "message", duration = 5
        )
      }
    })

    ## ── Internal helpers ────────────────────────────────────────────────────

    # Resolve identifier column: user choice or "ID"
    .id_col <- function(df) {
      ic <- input$vec_id_col
      if (!is.null(ic) && nzchar(ic) && ic %in% names(df)) ic else "ID"
    }

    # Unit string for a variable code
    .units <- function(var_code) {
      m <- Rwapor::WAPOR3_VARS[[var_code]]
      if (!is.null(m) && !is.null(m$units)) m$units else ""
    }

    # Long name for a variable code
    .long <- function(var_code) {
      m <- Rwapor::WAPOR3_VARS[[var_code]]
      if (!is.null(m) && !is.null(m$long_name)) m$long_name else var_code
    }

    # Number of distinct geometries in df
    .n_geoms <- function(df, ic) length(unique(df[[if (ic %in% names(df)) ic else "ID"]]))

    ## ── 5. Time Series Plot ─────────────────────────────────────────────────
    .make_ts_plot <- function() {
      df <- rv$ts_data
      req(df, nrow(df) > 0, "start_date" %in% names(df))

      id_col   <- .id_col(df)
      req(id_col %in% names(df))

      geom_sel  <- input$ts_geom   %||% "both"
      show_rib  <- isTRUE(input$show_ribbon)
      show_mean <- isTRUE(input$show_mean)
      facet_var <- isTRUE(input$facet_var)
      base_size <- input$base_size %||% 13
      gg_theme  <- input$gg_theme  %||% "minimal"
      pal       <- input$color_pal %||% "Set2"
      user_title <- trimws(input$plot_title %||% "")
      user_ylab  <- trimws(input$plot_ylab  %||% "")

      df[[id_col]] <- as.character(df[[id_col]])
      ids    <- sort(unique(df[[id_col]]))
      n_ids  <- length(ids)
      colors <- stats::setNames(.ts_pal(n_ids, pal), ids)

      vars_used <- unique(df$variable)

      y_label <- if (nzchar(user_ylab)) user_ylab else {
        if (length(vars_used) == 1) {
          u <- .units(vars_used)
          if (nzchar(u)) sprintf("%s (%s)", vars_used, u) else vars_used
        } else "Value"
      }
      title <- if (nzchar(user_title)) user_title else {
        if (length(vars_used) == 1) .long(vars_used) else "WaPOR Time Series"
      }

      p <- ggplot2::ggplot(
          df,
          ggplot2::aes(x = start_date, y = mean,
                       colour = .data[[id_col]], group = .data[[id_col]])
        ) +
        ggplot2::scale_colour_manual(values = colors, name = id_col) +
        ggplot2::scale_fill_manual(  values = colors, name = id_col) +
        ggplot2::scale_x_date(
          date_labels = "%b '%y",
          expand      = ggplot2::expansion(mult = 0.02)
        ) +
        ggplot2::labs(
          title   = title,
          x       = NULL,
          y       = y_label,
          colour  = id_col,
          fill    = id_col,
          caption = sprintf(
            "Period: %s \u2013 %s  \u00b7  Rwapor",
            format(min(df$start_date, na.rm = TRUE), "%d %b %Y"),
            format(max(df$start_date, na.rm = TRUE), "%d %b %Y")
          )
        ) +
        .ts_theme(gg_theme, base_size) +
        ggplot2::theme(
          legend.position = if (n_ids <= 12) "right" else "bottom"
        )

      # Optional min–max ribbon (behind lines)
      if (show_rib && all(c("min", "max") %in% names(df))) {
        p <- p + ggplot2::geom_ribbon(
          ggplot2::aes(ymin = min, ymax = max, fill = .data[[id_col]]),
          alpha = 0.15, colour = NA, show.legend = FALSE
        )
      }

      # Primary geom
      p <- switch(geom_sel,
        line  = p + ggplot2::geom_line(linewidth = 0.75),
        point = p + ggplot2::geom_point(size = 2),
        both  = p + ggplot2::geom_line(linewidth = 0.65) +
                    ggplot2::geom_point(size = 1.6),
        smooth = p + ggplot2::geom_point(size = 0.9, alpha = 0.35) +
                     ggplot2::geom_smooth(method = "loess", formula = y ~ x,
                                          se = TRUE, linewidth = 1.1),
        p + ggplot2::geom_line(linewidth = 0.75)
      )

      # Ensemble mean overlay (dashed black)
      if (show_mean) {
        df_m <- df |>
          dplyr::group_by(start_date, variable) |>
          dplyr::summarise(y_mean = mean(mean, na.rm = TRUE), .groups = "drop")
        p <- p + ggplot2::geom_line(
          data        = df_m,
          ggplot2::aes(x = start_date, y = y_mean),
          colour      = "#2c3e50",
          linewidth   = 1.3,
          linetype    = "dashed",
          inherit.aes = FALSE
        )
      }

      # Facet by variable (free y-axis; labelled with units)
      if (facet_var && length(vars_used) > 1) {
        unit_labeller <- ggplot2::labeller(
          variable = function(x) {
            vapply(x, function(v) {
              u <- .units(v)
              if (nzchar(u)) sprintf("%s  (%s)", v, u) else v
            }, character(1))
          }
        )
        p <- p + ggplot2::facet_wrap(~ variable, scales = "free_y", ncol = 1,
                                      labeller = unit_labeller)
      }

      p
    }

    output$plot_ts <- renderPlot({ .make_ts_plot() }, res = 120)

    ## ── 6. Seasonal Values Plot ─────────────────────────────────────────────
    .make_seasonal_plot <- function() {
      df_all   <- rv$ts_data
      req(df_all, nrow(df_all) > 0)

      sel_var  <- input$seas_var_sel
      req(!is.null(sel_var), nzchar(sel_var))
      df <- df_all[df_all$variable == sel_var, , drop = FALSE]
      req(nrow(df) > 0)

      id_col    <- .id_col(df)
      req(id_col %in% names(df))

      plot_type <- input$seas_plot_type %||% "bar"
      base_size <- input$base_size     %||% 13
      gg_theme  <- input$gg_theme      %||% "minimal"
      pal       <- input$color_pal     %||% "Set2"

      df[[id_col]] <- as.character(df[[id_col]])
      ids    <- sort(unique(df[[id_col]]))
      n_ids  <- length(ids)
      colors <- stats::setNames(.ts_pal(n_ids, pal), ids)

      u      <- .units(sel_var)
      title  <- sprintf("Seasonal values \u00b7 %s", .long(sel_var))

      # Determine aggregation rule (accumulation vs rate)
      is_accum <- grepl("-AETI|-PCP|-NPP|-TBP|-E-|-T-|-I-", sel_var)

      # Build seasonal summary per geometry
      df_seas <- df |>
        dplyr::group_by(.data[[id_col]], variable) |>
        dplyr::summarise(
          seas_total = if ("number_of_days" %in% names(df))
                         sum(mean * number_of_days, na.rm = TRUE)
                       else sum(mean, na.rm = TRUE),
          seas_mean  = mean(mean, na.rm = TRUE),
          q25        = stats::quantile(mean, 0.25, na.rm = TRUE),
          q75        = stats::quantile(mean, 0.75, na.rm = TRUE),
          n_obs      = dplyr::n(),
          .groups    = "drop"
        )
      df_seas$plot_val <- if (is_accum) df_seas$seas_total else df_seas$seas_mean
      y_lab <- if (is_accum) {
        if (nzchar(u)) sprintf("Seasonal total (%s)", u) else "Seasonal total"
      } else {
        if (nzchar(u)) sprintf("Mean (%s)", u) else "Mean"
      }

      base_theme <- .ts_theme(gg_theme, base_size) +
        ggplot2::theme(
          legend.position = "none",
          axis.text.x     = ggplot2::element_text(angle = 35, hjust = 1)
        )

      if (plot_type == "bar") {
        # Sort by value descending for visual hierarchy
        df_seas[[id_col]] <- factor(
          df_seas[[id_col]],
          levels = df_seas[[id_col]][order(df_seas$plot_val, decreasing = TRUE)]
        )
        p <- ggplot2::ggplot(
            df_seas,
            ggplot2::aes(x = .data[[id_col]], y = plot_val, fill = .data[[id_col]])
          ) +
          ggplot2::geom_col(width = 0.72, colour = NA) +
          ggplot2::geom_errorbar(
            ggplot2::aes(ymin = q25, ymax = q75),
            width = 0.2, colour = "grey30", linewidth = 0.6
          ) +
          ggplot2::geom_text(
            ggplot2::aes(label = format(round(plot_val, 1), big.mark = ",")),
            vjust = -0.5, size = base_size / 4.5, colour = "grey30"
          ) +
          ggplot2::scale_fill_manual(values = colors) +
          ggplot2::labs(title = title, x = NULL, y = y_lab,
                        caption = sprintf("Error bars = IQR  \u00b7  Rwapor")) +
          base_theme +
          ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))

      } else if (plot_type == "box") {
        p <- ggplot2::ggplot(
            df,
            ggplot2::aes(x = .data[[id_col]], y = mean, fill = .data[[id_col]])
          ) +
          ggplot2::geom_boxplot(
            notch        = FALSE,
            outlier.shape = 21,
            outlier.size  = 1.4,
            colour       = "grey25",
            linewidth    = 0.45
          ) +
          ggplot2::scale_fill_manual(values = colors) +
          ggplot2::labs(title = title, x = NULL,
                        y = if (nzchar(u)) sprintf("Per-timestep value (%s)", u) else "Value") +
          base_theme

      } else {
        # Dot / lollipop (Cleveland-style, sorted)
        df_seas[[id_col]] <- factor(
          df_seas[[id_col]],
          levels = df_seas[[id_col]][order(df_seas$plot_val)]
        )
        p <- ggplot2::ggplot(
            df_seas,
            ggplot2::aes(x = plot_val, y = .data[[id_col]], colour = .data[[id_col]])
          ) +
          ggplot2::geom_segment(
            ggplot2::aes(x = 0, xend = plot_val,
                         y = .data[[id_col]], yend = .data[[id_col]]),
            colour = "grey82", linewidth = 0.9
          ) +
          ggplot2::geom_point(size = 4.5) +
          ggplot2::geom_text(
            ggplot2::aes(label = format(round(plot_val, 1), big.mark = ",")),
            hjust = -0.35, size = base_size / 5, colour = "grey30"
          ) +
          ggplot2::scale_colour_manual(values = colors) +
          ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.15))) +
          ggplot2::labs(title = title, x = y_lab, y = NULL) +
          .ts_theme(gg_theme, base_size) +
          ggplot2::theme(legend.position = "none",
                         panel.grid.major.y = ggplot2::element_blank())
      }
      p
    }

    output$plot_seasonal <- renderPlot({ .make_seasonal_plot() }, res = 120)

    ## ── 7. Regression Plot ──────────────────────────────────────────────────
    .make_reg_plot <- function() {
      df_seas <- rv$seasonal_data
      req(df_seas, nrow(df_seas) > 0)

      x_var <- input$vars_reg_x
      y_var <- input$vars_reg_y
      req(!is.null(x_var), nzchar(x_var), !is.null(y_var), nzchar(y_var))

      id_col   <- .id_col(df_seas)
      base_size <- input$base_size %||% 13
      gg_theme  <- input$gg_theme  %||% "minimal"
      pal       <- input$color_pal %||% "Set2"
      by_geom   <- isTRUE(input$reg_by_geom)
      fit_line  <- isTRUE(input$reg_fit_line)
      show_eq   <- isTRUE(input$reg_show_eq)

      df_x <- df_seas[df_seas$variable == x_var, ]
      df_y <- df_seas[df_seas$variable == y_var, ]

      # Handle case where id_col might not be present (fall back to ID)
      join_col <- if (id_col %in% names(df_x) && id_col %in% names(df_y)) id_col else "ID"
      cols_x   <- intersect(c(join_col, "mean"), names(df_x))
      cols_y   <- intersect(c(join_col, "mean"), names(df_y))

      df_x2 <- df_x[, cols_x, drop = FALSE]
      df_y2 <- df_y[, cols_y, drop = FALSE]
      names(df_x2)[names(df_x2) == "mean"] <- "x_val"
      names(df_y2)[names(df_y2) == "mean"] <- "y_val"

      df_join <- merge(df_x2, df_y2, by = join_col)
      req(nrow(df_join) >= 2)

      df_join[[join_col]] <- as.character(df_join[[join_col]])
      ids    <- sort(unique(df_join[[join_col]]))
      n_ids  <- length(ids)
      colors <- stats::setNames(.ts_pal(n_ids, pal), ids)

      x_lab <- sprintf("%s (%s)", x_var, .units(x_var))
      y_lab <- sprintf("%s (%s)", y_var, .units(y_var))

      aes_pts <- if (by_geom) {
        ggplot2::aes(x = x_val, y = y_val, colour = .data[[join_col]])
      } else {
        ggplot2::aes(x = x_val, y = y_val)
      }

      p <- ggplot2::ggplot(df_join, aes_pts) +
        ggplot2::geom_point(size = 3.8, alpha = 0.88) +
        ggplot2::labs(
          title    = sprintf("Seasonal regression: %s vs %s", x_var, y_var),
          subtitle = sprintf("%d geometries  \u00b7  seasonal period %s \u2013 %s",
                             nrow(df_join),
                             format(input$period[1], "%d %b %Y"),
                             format(input$period[2], "%d %b %Y")),
          x        = x_lab,
          y        = y_lab,
          colour   = join_col,
          caption  = "OLS regression  \u00b7  Rwapor"
        ) +
        .ts_theme(gg_theme, base_size)

      if (by_geom) {
        p <- p +
          ggplot2::scale_colour_manual(values = colors) +
          ggplot2::theme(
            legend.position = if (n_ids <= 12) "right" else "bottom"
          )
      }

      if (fit_line) {
        p <- p + ggplot2::geom_smooth(
          method      = "lm",
          formula     = y ~ x,
          se          = TRUE,
          colour      = "#2c3e50",
          fill        = "#2c3e50",
          alpha       = 0.12,
          linewidth   = 1.15,
          inherit.aes = FALSE,
          ggplot2::aes(x = x_val, y = y_val),
          data        = df_join
        )

        # Equation + R² annotation
        if (show_eq && nrow(df_join) >= 3) {
          fit  <- stats::lm(y_val ~ x_val, data = df_join)
          cf   <- stats::coef(fit)
          r2   <- summary(fit)$r.squared
          pval <- stats::coef(summary(fit))[2, 4]
          sign_chr <- if (cf[2] >= 0) "+" else "\u2212"
          eq_str <- sprintf(
            "y = %.4f x  %s  %.3f\nR\u00b2 = %.3f    p = %.4f",
            cf[2], sign_chr, abs(cf[1]), r2, pval
          )
          p <- p + ggplot2::annotate(
            "label",
            x          = min(df_join$x_val, na.rm = TRUE),
            y          = max(df_join$y_val, na.rm = TRUE),
            label      = eq_str,
            hjust      = 0, vjust = 1,
            size       = base_size / 4.5,
            fill       = "white",
            colour     = "#2c3e50",
            fontface   = "mono",
            label.size = 0.3,
            lineheight = 1.4
          )
        }
      }
      p
    }

    output$plot_reg <- renderPlot({ .make_reg_plot() }, res = 120)

    output$reg_lm_text <- renderPrint({
      df_seas <- rv$seasonal_data
      req(df_seas, nrow(df_seas) > 0)
      x_var  <- input$vars_reg_x;  req(!is.null(x_var), nzchar(x_var))
      y_var  <- input$vars_reg_y;  req(!is.null(y_var), nzchar(y_var))
      id_col <- .id_col(df_seas)
      join_col <- if (id_col %in% names(df_seas)) id_col else "ID"

      df_x <- df_seas[df_seas$variable == x_var, c(join_col, "mean")]
      df_y <- df_seas[df_seas$variable == y_var, c(join_col, "mean")]
      names(df_x)[2] <- "x_val";  names(df_y)[2] <- "y_val"
      df_j <- merge(df_x, df_y, by = join_col)
      req(nrow(df_j) >= 3)

      fit <- stats::lm(y_val ~ x_val, data = df_j)
      cat(sprintf("OLS: %s (y) ~ %s (x)   |   n = %d geometries\n\n",
                  y_var, x_var, nrow(df_j)))
      print(summary(fit))
    })

    ## ── 8. Data Table ───────────────────────────────────────────────────────
    output$tbl_ts <- DT::renderDT({
      req(rv$ts_data)
      df <- rv$ts_data

      num_cols <- intersect(c("mean", "min", "max"), names(df))

      DT::datatable(
        df,
        filter   = "top",
        rownames = FALSE,
        class    = "compact hover stripe",
        options  = list(
          pageLength = 20,
          scrollX    = TRUE,
          dom        = "lrtip",
          order      = list(list(0, "asc"))
        )
      ) |>
        DT::formatRound(columns = num_cols, digits = 3) |>
        DT::formatStyle(
          columns            = "mean",
          background         = DT::styleColorBar(df$mean, "#b3d9ff"),
          backgroundSize     = "98% 70%",
          backgroundRepeat   = "no-repeat",
          backgroundPosition = "center"
        )
    })

    ## ── 9. Summary ──────────────────────────────────────────────────────────
    output$txt_summary <- renderPrint({
      req(rv$ts_data)
      df     <- rv$ts_data
      id_col <- .id_col(df)

      cat("\u2550\u2550 Time Series Summary ",
          paste(rep("\u2550", 38), collapse = ""), "\n\n", sep = "")
      cat(sprintf("  Observations  : %d\n",  nrow(df)))
      cat(sprintf("  Variables     : %s\n",  paste(unique(df$variable), collapse = ", ")))
      cat(sprintf("  Period        : %s \u2013 %s\n",
                  format(min(df$start_date, na.rm = TRUE), "%d %b %Y"),
                  format(max(df$start_date, na.rm = TRUE), "%d %b %Y")))
      if (id_col %in% names(df))
        cat(sprintf("  Geometries    : %d  [column: '%s']\n\n",
                    length(unique(df[[id_col]])), id_col))

      for (v in unique(df$variable)) {
        sub <- df[df$variable == v, ]
        cat(sprintf("\u2500\u2500 %s (%s) \u2500\n", v, .units(v)))
        cat(sprintf("  n=%d  mean=%.3f  sd=%.3f  [%.3f, %.3f]\n\n",
                    nrow(sub),
                    mean(sub$mean,  na.rm = TRUE),
                    stats::sd(sub$mean, na.rm = TRUE),
                    min(sub$mean,   na.rm = TRUE),
                    max(sub$mean,   na.rm = TRUE)))
      }

      if (!is.null(rv$seasonal_data) && nrow(rv$seasonal_data) > 0) {
        df_s <- rv$seasonal_data
        cat("\u2550\u2550 Seasonal Summary ",
            paste(rep("\u2550", 40), collapse = ""), "\n\n", sep = "")
        for (v in unique(df_s$variable)) {
          sub <- df_s[df_s$variable == v, ]
          cat(sprintf("  %s : %d geometries  |  mean = %.3f %s\n",
                      v, nrow(sub), mean(sub$mean, na.rm = TRUE), .units(v)))
        }
      }
    })

    ## ── 10. Download handlers ───────────────────────────────────────────────

    # Generic plot → file download
    .plot_dl <- function(plot_fn, stem, fmt, w = 10, h = 7) {
      shiny::downloadHandler(
        filename = function()
          sprintf("%s_%s.%s", stem, format(Sys.Date(), "%Y%m%d"), fmt),
        content = function(file) {
          p <- tryCatch(plot_fn(), error = function(e) NULL)
          req(p)
          ggplot2::ggsave(file, plot = p, device = fmt,
                          width = w, height = h, units = "in", dpi = 300)
        }
      )
    }

    output$dl_ts_png   <- .plot_dl(.make_ts_plot,       "timeseries",  "png")
    output$dl_ts_pdf   <- .plot_dl(.make_ts_plot,       "timeseries",  "pdf")
    output$dl_ts_svg   <- .plot_dl(.make_ts_plot,       "timeseries",  "svg")
    output$dl_seas_png <- .plot_dl(.make_seasonal_plot, "seasonal",    "png")
    output$dl_seas_pdf <- .plot_dl(.make_seasonal_plot, "seasonal",    "pdf")
    output$dl_reg_png  <- .plot_dl(.make_reg_plot,      "regression",  "png")
    output$dl_reg_pdf  <- .plot_dl(.make_reg_plot,      "regression",  "pdf")

    output$dl_csv <- shiny::downloadHandler(
      filename = function() sprintf("timeseries_%s.csv", format(Sys.Date(), "%Y%m%d")),
      content  = function(file) {
        req(rv$ts_data)
        utils::write.csv(rv$ts_data, file, row.names = FALSE)
      }
    )
    output$dl_parquet <- shiny::downloadHandler(
      filename = function() sprintf("timeseries_%s.parquet", format(Sys.Date(), "%Y%m%d")),
      content  = function(file) {
        req(rv$ts_data)
        if (requireNamespace("arrow", quietly = TRUE)) {
          arrow::write_parquet(rv$ts_data, file)
        } else {
          shiny::showNotification("Install the 'arrow' package for Parquet export.", type = "warning")
        }
      }
    )
    output$dl_rds <- shiny::downloadHandler(
      filename = function() sprintf("timeseries_%s.rds", format(Sys.Date(), "%Y%m%d")),
      content  = function(file) { req(rv$ts_data); saveRDS(rv$ts_data, file) }
    )

    ## ── 11. Reset ────────────────────────────────────────────────────────────
    observeEvent(input$btn_reset, {
      rv$vec_sf        <- NULL
      rv$ts_data       <- NULL
      rv$seasonal_data <- NULL
      updateSelectInput(session, "vars_ts",    selected = character(0))
      shiny::showNotification("Cleared.", type = "message", duration = 2)
    })

  })  # /moduleServer
}
