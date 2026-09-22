# Report GDAL capabilities required for remote WaPOR rasters

Report GDAL capabilities required for remote WaPOR rasters

## Usage

``` r
wapor_remote_capabilities(refresh = FALSE)
```

## Arguments

- refresh:

  Logical. Recompute the capability probe instead of using the session
  result. Defaults to `FALSE`.

## Value

A list with `has_curl`, `has_cog`, `streaming`, and `message`.
