# Get Variable Metadata

Retrieves metadata for WaPOR or AgERA5 variables. First checks the
built-in static metadata lists, then falls back to querying the FAO
GISMGR API for unknown variables. Results are cached using memoization
for performance.

## Usage

``` r
wapor_variable_metadata(variable)
```

## Arguments

- variable:

  Character. Variable code following the naming convention
  `{Level}-{Variable}-{TemporalResolution}` (e.g., "L1-AETI-D",
  "AGERA5-ET0-E").

## Value

A list with components:

- `long_name`: Full descriptive name of the variable

- `units`: Measurement units (e.g., "mm/day", "K")

- `scale`: Scale factor to convert raw values to physical units

Returns NULL if the variable is not found and API lookup fails.

## Details

The function uses memoization to cache API responses, so repeated calls
for the same variable are fast. Static metadata is available for all
WaPOR (L1, L2, L3) and AgERA5 variables.

## Examples

``` r
# Get metadata for a WaPOR variable
meta <- wapor_variable_metadata("L1-AETI-D")
meta$long_name
#> [1] "Actual EvapoTranspiration and Interception"
# [1] "Actual EvapoTranspiration and Interception"
meta$units
#> [1] "mm/day"
# [1] "mm/day"

# Get metadata for an AgERA5 variable
meta <- wapor_variable_metadata("AGERA5-ET0-E")
meta$units
#> [1] "mm/day"
# [1] "mm/day"

# Get metadata for L3 variable (now in static list)
meta <- wapor_variable_metadata("L3-AETI-D")
meta$units
#> [1] "mm/day"
# [1] "mm/day"
```
