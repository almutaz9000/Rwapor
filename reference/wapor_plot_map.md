# Plot a raster indicator

Plot a raster indicator

## Usage

``` r
wapor_plot_map(x, indicator = "value", title = NULL, save = NULL, dpi = 300)
```

## Arguments

- x:

  SpatRaster or numeric matrix.

- indicator:

  Character indicator name.

- title:

  Optional title.

- save:

  Optional output path. PNG is written at `dpi`.

- dpi:

  Resolution for saved raster output.

## Value

A ggplot object, invisibly if `save` is supplied.
