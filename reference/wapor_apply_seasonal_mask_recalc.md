# Apply Seasonal Adaptive Mask and Recalculate Stats

Creates a spatial mask based on the total seasonal sum of a reference
variable (e.g., L3-AETI-D or L3-NPP-D). Pixels that fall below a certain
percentile of the total seasonal sum are considered "bare" or
"non-cultivated" for that specific season and are excluded from the
statistics of all variables.

## Usage

``` r
wapor_apply_seasonal_mask_recalc(
  con,
  farm_id,
  polygon,
  start_date,
  end_date,
  mask_variable = "L3-AETI-D",
  percentile_threshold = 50
)
```

## Arguments

- con:

  DuckDB connection

- farm_id:

  Farm identifier

- polygon:

  sf object with farm boundary

- start_date:

  Start of the season

- end_date:

  End of the season

- mask_variable:

  Variable to use for creating the mask (default "L3-AETI-D")

- percentile_threshold:

  Percentile of the seasonal sum to use as the cutoff (default 50)

## Value

data.frame with updated statistics
