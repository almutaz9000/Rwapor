# Rwapor Developer Agent — Skill Catalog

Last updated: 2026-04-16

---

## Overview: Package Goals

**Rwapor** is an R package for:
1. **Downloading** WaPOR (FAO remote sensing) and AgERA5 (climate) raster data from the FAO GIS API.
2. **Extracting time series** with zonal statistics for crop fields and administrative boundaries.
3. **Calculating crop water productivity indicators** (AETI, ETc, CWP, BWP, Adequacy, Yield/NPP).
4. **Analyzing seasonal patterns** including anomaly detection and multi-season comparison.
5. **Visualizing** spatial raster data on interactive Leaflet maps.
6. **Monitoring** farm-level seasonal performance via DuckDB persistence.
7. **Generating reports and exports** — figures, maps, GeoTIFF outputs, CSV statistics.

The package is designed for agronomists, irrigation managers, and water productivity analysts.

---

## SKILL-001: Package Architecture

### 1.1 R Package Layer (`R/`)

| File | Responsibility |
|---|---|
| `api_client.R` | FAO GIS Manager API requests (tokens, pagination) |
| `wapor_map.R` | Download + save raster maps (multi-band GeoTIFF) |
| `wapor_ts.R` | Extract time-series / zonal statistics |
| `analysis.R` | Load crop mask, season rasters, crop class extraction |
| `analysis_indicators.R` | Seasonal AETI/ETc/RET/CWP/BWP calculations |
| `analysis_engine.R` | Core calculation engine (Kc, Peff, Adequacy, Yield) |
| `analysis_pipeline.R` | Orchestrates full seasonal analysis |
| `analysis_anomaly.R` | AETI anomaly detection (z-score, hotspot, compound) |
| `analysis_comparison.R` | Multi-season comparison tables |
| `analysis_utils.R` | Shared utilities (harmonize, validate) |
| `analysis_validation.R` | Config/data coverage validation |
| `crop_defaults.R` | FAO crop coefficient (Kc) lookup tables |
| `gdal_config.R` | GDAL performance settings |
| `interval_helpers.R` | Dekadal/monthly date range helpers |
| `metadata.R` | Variable metadata (units, long names) |
| `unit_convertor.R` | Raster unit conversion (mm/day → mm/dekad, Kelvin→Celsius) |
| `utils.R` | Package-wide logging, error handling, NULL-coalescing |
| `wapor_metadata_cache.R` | Memoise-based metadata caching |
| `wapor_res_key.R` | WaPOR resolution/temporal-code lookup |

### 1.2 Shiny Dashboard (`inst/shiny/`)

The dashboard follows a **modular Shiny architecture** with `bslib` 5-tab layout:

| Tab | Module | Purpose |
|---|---|---|
| Download | `mod_download.R` + `mod_aoi.R` | Select AOI, variables, period; download rasters |
| Visualisation | `mod_visualisation.R` | Interactive raster map with dual/query modes |
| Analysis | `mod_analysis.R` + UI helpers | Seasonal crop water productivity analysis |
| Timeseries | `mod_timeseries.R` | Per-polygon time series extraction and charts |
| Monitoring | `mod_monitoring.R` + `monitoring_helpers.R` | Farm monitoring with DuckDB persistence |

### 1.3 Module Communication Pattern

```r
# app.R: modules share state through reactive returns
dl_out <- mod_download_server("dl", l3_regions_meta = l3_regions_meta)

an_out <- mod_analysis_server("an",
  global_folder = dl_out$folder,   # shared folder from Download tab
  aoi_region    = dl_out$region)   # shared AOI from Download tab

mod_visualisation_server("vis",
  global_folder    = dl_out$folder,
  aoi_region       = dl_out$region,
  an_crop_mask_rast = an_out$mask_rast,   # Analysis results passed in
  an_start_rast     = an_out$start_rast,
  an_end_rast       = an_out$end_rast,
  an_crop_params    = an_out$crop_params)
```

**Rule**: Do NOT use `session$userData` or global variables for cross-module state.
Use reactive return values from `mod_*_server()`.

---

## SKILL-002: WaPOR / AgERA5 Data

### 2.1 Variable Naming Convention

```
L1-AETI-D    ← Level 1, Actual Evapotranspiration, Dekadal
L2-NPP-M     ← Level 2, Net Primary Production, Monthly
L3-AETI-D    ← Level 3 (high-res), AETI, Dekadal
AGERA5-ET0-E ← AgERA5, Reference ET, Daily
```

Pattern: `{SOURCE}-{VARNAME}-{RESOLUTION}`
- Sources: `L1`, `L2`, `L3`, `AGERA5`
- Resolutions: `D` = Dekadal, `M` = Monthly, `A` = Annual, `E` = Daily (AgERA5)

### 2.2 Period Format

Always pass period as a **character vector of length 2**:
```r
period <- c("2023-01-01", "2023-12-31")
# NEVER pass Date objects directly; always coerce with:
period <- as.character(c(start_date, end_date))
```

### 2.3 Region Types

```r
# Bounding box (WGS84): c(xmin, ymin, xmax, ymax)
region <- c(35.0, 33.0, 36.0, 34.0)

# Vector file path (SHP, GeoJSON, GPKG, KML)
region <- "path/to/aoi.geojson"

# L3 region code (3 uppercase letters)
region <- "AWA"  # Awash basin
```

### 2.4 Download Pattern

```r
# Download raster to file
wapor_map(
  region   = region,
  variable = "L1-AETI-D",
  period   = c("2023-01-01", "2023-12-31"),
  folder   = "output/data",
  seasonal = FALSE   # TRUE = aggregate to single seasonal raster
)

# Extract time series (zonal statistics for polygons)
ts <- wapor_ts(
  region   = "path/to/farms.geojson",
  variable = "L1-AETI-D",
  period   = c("2023-01-01", "2023-12-31"),
  identifier = "farm_id"
)
```

### 2.5 L3 Region Detection

When using L3 variables with spatial AOI, detect the region automatically:
```r
region_codes <- wapor_guess_region(variable, reg_info, period)
# reg_info comes from: wapor_parse_region(region)
# period MUST be character: as.character(c(start, end))
```

---

## SKILL-003: Analysis / Indicator Calculations

### 3.1 Seasonal Analysis Pipeline

Use `wapor_analysis_pipeline()` for full analyses:
```r
config <- list(
  ref_year    = 2023,
  period      = c("2023-10-01", "2024-03-31"),
  aeti_var    = "L3-AETI-D",
  ret_var     = "L3-RET-D",
  precip_var  = "L1-PCP-D",
  npp_var     = "L3-NPP-D",
  indicators  = c("AETI", "ETc", "Adequacy", "Yield", "CWP"),
  l3_code     = "AWA"
)

results <- wapor_analysis_pipeline(
  config       = config,
  data_source  = "local",
  folder       = "output/data",
  region       = "path/to/aoi.geojson",
  crop_mask    = "path/to/crop_mask.tif",
  season_start = "path/to/season_start.tif",
  season_end   = "path/to/season_end.tif",
  save_outputs = TRUE,
  output_folder = "output/analysis"
)
```

### 3.2 Key Indicators Summary

| Indicator | Function | Description |
|---|---|---|
| Seasonal AETI | `wapor_calc_seasonal_aeti()` | Actual ET with season weights |
| ETc | `wapor_calc_etc()` | Crop water requirement (Kc × ET0) |
| Adequacy | `wapor_calc_adequacy_etc()` | AETI / ETc ratio |
| CWP | `wapor_calc_cwp()` | Crop water productivity (Yield / AETI) |
| BWP | `wapor_calc_bwp()` | Biomass water productivity (NPP / AETI) |
| P95 AETI | `wapor_calc_p95_aeti()` | 95th percentile AETI for reference |
| Peff | `wapor_calc_peff()` | Effective precipitation |
| Blue Water | `wapor_calc_blue_water()` | AETI minus Peff |
| Green Water | `wapor_calc_green_water()` | Peff component |

### 3.3 Anomaly Detection

```r
# AETI anomaly (below class median)
anomalies <- wapor_detect_aeti_anomalies(
  aeti_seasonal, crop_mask, threshold = 0.5)

# Z-score anomaly (statistical outliers)
zscore <- wapor_detect_zscore_anomalies(
  aeti_seasonal, crop_mask, z_threshold = 1.5)

# Spatial hotspots (cluster detection)
hotspots <- wapor_detect_spatial_hotspots(aeti_seasonal)

# Compound anomalies (multi-indicator stress)
compound <- wapor_detect_compound_anomalies(
  aeti_seasonal, adequacy_raster, crop_mask)
```

### 3.4 Multi-Season Comparison

```r
results_list <- list(
  "Winter 2022" = winter_2022_results,
  "Winter 2023" = winter_2023_results
)
comparison_df <- wapor_compare_seasons(
  results_list,
  indicators = c("AETI", "ETc", "Adequacy", "Yield"),
  by = "overall"   # or "class" for per-crop comparison
)
```

---

## SKILL-004: Raster Visualization

### 4.1 Leaflet Raster Rendering Pattern

```r
# Load raster and compute range
r <- terra::rast(raster_path)[[band_index]]
r_vals <- terra::values(r, na.rm = TRUE)
pal <- leaflet::colorNumeric(
  palette = rev(viridisLite::viridis(n_colors)),
  domain  = range(r_vals),
  na.color = "transparent"
)

# Render to RGB PNG for leaflet
rgb_png <- tempfile(fileext = ".png")
terra::writeRaster(terra::colorize(r, col = scales::col_numeric(...)), rgb_png)

# Add to leaflet proxy
leafletProxy("map_id") |>
  clearImages() |>
  addRasterImage(r, colors = pal, opacity = 0.8, group = "raster") |>
  addLegend(pal = pal, values = r_vals, title = "Units")
```

### 4.2 Layer Group Management

Always clear ALL layer groups when switching modes:
```r
leafletProxy("map_id") |>
  clearImages() |>
  clearGroup("raster") |>
  clearGroup("raster1") |>
  clearGroup("raster2") |>
  clearGroup("raster_left") |>
  clearGroup("raster_right") |>
  clearGroup("raster_intersection") |>
  clearGroup("raster_query")
```

### 4.3 Dual Raster Comparison Modes

- **overlay**: Two raster layers at different opacities
- **intersection**: Show only pixels where BOTH rasters have values
- **swipe**: Side-by-side split with draggable slider (JavaScript via `shinyjs::runjs()`)

### 4.4 Color Palettes Available

```r
# Sequential: "viridis", "magma", "plasma", "inferno", "cividis"
# Diverging:  "RdYlGn", "RdYlBu", "Spectral", "BrBG"
# For anomaly maps: use "RdYlGn" (green=good, red=stress)
# For AETI/ET:     use "viridis" or "Blues"
# For precipitation: use "BuPu" or "YlGnBu"
# For crop masks: use "Set1" or custom discrete palette
```

### 4.5 Export Map/Figure for Reports

```r
# Export static map using ggplot2 + terra
library(ggplot2)
library(tidyterra)

p <- ggplot() +
  tidyterra::geom_spatraster(data = seasonal_aeti_raster) +
  scale_fill_gradientn(
    colours = rev(viridisLite::viridis(20)),
    name    = "AETI (mm/season)",
    na.value = "transparent"
  ) +
  geom_sf(data = aoi_sf, fill = NA, color = "black", linewidth = 0.5) +
  coord_sf() +
  labs(title = "Seasonal AETI 2023", subtitle = "mm per growing season") +
  theme_minimal()

# Save for report (300 DPI for publications)
ggsave("output/maps/seasonal_aeti_2023.png", p,
       width = 10, height = 8, dpi = 300)
# Also as PDF for vector export:
ggsave("output/maps/seasonal_aeti_2023.pdf", p,
       width = 10, height = 8)
```

### 4.6 Static Map Export (terra-native, no ggplot)

```r
# Quick PNG export using terra
png("output/maps/aeti_map.png", width = 1200, height = 900, res = 150)
terra::plot(seasonal_aeti,
  col   = viridisLite::viridis(20),
  main  = "Seasonal AETI (mm)",
  axes  = FALSE
)
dev.off()
```

---

## SKILL-005: Professional Shiny Dashboard Patterns

### 5.1 Page Layout (bslib)

```r
# Top-level: page_navbar with Bootstrap 5 theme
ui <- bslib::page_navbar(
  title = "Dashboard Title",
  theme = bslib::bs_theme(
    version   = 5,
    bootswatch = "flatly",     # or "cosmo", "lux", "litera"
    primary    = "#2c3e50"
  ),
  header = shiny::tagList(
    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", href = "premium_style.css")
    ),
    shinyjs::useShinyjs()
  ),
  bslib::nav_panel("Tab 1", icon = shiny::icon("chart-bar"), mod_tab1_ui("t1")),
  bslib::nav_panel("Tab 2", icon = shiny::icon("map"),       mod_tab2_ui("t2")),
  bslib::nav_spacer(),
  bslib::nav_item(shiny::actionButton("exit_btn", "Exit",
    icon = shiny::icon("power-off"), class = "btn-danger btn-sm"))
)
```

### 5.2 Module Structure Template

```r
# ui function
mod_example_ui <- function(id, ...) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      open  = TRUE,
      title = "Controls",
      shiny::div(
        class = "sidebar-scroll-area",
        bslib::accordion(
          id   = ns("controls_accordion"),
          open = "Data Selection",
          bslib::accordion_panel("Data Selection",
            icon = shiny::icon("database"),
            # inputs here
          ),
          bslib::accordion_panel("Options",
            icon = shiny::icon("sliders"),
            # options here
          )
        )
      ),
      shiny::div(
        class = "sidebar-sticky-footer",
        shiny::actionButton(ns("run_btn"), "Run Analysis",
          icon = shiny::icon("play"), class = "btn-primary w-100")
      )
    ),
    # Main content
    bslib::layout_column_wrap(
      width = 1,
      bslib::card(
        full_screen = TRUE,
        bslib::card_header(shiny::icon("chart-area"), " Results"),
        bslib::card_body(shiny::plotOutput(ns("result_plot")))
      )
    )
  )
}

# server function
mod_example_server <- function(id, global_folder, aoi_region) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Use reactive values for state
    rv <- shiny::reactiveValues(
      results = NULL,
      status  = "idle"
    )

    # Always return a list of reactives for cross-module sharing
    return(list(
      results = shiny::reactive(rv$results),
      status  = shiny::reactive(rv$status)
    ))
  })
}
```

### 5.3 Conditional UI (Server-Side Pattern — REQUIRED)

**NEVER** use `conditionalPanel` with namespaced module inputs. Always use server-side `renderUI`:

```r
# UI
shiny::uiOutput(ns("dynamic_controls_ui"))

# Server
output$dynamic_controls_ui <- shiny::renderUI({
  mode <- input$mode_selector
  if (is.null(mode) || mode == "simple") return(NULL)

  shiny::tagList(
    shiny::selectInput(ns("advanced_option"), "Advanced:", choices = c("A", "B")),
    shiny::sliderInput(ns("threshold"), "Threshold:", 0, 1, 0.5)
  )
})
```

### 5.4 NULL-Safe Dynamic Input Access

Always NULL-check inputs from `renderUI` before use:
```r
# ✓ Safe pattern
mode <- input$dual_display_mode
if (is.null(mode) || length(mode) == 0) mode <- "overlay"

# ✗ Unsafe — crashes before renderUI completes
if (input$dual_display_mode == "swipe") { ... }
```

### 5.5 Value Box Cards

```r
bslib::layout_column_wrap(
  width = "200px",
  fill  = FALSE,
  bslib::value_box(
    title    = "AETI",
    value    = shiny::textOutput(ns("vbox_aeti")),
    showcase = shiny::icon("droplet", class = "text-primary"),
    theme    = "light",
    class    = "border-primary py-1"
  ),
  bslib::value_box(
    title    = "Adequacy",
    value    = shiny::textOutput(ns("vbox_adequacy")),
    showcase = shiny::icon("percent", class = "text-success"),
    theme    = "light",
    class    = "border-success py-1"
  )
)
```

### 5.6 Progress Indicators

```r
# In server - show progress during long operations
shiny::withProgress(message = "Running analysis...", value = 0, {
  shiny::incProgress(0.2, detail = "Loading rasters...")
  # ... work ...
  shiny::incProgress(0.5, detail = "Computing indicators...")
  # ... work ...
  shiny::incProgress(1.0, detail = "Done")
})

# Spinner on output elements (shinycssloaders)
shinycssloaders::withSpinner(
  leaflet::leafletOutput(ns("map_id"), height = "600px"),
  type = 6, color = "#2c3e50"
)
```

### 5.7 DT Tables

```r
# Render a DT table with professional styling
output$results_table <- DT::renderDT({
  req(rv$results_df)
  DT::datatable(
    rv$results_df,
    options  = list(pageLength = 15, scrollX = TRUE, dom = "Bfrtip"),
    rownames = FALSE,
    class    = "table table-striped table-hover table-sm",
    filter   = "top",
    extensions = c("Buttons"),
    buttons  = list("csv", "excel", "pdf")
  ) |>
    DT::formatRound(columns = c("AETI", "ETc", "Adequacy"), digits = 1)
})
```

### 5.8 Download Handlers (Export)

```r
# CSV export
output$download_csv <- shiny::downloadHandler(
  filename = function() sprintf("results_%s.csv", Sys.Date()),
  content  = function(file) {
    utils::write.csv(rv$results_df, file, row.names = FALSE)
  }
)

# PNG map export
output$download_map <- shiny::downloadHandler(
  filename = function() sprintf("map_%s.png", Sys.Date()),
  content  = function(file) {
    req(rv$raster_result)
    png(file, width = 1600, height = 1200, res = 150)
    terra::plot(rv$raster_result,
      col  = viridisLite::viridis(20),
      main = paste("Seasonal AETI —", Sys.Date()))
    dev.off()
  }
)

# GeoTIFF export
output$download_tif <- shiny::downloadHandler(
  filename = function() sprintf("result_%s.tif", Sys.Date()),
  content  = function(file) {
    req(rv$raster_result)
    terra::writeRaster(rv$raster_result, file, overwrite = TRUE)
  }
)
```

### 5.9 Notifications and Error Handling

```r
# Success notification
shiny::showNotification(
  "Analysis complete!", type = "message", duration = 4)

# Warning notification
shiny::showNotification(
  "No data found for this period.", type = "warning", duration = 6)

# Error notification with details
shiny::showNotification(
  shiny::tagList(
    shiny::strong("Error: "), "Could not load raster.",
    shiny::br(), shiny::tags$small(e$message)
  ),
  type = "error", duration = 10
)
```

### 5.10 Async Operations (Promises)

For long-running downloads/analyses without blocking the UI:
```r
shiny::observeEvent(input$run_btn, {
  rv$status <- "running"
  shiny::showNotification("Processing...", id = "proc_msg", duration = NULL)

  future::future({
    # Long-running work (runs in background worker)
    wapor_analysis_pipeline(config, ...)
  }) %...>% (function(result) {
    rv$results <- result
    rv$status  <- "done"
    shiny::removeNotification("proc_msg")
    shiny::showNotification("Complete!", type = "message")
  }) %...!% (function(err) {
    rv$status <- "error"
    shiny::removeNotification("proc_msg")
    shiny::showNotification(err$message, type = "error", duration = 10)
  })
})
```

### 5.11 JavaScript Injection (Shiny + Leaflet)

For JavaScript that must execute after a reactive update (e.g., split-screen slider):
```r
# ✓ Correct: use shinyjs::runjs() for immediate execution
shinyjs::runjs("(function() {
  var map = document.querySelector('.leaflet-container');
  // ... slider setup ...
})()")

# ✗ Wrong: htmlwidgets::onRender() only fires on initial widget creation,
#   NOT when updated via leafletProxy()
proxy |> htmlwidgets::onRender("function(el, x) { ... }")
```

### 5.12 CSS Conventions (premium_style.css)

Utility classes used throughout the dashboard:
```css
/* Key layout classes */
.sidebar-scroll-area   /* Scrollable sidebar content area */
.sidebar-sticky-footer /* Fixed-bottom Run button area */
.ctrl-group-label      /* Uppercase section label in sidebar */
.ctrl-divider          /* Thin horizontal separator */
.check-row             /* Inline flex row for checkboxes */
.inline-row            /* Inline flex row for paired inputs */
.flex-1                /* flex: 1 1 auto inside .inline-row */
.code-preview-body     /* Scrollable code/text preview box */
.ts-save-panel         /* Save panel in Timeseries tab */
```

---

## SKILL-006: Monitoring Module (DuckDB)

### 6.1 DuckDB Persistence

The monitoring module stores farm time series to DuckDB for fast access:
```r
# Connecting to the monitoring database
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)

# Writing time series
DBI::dbWriteTable(con, "farm_ts", ts_df, append = TRUE, overwrite = FALSE)

# Reading with filter
ts_data <- DBI::dbGetQuery(con, "
  SELECT * FROM farm_ts
  WHERE variable IN ('L1-AETI-D', 'L1-RET-D')
    AND start_date >= '2023-01-01'
  ORDER BY farm_id, start_date
")

DBI::dbDisconnect(con, shutdown = TRUE)
```

### 6.2 Farm Stress Index

Farm stress = mean(AETI) / mean(RET) over the monitoring period.
Color coding:
- **Green** (≥ 0.8): adequate water supply
- **Yellow** (0.6–0.8): mild stress
- **Orange** (0.4–0.6): moderate stress
- **Red** (< 0.4): severe stress

---

## SKILL-007: Export and Reporting

### 7.1 Static Map for Reports (Publication Quality)

```r
library(ggplot2)
library(tidyterra)
library(sf)

make_report_map <- function(raster_path, aoi_path, title,
                            units_label, output_path,
                            palette = "viridis", width = 10, height = 8) {
  r   <- terra::rast(raster_path)
  aoi <- sf::st_read(aoi_path, quiet = TRUE)

  p <- ggplot() +
    tidyterra::geom_spatraster(data = r) +
    scale_fill_gradientn(
      colours  = rev(viridisLite::viridis(20)),
      name     = units_label,
      na.value = "transparent"
    ) +
    geom_sf(data = aoi, fill = NA, colour = "black", linewidth = 0.6) +
    annotation_scale(location = "bl") +        # requires ggspatial
    annotation_north_arrow(location = "tr") +
    coord_sf() +
    labs(title = title,
         caption = paste("Generated:", Sys.Date(), "| Source: FAO WaPOR v3")) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title    = element_text(face = "bold", size = 13),
      legend.position = "right"
    )

  ggsave(output_path, p, width = width, height = height, dpi = 300)
  invisible(output_path)
}
```

### 7.2 Time Series Chart for Reports

```r
make_report_timeseries <- function(ts_df, variable_label, units,
                                    output_path, group_col = "ID") {
  p <- ggplot(ts_df,
    aes(x = as.Date(start_date), y = mean, group = .data[[group_col]],
        colour = .data[[group_col]])) +
    geom_line(linewidth = 0.8) +
    geom_ribbon(aes(ymin = min, ymax = max,
                    fill = .data[[group_col]]), alpha = 0.15) +
    scale_x_date(date_labels = "%b %Y", date_breaks = "2 months") +
    labs(x = NULL, y = units, title = variable_label,
         colour = "Field", fill = "Field") +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x    = element_text(angle = 30, hjust = 1),
      legend.position = "bottom"
    )

  ggsave(output_path, p, width = 12, height = 5, dpi = 200)
  invisible(output_path)
}
```

### 7.3 Multi-Panel Report Figure

```r
library(patchwork)

# Combine multiple ggplot objects into a report panel
multi_panel_report <- function(plots, ncol = 2, title = NULL, output_path) {
  combined <- patchwork::wrap_plots(plots, ncol = ncol) +
    patchwork::plot_annotation(
      title   = title,
      caption = paste("Generated:", Sys.Date(), "| Rwapor package"),
      theme   = theme(
        plot.title   = element_text(size = 14, face = "bold"),
        plot.caption = element_text(size = 9, colour = "grey50")
      )
    )
  ggsave(output_path, combined,
         width = 14, height = 10, dpi = 300)
  invisible(output_path)
}
```

### 7.4 GeoTIFF Export with Metadata

```r
# Assign descriptive metadata before writing
names(r_out) <- "seasonal_AETI_2023"
terra::varnames(r_out) <- "Seasonal AETI"
terra::units(r_out) <- "mm/season"

terra::writeRaster(r_out, "output/seasonal_aeti_2023.tif",
  overwrite = TRUE,
  NAflag    = -9999,
  gdal      = c("COMPRESS=LZW", "TILED=YES")
)
```

### 7.5 Automated R Markdown Report

```r
# Generate HTML/PDF report programmatically
rmarkdown::render(
  input       = system.file("templates", "season_report.Rmd", package = "Rwapor"),
  output_file = file.path(output_folder, paste0("season_report_", Sys.Date(), ".html")),
  params      = list(
    analysis_results = results,
    period           = config$period,
    region_name      = "Awash Irrigation District",
    season           = "Winter 2023"
  )
)
```

---

## SKILL-008: Adding a New Shiny Module

### Step-by-step checklist

1. **Create** `inst/shiny/mod_<name>.R` with `mod_<name>_ui(id, ...)` and `mod_<name>_server(id, ...)`.
2. **Source** it in `inst/shiny/app.R` via `source("mod_<name>.R")`.
3. **Add tab** in the `ui` object: `bslib::nav_panel("Name", icon = shiny::icon("icon"), mod_<name>_ui("nm", ...))`.
4. **Call server** in `server()`: `mod_<name>_server("nm", global_folder = dl_out$folder, aoi_region = dl_out$region)`.
5. **Export any reactives** at the bottom of the server function: `return(list(output_val = reactive(rv$val)))`.
6. **Add CSS** to `inst/shiny/www/premium_style.css` if the module needs custom styles.
7. **Document** the module in `vignettes/shiny-dashboard.Rmd`.

### Module skeleton

```r
mod_myfeature_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      title = "Controls", width = 280, open = TRUE,
      shiny::div(class = "sidebar-scroll-area",
        bslib::accordion(id = ns("acc"), open = "Settings",
          bslib::accordion_panel("Settings", icon = shiny::icon("sliders"),
            # inputs
          )
        )
      ),
      shiny::div(class = "sidebar-sticky-footer",
        shiny::actionButton(ns("go"), "Run",
          class = "btn-primary w-100", icon = shiny::icon("play"))
      )
    ),
    bslib::card(
      full_screen = TRUE,
      bslib::card_header(shiny::icon("table"), " Results"),
      bslib::card_body(DT::DTOutput(ns("tbl")))
    )
  )
}

mod_myfeature_server <- function(id, global_folder, aoi_region) {
  shiny::moduleServer(id, function(input, output, session) {
    ns     <- session$ns
    rv     <- shiny::reactiveValues(df = NULL)

    shiny::observeEvent(input$go, {
      folder <- shiny::req(global_folder())
      shiny::withProgress("Working...", value = 0, {
        tryCatch({
          rv$df <- compute_something(folder)
          shiny::incProgress(1)
        }, error = function(e) {
          shiny::showNotification(e$message, type = "error")
        })
      })
    })

    output$tbl <- DT::renderDT({
      shiny::req(rv$df)
      DT::datatable(rv$df, rownames = FALSE,
        class = "table table-sm table-striped")
    })

    return(list(data = shiny::reactive(rv$df)))
  })
}
```

---

## SKILL-009: Testing

### 9.1 Run Tests

```r
# From project root
devtools::test()

# Specific test file
testthat::test_file("tests/testthat/test-analysis.R")
```

### 9.2 Test Conventions

- Tests live in `tests/testthat/test-<filename>.R`
- Use `withr::with_tempdir()` for tests that write files
- Use `testthat::skip_on_cran()` / `skip_if_offline()` for API tests
- Always test edge cases: empty region, zero-length period, NULL crop mask

### 9.3 Key test patterns

```r
# Test indicator calculations
test_that("wapor_calc_cwp returns correct values", {
  aeti <- terra::rast(matrix(c(200, 300, NA, 400), 2, 2))
  npp  <- terra::rast(matrix(c(1000, 1500, NA, 2000), 2, 2))
  result <- wapor_calc_cwp(npp, aeti)
  expect_equal(terra::values(result)[!is.na(terra::values(result))],
               c(5, 5, 5), tolerance = 0.01)
})
```

---

## SKILL-010: Package Conventions

| Convention | Rule |
|---|---|
| Variable naming | `snake_case` for all functions and variables |
| Function prefix | All exported functions use `wapor_` prefix |
| Module prefix | All Shiny modules use `mod_` prefix |
| Error handling | Use `stop(..., call. = FALSE)` in package functions; `tryCatch` with `shiny::showNotification` in Shiny |
| Logging | Use `log_msg()` helper (defined in `utils.R`) throughout |
| Documentation | All exported functions must have `@param`, `@return`, `@export`, `@examples` |
| NULL coalescing | Use `%||%` operator (defined in `utils.R`) |
| Period type | Always character `c("YYYY-MM-DD", "YYYY-MM-DD")` |
| Raster CRS | Always assign CRS if missing (assume EPSG:4326 for global products) |

---

## Quick Reference: Common Workflows

### Download + Analyze + Export (Script)
```r
library(Rwapor)

# 1. Download seasonal data
wapor_map(region = "aoi.geojson", variable = "L3-AETI-D",
          period = c("2023-10-01", "2024-03-31"),
          folder = "data/", seasonal = TRUE)

# 2. Run analysis
results <- wapor_analysis_pipeline(
  config = list(
    period = c("2023-10-01", "2024-03-31"),
    aeti_var = "L3-AETI-D", ret_var = "L3-RET-D",
    indicators = c("AETI", "ETc", "Adequacy", "CWP"),
    l3_code = "AWA"
  ),
  data_source = "local", folder = "data/",
  region = "aoi.geojson",
  crop_mask = "data/crop_mask.tif",
  save_outputs = TRUE, output_folder = "output/"
)

# 3. Export map for report
ggsave("output/maps/aeti_map.png",
  ggplot() +
    tidyterra::geom_spatraster(data = results$rasters$AETI) +
    scale_fill_gradientn(colours = viridisLite::viridis(20)) +
    theme_minimal(),
  width = 10, height = 8, dpi = 300)
```

### Add a New Analysis Indicator to the Shiny Dashboard
1. Add calculation function to `R/analysis_indicators.R` (or `analysis_engine.R`)
2. Export the function in `NAMESPACE` (via `@export` roxygen tag)
3. Add the indicator to `config$indicators` list in `mod_analysis_ui_sidebar.R`
4. Handle the new indicator in `analysis_pipeline.R`
5. Display in `mod_analysis_ui_body.R` with a value box or chart
6. Add unit to `metadata.R` if needed
