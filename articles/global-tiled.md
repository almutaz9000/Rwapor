# Global Tiled Seasonal Analysis

The tiled engine processes large WaPOR seasonal inputs with a bounded
working window. It is the recommended path when an AOI cannot be loaded
safely as a full raster stack.

``` r

library(Rwapor)
config <- list(
  period = c("2023-01-01", "2023-12-31"),
  data_source = "api", aeti_var = "L1-AETI-D", ret_var = "L1-RET-D",
  precip_var = "L1-PCP-D", indicators = "agg_aeti",
  folder = "wapor_data", reference_layer = "aeti"
)
params <- wapor_create_crop_params(class_value = 1, crop_name = "Maize")
result <- wapor_run_seasonal_analysis_tiled(
  config = config, crop_params = params, tile_size = wapor_suggest_tile_size(36)
)
```

`reference_layer` and `resampling_method` define the target grid
explicitly. Use nearest-neighbour resampling for categorical masks and
continuous methods for fluxes. The engine writes a manifest and
assembles outputs without holding the complete AOI in memory.
