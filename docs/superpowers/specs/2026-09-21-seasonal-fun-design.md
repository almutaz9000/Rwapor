# Seasonal Raster Summary Function Design

## Goal

Allow callers to select the statistic calculated by seasonal wapor_map()
and wapor_ts() requests without changing the current default behavior.

## Public interface

Add fun = NULL to wapor_map() and wapor_ts().

- NULL preserves the existing variable-aware aggregation rule: accumulated
  products use a weighted sum, while non-accumulated products use a weighted
  mean.
- "sum" explicitly requests the existing weighted sum semantics.
- "mean", "std", "min", "max", and "median" use every source layer
  whose interval overlaps the requested season exactly once. They do not scale
  a partly overlapping first or last layer.
- Invalid values fail before data download with a clear error listing the
  accepted values.

"std" is the sample standard deviation, matching stats::sd(). A pixel
with fewer than two non-missing source layers returns NA for this statistic.

## Computation

The weighted sum/default variable-aware path remains the current incremental
implementation, including overlap and temporal-unit multipliers. Explicit
equal-step summaries build a lazy stack from the already downloaded seasonal
groups and apply the requested Terra reducer block-wise. No complete raster is
materialized in an R vector.

All summary functions ignore missing source-layer pixels. The equal-step
functions only use planned layers with overlap_days > 0.

## Outputs

The existing default filenames and values remain unchanged. An explicitly
selected summary function receives a function-qualified default filename, for
example WAPOR-3.L3-AETI-M.seasonal.median.Season1.2020-03-01_2021-02-28.tif.

For wapor_map(), output units are the existing seasonal units for default or
"sum", and the source variable units for mean, std, min, max, and median.
Output layer names and log messages identify the selected summary.

For seasonal wapor_ts(), the value column is named seasonal_<fun> and has
the same units rule. Default calls retain their present seasonal_sum or
seasonal_mean column names.

## Scope and tests

Update roxygen-generated Rd documentation and the agent skill examples. Add
synthetic-raster tests for default compatibility, weighted sum, equal-step
statistics, partial-overlap inclusion, missing values, invalid functions,
units, filenames, map output, and seasonal time-series results.

No WaPOR product semantics, URL planning, L3 selection, or non-seasonal
downloads change.
