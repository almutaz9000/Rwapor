# Configure GDAL for Efficient HTTP Streaming

Sets GDAL environment variables that control HTTP streaming performance
for Cloud-Optimized GeoTIFFs (COGs) accessed via `/vsicurl/`. Called
automatically when the package loads; invoke manually to override
defaults or to inspect what the package applied.

## Usage

``` r
wapor_configure_gdal(
  chunk_size = NULL,
  vsi_cache = TRUE,
  vsi_cache_size = 100000000L,
  gdal_cachemax = 512L,
  http_multiplex = TRUE,
  verbose = FALSE,
  overwrite = TRUE
)
```

## Arguments

- chunk_size:

  `NULL` (default) or an integer between 1024 and 10485760: the HTTP
  read chunk size in bytes (`CPL_VSIL_CURL_CHUNK_SIZE`). `NULL` leaves
  the variable alone, so GDAL uses its own default (16 KB, grown
  automatically for sequential reads). GDAL reads this value once, at
  the first remote read of the R session: set it before any remote read,
  or it has no effect. Large values make every remote file open download
  a whole chunk, which is slow for the small windows Rwapor reads.

- vsi_cache:

  Logical. Enable the VSI (virtual file system) in-memory LRU cache.
  Avoids re-fetching raster blocks already read. Default `TRUE`.

- vsi_cache_size:

  Integer. VSI cache capacity in bytes. Default 100 MB.

- gdal_cachemax:

  Integer. GDAL raster block cache in MB. Prevents repeated reads of the
  same raster tile. Default 512 MB.

- http_multiplex:

  Logical. Enable HTTP/2 request multiplexing. Allows multiple HTTP
  requests over a single connection when the server supports HTTP/2.
  Default `TRUE`.

- verbose:

  Logical. Print the applied settings to the console. Default `FALSE`.

- overwrite:

  Logical. If `TRUE` (default for manual calls), replace existing
  values. On package load it is `FALSE`: variables already set by the
  user, `.Renviron` or an institutional setup are left unchanged.

## Value

Invisibly, a named character vector of the environment variable values
applied (only the variables that were set).

## Details

### Why these settings matter

WaPOR/AgERA5 rasters are hosted as Cloud-Optimized GeoTIFFs (COGs). GDAL
accesses them via HTTP range requests through `/vsicurl/`.

1.  **`GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR"`** — GDAL normally
    issues a directory listing request before opening a remote file.
    Disabling it saves HTTP round-trips for every file.

2.  **`VSI_CACHE = TRUE`** — Caches recently read bytes in RAM so that
    repeated access to the same raster area (e.g., during
    [`crop()`](https://rspatial.github.io/terra/reference/crop.html) +
    [`mask()`](https://rspatial.github.io/terra/reference/mask.html))
    does not re-fetch from the server.

3.  **`CPL_VSIL_CURL_CHUNK_SIZE` is left at GDAL's default.** Up to
    version 1.0.5 the package set it to 10 MB. Measured with
    [`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
    on WaPOR v3 (150 polygons, 36 dekads): Level 2 took 343 s and
    requested 1,091 MB with the 10 MB chunk, against 21 s and 17 MB
    without it; Level 3 took 66 s and 232 MB against 27 s and 14 MB.
    Extracted values were identical.

While the package itself reads remote rasters it also limits `/vsicurl/`
to `.tif` files (`CPL_VSIL_CURL_ALLOWED_EXTENSIONS`), which stops two
failing side-file requests per raster. The limit is removed again after
each read; switch it off with
`options(Rwapor.remote_extension_filter = FALSE)`.

## See also

[`wapor_gdal_settings()`](https://almutaz9000.github.io/Rwapor/reference/wapor_gdal_settings.md)
to view current values.

## Examples

``` r
# Apply package defaults (also called automatically on attach)
wapor_configure_gdal()

# A specific HTTP chunk size; only effective before the first remote read
wapor_configure_gdal(chunk_size = 1024L * 1024L)

# Confirm what was applied
wapor_gdal_settings()
#>     CPL_VSIL_CURL_CHUNK_SIZE                    VSI_CACHE 
#>                    "1048576"                       "TRUE" 
#>               VSI_CACHE_SIZE                GDAL_CACHEMAX 
#>                  "100000000"                        "512" 
#> GDAL_DISABLE_READDIR_ON_OPEN          GDAL_HTTP_MAX_RETRY 
#>                  "EMPTY_DIR"                          "3" 
#>        GDAL_HTTP_RETRY_DELAY            GDAL_HTTP_TIMEOUT 
#>                          "2"                         "60" 
#>          GDAL_HTTP_MULTIPLEX            GDAL_HTTP_VERSION 
#>                        "YES"                          "2" 
#>                     PROJ_LIB 
#>                           "" 
```
