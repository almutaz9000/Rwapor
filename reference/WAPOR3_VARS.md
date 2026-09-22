# WaPOR v3 Variable Metadata

A named list containing metadata for WaPOR version 3 variables including
Level 1 (L1), Level 2 (L2), and Level 3 (L3) products. Each entry
contains the variable's long name, measurement units, and scale factor.

## Usage

``` r
WAPOR3_VARS
```

## Format

A named list where each element is a list with:

- long_name:

  Character. Full descriptive name of the variable

- units:

  Character. Measurement units (e.g., "mm/day", "kg/m3")

- scale:

  Numeric. Scale factor to convert raw values to physical units. Note:
  WaPOR GeoTIFFs include scale/offset in their raster metadata, so
  [`terra::rast()`](https://rspatial.github.io/terra/reference/rast.html)
  automatically applies the scale factor when reading pixel values. The
  scale values here are retained for reference and for contexts where
  raw integer values are used directly.

## Details

Variable naming convention: `{Level}-{Variable}-{TemporalResolution}`

**Levels:**

- L1: Continental scale (~300m for ETLook variables; RET ~11 km; PCP ~5
  km)

- L2: Country/regional scale (~100m; RET and PCP not available at this
  level)

- L3: Sub-national / irrigation scheme scale (~20m; RET and PCP not
  available at this level)

**Temporal Resolutions:**

- A: Annual

- M: Monthly

- D: Dekadal (10-day periods)

- E: Daily

## See also

[AGERA5_VARS](https://almutaz9000.github.io/Rwapor/reference/AGERA5_VARS.md)
for climate variables,
[L3_REGIONS](https://almutaz9000.github.io/Rwapor/reference/L3_REGIONS.md)
for L3 region codes,
[`wapor_variable_metadata()`](https://almutaz9000.github.io/Rwapor/reference/wapor_variable_metadata.md)
for dynamic metadata fetching

## Examples

``` r
# Get metadata for dekadal ET
WAPOR3_VARS[["L1-AETI-D"]]
#> $long_name
#> [1] "Actual EvapoTranspiration and Interception"
#> 
#> $units
#> [1] "mm/day"
#> 
#> $scale
#> [1] 0.1
#> 

# List all available variables
names(WAPOR3_VARS)
#>  [1] "L1-AETI-A" "L1-AETI-D" "L1-AETI-M" "L1-E-A"    "L1-E-D"    "L1-GBWP-A"
#>  [7] "L1-I-A"    "L1-I-D"    "L1-NBWP-A" "L1-NPP-D"  "L1-NPP-M"  "L1-PCP-A" 
#> [13] "L1-PCP-D"  "L1-PCP-E"  "L1-PCP-M"  "L1-RET-D"  "L1-RET-E"  "L1-RSM-D" 
#> [19] "L1-T-A"    "L1-T-D"    "L1-TBP-A"  "L2-AETI-A" "L2-AETI-D" "L2-AETI-M"
#> [25] "L2-E-A"    "L2-E-D"    "L2-GBWP-A" "L2-I-A"    "L2-I-D"    "L2-NBWP-A"
#> [31] "L2-NPP-D"  "L2-NPP-M"  "L2-RSM-D"  "L2-T-A"    "L2-T-D"    "L2-TBP-A" 
#> [37] "L3-AETI-A" "L3-AETI-D" "L3-AETI-M" "L3-AETI-E" "L3-E-A"    "L3-E-D"   
#> [43] "L3-E-E"    "L3-GBWP-A" "L3-I-E"    "L3-NPP-D"  "L3-NPP-M"  "L3-NPP-E" 
#> [49] "L3-RSM-D"  "L3-RSM-E"  "L3-T-A"    "L3-T-D"    "L3-T-E"    "L3-TBP-A" 

# List L3 variables only
grep("^L3-", names(WAPOR3_VARS), value = TRUE)
#>  [1] "L3-AETI-A" "L3-AETI-D" "L3-AETI-M" "L3-AETI-E" "L3-E-A"    "L3-E-D"   
#>  [7] "L3-E-E"    "L3-GBWP-A" "L3-I-E"    "L3-NPP-D"  "L3-NPP-M"  "L3-NPP-E" 
#> [13] "L3-RSM-D"  "L3-RSM-E"  "L3-T-A"    "L3-T-D"    "L3-T-E"    "L3-TBP-A" 
```
