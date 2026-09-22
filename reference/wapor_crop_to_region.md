# Crop (and Optionally Mask) a Raster to a Parsed Region

Internal helper that handles CRS alignment, cropping, and optional
masking for vector or bounding-box regions. Eliminates duplicated
crop/mask logic across wapor_map, wapor_ts, and seasonal_download.

## Usage

``` r
wapor_crop_to_region(r, reg_info, do_mask = FALSE)
```

## Arguments

- r:

  SpatRaster to crop.

- reg_info:

  List from
  [`wapor_parse_region()`](https://almutaz9000.github.io/Rwapor/reference/wapor_parse_region.md)
  with `$type` and `$value`.

- do_mask:

  Logical. If TRUE, also mask to vector geometry (not just crop).

## Value

Cropped (and optionally masked) SpatRaster.
