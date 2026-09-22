# Write a Cloud-Optimized GeoTIFF

Writes `x` with the GDAL COG driver when available. If that driver is
missing, falls back to a tiled GeoTIFF with internal overviews so the
file is still range-request friendly.

## Usage

``` r
wapor_write_cog(x, filename, overwrite = TRUE, ...)
```

## Arguments

- x:

  SpatRaster to write.

- filename:

  Character. Output `.tif` path.

- overwrite:

  Logical. Overwrite an existing file. Default `TRUE`.

- ...:

  Passed to
  [`terra::writeRaster()`](https://rspatial.github.io/terra/reference/writeRaster.html)
  (for example `NAflag`).

## Value

The `filename`, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
r <- terra::rast(nrows = 4, ncols = 4, vals = 1:16)
wapor_write_cog(r, tempfile(fileext = ".tif"))
} # }
```
