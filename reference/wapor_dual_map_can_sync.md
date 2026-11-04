# Whether dual-map pan/zoom lock can be attached

Leaflet.extras2 `addLeafletsync` looks up widgets with
`HTMLWidgets.find`. That fails if the Side-by-Side tab has not created
the maps yet. Wait until both maps have reported a zoom (they exist in
the DOM) before syncing.

## Usage

``` r
wapor_dual_map_can_sync(locked, left_zoom, right_zoom)
```

## Arguments

- locked:

  Logical. The "Lock pan & zoom" checkbox.

- left_zoom, right_zoom:

  Numeric zoom from `input$map_*_zoom`, or NULL.

## Value

Logical.
