# Agent Skill Updates

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
