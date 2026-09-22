#' Report GDAL capabilities required for remote WaPOR rasters
#'
#' @param refresh Logical. Recompute the capability probe instead of using the
#'   session result. Defaults to `FALSE`.
#' @return A list with `has_curl`, `has_cog`, `streaming`, and `message`.
#' @export
wapor_remote_capabilities <- function(refresh = FALSE) {
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("'refresh' must be a single logical value", call. = FALSE)
  }
  if (!isTRUE(refresh)) {
    cached <- getOption("Rwapor.remote_capabilities")
    if (is.list(cached)) return(cached)
  }

  drivers <- tryCatch(terra::gdal(drivers = TRUE), error = function(e) NULL)
  has_cog <- !is.null(drivers) && "COG" %in% drivers$name
  has_curl <- !is.null(drivers) && any(
    grepl("vsicurl|curl", drivers$longname, ignore.case = TRUE)
  )
  streaming <- isTRUE(has_cog && has_curl)
  message <- if (streaming) {
    "GDAL supports /vsicurl/ and the COG driver."
  } else {
    paste(
      "GDAL does not provide the complete remote COG capability:",
      if (!has_curl) "curl /vsicurl support is missing." else NULL,
      if (!has_cog) "the COG driver is missing." else NULL
    )
  }
  result <- list(
    has_curl = isTRUE(has_curl),
    has_cog = isTRUE(has_cog),
    streaming = streaming,
    message = message
  )
  options(Rwapor.remote_capabilities = result)
  result
}

.wapor_remote_cache_dir <- function() {
  configured <- getOption("Rwapor.remote_cache_dir", "")
  cache_dir <- if (nzchar(configured)) {
    path.expand(configured)
  } else {
    file.path(tools::R_user_dir("Rwapor", "cache"), "rasters")
  }
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(cache_dir) || file.access(cache_dir, 2) != 0) {
    stop(sprintf("Remote raster cache is not writable: %s", cache_dir), call. = FALSE)
  }
  cache_dir
}

.wapor_download_remote_raster <- function(url, cache_dir = .wapor_remote_cache_dir()) {
  raw_url <- sub("^/vsicurl/", "", url)
  if (!grepl("^https?://", raw_url, ignore.case = TRUE)) return(raw_url)
  key <- digest::digest(raw_url, algo = "sha256")
  target <- file.path(cache_dir, paste0(key, ".tif"))
  if (file.exists(target) && isTRUE(file.info(target)$size > 0)) return(target)

  temp <- tempfile(pattern = paste0(key, "-"), tmpdir = cache_dir, fileext = ".part")
  on.exit(unlink(temp, force = TRUE), add = TRUE)
  old_timeout <- getOption("timeout")
  options(timeout = max(60, old_timeout %||% 60))
  on.exit(options(timeout = old_timeout), add = TRUE)
  status <- tryCatch(
    utils::download.file(raw_url, temp, mode = "wb", quiet = TRUE),
    error = function(e) stop(sprintf("Failed to cache remote raster '%s': %s", raw_url, e$message), call. = FALSE)
  )
  if (!identical(status, 0L) || !file.exists(temp) || isTRUE(file.info(temp)$size <= 0)) {
    stop(sprintf("Failed to cache remote raster '%s'", raw_url), call. = FALSE)
  }
  if (!file.rename(temp, target)) {
    if (!file.exists(target)) stop(sprintf("Could not publish cached raster: %s", target), call. = FALSE)
  }
  target
}

.wapor_resolve_remote_sources <- function(urls, fallback = getOption("Rwapor.remote_fallback", "stream")) {
  if (!is.character(urls) || length(urls) == 0) return(character(0))
  fallback <- match.arg(fallback, c("download", "error", "stream"))
  caps <- wapor_remote_capabilities()
  if (identical(fallback, "stream") || isTRUE(caps$streaming)) {
    return(.wapor_prefix_vsicurl(urls))
  }
  if (identical(fallback, "error")) {
    stop(
      paste0(
        "Remote COG streaming is unavailable. ", caps$message,
        " Set options(Rwapor.remote_fallback = 'download') to use the local cache fallback."
      ),
      call. = FALSE
    )
  }
  vapply(urls, .wapor_download_remote_raster, character(1))
}
