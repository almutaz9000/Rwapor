# Leaflet groups owned by the Visualisation raster overlay

Analysis overlays (`lyr_crop_mask`, season start/end) are excluded so a
raster change does not wipe them.

## Usage

``` r
wapor_vis_overlay_clear_groups(mode = "single")
```

## Arguments

- mode:

  Visualisation mode (unused; all overlay groups are returned so
  leftover layers from a previous mode are removed).

## Value

Character vector of group names.
