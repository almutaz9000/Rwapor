# Whether the Visualisation overlay observer may mutate the Leaflet map

Call this before `leafletProxy()` / `clearGroup()` so a missing raster
cannot blank the map.

## Usage

``` r
wapor_vis_overlay_ready(mode, r1 = NULL, r2 = NULL, query = NULL)
```

## Arguments

- mode:

  Visualisation mode (`single`, `dual`, `query`).

- r1, r2:

  Prepared raster objects or sentinels. `NULL` means not ready.

- query:

  Query result list with `success` and `raster`, or `NULL`.

## Value

Logical.
