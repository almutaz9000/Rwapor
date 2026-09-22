# Fix PROJ_LIB Environment Variable

Automatically detects if the `PROJ_LIB` environment variable is pointing
to an incompatible PROJ database (common on Windows with multiple GIS
installations like PostGIS) and redirects it to the database provided by
the `sf` or `terra` packages.

## Usage

``` r
wapor_fix_proj(verbose = FALSE)
```

## Arguments

- verbose:

  Logical. Print messages about the detection and fix.

## Value

Character. The `PROJ_LIB` path being used.
