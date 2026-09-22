# WaPOR Level 3 Region Metadata

A named list containing metadata for all available WaPOR Level 3 (L3)
regions. Each region represents an irrigation scheme, river basin, or
study area at high resolution (~20m in WaPOR v3). Region codes are
3-letter uppercase identifiers used by the FAO GISMGR API.

## Usage

``` r
L3_REGIONS
```

## Format

A named list where each element (keyed by 3-letter region code) is a
list with:

- name:

  Character. Full name of the region/study area

- country:

  Character. Country where the region is located

## Details

Sourced from the FAO GISMGR mosaicsets API (grid.tile.code and
grid.tile.caption fields). Not all regions are available for all L3
variables – availability depends on the specific product.

## See also

[WAPOR3_VARS](https://almutaz9000.github.io/Rwapor/reference/WAPOR3_VARS.md)
for variable metadata

## Examples

``` r
# Get region info for Awash Basin
L3_REGIONS[["AWA"]]
#> $name
#> [1] "Awash"
#> 
#> $country
#> [1] "Ethiopia"
#> 

# List all region codes
names(L3_REGIONS)
#>  [1] "MIT" "MAG" "NDV" "ENO" "ZAN" "AWA" "KOG" "ERB" "GAR" "NAJ" "JAF" "JVA"
#> [13] "BUS" "KMW" "KTB" "BKA" "LCE" "LDA" "LOT" "ODN" "LOU" "LAM" "MBL" "KWL"
#> [25] "SNG" "PAL" "LAK" "MUV" "YAN" "SED" "MAL" "GEZ" "JEN" "KAI" "THR" "VTM"
#> [37] "SAN"

# Get all regions in a specific country
Filter(function(r) r$country == "Kenya", L3_REGIONS)
#> $BUS
#> $BUS$name
#> [1] "Busia"
#> 
#> $BUS$country
#> [1] "Kenya"
#> 
#> 
#> $KMW
#> $KMW$name
#> [1] "Mwea"
#> 
#> $KMW$country
#> [1] "Kenya"
#> 
#> 
#> $KTB
#> $KTB$name
#> [1] "Tana and Bura"
#> 
#> $KTB$country
#> [1] "Kenya"
#> 
#> 
```
