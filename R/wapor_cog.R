#' Write a Cloud-Optimized GeoTIFF
#'
#' Writes `x` with the GDAL COG driver when available. If that driver is
#' missing, falls back to a tiled, compressed GeoTIFF. The fallback remains
#' readable and can support efficient range access, but is not guaranteed to
#' satisfy the complete COG overview specification.
#'
#' @param x SpatRaster to write.
#' @param filename Character. Output `.tif` path.
#' @param overwrite Logical. Overwrite an existing file. Default `TRUE`.
#' @param datatype Character. Output GDAL datatype: one of `"INT1U"`, `"INT1S"`,
#'   `"INT2U"`, `"INT2S"`, `"INT4U"`, `"INT4S"`, `"FLT4S"`, `"FLT8S"`. If `NULL`
#'   (default), the datatype is probed from the actual cell values of the first
#'   layer: integer-valued rasters within the INT4 range are written as `"INT4S"`,
#'   everything else as `"FLT4S"`.
#' @param ... Passed to [terra::writeRaster()] (for example `NAflag`).
#' @return The `filename`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' r <- terra::rast(nrows = 4, ncols = 4, vals = 1:16)
#' wapor_write_cog(r, tempfile(fileext = ".tif"))
#' }
wapor_write_cog <- function(x, filename, overwrite = TRUE, datatype = NULL, ...) {
  if (!inherits(x, "SpatRaster")) {
    stop("'x' must be a SpatRaster", call. = FALSE)
  }
  if (!is.character(filename) || length(filename) != 1L || !nzchar(filename)) {
    stop("'filename' must be a single non-empty path", call. = FALSE)
  }

  dir_name <- dirname(filename)
  if (!dir.exists(dir_name)) {
    dir.create(dir_name, recursive = TRUE, showWarnings = FALSE)
  }

  if (file.exists(filename) && !isTRUE(overwrite)) {
    stop(sprintf("File already exists: %s", filename), call. = FALSE)
  }

  ext <- tools::file_ext(filename)
  if (!nzchar(ext)) ext <- "tif"
  tmp <- paste0(filename, ".partial.", ext)
  if (file.exists(tmp)) {
    unlink(tmp, force = TRUE)
  }

  drivers <- tryCatch(terra::gdal(drivers = TRUE)$name, error = function(e) character(0))
  use_cog <- length(drivers) && "COG" %in% drivers

  # Determine datatype from actual cell values (not storage type) so COG
  # writes match the data, not the in-memory representation.
  known_dtypes <- c("INT1U", "INT1S", "INT2U", "INT2S", "INT4U", "INT4S", "FLT4S", "FLT8S")
  if (is.null(datatype)) {
    datatype <- .wapor_probe_datatype(x)
  } else {
    if (!datatype %in% known_dtypes) {
      stop(sprintf("'datatype' must be one of: %s", paste(known_dtypes, collapse = ", ")), call. = FALSE)
    }
  }

  # Lookup actual bytes per value so BIGTIFF threshold is correct for all dtypes.
  .dtype_bytes <- c(
    INT1U = 1L, INT1S = 1L,
    INT2U = 2L, INT2S = 2L,
    INT4U = 4L, INT4S = 4L,
    FLT4S = 4L, FLT8S = 8L
  )
  bytes_per_val <- .dtype_bytes[[datatype]] %||% 4L
  ncell_x <- as.numeric(terra::ncell(x)) * as.numeric(terra::nlyr(x))
  bigtiff <- if (isTRUE(ncell_x * bytes_per_val > 3.5e9)) "YES" else "IF_NEEDED"
  predictor <- if (datatype %in% c("FLT4S", "FLT8S")) "PREDICTOR=3" else "PREDICTOR=2"

  on.exit({
    if (file.exists(tmp) && !identical(normalizePath(tmp, winslash = "/", mustWork = FALSE),
                                       normalizePath(filename, winslash = "/", mustWork = FALSE))) {
      unlink(tmp, force = TRUE)
    }
  }, add = TRUE)

  if (isTRUE(use_cog)) {
    terra::writeRaster(
      x,
      tmp,
      overwrite = TRUE,
      filetype = "COG",
      datatype = datatype,
      gdal = c("COMPRESS=LZW", "OVERVIEWS=AUTO", predictor, paste0("BIGTIFF=", bigtiff)),
      ...
    )
  } else {
    terra::writeRaster(
      x,
      tmp,
      overwrite = TRUE,
      datatype = datatype,
      gdal = c("TILED=YES", "COMPRESS=LZW", "COPY_SRC_OVERVIEWS=YES", predictor, paste0("BIGTIFF=", bigtiff)),
      ...
    )
  }

  if (file.exists(filename)) {
    unlink(filename, force = TRUE)
  }
  if (!file.rename(tmp, filename)) {
    if (!file.copy(tmp, filename, overwrite = TRUE)) {
      stop(sprintf("Failed to publish COG to %s", filename), call. = FALSE)
    }
    unlink(tmp, force = TRUE)
  }
  invisible(filename)
}

#' Probe the output datatype from actual cell values
#'
#' Samples up to 10000 cells from the first layer of `x` and determines the
#' smallest GDAL datatype that can losslessly represent all non-NA values.
#' Integer-valued rasters within the INT4 range are classified as `"INT4S"` (or
#' `"INT4U"` when all values are non-negative); everything else is `"FLT4S"`.
#'
#' @param x SpatRaster.
#' @return A single datatype string: `"INT4U"`, `"INT4S"`, or `"FLT4S"`.
#' @keywords internal
#' @noRd
.wapor_probe_datatype <- function(x) {
  n <- terra::ncell(x)
  if (n == 0L) return("FLT4S")

  sample_size <- min(n, 10000L)
  ncol_x <- max(1L, as.integer(terra::ncol(x)))
  sample_rows <- max(1L, ceiling(sample_size / ncol_x))

  vals <- tryCatch(
    as.numeric(terra::readValues(x, row = 1L, nrows = sample_rows, mat = TRUE)),
    error = function(e) NULL
  )
  if (!is.null(vals) && length(vals) > sample_size) vals <- vals[seq_len(sample_size)]
  if (is.null(vals)) return("FLT4S")

  vals <- vals[!is.na(vals)]
  if (length(vals) == 0L) return("FLT4S")

  # Integer-valued check: all non-NA values within 1e-6 of an integer.
  is_int_val <- all(abs(vals - round(vals)) < 1e-6)
  if (!is_int_val) return("FLT4S")

  rng <- range(vals, na.rm = TRUE)
  # INT4S range: -2147483648 .. 2147483647
  if (rng[1] >= -2147483648 && rng[2] <= 2147483647) {
    if (rng[1] >= 0) return("INT4U")
    return("INT4S")
  }

  # Integer-valued but outside INT4 range: fall back to float.
  "FLT4S"
}

#' Write a Cloud-Optimized GeoTIFF
#' @param r SpatRaster to write.
#' @param path Output path.
#' @param ... Passed to `wapor_write_cog()`.
#' @return `path`, invisibly.
#' @export
write_raster_cog <- function(r, path, ...) {
  wapor_write_cog(r, path, ...)
}

#' Write an L3 mosaic and coverage manifest
#'
#' @param asset_paths Named character vector of per-L3 GeoTIFF asset paths.
#' @param output_dir Directory for the VRT, COG, and JSON manifest.
#' @param output_stem File stem for generated assets.
#' @return A list with VRT, COG, manifest paths, and coverage metadata.
#' @export
wapor_write_l3_mosaic <- function(asset_paths, output_dir, output_stem) {
  if (!is.character(asset_paths) || !length(asset_paths) || is.null(names(asset_paths)) ||
      any(!nzchar(names(asset_paths))) || any(!file.exists(asset_paths))) {
    stop("'asset_paths' must be a named vector of existing GeoTIFF paths", call. = FALSE)
  }
  if (!is.character(output_dir) || length(output_dir) != 1L || !nzchar(output_dir) ||
      !is.character(output_stem) || length(output_stem) != 1L || !nzchar(output_stem)) {
    stop("'output_dir' and 'output_stem' must be single non-empty strings", call. = FALSE)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  l3_codes <- sort(unique(names(asset_paths)))
  asset_paths <- unname(asset_paths[l3_codes])
  vrt_path <- file.path(output_dir, paste0(output_stem, ".vrt"))
  cog_path <- file.path(output_dir, paste0(output_stem, ".tif"))
  manifest_path <- file.path(output_dir, paste0(output_stem, ".coverage.json"))
  terra::vrt(asset_paths, filename = vrt_path, overwrite = TRUE)
  mosaic <- terra::rast(vrt_path)
  wapor_write_cog(mosaic, cog_path, overwrite = TRUE)
  coverage <- list(l3_codes = l3_codes, asset_paths = stats::setNames(asset_paths, l3_codes),
                   vrt_path = vrt_path, cog_path = cog_path)
  jsonlite::write_json(coverage, manifest_path, pretty = TRUE, auto_unbox = TRUE)
  list(vrt_path = vrt_path, cog_path = cog_path, manifest_path = manifest_path, coverage = coverage)
}

.wapor_period_list <- function(period) {
  if (is.list(period)) period else list(period)
}

.wapor_period_label <- function(period, i = 1L) {
  nm <- names(period)
  if (!is.null(nm) && length(nm) >= i && nzchar(nm[[i]])) {
    return(nm[[i]])
  }
  p <- if (is.list(period)) period[[i]] else period
  paste(p, collapse = "_")
}

wapor_map_mosaic_all <- function(region, variable, period, folder, filename = NULL,
                                 separate_files = FALSE, unit_conversion = NULL,
                                 seasonal = FALSE, mask = FALSE, parallel = FALSE,
                                 batching = TRUE, batch_size = 12L,
                                 partial = FALSE, cog = FALSE, fun = NULL) {
  periods <- .wapor_period_list(period)
  results <- list()
  for (var in variable) {
    for (i in seq_along(periods)) {
      p <- periods[[i]]
      l3_codes <- wapor_resolve_l3_selection(
        wapor_guess_region(var, wapor_parse_region(region), p),
        l3_mode = "mosaic_all"
      )
      source_root <- file.path(folder, "l3_sources", var, .wapor_period_label(period, i))
      asset_paths <- vapply(l3_codes, function(code) {
        path <- wapor_map(
          region = region, variable = var, period = p,
          folder = file.path(source_root, code), filename = filename,
          separate_files = FALSE, unit_conversion = unit_conversion,
          seasonal = seasonal, mask = mask, parallel = parallel,
          batching = batching, batch_size = batch_size,
          l3_region = code, l3_mode = "select",
          partial = partial, cog = cog, fun = fun
        )
        if (is.list(path) && !is.null(path$seasonal_aggregate)) path <- path$seasonal_aggregate
        if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
          stop(sprintf("L3 source asset was not written for %s / %s", var, code), call. = FALSE)
        }
        path
      }, character(1))
      names(asset_paths) <- l3_codes
      stem <- tools::file_path_sans_ext(filename %||% paste0(var, "_", .wapor_period_label(period, i), "_mosaic"))
      key <- paste(var, .wapor_period_label(period, i), sep = "/")
      results[[key]] <- wapor_write_l3_mosaic(asset_paths, file.path(folder, "l3_mosaic", var), stem)
    }
  }
  if (length(results) == 1L) results[[1]] else results
}

wapor_ts_mosaic_all <- function(region, variable, period, identifier = NULL,
                                unit_conversion = NULL, seasonal = FALSE,
                                download_locally = FALSE, parallel = FALSE,
                                batching = TRUE, batch_size = 12L,
                                partial = FALSE, fun = NULL) {
  codes <- wapor_resolve_l3_selection(
    wapor_guess_region(variable, wapor_parse_region(region), period),
    l3_mode = "mosaic_all"
  )
  parts <- lapply(codes, function(code) {
    df <- wapor_ts(
      region = region, variable = variable, period = period,
      identifier = identifier, unit_conversion = unit_conversion,
      seasonal = seasonal, download_locally = download_locally,
      parallel = parallel, batching = batching, batch_size = batch_size,
      l3_region = code, l3_mode = "select", partial = partial, fun = fun
    )
    df$l3_region <- code
    df
  })
  do.call(rbind, parts)
}

wapor_shiny_l3_choices <- function(codes) {
  codes <- unique(as.character(codes))
  choices <- stats::setNames(codes, codes)
  if (length(codes) > 1L) {
    choices <- c(choices, stats::setNames("__MOSAIC_ALL__", "Mosaic all intersecting L3 regions"))
  }
  choices
}

wapor_shiny_l3_selection <- function(codes, current = NULL) {
  codes <- unique(as.character(codes))
  if (identical(current, "__MOSAIC_ALL__") && length(codes) > 1L) {
    return("__MOSAIC_ALL__")
  }
  if (!is.null(current) && nzchar(current) && current %in% codes) {
    return(current)
  }
  if (length(codes) == 1L) {
    return(codes[[1]])
  }
  ""
}

