# Agent Skill Updates

## 2026-04-16 — Package Structure Review & Comprehensive Skill Catalog

- Agent: Rwapor-dev
- Scope: Full package architecture review and skill catalog creation.
- Reference file: `memories/repo/developer-skills.md` — contains 10 skill domains.

### Skills Added / Updated

#### SKILL-001: Package Architecture
- Rwapor has two layers: `R/` (core functions) and `inst/shiny/` (interactive dashboard).
- Cross-module state is passed as reactive return values, NOT global variables or `session$userData`.
- Each Shiny tab corresponds to exactly one `mod_*_ui` / `mod_*_server` pair.

#### SKILL-002: WaPOR / AgERA5 Data
- Variable naming: `{SOURCE}-{VARNAME}-{RESOLUTION}` e.g., `L3-AETI-D`, `AGERA5-ET0-E`.
- Period MUST always be `character` vector of length 2. Coerce with `as.character()` before any API call.
- Region types: bbox `c(xmin,ymin,xmax,ymax)`, vector file path, or L3 code (3 uppercase letters).

#### SKILL-003: Analysis / Indicator Calculations
- Full pipeline: `wapor_analysis_pipeline(config, data_source, folder, region, crop_mask, ...)`.
- Key indicators: AETI, ETc, CWP, BWP, Adequacy, Peff, Blue Water, Green Water, P95.
- Anomaly detection: `wapor_detect_aeti_anomalies()`, `wapor_detect_zscore_anomalies()`, `wapor_detect_spatial_hotspots()`.

#### SKILL-004: Raster Visualization
- Always clear ALL 7 layer groups when switching visualization modes (see SKILL-004.2).
- For anomaly maps use `RdYlGn` palette; for AETI/ET use `viridis` or `Blues`.
- Static export at 300 DPI: use `ggplot2` + `tidyterra::geom_spatraster()` + `ggsave()`.

#### SKILL-005: Professional Shiny Dashboard Patterns
- `bslib::page_navbar` + Bootstrap 5 with `bootswatch = "flatly"` is the standard layout.
- Module skeleton: sidebar-accordion for controls + sticky-footer Run button + card body for results.
- NEVER use `conditionalPanel` with module-namespaced inputs; ALWAYS use `renderUI` / `uiOutput`.
- NULL-check ALL inputs from `renderUI` before using in `if()` conditions.
- Value boxes: `bslib::value_box(title, value = textOutput(...), showcase = icon(...), theme = "light")`.
- Long operations: wrap with `future::future() %...>%` for async execution.
- JavaScript injection: use `shinyjs::runjs()` NOT `htmlwidgets::onRender()` for proxy updates.

#### SKILL-006: Monitoring Module (DuckDB)
- Farm time series are persisted to DuckDB at `inst/shiny/monitoring.duckdb`.
- Connect with `DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)`, always disconnect after use.
- Stress index = mean(AETI) / mean(RET); color scale: green ≥ 0.8, yellow 0.6–0.8, orange 0.4–0.6, red < 0.4.

#### SKILL-007: Export and Reporting
- Publication-quality map: `ggplot() + tidyterra::geom_spatraster(data=r) + ggsave(..., dpi=300)`.
- Multi-panel figure: use `patchwork::wrap_plots()` + `plot_annotation()`.
- GeoTIFF with metadata: set `names()`, `terra::varnames()`, `terra::units()` before `terra::writeRaster()`.
- Download handler pattern for CSV / PNG / GeoTIFF in Shiny (see SKILL-007 examples).
- R Markdown report: `rmarkdown::render(template, params=list(...))`.

#### SKILL-008: Adding a New Shiny Module
- Step-by-step checklist and skeleton template in `developer-skills.md` SKILL-008.

#### SKILL-009: Testing
- Run with `devtools::test()` from project root.
- Use `withr::with_tempdir()` for file-writing tests; `skip_if_offline()` for API tests.

#### SKILL-010: Package Conventions
- All exported R functions: `wapor_` prefix, snake_case, with full roxygen documentation.
- All Shiny modules: `mod_` prefix.
- Logging: always use `log_msg()` helper from `utils.R`.
- NULL coalescing: use `%||%` from `utils.R`.

---

## 2026-04-01 (Session 2)
- Agent: Rwapor-dev
- Instruction update: Never use `htmlwidgets::onRender()` with `leafletProxy()` - it only executes on widget creation, not updates.
- Why: `onRender()` attaches JavaScript to the initial widget render; proxy updates don't trigger it again.
- Pattern: Use `shinyjs::runjs()` to execute JavaScript immediately when reactive conditions change.
- Example trigger: Split-screen slider JavaScript not executing when switching to swipe mode.
- Fix: Replace `proxy |> htmlwidgets::onRender("...")` with `shinyjs::runjs("(function() { ... })()")` after proxy updates.

## 2026-04-01
- Agent: Rwapor-dev
- Instruction update: In Shiny modules, NEVER use `conditionalPanel` with namespaced inputs - always use server-side `renderUI` pattern.
- Why: `conditionalPanel` JavaScript cannot reliably resolve module-namespaced inputs (e.g., `input['mod-var']`).
- Pattern: `uiOutput(NS(id, "ui_elem"))` + `output$ui_elem <- renderUI({ if (condition) { ...UI... } })`
- Example trigger: Second raster selector not appearing in visualization dual mode.

## 2026-04-01
- Agent: Rwapor-dev
- Instruction update: Always NULL-check dynamic inputs from `renderUI` before use in conditionals or logic.
- Why: Input values are NULL until `renderUI` completes, causing "argument is of length zero" crashes.
- Pattern: `if (is.null(x) || length(x) == 0) x <- default_value`
- Example trigger: `if (input$dual_display_mode == "swipe")` crashes when input is NULL.

## 2026-04-01
- Agent: Rwapor-dev
- Instruction update: When switching leaflet visualization modes, explicitly clear ALL layer groups (not just default "raster" group).
- Why: Multiple layer groups (raster1, raster2, raster_left, raster_right, raster_intersection, raster_query) persist across mode changes.
- Pattern: Chain `clearGroup()` for all 7 known groups before rendering new mode.
- Example trigger: Previous rasters remain visible when switching from dual to single mode.

## 2026-04-01
- Agent: Rwapor-dev
- Instruction update: JavaScript debugging commands (e.g., `document.querySelector...`) run in BROWSER console (F12), NOT R console.
- Why: Users often try running JavaScript in R console, causing "unexpected symbol" errors.
- Pattern: Explicitly instruct users to "press F12 → Console tab" and paste JavaScript there.
- Example trigger: User tried `document.querySelectorAll('.leaflet-sbs-container').length` in R console.

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: For L3 overlap detection, always normalize `period` to character before `wapor_guess_region()`.
- Why: Prevents recurring runtime validation failures.
- Example trigger: AOI upload + L3 variable selection in download module.

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: Avoid silent error swallowing in Shiny reactives; return status+message object.
- Why: `NULL`-only fallbacks hide root cause and mislead users.
- Example trigger: Auto-detection reports "no overlap" when parse/API call actually failed.

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: For Windows/OneDrive AOI uploads, include explicit local-file diagnostics and sync guidance.
- Why: Frequent false "file does not exist" from cloud placeholders.
- Example trigger: Raster AOI selection from OneDrive Desktop path.
