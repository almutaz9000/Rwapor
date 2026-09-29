# Plot one time series per unit with a dashed reference line

Draws one line per unit (for example the seasonal or monthly AETI of
every farm), optionally coloured by a group column, and an optional
reference series (for example ETc) as a black dashed line. Units above
the reference used more water than the reference in that period, units
below used less.

## Usage

``` r
wapor_plot_unit_series(
  data,
  unit_col,
  time_col,
  value_col,
  colour_col = NULL,
  reference = NULL,
  reference_label = "Reference",
  title = NULL,
  x_label = NULL,
  y_label = NULL,
  colour_label = NULL,
  points = TRUE,
  alpha = 0.6,
  date_labels = "%b %Y",
  date_breaks = NULL,
  out_file = NULL,
  width = 10,
  height = 5.5,
  dpi = 300
)
```

## Arguments

- data:

  Data frame in long format: one row per unit and time step.

- unit_col, time_col, value_col:

  Names of the unit, time and value columns.

- colour_col:

  Optional column used to colour the lines (for example the crop type).
  `NULL` draws every line in grey.

- reference:

  Optional data frame with the columns `time_col` and `value_col`: one
  reference value per time step, drawn as a dashed line.

- reference_label:

  Legend label of the reference line.

- title, x_label, y_label, colour_label:

  Plot title, axis titles and colour legend title.

- points:

  Draw a point at every value.

- alpha:

  Transparency of the unit lines and points.

- date_labels, date_breaks:

  Axis labels and breaks when `time_col` is a Date (see
  [`ggplot2::scale_x_date()`](https://ggplot2.tidyverse.org/reference/scale_date.html)).
  `date_breaks = NULL` lets ggplot2 choose.

- out_file:

  Optional PNG path to save the plot.

- width, height, dpi:

  Size (inches) and resolution of the saved plot.

## Value

A ggplot object, invisibly when `out_file` is supplied.

## Details

The time column may be a character or factor (for example seasons
`"2018/2019"`, kept in factor order or sorted), a Date or a number.

## Examples

``` r
if (FALSE) { # \dontrun{
farms <- data.frame(Name = rep(c("F001", "F002"), each = 3),
                    season = rep(c("2022/2023", "2023/2024", "2024/2025"), 2),
                    aeti_mm = c(900, 950, 1010, 1150, 1200, 1180),
                    main_type = rep(c("Orange", "Lemon"), each = 3))
etc <- data.frame(season = c("2022/2023", "2023/2024", "2024/2025"),
                  aeti_mm = c(1048, 1033, 1056))
wapor_plot_unit_series(farms, "Name", "season", "aeti_mm", colour_col = "main_type",
                       reference = etc, reference_label = "Seasonal ETc",
                       y_label = "Seasonal AETI and ETc (mm)")
} # }
```
