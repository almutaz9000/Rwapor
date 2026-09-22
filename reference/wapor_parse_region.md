# Parse Region Argument

Parses various region input formats into a standardized structure for
use in other package functions.

## Usage

``` r
wapor_parse_region(region)
```

## Arguments

- region:

  One of:

  - Character path to a vector file (shapefile, GeoJSON, GeoPackage,
    etc.)

  - Character L3 region code (3 uppercase letters, e.g., "AWA")

  - Numeric vector of length 4 representing bounding box:
    `c(xmin, ymin, xmax, ymax)` in WGS84 (EPSG:4326)

## Value

A list with components:

- `type`: One of "l3_code", "vector", or "bbox"

- `value`: The parsed region object (character code, sf object, or
  st_bbox)

## Examples

``` r
# Parse a bounding box (xmin, ymin, xmax, ymax)
region_info <- wapor_parse_region(c(35.0, 33.0, 36.0, 34.0))
region_info$type
#> [1] "bbox"
# [1] "bbox"

# Parse an L3 region code
region_info <- wapor_parse_region("AWA")
region_info$type
#> [1] "l3_code"
# [1] "l3_code"

if (FALSE) { # \dontrun{
# Parse a shapefile
region_info <- wapor_parse_region("path/to/region.shp")
region_info$type
# [1] "vector"
} # }
```
