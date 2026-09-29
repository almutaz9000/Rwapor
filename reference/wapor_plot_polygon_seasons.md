# Plot selected polygon units over several raster layers

Draws a grid of small maps with one row per polygon unit (for example a
farm) and one column per layer of `x` (for example one seasonal AETI map
per season). Every panel of a row shows the same unit at the same size:
the layer cropped to the unit's square extent plus `buffer`, with all
polygon outlines of the unit on top. All panels share one colour scale,
computed from all pixels of all layers of `x`, so colours can be
compared between units and between layers.

## Usage

``` r
wapor_plot_polygon_seasons(
  x,
  polygons,
  id_col,
  ids = NULL,
  row_labels = NULL,
  col_labels = NULL,
  title = NULL,
  legend_title = NULL,
  scale = c("continuous", "percentile_stretch"),
  limits = NULL,
  probs = c(0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98),
  palette = "YlGnBu",
  reverse = TRUE,
  line_width = 0.4,
  line_colour = "black",
  buffer = 40,
  legend_size = 3,
  out_file = NULL,
  width = 14,
  height = NULL,
  dpi = 300
)
```

## Arguments

- x:

  SpatRaster (or raster file path) with one layer per column.

- polygons:

  sf object, SpatVector or vector file path. Reprojected to the CRS of
  `x`.

- id_col:

  Name of the column that groups polygons into units.

- ids:

  Units to draw, one row each, in this order. Defaults to all units
  (sorted).

- row_labels:

  Row titles, one per `ids`, unique. Defaults to `ids`.

- col_labels:

  Column titles, one per layer of `x`. Defaults to the layer names.

- title:

  Plot title.

- legend_title:

  Colour bar title. Defaults to `title`.

- scale:

  `"continuous"` gradient spread evenly between `limits`, or
  `"percentile_stretch"` gradient anchored at the `probs` quantiles.

- limits:

  Range of the continuous scale: `NULL` (2nd to 98th percentile, values
  outside are drawn in the end colours), `"full"` (minimum to maximum)
  or two numbers. Not used for `"percentile_stretch"`, whose range is
  the first to last quantile.

- probs:

  Quantiles used as colour anchors when `scale = "percentile_stretch"`
  (at least two, distinct values).

- palette:

  A [`grDevices::hcl.pals()`](https://rdrr.io/r/grDevices/palettes.html)
  palette name or a vector of colours.

- reverse:

  Reverse the palette direction.

- line_width, line_colour:

  Polygon outline width and colour.

- buffer:

  Margin around each unit, in metres. Converted to degrees (1 degree =
  111,320 m) when `x` has a longitude/latitude CRS.

- legend_size:

  Colour bar length relative to the ggplot2 default. With a single row
  the colour bar is as tall as the panels.

- out_file:

  Optional PNG path to save the plot.

- width, height, dpi:

  Size (inches) and resolution of the saved plot. `height = NULL` sizes
  it from the number of rows and columns.

## Value

A ggplot object, invisibly when `out_file` is supplied.

## Details

`scale = "percentile_stretch"` keeps one continuous gradient but anchors
its colours at the `probs` quantiles of `x` instead of spreading them
evenly between the limits: the colour changes fastest where most pixels
are, so differences stand out more. The colour bar ticks are the anchor
values.

## See also

[`wapor_plot_polygon_grid()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plot_polygon_grid.md)
for one panel per unit and one layer.

## Examples

``` r
if (FALSE) { # \dontrun{
seasons <- terra::rast(c("aeti_2018.tif", "aeti_2019.tif", "aeti_2020.tif"))
names(seasons) <- c("2018/2019", "2019/2020", "2020/2021")
wapor_plot_polygon_seasons(
  seasons, "parcels.gpkg", id_col = "farm", ids = c("F053", "F008", "F058"),
  row_labels = c("F053 above ETc", "F008 changes", "F058 below ETc"),
  title = "Seasonal AETI", legend_title = "Seasonal AETI\n(mm)",
  scale = "percentile_stretch", out_file = "sample_farms.png"
)
} # }
```
