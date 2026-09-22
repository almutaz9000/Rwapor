# Get Available Temporal Codes for a Variable

Determines which temporal resolutions (annual, monthly, dekadal, daily)
are available for a given WaPOR or AgERA5 variable by checking the
static metadata lists. For L3 variables, checks L2 equivalents as
fallback.

## Usage

``` r
wapor_temporal_codes(variable)
```

## Arguments

- variable:

  Character. Variable name (e.g., `"L2-AETI-D"`, `"L1-NPP-M"`).

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
