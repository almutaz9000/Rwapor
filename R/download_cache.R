# R/download_cache.R
# =============================================================================
# Download once, analyse many times (also without internet)
# =============================================================================

#' Download WaPOR Rasters Once for Local or Offline Analysis
#'
#' Saves one GeoTIFF per time step for an area, in the layout
#' [wapor_run_seasonal_analysis()] reads with `data_source = "local"`:
#' `<folder>/<variable>/<provider>.<variable>.<date>.tif`. Files that are already
#' there are not downloaded again, so the call can be repeated to complete or
#' extend a period, and it works without internet once the files exist.
#'
#' Since version 1.0.6 streaming from the server is about as fast as reading
#' local files, so this is for work without a connection (field work, training
#' rooms) and for analyses that are repeated many times on the same area.
#'
#' @param variable Character vector of variable codes (for example
#'   `c("L3-AETI-D", "L1-RET-D")`).
#' @param region Area to download: a vector file path, an `sf` object, a
#'   bounding box `c(xmin, ymin, xmax, ymax)` in WGS84, or an L3 region code.
#' @param period `c(start_date, end_date)` in `"YYYY-MM-DD"` format.
#' @param folder Folder that holds one sub-folder per variable. Created if needed.
#' @param l3_region Optional L3 region code for Level 3 variables.
#' @param mask Logical. `FALSE` (default) keeps every pixel of the bounding box
#'   of `region`. `TRUE` sets pixels outside a polygon region to `NA`; do not
#'   use it for coarse Level 1 variables, where one pixel covers many fields.
#' @param overwrite Logical. Download the files of `period` again and replace
#'   them (for the same area). Default `FALSE`.
#'
#' @return Invisibly, the paths of the files for the period: a character vector
#'   for one variable, a named list for several. Each vector carries an
#'   attribute `"wapor_status"` with the number of files downloaded, already
#'   present, and whether the server was reachable.
#'
#' @details
#' Values are stored in the unit of the source (for example mm/day for dekadal
#' evapotranspiration): the scale factor of the WaPOR files is applied exactly
#' once and no temporal conversion is made, which is what the seasonal analysis
#' expects from local files. AgERA5 temperatures are converted to degrees
#' Celsius.
#'
#' Each file is written under a temporary name and renamed when complete, so an
#' interrupted download never leaves a partial file that a later call would skip.
#'
#' A folder belongs to one area. The first download writes the area into
#' `<folder>/<variable>/.wapor_download.json`; a later call for an area that is
#' not inside it (or with a different `mask`) stops instead of mixing extents,
#' also with `overwrite = TRUE`. Use another folder for another area.
#'
#' Without a connection the function returns the files already saved for the
#' period and warns that it could not check whether the period is complete. It
#' stops when there are none.
#'
#' @seealso [wapor_run_seasonal_analysis()] (`config$cache_dir` calls this
#'   function for the variables an analysis needs), [wapor_map()].
#' @export
#'
#' @examples
#' \dontrun{
#' files <- wapor_download(
#'   variable = c("L3-AETI-D", "L1-RET-D"),
#'   region   = "citrus_fields.geojson",
#'   period   = c("2024-03-01", "2025-02-28"),
#'   folder   = "wapor_data",
#'   l3_region = "JVA"
#' )
#' attr(files[["L3-AETI-D"]], "wapor_status")
#' }
wapor_download <- function(variable, region, period, folder, l3_region = NULL,
                           mask = FALSE, overwrite = FALSE) {
  if (!is.character(variable) || !length(variable) || anyNA(variable) || any(!nzchar(variable))) {
    stop("'variable' must be a character vector of variable codes", call. = FALSE)
  }
  if (!is.character(period) || length(period) != 2L || anyNA(as.Date(period, optional = TRUE))) {
    stop("'period' must be c(start_date, end_date) in 'YYYY-MM-DD' format", call. = FALSE)
  }
  if (!is.character(folder) || length(folder) != 1L || is.na(folder) || !nzchar(folder)) {
    stop("'folder' must be a single folder path", call. = FALSE)
  }
  for (arg in c("mask", "overwrite")) {
    value <- get(arg)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop(sprintf("'%s' must be TRUE or FALSE", arg), call. = FALSE)
    }
  }
  reg_info <- wapor_parse_region(region)
  variable <- unique(variable)
  out <- lapply(variable, function(v) {
    .wapor_download_one(v, reg_info, period, folder, l3_region, mask, overwrite)
  })
  names(out) <- variable
  invisible(if (length(variable) == 1L) out[[1]] else out)
}

#' Download the missing time steps of one variable (internal)
#' @keywords internal
#' @noRd
.wapor_download_one <- function(variable, reg_info, period, folder, l3_region, mask, overwrite) {
  out_dir <- file.path(folder, variable)
  tres <- utils::tail(strsplit(variable, "-")[[1]], 1)
  status <- function(paths, downloaded, online) {
    structure(paths, wapor_status = list(variable = variable, downloaded = downloaded,
                                         existing = length(paths) - downloaded, online = online))
  }
  # Also with overwrite = TRUE: replacing some dates with another area would mix extents.
  .wapor_download_check_area(out_dir, reg_info, mask, l3_region)

  urls <- tryCatch(wapor_generate_urls(variable, l3_region = l3_region, period = period),
                   error = function(e) e)
  if (inherits(urls, "error") || !length(urls)) {
    reason <- if (inherits(urls, "error")) conditionMessage(urls) else "no files listed for this period"
    saved <- if (dir.exists(out_dir)) {
      suppressWarnings(wapor_local_rasters(folder, variable, period[1], period[2]))
    } else {
      character(0)
    }
    if (!length(saved)) {
      stop(sprintf("Cannot list %s on the WaPOR server (%s) and no saved files for %s to %s in '%s'.",
                   variable, reason, period[1], period[2], out_dir), call. = FALSE)
    }
    warning(sprintf(
      paste0("Cannot list %s on the WaPOR server (%s). Using the %d file(s) already saved in '%s'; ",
             "it was not possible to check that the period is complete."),
      variable, reason, length(saved), out_dir
    ), call. = FALSE)
    return(status(saved, 0L, FALSE))
  }

  dates <- vapply(urls, function(u) {
    as.character(wapor_date_info(sub("^/vsicurl/", "", u), tres = tres)$start_date)
  }, character(1), USE.NAMES = FALSE)
  if (anyDuplicated(dates)) {
    stop(sprintf("%s has more than one file per date for this area (several L3 regions?). Pass 'l3_region'.",
                 variable), call. = FALSE)
  }
  provider <- sub("\\..*$", "", basename(urls))
  targets <- file.path(out_dir, sprintf("%s.%s.%s.tif", provider, variable, dates))
  present <- file.exists(targets) & !is.na(file.size(targets)) & file.size(targets) > 0
  todo <- which(isTRUE(overwrite) | !present)
  if (!length(todo)) {
    .wapor_inform(sprintf("%s: all %d file(s) already saved in '%s'.", variable, length(targets), out_dir))
    return(status(targets, 0L, TRUE))
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  .wapor_inform(sprintf("%s: downloading %d of %d file(s) to '%s'...", variable, length(todo),
                        length(targets), out_dir))
  sources <- .wapor_resolve_remote_sources(urls[todo])
  io_plan <- .wapor_io_plan(sources, reg_info, n_targets = 2L)
  batch <- .wapor_resolve_batch_size(NULL, io_plan)
  for (idx in split(seq_along(todo), ceiling(seq_along(todo) / batch))) {
    .wapor_with_remote_io(.wapor_retry_remote_operation(function() {
      r <- terra::rast(sources[idx])
      # Raw stored values, cropped, then the file scale applied exactly once.
      src <- .wapor_detach_source_scale(r)
      r <- wapor_crop_to_region(src$raster, reg_info, do_mask = mask)
      r <- .wapor_apply_source_scale(r, src$scale, src$offset)
      r <- wapor_convert_temperature(r, variable)
      names(r) <- dates[todo[idx]]
      for (i in seq_along(idx)) {
        .wapor_write_then_publish(.wapor_prepare_map_output(r[[i]], variable, "none"), targets[todo[idx[i]]])
      }
      TRUE   # the retry helper reads NULL as a failed attempt
    }, label = sprintf("%s download (%d file(s))", variable, length(idx))))
  }
  .wapor_download_write_area(out_dir, reg_info, mask, l3_region)
  status(targets, length(todo), TRUE)
}

#' Write a raster under a temporary name and rename it when complete (internal)
#'
#' The temporary name does not end in `.tif`, so the local reader never sees a
#' partial file.
#' @keywords internal
#' @noRd
.wapor_write_then_publish <- function(r, target) {
  tmp <- paste0(target, ".part")
  on.exit(if (file.exists(tmp)) unlink(tmp, force = TRUE), add = TRUE)
  terra::writeRaster(r, tmp, overwrite = TRUE, filetype = "GTiff", datatype = "FLT4S",
                     NAflag = -9999, gdal = .wapor_float_gtiff_options())
  if (file.exists(target)) unlink(target, force = TRUE)
  if (!file.rename(tmp, target) && !file.copy(tmp, target, overwrite = TRUE)) {
    stop(sprintf("Could not write '%s'", target), call. = FALSE)
  }
  invisible(target)
}

.wapor_download_area_file <- function(out_dir) file.path(out_dir, ".wapor_download.json")

#' Area description stored with a downloaded variable (internal)
#' @keywords internal
#' @noRd
.wapor_download_area <- function(reg_info, mask, l3_region) {
  bbox <- tryCatch(.wapor_region_bbox(reg_info), error = function(e) NULL)
  list(
    bbox = if (is.null(bbox)) NULL else as.numeric(bbox),
    region_code = if (identical(reg_info$type, "l3_code")) as.character(reg_info$value) else NULL,
    mask = isTRUE(mask),
    l3_region = if (is.null(l3_region)) NULL else as.character(l3_region)
  )
}

.wapor_download_write_area <- function(out_dir, reg_info, mask, l3_region) {
  path <- .wapor_download_area_file(out_dir)
  if (file.exists(path)) return(invisible(path))   # the first download defines the folder's area
  jsonlite::write_json(.wapor_download_area(reg_info, mask, l3_region), path,
                       auto_unbox = TRUE, digits = NA, null = "null")
  invisible(path)
}

#' Stop when a folder already holds another area (internal)
#'
#' Folders without the note (filled by other tools) are accepted as they are.
#' @keywords internal
#' @noRd
.wapor_download_check_area <- function(out_dir, reg_info, mask, l3_region) {
  path <- .wapor_download_area_file(out_dir)
  if (!file.exists(path)) return(invisible(TRUE))
  saved <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(saved)) return(invisible(TRUE))
  now <- .wapor_download_area(reg_info, mask, l3_region)
  refuse <- function(why) {
    stop(sprintf(paste0("'%s' already holds downloads for another %s. Use another folder ",
                        "for this request (or delete that folder to start again)."), out_dir, why),
         call. = FALSE)
  }
  if (!identical(isTRUE(saved$mask), now$mask)) refuse("'mask' setting")
  if (!identical(saved$l3_region %||% NULL, now$l3_region)) refuse("L3 region")
  if (!identical(saved$region_code %||% NULL, now$region_code)) refuse("region")
  if (!is.null(saved$bbox) && !is.null(now$bbox)) {
    a <- as.numeric(saved$bbox); b <- now$bbox; tol <- 1e-7
    inside <- b[1] >= a[1] - tol && b[2] >= a[2] - tol && b[3] <= a[3] + tol && b[4] <= a[4] + tol
    same <- all(abs(a - b) <= tol)
    # Masked files only fit the polygons they were cut to; unmasked files serve any area inside.
    if ((now$mask && !same) || (!now$mask && !inside)) refuse("area")
  }
  invisible(TRUE)
}
