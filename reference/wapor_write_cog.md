# Write a Cloud-Optimized GeoTIFF

Writes `x` with the GDAL COG driver when available. If that driver is
missing, falls back to a tiled, compressed GeoTIFF. The fallback remains
readable and can support efficient range access, but is not guaranteed
to satisfy the complete COG overview specification.

## Usage

``` r
wapor_write_cog(x, filename, overwrite = TRUE, datatype = NULL, ...)
```

## Arguments

- x:

  SpatRaster to write.

- filename:

  Character. Output `.tif` path.

- overwrite:

  Logical. Overwrite an existing file. Default `TRUE`.

- datatype:

  Character. Output GDAL datatype: one of `"INT1U"`, `"INT1S"`,
  `"INT2U"`, `"INT2S"`, `"INT4U"`, `"INT4S"`, `"FLT4S"`, `"FLT8S"`. If
  `NULL` (default), the datatype is probed from the actual cell values
  of the first layer: integer-valued rasters within the INT4 range are
  written as `"INT4S"`, everything else as `"FLT4S"`.

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
