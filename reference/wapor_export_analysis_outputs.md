# Export Analysis Outputs to Structured Folders

Export Analysis Outputs to Structured Folders

## Usage

``` r
wapor_export_analysis_outputs(
  results,
  folder,
  indicators = character(0),
  season_label = NULL,
  include_dekadal = FALSE,
  include_monthly = TRUE,
  include_seasonal_tables = TRUE,
  cog = FALSE
)
```

## Arguments

- results:

  List of analysis results from
  [`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md).

- folder:

  Path to the base output folder.

- indicators:

  Character vector of indicators that were requested.

- season_label:

  Optional season label for single-season exports.

- include_dekadal:

  Logical. Write aligned dekadal stacks (only present when the analysis
  ran with `keep_intermediates = TRUE`). Default `FALSE`: they are large
  and the inputs are usually already on disk.

- include_monthly:

  Logical. Write monthly PCP/Peff summary CSV files.

- include_seasonal_tables:

  Logical. Write seasonal summary tables as CSV.

- cog:

  Logical. Write rasters as Cloud-Optimized GeoTIFF when possible.
