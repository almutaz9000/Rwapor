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
  dpi = 300
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

## Value

A combined ggplot or patchwork object.
