# Get the native-grid resolution key for a WaPOR / AgERA5 variable

Returns a short string that identifies the native pixel grid of a
variable. Variables that share the same key are on the same spatial grid
and can safely be stacked for a single zonal-statistics pass. Variables
with *different* keys must be extracted independently.

## Usage

``` r
wapor_res_key(variable)
```

## Arguments

- variable:

  Character scalar. Variable code such as `"L1-AETI-D"`, `"L1-PCP-D"`,
  `"L2-AETI-D"`, `"L3-AETI-D"`, or `"AGERA5-ET0-E"`.

## Value

A character scalar, e.g. `"L1_300m"`, `"L1_5000m"`, `"L2_100m"`,
`"L3_30m"`, `"AGERA5_11000m"`. Returns `variable` itself (unique key) if
not recognised, which safely prevents it from being batched with others.

## Details

Within Level 1, variables originate from different sensors:

- AETI / E / T / I / NPP / TBP / GBWP / NBWP — MODIS (~300 m)

- PCP — CHIRPS (~5 000 m)

- RET — ERA5 (~30 000 m)

- RSM — Sentinel-1 (~500 m)

Grouping L1 variables by level prefix alone would be incorrect because
they cannot be stacked onto the same grid without resampling.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_res_key("L1-AETI-D")   # "L1_300m"
wapor_res_key("L1-PCP-D")    # "L1_5000m"
wapor_res_key("L1-RET-D")    # "L1_30000m"
wapor_res_key("L2-AETI-D")   # "L2_100m"
wapor_res_key("L3-AETI-D")   # "L3_30m"
wapor_res_key("AGERA5-ET0-E") # "AGERA5_11000m"
} # }
```
