# Compute P95 of AETI Within Crop Class

Extracts the 95th percentile of seasonal AETI for each crop class.

## Usage

``` r
wapor_calc_p95_aeti(aeti_seasonal, crop_mask, min_pixels = 30L)
```

## Arguments

- aeti_seasonal:

  SpatRaster. Seasonal AETI raster.

- crop_mask:

  SpatRaster. Crop mask with integer class values.

- min_pixels:

  Integer. Minimum pixel count to compute P95. Classes with fewer pixels
  return NA. Default 30.

## Value

A data.frame with columns: class_value, p95_aeti, n_pixels, valid.
