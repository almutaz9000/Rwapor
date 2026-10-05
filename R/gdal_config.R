#' @keywords internal
.RWAPOR_GDAL_DEFAULTS <- c(
  # CPL_VSIL_CURL_CHUNK_SIZE is deliberately not set. GDAL reads remote files
  # in whole chunks and fixes the chunk size at the first remote read of the
  # session; a 10 MB chunk made one small window of a global file request
  # 20 MB (0.23 MB with GDAL's own default). See ISS-20261005-001.

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

# File extensions Rwapor reads through /vsicurl/. Applied only while the
# package reads remote rasters (see .wapor_with_remote_io()), never for the
# whole session, so the user's own /vsicurl/ reads of other formats still work.
.RWAPOR_REMOTE_EXTENSIONS <- ".tif,.tiff,.TIF,.TIFF"


#' Configure GDAL for Efficient HTTP Streaming
#'
#' Sets GDAL environment variables that control HTTP streaming performance
#' for Cloud-Optimized GeoTIFFs (COGs) accessed via `/vsicurl/`. Called
#' automatically when the package loads; invoke manually to override defaults
#' or to inspect what the package applied.
#'
#' @param chunk_size `NULL` (default) or an integer between 1024 and 10485760:
#'   the HTTP read chunk size in bytes (`CPL_VSIL_CURL_CHUNK_SIZE`). `NULL`
#'   leaves the variable alone, so GDAL uses its own default (16 KB, grown
#'   automatically for sequential reads). GDAL reads this value once, at the
#'   first remote read of the R session: set it before any remote read, or it
#'   has no effect. Large values make every remote file open download a whole
#'   chunk, which is slow for the small windows Rwapor reads.
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
#' @param overwrite Logical. If `TRUE` (default for manual calls), replace
#'   existing values. On package load it is `FALSE`: variables already set by
#'   the user, `.Renviron` or an institutional setup are left unchanged.
#'
#' @return Invisibly, a named character vector of the environment variable
#'   values applied (only the variables that were set).
#'
#' @details
#' ## Why these settings matter
#'
#' WaPOR/AgERA5 rasters are hosted as Cloud-Optimized GeoTIFFs (COGs).
#' GDAL accesses them via HTTP range requests through `/vsicurl/`.
#'
#' 1. **`GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR"`** — GDAL normally issues
#'    a directory listing request before opening a remote file. Disabling it
#'    saves HTTP round-trips for every file.
#'
#' 2. **`VSI_CACHE = TRUE`** — Caches recently read bytes in RAM so that
#'    repeated access to the same raster area (e.g., during `crop()` + `mask()`)
#'    does not re-fetch from the server.
#'
#' 3. **`CPL_VSIL_CURL_CHUNK_SIZE` is left at GDAL's default.** Up to version
#'    1.0.5 the package set it to 10 MB. Measured with [wapor_ts()] on WaPOR v3
#'    (150 polygons, 36 dekads): Level 2 took 343 s and requested 1,091 MB with
#'    the 10 MB chunk, against 21 s and 17 MB without it; Level 3 took 66 s and
#'    232 MB against 27 s and 14 MB. Extracted values were identical.
#'
#' While the package itself reads remote rasters it also limits `/vsicurl/` to
#' `.tif` files (`CPL_VSIL_CURL_ALLOWED_EXTENSIONS`), which stops two failing
#' side-file requests per raster. The limit is removed again after each read;
#' switch it off with `options(Rwapor.remote_extension_filter = FALSE)`.
#'
#' @seealso [wapor_gdal_settings()] to view current values.
#'
#' @export
#'
#' @examples
#' # Apply package defaults (also called automatically on attach)
#' wapor_configure_gdal()
#'
#' # A specific HTTP chunk size; only effective before the first remote read
#' wapor_configure_gdal(chunk_size = 1024L * 1024L)
#'
#' # Confirm what was applied
#' wapor_gdal_settings()
wapor_configure_gdal <- function(
    chunk_size     = NULL,
    vsi_cache      = TRUE,
    vsi_cache_size = 100000000L,
    gdal_cachemax  = 512L,
    http_multiplex = TRUE,
    verbose        = FALSE,
    overwrite      = TRUE
) {
  if (!is.null(chunk_size) &&
      (!is.numeric(chunk_size) || length(chunk_size) != 1 || is.na(chunk_size) ||
       chunk_size < 1024 || chunk_size > 10485760)) {
    stop("'chunk_size' must be NULL or a single number of bytes between 1024 and 10485760",
         call. = FALSE)
  }
  if (!is.logical(vsi_cache) || length(vsi_cache) != 1) {
    stop("'vsi_cache' must be a single logical value", call. = FALSE)
  }

  settings <- c(
    if (!is.null(chunk_size)) c(CPL_VSIL_CURL_CHUNK_SIZE = as.character(as.integer(chunk_size))),
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

  if (!isTRUE(overwrite)) {
    current <- Sys.getenv(names(settings), unset = "")
    settings <- settings[!nzchar(current)]
  }
  if (length(settings)) do.call(Sys.setenv, as.list(settings))

  if (isTRUE(verbose)) {
    message("Rwapor GDAL settings applied:")
    for (nm in names(settings)) {
      message(sprintf("  %-40s = %s", nm, settings[[nm]]))
    }
  }

  invisible(settings)
}


#' Fix PROJ_LIB Environment Variable
#'
#' Automatically detects if the `PROJ_LIB` environment variable is pointing
#' to an incompatible PROJ database (common on Windows with multiple GIS
#' installations like PostGIS) and redirects it to the database provided
#' by the `sf` or `terra` packages.
#'
#' @param verbose Logical. Print messages about the detection and fix.
#'
#' @return Character. The `PROJ_LIB` path being used.
#'
#' @export
wapor_fix_proj <- function(verbose = FALSE) {
  # Newer GDAL/PROJ uses PROJ_DATA, older uses PROJ_LIB
  proj_vars <- c("PROJ_LIB", "PROJ_DATA")
  current_paths <- Sys.getenv(proj_vars, unset = "")
  
  # Offending paths usually contain PostgreSQL or PostGIS
  is_offending <- any(grepl("PostgreSQL|PostGIS", current_paths, ignore.case = TRUE))
  
  if (!is_offending && all(nzchar(current_paths))) {
    return(invisible(current_paths[1]))
  }
  
  # Try to find PROJ in sf or terra packages
  search_pkgs <- c("sf", "terra")
  new_path <- ""
  
  for (pkg in search_pkgs) {
    pkg_path <- system.file("proj", package = pkg)
    if (nzchar(pkg_path) && dir.exists(pkg_path)) {
      new_path <- pkg_path
      break
    }
  }
  
  if (nzchar(new_path)) {
    if (isTRUE(verbose)) {
      if (is_offending) {
        message(sprintf("Rwapor: Redirecting PROJ from PostGIS to package-internal database: %s", new_path))
      } else {
        message(sprintf("Rwapor: Setting PROJ to: %s", new_path))
      }
    }
    # Set both for compatibility
    Sys.setenv(PROJ_LIB = new_path)
    Sys.setenv(PROJ_DATA = new_path)
    return(invisible(new_path))
  }
  
  invisible(current_paths[1])
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
  vars <- c("CPL_VSIL_CURL_CHUNK_SIZE", names(.RWAPOR_GDAL_DEFAULTS), "PROJ_LIB")
  vals <- Sys.getenv(vars, unset = "")
  names(vals) <- vars
  vals
}


# Applied automatically on package load, without overwriting GDAL variables
# the user already set. Opt out of the GDAL HTTP settings with
# RWAPOR_AUTO_CONFIG=false (e.g. in .Renviron) or
# options(Rwapor.configure_gdal = FALSE) before loading. The PROJ fix has its
# own switch, options(Rwapor.fix_proj = FALSE): without it a foreign PROJ
# database on the path (PostGIS) costs about 0.35 s per raster open.
.onLoad <- function(libname, pkgname) {
  # Fix PROJ first to prevent GDAL initialization errors on Windows systems
  # that have PostGIS in their PATH.
  if (!isFALSE(getOption("Rwapor.fix_proj", TRUE))) wapor_fix_proj(verbose = FALSE)
  auto <- tolower(Sys.getenv("RWAPOR_AUTO_CONFIG", "true")) %in% c("true", "1", "yes") &&
    isTRUE(getOption("Rwapor.configure_gdal", TRUE))
  if (!auto) return(invisible(NULL))
  wapor_configure_gdal(verbose = FALSE, overwrite = FALSE)

  # Quiet capability check: warn once if GDAL appears to lack curl/COG support.
  .wapor_check_gdal_capabilities()
}

.wapor_check_gdal_capabilities <- function() {
  # Only emit one warning per session, even if the package is reloaded.
  if (isTRUE(getOption("Rwapor.gdal_checked", FALSE))) return(invisible(NULL))
  options(Rwapor.gdal_checked = TRUE)

  gdal_drivers <- tryCatch(terra::gdal(drivers = TRUE), error = function(e) NULL)
  has_cog <- !is.null(gdal_drivers) && "COG" %in% gdal_drivers$name
  # /vsicurl/ is a virtual file system, not a driver, so it never appears in
  # the driver table. GDAL builds its HTTP driver only when curl is available,
  # so that driver is the reliable signal.
  has_curl <- !is.null(gdal_drivers) && "HTTP" %in% gdal_drivers$name

  if (!has_curl || !has_cog) {
    msg <- c(
      "Rwapor: GDAL does not appear to support /vsicurl/ streaming and/or the COG driver.",
      if (!has_curl) "  - vsicurl (curl) support is missing" else NULL,
      if (!has_cog)  "  - COG driver is missing" else NULL,
      "  Streaming functions (wapor_map, wapor_ts, analysis engine) will fail at the first remote read."
    )
    warning(paste(msg, collapse = "\n"), call. = FALSE, immediate. = TRUE)
  }
  invisible(NULL)
}
