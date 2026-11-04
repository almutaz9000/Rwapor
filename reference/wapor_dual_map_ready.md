# Whether dual-map pan/zoom lock can be attached

Leaflet.extras2 `addLeafletsync` looks up widgets with
`HTMLWidgets.find`. That fails if the Side-by-Side tab has not created
the maps yet. Wait until both maps have reported a zoom (they exist in
the DOM) before syncing.

## Usage

``` r
wapor_dual_map_ready(left_zoom, right_zoom)
```

## Arguments

- left_zoom, right_zoom:

  Numeric zoom from `input$map_*_zoom`, or NULL.

- locked:

  Logical. The "Lock pan & zoom" checkbox.

## Value

Logical.

Logical.
