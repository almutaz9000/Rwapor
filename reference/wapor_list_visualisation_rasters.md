# List GeoTIFF rasters under a project folder

List GeoTIFF rasters under a project folder

## Usage

``` r
wapor_list_visualisation_rasters(folder, only_seasonal = FALSE)
```

## Arguments

- folder:

  Character path. Missing or non-directory returns `character(0)`.

- only_seasonal:

  Logical. If `TRUE`, keep seasonal rasters only.

## Value

Character vector of relative paths using forward slashes.
