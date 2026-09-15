# Shiny Visualization Module Mapping

This document maps the visual components seen in the dashboard screenshot to the underlying Shiny R code implementation.

## UI Screenshot to R Modules

* The **Rwapor Dashboard UI Screenshot** ([dashboard_screenshot.png](file:///C:/Users/almut/OneDrive/Documents/Bitbucket/wapordl/Rwapor/man/figures/dashboard_screenshot.png)) represents the visual layout of the application.
  * The frontend UI code is implemented in the R function `mod_visualisation_ui` in the visualization module file [inst/shiny/mod_visualisation.R](file:///C:/Users/almut/OneDrive/Documents/Bitbucket/wapordl/Rwapor/inst/shiny/mod_visualisation.R).
  * The backend rendering logic is implemented in the R function `mod_visualisation_server` in the module file [inst/shiny/mod_visualisation.R](file:///C:/Users/almut/OneDrive/Documents/Bitbucket/wapordl/Rwapor/inst/shiny/mod_visualisation.R).

* The **Color Palette Controls** widget on the UI screenshot conceptually references the palette inputs defined in `mod_visualisation_ui` and processed in `mod_visualisation_server`.

* The **Leaflet Map Visualization Pane** on the UI screenshot dynamically displays maps rendered by `mod_visualisation_server`.

* The **Raster Summary Statistics Table** on the UI screenshot outputs metrics calculated reactively in `mod_visualisation_server`.
