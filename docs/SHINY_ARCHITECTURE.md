# Shiny Visualization Module Mapping

This document maps the visual components seen in the dashboard screenshot to the underlying Shiny R code implementation.

## UI Screenshot to R Modules

* The **Rwapor Dashboard UI Screenshot** ([dashboard_screenshot.png](../man/figures/dashboard_screenshot.png)) represents the visual layout of the application.
  * The frontend UI code is implemented in the R function `mod_visualisation_ui` in the visualization module file [inst/shiny/mod_visualisation.R](../inst/shiny/mod_visualisation.R).
  * The backend rendering logic is implemented in the R function `mod_visualisation_server` in the module file [inst/shiny/mod_visualisation.R](../inst/shiny/mod_visualisation.R).

* The **Color Palette Controls** widget on the UI screenshot conceptually references the palette inputs defined in `mod_visualisation_ui` and processed in `mod_visualisation_server`.

* The **Leaflet Map Visualization Pane** on the UI screenshot dynamically displays maps rendered by `mod_visualisation_server`.

* The **Raster Summary Statistics Table** on the UI screenshot outputs metrics calculated reactively in `mod_visualisation_server`.

* The **Dual Compare (Synced)** tab is a separate module, [inst/shiny/mod_dual_map.R](../inst/shiny/mod_dual_map.R), showing two independently selectable rasters on two view-synchronized Leaflet maps (`mod_dual_map_ui` / `mod_dual_map_server`). It is distinct from the "Dual Compare" overlay mode inside `mod_visualisation_ui`, which draws two rasters on one map.
