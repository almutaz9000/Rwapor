---
description: Scaffold a new Shiny module following the Rwapor mod_*.R pattern
argument-hint: Module name and purpose, e.g. "export Export results to various formats"
---

# New Shiny Module

Scaffold a new modular Shiny component for the Rwapor dashboard.

Initial request: $ARGUMENTS

## Phase 1: Parse the request

Extract from `$ARGUMENTS`:
- **Module name** (will become `mod_<name>.R` and functions `mod_<name>_ui` / `mod_<name>_server`)
- **Purpose** (what this module does in the dashboard)

If unclear, ask the user.

## Phase 2: Read existing module patterns

Read these files before writing any code:
1. `inst/shiny/mod_download.R` — simpler server-side pattern, shinyFiles usage, shinyvalidate
2. `inst/shiny/mod_aoi.R` — Leaflet integration, file upload pattern
3. `inst/shiny/utils_shiny.R` — shared helpers including `get_shinyfiles_roots()`
4. `inst/shiny/app.R` — how modules are composed (navbar tabs, module calls, shared state)

Look for:
- UI function structure (bslib cards, sidebar layout, action buttons)
- Server function signature (`id`, reactive inputs from other modules)
- How `ns()` is used for namespacing
- How `shiny::moduleServer()` wraps logic
- How modules pass reactive values to each other
- Bootstrap 5 / bslib theming patterns

## Phase 3: Clarify

Ask the user:
1. What inputs does this module need from other modules? (e.g., AOI region, output folder)
2. What reactive values does it expose back to the app?
3. Does it need file browsing? (uses `get_shinyfiles_roots()` from utils_shiny.R)
4. Does it need form validation? (uses shinyvalidate `InputValidator`)
5. Which navbar tab should it appear under, or is it a new tab?

Wait for answers.

## Phase 4: Implement

Create `inst/shiny/mod_<name>.R` with:
1. Roxygen2 header block documenting UI and server functions
2. `mod_<name>_ui(id)` — UI definition using bslib cards, consistent with other modules
3. `mod_<name>_server(id, ...)` — server logic using `shiny::moduleServer()`
4. Use `get_shinyfiles_roots()` (not inline reactive) if file browsing is needed
5. No inline `roots <- shiny::reactive({...})` blocks — always use the shared helper

Then update `inst/shiny/app.R` to:
- Source or reference the new module
- Add the new tab/panel to the navbar
- Wire up the module call with correct reactive inputs

Confirm what was created and what the user needs to test manually.
