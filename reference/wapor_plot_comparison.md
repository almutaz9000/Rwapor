# Plot several raster indicators side by side

Plot several raster indicators side by side

## Usage

``` r
wapor_plot_comparison(
  arrays,
  titles = NULL,
  indicator = "value",
  suptitle = NULL,
  save = NULL,
  dpi = 300,
  limits = NULL,
  max_cells = 1e+06,
  aggregate_fun = NULL
)
```

## Arguments

- arrays:

  Non-empty list of SpatRaster objects or numeric matrices.

- titles:

  Optional character vector of panel titles.

- indicator:

  Character indicator name used for labels and palettes.

- suptitle:

  Optional overall title.

- save:

  Optional output path.

- dpi:

  Resolution for saved output.

- limits:

  Optional common fill limits. Defaults to the global range across all
  input maps so panels are directly comparable.

- max_cells:

  Maximum cells per SpatRaster preview. See
  [`wapor_plot_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plot_map.md).

- aggregate_fun:

  Optional reduction function for oversized rasters. See
  [`wapor_plot_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plot_map.md).

## Value

A combined ggplot or patchwork object.
