# Get L3 Raster Extent (Persistently Cached)

Fetches the extent of a remote raster and returns it as a WGS84 polygon.
Results are cached to disk so they persist across R sessions,
eliminating expensive remote raster opens on subsequent calls.

## Usage

``` r
wapor_l3_extent(url, code)
```

## Arguments

- url:

  Character. Download URL for the raster.

- code:

  Character. 3-letter L3 region code used as cache key.

## Value

A SpatVector polygon in EPSG:4326, or NULL on failure.
