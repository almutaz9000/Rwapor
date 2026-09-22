# Show Current GDAL Environment Settings

Returns the current values of GDAL environment variables that Rwapor
uses for HTTP streaming performance. Useful for diagnosing configuration
and confirming that
[`wapor_configure_gdal()`](https://almutaz9000.github.io/Rwapor/reference/wapor_configure_gdal.md)
has been applied.

## Usage

``` r
wapor_gdal_settings()
```

## Value

A named character vector. Values are empty strings `""` if a variable
has not been set in the current session.

## See also

[`wapor_configure_gdal()`](https://almutaz9000.github.io/Rwapor/reference/wapor_configure_gdal.md)
to apply or change settings.

## Examples

``` r
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
