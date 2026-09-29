# Plot a raster as a grid of small maps, one per polygon unit

Groups `polygons` into units by `id_col` (for example parcels grouped by
farm) and draws one panel per unit: the raster cropped to the unit's
extent plus `buffer`, with every polygon outline of the unit drawn on
top. Panels are laid out `per_page` to a page, and each page can be
saved as a PNG.

## Usage

``` r
wapor_plot_polygon_grid(
  x,
  polygons,
  id_col,
  label_col = NULL,
  per_page = 24,
  ncol = 6,
  title = NULL,
  legend_title = NULL,
  common_scale = TRUE,
  scale = c("continuous", "percentile", "breaks"),
  limits = NULL,
  probs = c(0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98),
  breaks = NULL,
  palette = "YlGnBu",
  reverse = TRUE,
  line_width = 0.4,
  line_colour = "black",
  buffer = 40,
  square = TRUE,
  mask_outside = FALSE,
  legend_size = 3,
  out_dir = NULL,
  prefix = "polygon_grid",
  width = 12,
  height = 9.5,
  dpi = 300
)
```

## Arguments

- x:

  SpatRaster or raster file path. Only the first layer is drawn.

- polygons:

  sf object, SpatVector or vector file path. Reprojected to the CRS of
  `x`.

- id_col:

  Name of the column that groups polygons into units; one panel per
  unique value. Polygons with a missing id are dropped with a warning.

- label_col:

  Optional column whose first value per unit is added to the panel title
  (for example the crop type).

- per_page, ncol:

  Panels per page and per row.

- title:

  Page title. Defaults to the layer name of `x`. With several pages,
  "(page i of n)" is appended.

- legend_title:

  Colour bar title. Defaults to `title`.

- common_scale:

  `TRUE` (default): one colour scale shared by all panels. `FALSE`:
  every panel has its own scale (needs the patchwork package).

- scale:

  `"continuous"` gradient, `"percentile"` classes at the `probs`
  quantiles of `x`, or `"breaks"` classes at your `breaks`.

- limits:

  Range of the continuous scale: `NULL` (2nd to 98th percentile, values
  outside are drawn in the end colours), `"full"` (minimum to maximum)
  or two numbers.

- probs:

  Quantiles used as class limits when `scale = "percentile"`.

- breaks:

  Class limits when `scale = "breaks"` (at least two).

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

- square:

  `TRUE` (default): square panels centred on the unit. `FALSE`: each
  panel keeps the shape of its unit (needs patchwork).

- mask_outside:

  Hide pixels outside the unit's polygons.

- legend_size:

  Colour bar length relative to the ggplot2 default (3 = three times
  longer, about the height of an 8-class legend). A single row of
  panels, and every panel with its own scale, gets a colour bar as tall
  as its panels instead, so the bar is never taller than the plot.

- out_dir:

  Optional folder. Every page is saved as `<prefix>_page<i>.png`.

- prefix:

  File name prefix for saved pages.

- width, height, dpi:

  Size (inches) and resolution of saved pages.

## Value

A named list of ggplot (or patchwork) objects, one per page (`page_1`,
`page_2`, ...), invisibly when `out_dir` is supplied.

## Details

The shared colour scale (and the percentile classes) are computed from
all pixels of `x`, not only the pixels inside the panels, so the panels
use the same colours as a map of the whole raster. Crop `x` first to
limit the scale to an area of interest.

## Examples

``` r
if (FALSE) { # \dontrun{
pages <- wapor_plot_polygon_grid(
  "seasonal_aeti.tif", "parcels.gpkg", id_col = "farm",
  label_col = "crop", title = "Seasonal AETI", legend_title = "AETI (mm)",
  out_dir = "figures", prefix = "aeti_farms"
)
pages$page_1

# Adequacy in fixed classes, own colours
wapor_plot_polygon_grid(
  adequacy, parcels, id_col = "farm", scale = "breaks",
  breaks = c(0.68, 0.8, 1, 1.2),
  palette = c("#d73027", "#fc8d59", "#fee08b", "#91bfdb", "#4575b4"),
  reverse = FALSE
)
} # }
```
