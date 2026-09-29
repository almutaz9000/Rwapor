# Run Windowed / Tiled Seasonal Analysis Engine

Runs
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
with `processing = "tiled"`: the analysis area is split into square
tiles, each tile is aggregated from windowed source reads, written as an
immutable GeoTIFF/COG and recorded in a versioned run manifest.
Completed tiles can be resumed. Tile outputs are assembled with a VRT
rather than by holding a full-area mosaic in memory.

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

  List of configuration parameters (see
  [`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)).

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

List with paths to written raster files (`saved_files`), the run
manifest path, tile counts, VRT-backed `results` rasters, and the full
engine result as `analysis`.

## Details

Results are identical to the in-memory engine; only memory use differs.
Tiles run in parallel under the active
[`future::plan()`](https://future.futureverse.org/reference/plan.html).
