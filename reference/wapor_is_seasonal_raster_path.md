# Detect seasonal rasters from relative paths

Matches WaPOR seasonal download folders (`<var>_seasonal`), `.seasonal.`
filenames, analysis `seasonal_rasters/` outputs, and seasonal
components. Dekadal/monthly/annual time-step files are not treated as
seasonal.

## Usage

``` r
wapor_is_seasonal_raster_path(path)
```

## Arguments

- path:

  Character vector of relative raster paths.

## Value

Logical vector, same length as `path`.
