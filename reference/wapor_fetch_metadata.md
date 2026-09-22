# Fetch WaPOR Metadata from JSON Cache Files

Reads pre-built metadata JSON files bundled with the package and returns
a data.frame describing WaPOR Level 1, 2, or 3 datasets.

## Usage

``` r
wapor_fetch_metadata(level)
```

## Arguments

- level:

  Character. One of `"L1"`, `"L2"`, `"L3"`, or `"all"`. When `"all"` is
  supplied, all three levels are read and row-bound.

## Value

A data.frame with columns:

- code:

  Character. Dataset code (e.g., `"L1-AETI-D"`).

- long_name:

  Character. Descriptive name.

- units:

  Character. Physical units.

- scale:

  Numeric. Scale factor.

- temporal_resolution:

  Character. Temporal resolution code.

- spatial_extent:

  List column. Named list with `xmin`, `xmax`, `ymin`, `ymax`, or `NULL`
  when not available.

- level:

  Character. Level identifier (`"L1"`, `"L2"`, or `"L3"`).

## Details

JSON files are resolved at runtime from a writable user cache first and
fall back to the installed package metadata bundled under
`inst/metadata/`. Call
[`wapor_update_metadata()`](https://almutaz9000.github.io/Rwapor/reference/wapor_update_metadata.md)
to refresh the user cache from the live API.

## Examples

``` r
if (FALSE) { # \dontrun{
# Fetch all L1 datasets
meta <- wapor_fetch_metadata("L1")
head(meta)

# Fetch everything at once
all_meta <- wapor_fetch_metadata("all")
} # }
```
