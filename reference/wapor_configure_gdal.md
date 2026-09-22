# Configure GDAL for Efficient HTTP Streaming

Sets GDAL environment variables that control HTTP streaming performance
for Cloud-Optimized GeoTIFFs (COGs) accessed via `/vsicurl/`. Called
automatically when the package loads; invoke manually to override
defaults or to inspect what the package applied.

## Usage

``` r
wapor_configure_gdal(
  chunk_size = 10485760L,
  vsi_cache = TRUE,
  vsi_cache_size = 100000000L,
  gdal_cachemax = 512L,
  http_multiplex = TRUE,
  verbose = FALSE
)
```

## Arguments

- chunk_size:

  Integer. HTTP read chunk size in bytes. The GDAL built-in default (16
  KB) forces hundreds of HTTP round-trips per raster file. Increasing
  this to 10 MB (default here) reduces those to a handful of large
  requests. Set higher (e.g., `32 * 1024^2` = 32 MB) on fast
  connections.

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

## Value

Invisibly, a named character vector of the environment variable values
applied.

## Details

### Why these settings matter

WaPOR/AgERA5 rasters are hosted as Cloud-Optimized GeoTIFFs (COGs). GDAL
accesses them via HTTP range requests through `/vsicurl/`. Three
settings have by far the largest impact:

1.  **`CPL_VSIL_CURL_CHUNK_SIZE`** — Each GDAL block read becomes one
    HTTP range request. At the 16 KB default, a single dekadal raster
    crop may issue 200–1000 requests. At 10 MB, the same operation needs
    3–5.

2.  **`GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR"`** — GDAL normally
    issues a directory listing request before opening a remote file.
    Disabling it saves one HTTP round-trip per file.

3.  **`VSI_CACHE = TRUE`** — Caches recently read bytes in RAM so that
    repeated access to the same raster area (e.g., during
    [`crop()`](https://rspatial.github.io/terra/reference/crop.html) +
    [`mask()`](https://rspatial.github.io/terra/reference/mask.html))
    does not re-fetch from the server.

## See also

[`wapor_gdal_settings()`](https://almutaz9000.github.io/Rwapor/reference/wapor_gdal_settings.md)
to view current values.

## Examples

``` r
# Apply package defaults (also called automatically on attach)
wapor_configure_gdal()

# Larger chunks for high-bandwidth connections
wapor_configure_gdal(chunk_size = 32L * 1024L * 1024L)

# Confirm what was applied
wapor_gdal_settings()
#>     CPL_VSIL_CURL_CHUNK_SIZE                    VSI_CACHE 
#>                   "33554432"                       "TRUE" 
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
