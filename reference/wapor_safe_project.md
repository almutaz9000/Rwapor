# Safe Terra Projection Wrapper

Eliminates PROJ database collisions on some Windows environments when
projecting between WGS84 and UTM.

## Usage

``` r
wapor_safe_project(x, y)
```

## Arguments

- x:

  SpatVector or SpatRaster

- y:

  target CRS

## Value

SpatVector or SpatRaster
