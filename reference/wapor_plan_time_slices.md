# Plan Optimal WaPOR Time Slices for Seasonal Aggregation

Builds an optimized download plan for aggregating WaPOR raster data over
a date range. The plan minimizes the number of rasters to download by
preferring coarser temporal resolutions (annual \> monthly \> dekadal \>
daily) for periods that are fully covered.

## Usage

``` r
wapor_plan_time_slices(
  start_date,
  end_date,
  avail = c("A", "M", "D", "E"),
  inclusive = TRUE
)
```

## Arguments

- start_date:

  Character string `"YYYY-MM-DD"` or a Date object.

- end_date:

  Character string `"YYYY-MM-DD"` or a Date object.

- avail:

  Character vector of available temporal codes for the variable. Must be
  a subset of `c("A", "M", "D", "E")`. For example, L2 AETI typically
  has `c("A", "M", "D")`.

- inclusive:

  Logical. If `TRUE` (default), both `start_date` and `end_date` are
  included in the range. If `FALSE`, the range is treated as half-open
  `[start_date, end_date)`.

## Value

A data.frame with one row per raster to download, sorted by
`slice_start`. Columns:

- code:

  Temporal resolution code: `"A"`, `"M"`, `"D"`, or `"E"`.

- period_id:

  Identifier for the time slice, e.g. `"2022"`, `"2023-04"`,
  `"2022-10-D2"`, `"2022-10-13"`.

- slice_start:

  Date. Start of the raster slice.

- slice_end:

  Date. End of the raster slice.

- overlap_start:

  Date. Start of the overlap with the requested range.

- overlap_end:

  Date. End of the overlap with the requested range.

- weight:

  Numeric in \\\[0, 1\]\\. `overlap_days / slice_days`.

- slice_days:

  Integer. Total days in the slice.

- overlap_days:

  Integer. Days of overlap with the requested range.

## Details

This function does **not** download any data. It returns a plan (data
frame) describing which rasters to download and how much of each slice
overlaps the requested season.

Final aggregation is resolved downstream from variable metadata: period
totals use weighted sums, daily-rate products use overlap-day
multipliers, and state variables can use time-weighted means.

**Approximation note:** When fractional weights are applied to monthly
(`M`) or annual (`A`) slices, downstream aggregation assumes uniform
daily distribution within the slice. Dekadal (`D`) fractional weights
involve a smaller approximation. Daily (`E`) slices always have
`weight = 1`.

## Examples

``` r
if (FALSE) { # \dontrun{
# Plan for L2 AETI (no daily data) over a partial season
plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("A", "M", "D"))
print(plan)

# Downstream seasonal aggregation uses the plan together with variable metadata.

# Plan for a multi-year range
plan <- wapor_plan_time_slices("2018-01-01", "2023-06-22", avail = c("A", "M", "D"))
print(plan)

# If only monthly data is available
plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M"))
print(plan)
} # }
```
