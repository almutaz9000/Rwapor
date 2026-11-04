# Build selectize optgroups for Visualisation raster pickers

Build selectize optgroups for Visualisation raster pickers

## Usage

``` r
wapor_visualisation_raster_choices(
  folder,
  an_folder = NULL,
  only_seasonal = FALSE
)
```

## Arguments

- folder:

  Project / download folder.

- an_folder:

  Optional analysis output folder. Prefixed with `[AN] ` when it is a
  different directory.

- only_seasonal:

  Logical seasonal filter.

## Value

Named list of character vectors (optgroups), or `character(0)`.
