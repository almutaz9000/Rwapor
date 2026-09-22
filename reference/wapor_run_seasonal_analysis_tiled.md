# Run Windowed / Tiled Seasonal Analysis Engine

Processes seasonal analysis in deterministic spatial tiles so large
extents do not need the full cube in RAM. Each tile is cropped, run
through tile-local block reducers, written as an immutable GeoTIFF/COG,
and recorded in a versioned run manifest. Completed tiles can be
resumed. Tile assets are assembled with a VRT rather than by keeping a
full-AOI mosaic in memory.

## Usage

``` r
wapor_run_seasonal_analysis_tiled(
  config,
  crop_params,
  rasters,
  output_dir = tempdir(),
  tile_size = 512L,
  progress_callback = NULL,
  cog = FALSE,
  resume = FALSE
)
```

## Arguments

- config:

  List of configuration parameters.

- crop_params:

  data.frame of crop class parameters.

- rasters:

  List of SpatRaster objects (mask, start, end).

- output_dir:

  Character. Output directory for tiled GeoTIFF products.

- tile_size:

  Integer. Square tile width/height in pixels (default: 512).

- progress_callback:

  Optional progress function(value, detail).

- cog:

  Logical. Write outputs with
  [`wapor_write_cog()`](https://almutaz9000.github.io/Rwapor/reference/wapor_write_cog.md).
  Default `FALSE`.

- resume:

  Logical. Reuse valid completed tiles from an existing run manifest in
  `output_dir`. Default `FALSE`.

## Value

List with paths to written raster files, the run manifest, tile counts,
and VRT-backed `results` rasters.
