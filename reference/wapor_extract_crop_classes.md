# Extract Unique Crop Classes from Crop Mask

Extracts unique integer class values and computes summary statistics
(pixel count, approximate area) for each class.

## Usage

``` r
wapor_extract_crop_classes(
  crop_mask,
  exclude_nodata = TRUE,
  min_pixels = 10,
  nodata_values = c(0, 255, -9999, -32768, 65535, -3.4e+38)
)
```

## Arguments

- crop_mask:

  SpatRaster. A harmonized crop mask raster.

- exclude_nodata:

  Logical. If TRUE (default), filters out common nodata values (0, 255,
  -9999, -32768) from the class list.

- min_pixels:

  Integer. Minimum pixel count for a class to be included. Default
  is 10. This helps filter out very small spurious classes.

- nodata_values:

  Numeric vector. Values to treat as NoData.

## Value

A data.frame with columns: class_value, pixel_count, area_ha.
