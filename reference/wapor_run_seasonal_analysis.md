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

  List of configuration parameters.

- crop_params:

  data.frame of crop class parameters (Kc, HI, etc.).

- rasters:

  List of terra::SpatRaster objects (mask, start, end).

- aoi_region:

  Optional numeric vector for the region bbox.

- progress_callback:

  Optional function(value, detail) for updates.

## Value

List of results (SpatRaster objects and summary tables).

## Details

Alignment uses `config$reference_layer` (`"aeti"` default, also
`"crop_mask"`, `"ret"`, `"pcp"`, `"npp"`, `"template"`). Continuous
WaPOR layers are bilinear-resampled onto that grid; crop mask and
Julian-day rasters use nearest neighbour. Overlap failures name both
extents.
