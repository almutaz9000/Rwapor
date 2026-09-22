# Get Available Temporal Codes for a Variable

Determines which temporal resolutions (annual, monthly, dekadal, daily)
are available for a given WaPOR or AgERA5 variable from the validated
metadata catalogue. For L3 variables with a region and period, it also
checks actual URLs for region-specific availability.

## Usage

``` r
wapor_temporal_codes(variable, l3_region = NULL, period = NULL)
```

## Arguments

- variable:

  Character. Variable name (e.g., `"L2-AETI-D"`, `"L1-NPP-M"`).

- l3_region:

  Optional L3 region code. When supplied with `period`, availability is
  checked against that region's actual URLs.

- period:

  Optional character date range `c(start_date, end_date)` used for
  region-specific L3 availability checks.

## Value

Character vector of available temporal codes (e.g., `c("A", "M", "D")`),
ordered from coarsest to finest.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_temporal_codes("L1-AETI-D")
# [1] "A" "M" "D"

wapor_temporal_codes("L2-NPP-D")
# [1] "M" "D"
} # }
```
