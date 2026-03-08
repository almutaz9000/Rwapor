#' @keywords internal
.RWAPOR_GDAL_DEFAULTS <- c(
  # HTTP chunk size: GDAL default is 16 KB (16384 bytes). Each raster read
  # requires many HTTP round-trips at that size. 10 MB dramatically reduces
  # round-trips for Cloud-Optimized GeoTIFFs.
  CPL_VSIL_CURL_CHUNK_SIZE     = "10485760",

  # VSI (virtual file system) in-memory LRU cache for recently read blocks.
  VSI_CACHE                    = "TRUE",
  VSI_CACHE_SIZE               = "100000000",   # 100 MB

  # GDAL raster block cache (in MB). Prevents re-reading the same blocks.
  GDAL_CACHEMAX                = "512",

  # Skip the expensive directory-listing HTTP request GDAL issues for every
  # /vsicurl/ file it opens. "EMPTY_DIR" treats remote dirs as empty.
  GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",

  # HTTP connection robustness
  GDAL_HTTP_MAX_RETRY          = "3",
  GDAL_HTTP_RETRY_DELAY        = "2",
  GDAL_HTTP_TIMEOUT            = "60",

  # HTTP/2 multiplexing: one TCP connection handles multiple requests in
  # parallel. Only active when the server supports HTTP/2.
  GDAL_HTTP_MULTIPLEX          = "YES",
  GDAL_HTTP_VERSION            = "2"
)


#' Configure GDAL for Efficient HTTP Streaming
#'
#' Sets GDAL environment variables that control HTTP streaming performance
#' for Cloud-Optimized GeoTIFFs (COGs) accessed via `/vsicurl/`. Called
#' automatically when the package loads; invoke manually to override defaults
#' or to inspect what the package applied.
#'
#' @param chunk_size Integer. HTTP read chunk size in bytes.
#'   The GDAL built-in default (16 KB) forces hundreds of HTTP round-trips per
#'   raster file. Increasing this to 10 MB (default here) reduces those to a
#'   handful of large requests. Set higher (e.g., `32 * 1024^2` = 32 MB) on
#'   fast connections.
#' @param vsi_cache Logical. Enable the VSI (virtual file system) in-memory
#'   LRU cache. Avoids re-fetching raster blocks already read. Default `TRUE`.
#' @param vsi_cache_size Integer. VSI cache capacity in bytes. Default 100 MB.
#' @param gdal_cachemax Integer. GDAL raster block cache in MB. Prevents
#'   repeated reads of the same raster tile. Default 512 MB.
#' @param http_multiplex Logical. Enable HTTP/2 request multiplexing.
#'   Allows multiple HTTP requests over a single connection when the server
#'   supports HTTP/2. Default `TRUE`.
#' @param verbose Logical. Print the applied settings to the console.
#'   Default `FALSE`.
#'
#' @return Invisibly, a named character vector of the environment variable
#'   values applied.
#'
#' @details
#' ## Why these settings matter
#'
#' WaPOR/AgERA5 rasters are hosted as Cloud-Optimized GeoTIFFs (COGs).
#' GDAL accesses them via HTTP range requests through `/vsicurl/`. Three
#' settings have by far the largest impact:
#'
#' 1. **`CPL_VSIL_CURL_CHUNK_SIZE`** — Each GDAL block read becomes one HTTP
#'    range request. At the 16 KB default, a single dekadal raster crop
#'    may issue 200–1000 requests. At 10 MB, the same operation needs 3–5.
#'
#' 2. **`GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR"`** — GDAL normally issues
#'    a directory listing request before opening a remote file. Disabling it
#'    saves one HTTP round-trip per file.
#'
#' 3. **`VSI_CACHE = TRUE`** — Caches recently read bytes in RAM so that
#'    repeated access to the same raster area (e.g., during `crop()` + `mask()`)
#'    does not re-fetch from the server.
#'
#' @seealso [wapor_gdal_settings()] to view current values.
#'
#' @export
#'
#' @examples
#' # Apply package defaults (also called automatically on attach)
#' wapor_configure_gdal()
#'
#' # Larger chunks for high-bandwidth connections
#' wapor_configure_gdal(chunk_size = 32L * 1024L * 1024L)
#'
#' # Confirm what was applied
#' wapor_gdal_settings()
wapor_configure_gdal <- function(
    chunk_size     = 10485760L,
    vsi_cache      = TRUE,
    vsi_cache_size = 100000000L,
    gdal_cachemax  = 512L,
    http_multiplex = TRUE,
    verbose        = FALSE
) {
  if (!is.numeric(chunk_size) || length(chunk_size) != 1 || chunk_size < 1) {
    stop("'chunk_size' must be a single positive integer (bytes)", call. = FALSE)
  }
  if (!is.logical(vsi_cache) || length(vsi_cache) != 1) {
    stop("'vsi_cache' must be a single logical value", call. = FALSE)
  }

  settings <- c(
    CPL_VSIL_CURL_CHUNK_SIZE     = as.character(as.integer(chunk_size)),
    VSI_CACHE                    = if (isTRUE(vsi_cache)) "TRUE" else "FALSE",
    VSI_CACHE_SIZE               = as.character(as.integer(vsi_cache_size)),
    GDAL_CACHEMAX                = as.character(as.integer(gdal_cachemax)),
    GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",
    GDAL_HTTP_MAX_RETRY          = "3",
    GDAL_HTTP_RETRY_DELAY        = "2",
    GDAL_HTTP_TIMEOUT            = "60",
    GDAL_HTTP_MULTIPLEX          = if (isTRUE(http_multiplex)) "YES" else "NO",
    GDAL_HTTP_VERSION            = "2"
  )

  do.call(Sys.setenv, as.list(settings))

  if (isTRUE(verbose)) {
    message("Rwapor GDAL settings applied:")
    for (nm in names(settings)) {
      message(sprintf("  %-40s = %s", nm, settings[[nm]]))
    }
  }

  invisible(settings)
}


#' Show Current GDAL Environment Settings
#'
#' Returns the current values of GDAL environment variables that Rwapor
#' uses for HTTP streaming performance. Useful for diagnosing configuration
#' and confirming that [wapor_configure_gdal()] has been applied.
#'
#' @return A named character vector. Values are empty strings `""` if a
#'   variable has not been set in the current session.
#'
#' @seealso [wapor_configure_gdal()] to apply or change settings.
#'
#' @export
#'
#' @examples
#' wapor_gdal_settings()
wapor_gdal_settings <- function() {
  vars <- names(.RWAPOR_GDAL_DEFAULTS)
  vals <- Sys.getenv(vars, unset = "")
  names(vals) <- vars
  vals
}


# Applied automatically when the package is attached.
.onLoad <- function(libname, pkgname) {
  wapor_configure_gdal(verbose = FALSE)
}
