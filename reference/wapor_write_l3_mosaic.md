# Write an L3 mosaic and coverage manifest

Write an L3 mosaic and coverage manifest

## Usage

``` r
wapor_write_l3_mosaic(asset_paths, output_dir, output_stem)
```

## Arguments

- asset_paths:

  Named character vector of per-L3 GeoTIFF asset paths.

- output_dir:

  Directory for the VRT, COG, and JSON manifest.

- output_stem:

  File stem for generated assets.

## Value

A list with VRT, COG, manifest paths, and coverage metadata.
