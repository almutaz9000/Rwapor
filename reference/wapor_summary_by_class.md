# Summarise a raster by crop-mask class

Summarise a raster by crop-mask class

## Usage

``` r
wapor_summary_by_class(r, crop_mask, class_stats = NULL, var_name = "value")
```

## Arguments

- r:

  SpatRaster.

- crop_mask:

  SpatRaster of integer class values.

- class_stats:

  Optional data.frame with a `class_value` column to merge.

- var_name:

  Character. Used to name the mean column `mean_<var_name>`.

## Value

data.frame of class means, or `NULL` if inputs are missing.
