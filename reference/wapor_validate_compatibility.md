# Validate metadata compatibility for a multi-input calculation

Applies an operation-specific contract to provenance records or
SpatRasters. Known conflicts return `status = "failed"` in every mode.
Missing metadata warns by default and produces a failed report in strict
mode. Calculation callers must stop when the returned status is
`failed`.

## Usage

``` r
wapor_validate_compatibility(
  inputs,
  operation = c("same_period", "harmonized_units", "harmonized_pair",
    "harmonized_series", "ratio", "ratio_series", "add", "add_series", "seasonal_ratio",
    "time_series", "complete_series", "water_productivity"),
  mode = c("warn", "strict")
)
```

## Arguments

- inputs:

  Named list of provenance records, SpatRasters, or result objects
  containing provenance. Meaningful names improve diagnostics.

- operation:

  One of `same_period`, `harmonized_units`, `harmonized_pair`,
  `harmonized_series`, `ratio`, `ratio_series`, `add`, `add_series`,
  `seasonal_ratio`, `time_series`, `complete_series`, or
  `water_productivity`.

- mode:

  Missing-metadata policy: `"warn"` (default) or `"strict"`.

## Value

List with status (`passed`, `warning`, or `failed`), errors, warnings,
and check records.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_validate_compatibility(list(yield = yield_meta, aeti = aeti_meta),
                             operation = "water_productivity")
} # }
```
