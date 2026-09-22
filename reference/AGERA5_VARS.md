# AgERA5 Climate Variable Metadata

A named list containing metadata for AgERA5 climate reanalysis
variables. AgERA5 provides climate data based on ERA5 reanalysis,
tailored for agricultural applications.

## Usage

``` r
AGERA5_VARS
```

## Format

A named list where each element is a list with:

- long_name:

  Character. Full descriptive name of the variable

- units:

  Character. Measurement units

- scale:

  Numeric. Scale factor (typically 1.0 for AgERA5)

## Details

Variable naming convention: `AGERA5-{Variable}-{TemporalResolution}`

**Available Variables:**

- ET0: Reference Evapotranspiration (FAO Penman-Monteith)

- TMIN/TMAX: Minimum/Maximum Air Temperature at 2m

- SRF: Solar Radiation Flux

- WS: Wind Speed at 2m

- PF: Precipitation Flux

## See also

[WAPOR3_VARS](https://almutaz9000.github.io/Rwapor/reference/WAPOR3_VARS.md)
for WaPOR variables

## Examples

``` r
# Get metadata for daily ET0
AGERA5_VARS[["AGERA5-ET0-E"]]
#> $long_name
#> [1] "Reference Evapotranspiration"
#> 
#> $units
#> [1] "mm/day"
#> 
#> $scale
#> [1] 1
#> 

# List all AgERA5 variables
names(AGERA5_VARS)
#>  [1] "AGERA5-ET0-E"  "AGERA5-ET0-D"  "AGERA5-ET0-M"  "AGERA5-ET0-A" 
#>  [5] "AGERA5-TMIN-E" "AGERA5-TMAX-E" "AGERA5-SRF-E"  "AGERA5-WS-E"  
#>  [9] "AGERA5-PF-E"   "AGERA5-PF-D"   "AGERA5-PF-M"   "AGERA5-PF-A"  
#> [13] "AGERA5-RH06-E" "AGERA5-RH09-E" "AGERA5-RH12-E" "AGERA5-RH15-E"
#> [17] "AGERA5-RH18-E"
```
