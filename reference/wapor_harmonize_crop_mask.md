# Harmonize Crop Mask to AETI Geometry

Convenience wrapper that harmonizes a crop mask raster to match the AETI
raster geometry using nearest-neighbor resampling.

## Usage

``` r
wapor_harmonize_crop_mask(crop_mask, target_raster)
```

## Arguments

- crop_mask:

  SpatRaster. The crop mask raster (integer class values).

- target_raster:

  SpatRaster. The AETI raster defining the target geometry.

## Value

A harmonized SpatRaster.
