# R/netcdf_export.R
# =============================================================================
# NetCDF export of downloaded WaPOR raster stacks
# =============================================================================

#' Export Downloaded WaPOR Rasters as a NetCDF Cube
#'
#' Reads per-date GeoTIFF files from a [wapor_download()] cache folder,
#' stacks them in time order, and writes a single CF-compliant NetCDF-4 file.
#' The GeoTIFF cache is preserved unchanged; this is an *additional* export
#' for interchange with Python (xarray, CDO, Panoply) or other climate tools.
#'
#' The output layout is:
#' `<folder>/netcdf/<variable>/<variable>.<start>_<end>.nc`
#'
#' Existing files are overwritten only when `overwrite = TRUE`.  Writes are
#' atomic: the file is written to a `.partial.nc` sibling and renamed on
#' success.
#'
#' @param folder Character. Root download folder (same as the first argument of
#'   [wapor_download()]).
#' @param variable Character. Variable code (e.g. `"L1-AETI-D"`).
#' @param period Optional `c(start, end)` in `"YYYY-MM-DD"` to restrict the
#'   layers included. Default `NULL` uses all files found in the folder.
#' @param output_dir Optional override for the destination directory.  Default
#'   is `<folder>/netcdf/<variable>/`.
#' @param filename Optional filename.  Default is
#'   `<variable>.<first_date>_<last_date>.nc`.
#' @param overwrite Logical.  Replace an existing file. Default `FALSE`.
#' @param compression Integer 1-9, or `NA` for no compression. Default `4`.
#' @param varname Character. NetCDF variable name. Default is the WaPOR
#'   variable code with hyphens replaced by underscores.
#' @param longname Character. Human-readable description written as the NetCDF
#'   `long_name` attribute. Default is derived from WaPOR metadata when
#'   available, otherwise the variable code.
#' @param unit Character. Physical unit string. Default is read from the first
#'   GeoTIFF's stored unit; pass explicitly to override.
#' @param add_time_bounds Logical. Write a CF `time_bnds` auxiliary coordinate
#'   variable encoding each dekad's start and end date. Default `TRUE`. This
#'   preserves the 8-11 day last-dekad duration that is lost when only the
#'   start date is recorded.
#'
#' @return Character. Path to the written `.nc` file, invisibly.
#'
#' @details
#' The function requires the \pkg{ncdf4} package (a Suggests dependency of
#' terra).  An informative error is raised when it is absent.
#'
#' Values are written in `"float"` precision (32-bit), consistent with the
#' `FLT4S` GeoTIFFs written by [wapor_download()].  Missing values are stored
#' as `1e30` (the NetCDF default for float).
#'
#' Time is encoded as days since the Unix epoch (`1970-01-01`) with
#' `calendar = "standard"`.  When `add_time_bounds = TRUE` a `time_bnds`
#' variable with shape `(2, ntime)` records the start and end of every dekad.
#'
#' CF attributes written: `Conventions = "CF-1.6"`, `institution`,
#' `source = "FAO WaPOR v3"`, `created_by`, `created_date`.
#'
#' @seealso [wapor_download()], [wapor_local_rasters()]
#'
#' @examples
#' \dontrun{
#' # After downloading:
#' wapor_download("L1-AETI-D", region = my_aoi, period = c("2024-01-01","2024-12-31"),
#'                folder = "wapor_data")
#' nc <- wapor_export_netcdf("wapor_data", "L1-AETI-D")
#' # Open in Python: xr.open_dataset(nc)
#' }
#' @export
wapor_export_netcdf <- function(
    folder,
    variable,
    period         = NULL,
    output_dir     = NULL,
    filename       = NULL,
    overwrite      = FALSE,
    compression    = 4L,
    varname        = NULL,
    longname       = NULL,
    unit           = NULL,
    add_time_bounds = TRUE
) {
  if (!requireNamespace("ncdf4", quietly = TRUE)) {
    stop(
      "Package 'ncdf4' is required for wapor_export_netcdf(). ",
      "Install it with: install.packages('ncdf4')",
      call. = FALSE
    )
  }
  if (!is.character(folder) || length(folder) != 1L || !nzchar(folder)) {
    stop("'folder' must be a single non-empty path.", call. = FALSE)
  }
  if (!is.character(variable) || length(variable) != 1L || !nzchar(variable)) {
    stop("'variable' must be a single variable code such as \"L1-AETI-D\".", call. = FALSE)
  }

  # --- Resolve source files ---
  start <- if (!is.null(period)) period[1] else "1900-01-01"
  end   <- if (!is.null(period)) period[2] else "2100-12-31"
  paths <- wapor_local_rasters(folder, variable, start, end)
  if (length(paths) == 0L) {
    stop(sprintf(
      "No GeoTIFF files found for variable '%s' in folder '%s'.",
      variable, folder
    ), call. = FALSE)
  }

  # --- Derive per-layer dates from filenames ---
  dates_chr <- vapply(
    basename(paths),
    function(nm) .wapor_ymd_from_name(nm),
    character(1),
    USE.NAMES = FALSE
  )
  if (anyNA(dates_chr)) {
    bad <- paths[is.na(dates_chr)]
    stop(sprintf(
      "Cannot extract a date from these file names (expected YYYY-MM-DD):\n  %s",
      paste(basename(bad), collapse = "\n  ")
    ), call. = FALSE)
  }
  dates <- as.Date(dates_chr)

  # --- Compute dekad end dates (for time_bnds) ---
  dekad_ends <- vapply(dates, function(d) {
    day <- as.integer(format(d, "%d"))
    if (day <= 10L) {
      d + 9L
    } else if (day <= 20L) {
      d + 9L
    } else {
      last <- as.integer(lubridate::days_in_month(d))
      as.Date(paste0(format(d, "%Y-%m-"), sprintf("%02d", last)))
    }
  }, numeric(1))
  dekad_ends <- as.Date(dekad_ends, origin = "1970-01-01")

  # --- Read stack + collect units ---
  layers <- lapply(paths, terra::rast)
  # Coerce all layers to same geometry as the first (guard against tiny diffs)
  ref <- layers[[1]]
  if (length(layers) > 1L) {
    layers <- lapply(layers, function(l) {
      if (!isTRUE(terra::compareGeom(l, ref, stopOnError = FALSE))) {
        l <- terra::resample(l, ref, method = "bilinear")
      }
      l
    })
  }
  stack <- terra::rast(layers)

  # --- Units ---
  if (is.null(unit)) {
    stored_units <- tryCatch(
      terra::units(ref)[1],
      error = function(e) NA_character_
    )
    unit <- if (is.na(stored_units) || !nzchar(stored_units)) "unknown" else stored_units
  }

  # --- varname / longname ---
  if (is.null(varname)) {
    varname <- gsub("-", "_", variable)
  }
  if (is.null(longname)) {
    meta <- tryCatch(wapor_variable_metadata(variable), error = function(e) NULL)
    longname <- if (!is.null(meta$name) && nzchar(meta$name)) meta$name else variable
  }

  # --- Output path ---
  first_date <- as.character(min(dates))
  last_date  <- as.character(max(dates))
  if (is.null(output_dir)) {
    output_dir <- file.path(folder, "netcdf", variable)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(filename)) {
    filename <- sprintf("%s.%s_%s.nc", variable, first_date, last_date)
  }
  nc_path <- file.path(output_dir, filename)
  if (file.exists(nc_path) && !isTRUE(overwrite)) {
    stop(sprintf(
      "Output already exists: '%s'. Use overwrite = TRUE to replace it.",
      nc_path
    ), call. = FALSE)
  }
  tmp_path <- paste0(nc_path, ".partial.nc")
  on.exit({
    if (file.exists(tmp_path)) unlink(tmp_path, force = TRUE)
  }, add = TRUE)

  # --- Compress arg ---
  compress_int <- if (is.na(compression) || is.null(compression)) {
    NA_integer_
  } else {
    as.integer(compression)
  }

  # --- Build terra time axis and write via writeCDF ---
  terra::time(stack) <- dates
  invisible(
    terra::writeCDF(
      stack,
      tmp_path,
      overwrite = TRUE,
      varname   = varname,
      longname  = longname,
      unit      = unit,
      compression = compress_int
    )
  )

  # --- Add CF global attributes + time_bnds via ncdf4 ---
  nc <- ncdf4::nc_open(tmp_path, write = TRUE)
  nc_closed <- FALSE
  on.exit({
    if (!nc_closed) tryCatch(ncdf4::nc_close(nc), error = function(e) NULL)
    if (file.exists(tmp_path)) unlink(tmp_path, force = TRUE)
  }, add = TRUE)

  # CF global attributes
  ncdf4::ncatt_put(nc, 0, "Conventions",  "CF-1.6",    prec = "text")
  ncdf4::ncatt_put(nc, 0, "institution",  "FAO",       prec = "text")
  ncdf4::ncatt_put(nc, 0, "source",       "FAO WaPOR v3", prec = "text")
  ncdf4::ncatt_put(nc, 0, "created_by",
    paste0("R package Rwapor (wapor_export_netcdf)"), prec = "text")
  ncdf4::ncatt_put(nc, 0, "created_date",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"), prec = "text")

  # time_bnds: (2, ntime) in days since epoch --------------------------------
  if (isTRUE(add_time_bounds)) {
    epoch <- as.Date("1970-01-01")
    t_start <- as.numeric(dates - epoch)        # vector length ntime
    t_end   <- as.numeric(dekad_ends - epoch)   # vector length ntime
    ntime   <- length(dates)

    # nbnds dim
    dim_nbnds <- ncdf4::ncdim_def("nbnds", units = "", vals = 1:2,
                                  create_dimvar = FALSE)
    # get existing time dim from the file
    time_dim <- nc$dim[["time"]]
    if (is.null(time_dim)) time_dim <- nc$dim[[1]]   # fallback if terra names it differently

    var_bnds <- ncdf4::ncvar_def(
      name    = "time_bnds",
      units   = "days since 1970-01-01",
      dim     = list(dim_nbnds, time_dim),
      missval = 1e30,
      prec    = "double"
    )
    nc <- ncdf4::ncvar_add(nc, var_bnds)
    ncdf4::ncvar_put(nc, "time_bnds", matrix(c(t_start, t_end), nrow = 2, byrow = TRUE))
    # attach bounds attribute to the time variable
    if (!is.null(nc$var[["time"]])) {
      ncdf4::ncatt_put(nc, "time", "bounds", "time_bnds", prec = "text")
    }
  }

  ncdf4::nc_close(nc)
  nc_closed <- TRUE
  if (file.exists(nc_path) && isTRUE(overwrite)) unlink(nc_path, force = TRUE)
  ok <- suppressWarnings(file.rename(tmp_path, nc_path))
  if (!isTRUE(ok) || !file.exists(nc_path)) {
    # rename may fail across volumes; fall back to copy
    if (file.exists(tmp_path) && file.copy(tmp_path, nc_path, overwrite = TRUE)) {
      unlink(tmp_path, force = TRUE)
    } else {
      stop(sprintf("Could not publish NetCDF to '%s'.", nc_path), call. = FALSE)
    }
  }
  # Confirm and discard the leftover tmp if any
  if (file.exists(tmp_path)) unlink(tmp_path, force = TRUE)

  invisible(nc_path)
}
