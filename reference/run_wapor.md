# Run the Rwapor Shiny Dashboard

Launches an interactive Shiny application that provides a graphical user
interface for configuring and executing WaPOR and AgERA5 data downloads
via the
[`wapor_map`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md)
function.

## Usage

``` r
run_wapor(display.mode = "normal", launch.browser = interactive(), ...)
```

## Arguments

- display.mode:

  Character. Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

- launch.browser:

  Logical. Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

- ...:

  Additional arguments passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Details

The dashboard allows users to:

- Select variables (WaPOR or AgERA5).

- Define regions of interest by drawing bounding boxes on a satellite
  map or by uploading a vector file (.geojson, .gpkg, .kml).

- Configure output formats, unit conversions, and temporal periods.

- Preview the exact R code that will be executed.

- Trigger data downloads directly from the interface.

- Monitor farm performance during the current growing season using the
  **Monitoring** tab, which stores WaPOR time series per farm polygon in
  a local DuckDB database and displays agronomic stress indicators
  (ETa/ETp, transpiration fraction, cumulative AETI, NPP).

## Monitoring tab

The Monitoring tab requires the duckdb package
(`install.packages("duckdb")`). It:

1.  Accepts a vector file (GeoJSON, GeoPackage, Shapefile) of farm
    polygons.

2.  Allows the user to select the crop-type column, sowing date, and
    WaPOR variables to track.

3.  On each "Monitor / Update" click it fetches only the *missing*
    dekads (incremental update) and appends them to the local DuckDB
    file.

4.  Optionally clips and stores AOI raster layers as BLOB objects in the
    same database for offline visualisation.

5.  Displays a farm map coloured by stress index, per-farm time-series
    plots, a raster viewer, and a stress dashboard with colour-coded
    farm performance table.

## Examples

``` r
if (FALSE) { # \dontrun{
run_wapor()
} # }
```
