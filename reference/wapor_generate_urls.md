# Generate URLs for WaPOR/AgERA5 Resources

Generates download URLs for WaPOR or AgERA5 raster data from the FAO
GISMGR API based on variable name, region, and time period.

## Usage

``` r
wapor_generate_urls(variable, l3_region = NULL, period = NULL)
```

## Arguments

- variable:

  Character. Variable name following WaPOR/AgERA5 naming convention
  (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E"). The format is
  `{Level}-{Variable}-{TemporalResolution}` where:

  - Level: L1, L2, L3 (WaPOR) or AGERA5

  - Variable: AETI, E, I, NPP, PCP, T, GBWP, NBWP, ET0, TMIN, TMAX, etc.

  - Temporal: D (dekadal), M (monthly), A (annual), E (daily)

- l3_region:

  Character. Optional L3 region code for Level 3 data (e.g., "AWA" for
  Awash Basin). Only applicable for L3 variables.

- period:

  Character vector of length 2. Optional date range as
  `c(start_date, end_date)` in "YYYY-MM-DD" format.

## Value

Character vector of download URLs, sorted chronologically.

## Details

Results are cached using memoization so that repeated calls with
identical arguments within the same session avoid redundant API
requests.

## Examples

``` r
if (FALSE) { # \dontrun{
# Get URLs for dekadal evapotranspiration in January 2023
urls <- wapor_generate_urls(
  variable = "L1-AETI-D",
  period = c("2023-01-01", "2023-01-31")
)

# Get URLs for L3 data in Awash Basin
urls <- wapor_generate_urls(
  variable = "L3-AETI-D",
  l3_region = "AWA",
  period = c("2023-01-01", "2023-03-31")
)

# Get AgERA5 reference evapotranspiration
urls <- wapor_generate_urls(
  variable = "AGERA5-ET0-E",
  period = c("2023-06-01", "2023-06-30")
)
} # }
```
