# Plot a raster indicator

Plot a raster indicator

## Usage

``` r
wapor_plot_map(
  x,
  indicator = "value",
  title = NULL,
  save = NULL,
  dpi = 300,
  max_cells = 1e+06,
  aggregate_fun = NULL,
  limits = NULL,
  show_scale = FALSE,
  show_north_arrow = FALSE
)
```

## Arguments

- x:

  SpatRaster or numeric matrix.

- indicator:

  Character indicator name. Adequacy is centered at 1, anomalies at 0,
  and CWP/BWP use a viridis scale.

- title:

  Optional title.

- save:

  Optional output path. PNG is written at `dpi`.

- dpi:

  Resolution for saved raster output.

- max_cells:

  Maximum cells in a SpatRaster plot preview. Oversized continuous
  rasters are block-aggregated using the mean. Categorical rasters
  require an explicit `aggregate_fun`. Set to `NULL` to disable the
  limit.

- aggregate_fun:

  Optional aggregation function or terra-supported name (for example,
  `"modal"`) used when reducing an oversized raster.

- limits:

  Optional two-value fill scale limits, useful for comparing maps.

- show_scale, show_north_arrow:

  Add a scale bar or north arrow to a georeferenced SpatRaster plot.
  Requires `ggspatial`.

## Value

A ggplot object, invisibly if `save` is supplied.
