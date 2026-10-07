# Run Seasonal Analysis Engine

Standalone function that performs the seasonal analysis workflow.

## Usage

``` r
wapor_run_seasonal_analysis(
  config,
  crop_params,
  rasters,
  aoi_region = NULL,
  progress_callback = NULL
)
```

## Arguments

- config:

  List of configuration parameters. Besides the variable codes,
  `period`, `data_source`, `folder` and `indicators`, it accepts:

  - `processing`: `"auto"` (default), `"memory"`, `"stream"` or
    `"tiled"`. See
    [`wapor_plan_processing()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plan_processing.md).

  - `min_coverage`: share of season days a pixel must have data for
    (default `1`, every dekad). Pixels below it are `NA` rather than
    having missing dekads counted as zero.

  - `keep_intermediates`: keep `dekadal_stacks` and `season_weights` in
    the result. Default `FALSE` (they are large; indicator steps that
    need them still get them). The run logs an estimate of the disk
    space it writes and warns when the output or temporary folder has
    less free space (`options(Rwapor.disk_check = FALSE)` turns the
    check off).

  - `output_dir`: folder for stream and tiled outputs (default: a folder
    under [`tempdir()`](https://rdrr.io/r/base/tempfile.html)).

  - `cache_dir`: with `data_source = "api"`, a folder in which the
    source rasters this run needs are saved first with
    [`wapor_download()`](https://almutaz9000.github.io/Rwapor/reference/wapor_download.md)
    (only the missing ones) and then read locally. Later runs for the
    same area read the saved files and work without internet. One folder
    per area; not available with `l3_mode = "mosaic_all"`.

  - `reference_layer`, `resampling_method`: target grid and per-layer
    resampling (see Details).

- crop_params:

  data.frame of crop class parameters (Kc, HI, etc.).

- rasters:

  List of terra::SpatRaster objects (mask, start, end).

- aoi_region:

  Optional region (bbox, vector path or sf). When `NULL`, the extent of
  `rasters$crop_mask` (or the season rasters) is used.

- progress_callback:

  Optional function(value, detail) for updates.

## Value

List of results (SpatRaster objects and summary tables), including
`coverage` (per-variable share of season days with data) and
`processing` (the
[`wapor_plan_processing()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plan_processing.md)
plan that ran).

## Details

Alignment uses `config$reference_layer` (`"aeti"` default, also
`"crop_mask"`, `"ret"`, `"pcp"`, `"npp"`, `"template"`).

Seasonal and monthly totals are summed at each source's native
resolution and then resampled once onto the analysis grid. With the
default nearest-neighbour resampling every output value is a raw server
value or a sum of raw values. Set `config$resampling_method` (for
example `c(ret = "bilinear")`) to interpolate instead. Crop mask and
season rasters always use nearest neighbour.
