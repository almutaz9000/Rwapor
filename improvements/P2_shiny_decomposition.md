# Implementation Plan: Shiny Module Decomposition (P2)

## Goal
Reduce the complexity and file size of the primary Shiny modules (`mod_monitoring.R` and `mod_analysis.R`) by decomposing them into smaller, specialized sub-modules.

## Proposed Changes

### `inst/shiny/mod_monitoring/` (New Directory)
- **`mod_monitoring_ui_sidebar.R`**: Logic for the left panel (project selection, file upload).
- **`mod_monitoring_ui_map.R`**: Logic for the Leaflet map and spatial filters.
- **`mod_monitoring_server_logic.R`**: Core reactive logic for database querying and raster processing.

### `inst/shiny/mod_monitoring.R`
- Refactor as a "Parent" module that orchestrates the sub-modules.
- Move large helper functions (like `render_monitoring_map`) to `inst/shiny/monitoring_helpers.R`.

## Verification Plan
1. Launch the dashboard.
2. Verify that all interactions in the Monitoring tab (uploading AOI, starting run, viewing results) function exactly as before.
3. Check the code for cleaner reactive chains and reduced file size.
