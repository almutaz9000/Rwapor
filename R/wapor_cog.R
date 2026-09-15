#' Write a Cloud-Optimized GeoTIFF
#'
#' Writes `x` with the GDAL COG driver when available. If that driver is
#' missing, falls back to a tiled GeoTIFF with internal overviews so the
#' file is still range-request friendly.
#'
#' @param x SpatRaster to write.
#' @param filename Character. Output `.tif` path.
#' @param overwrite Logical. Overwrite an existing file. Default `TRUE`.
#' @param ... Passed to [terra::writeRaster()] (for example `NAflag`).
#' @return The `filename`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' r <- terra::rast(nrows = 4, ncols = 4, vals = 1:16)
#' wapor_write_cog(r, tempfile(fileext = ".tif"))
#' }
wapor_write_cog <- function(x, filename, overwrite = TRUE, ...) {
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
  datatype <- if (terra::is.int(x)) "INT4S" else "FLT4S"
  ncell_x <- as.numeric(terra::ncell(x)) * as.numeric(terra::nlyr(x))
  bigtiff <- if (isTRUE(ncell_x * 8 > 3.5e9)) "YES" else "IF_NEEDED"
  predictor <- if (identical(datatype, "FLT4S")) "PREDICTOR=3" else "PREDICTOR=2"

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
                                 partial = FALSE, cog = FALSE) {
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
          partial = partial, cog = cog
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
                                partial = FALSE) {
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
      l3_region = code, l3_mode = "select", partial = partial
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

