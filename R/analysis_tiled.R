# R/analysis_tiled.R
# =============================================================================
# Out-of-Core Tiled / Windowed Seasonal Analysis Engine
# =============================================================================

.wapor_tiled_row_windows <- function(nrow, tile_size) {
  tile_size <- max(1L, as.integer(tile_size))
  starts <- seq(1L, as.integer(nrow), by = tile_size)
  lapply(starts, function(r0) {
    list(row = r0, nrows = min(tile_size, as.integer(nrow) - r0 + 1L))
  })
}

#' Run Windowed / Tiled Seasonal Analysis Engine
#'
#' Processes seasonal analysis in spatial row windows so large extents
#' (continental Level 1 grids) do not need the full cube in RAM. Each
#' window is cropped, run through [wapor_run_seasonal_analysis()], and
#' merged. Grids that fit in a single tile still use the in-memory engine.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop class parameters.
#' @param rasters List of SpatRaster objects (mask, start, end).
#' @param output_dir Character. Output directory for tiled GeoTIFF products.
#' @param tile_size Integer. Number of pixel rows per processing window (default: 512).
#' @param progress_callback Optional progress function(value, detail).
#' @param cog Logical. Write outputs with [wapor_write_cog()]. Default `FALSE`.
#' @return List with paths to written raster files, class summary data.frames,
#'   and the merged in-memory `results` for the last/full run when small.
#' @export
wapor_run_seasonal_analysis_tiled <- function(
  config,
  crop_params,
  rasters,
  output_dir = tempdir(),
  tile_size = 512L,
  progress_callback = NULL,
  cog = FALSE
) {
  if (is.null(progress_callback)) progress_callback <- function(v, d) NULL

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  write_out <- function(r, path) {
    if (is.null(r)) return(invisible(NULL))
    if (isTRUE(cog)) {
      wapor_write_cog(r, path, overwrite = TRUE)
    } else {
      terra::writeRaster(r, path, overwrite = TRUE)
    }
    path
  }

  template_candidates <- Filter(
    function(x) inherits(x, "SpatRaster"),
    list(rasters$crop_mask, rasters$season_start, rasters$season_end)
  )
  template <- if (length(template_candidates)) template_candidates[[1]] else NULL

  n_row <- if (!is.null(template)) terra::nrow(template) else NA_integer_
  windows <- if (!is.na(n_row) && n_row > as.integer(tile_size)) {
    .wapor_tiled_row_windows(n_row, tile_size)
  } else {
    list()
  }

  if (!length(windows)) {
    progress_callback(0.1, "Grid fits in one tile; using in-memory engine...")
    results <- Rwapor::wapor_run_seasonal_analysis(
      config = config,
      crop_params = crop_params,
      rasters = rasters,
      progress_callback = function(v, d) progress_callback(0.1 + 0.8 * v, d)
    )
    saved_files <- list()
    if (!is.null(results$seasonal_aeti$raster)) {
      saved_files$seasonal_aeti <- write_out(
        results$seasonal_aeti$raster, file.path(output_dir, "seasonal_aeti.tif")
      )
    }
    if (!is.null(results$seasonal_biomass)) {
      saved_files$seasonal_biomass <- write_out(
        results$seasonal_biomass, file.path(output_dir, "seasonal_biomass.tif")
      )
    }
    if (!is.null(results$seasonal_biomass_t)) {
      saved_files$seasonal_biomass_t <- write_out(
        results$seasonal_biomass_t, file.path(output_dir, "seasonal_biomass_t.tif")
      )
    }
    if (!is.null(results$adequacy_etc)) {
      saved_files$adequacy_etc <- write_out(
        results$adequacy_etc, file.path(output_dir, "adequacy_etc.tif")
      )
    }
    progress_callback(1.0, "Tiled seasonal processing complete.")
    return(list(results = results, saved_files = saved_files, n_tiles = 1L))
  }

  crop_window <- function(r, win) {
    if (is.null(r) || !inherits(r, "SpatRaster")) return(r)
    r0 <- win$row
    r1 <- win$row + win$nrows - 1L
    nr <- terra::nrow(r)
    cell_h <- (terra::ymax(r) - terra::ymin(r)) / nr
    ymax_w <- terra::ymax(r) - (r0 - 1) * cell_h
    ymin_w <- terra::ymax(r) - r1 * cell_h
    terra::crop(r, terra::ext(terra::xmin(r), terra::xmax(r), ymin_w, ymax_w))
  }

  tile_aeti <- list()
  tile_adeq <- list()
  tile_biomass <- list()
  n_tiles <- length(windows)

  for (i in seq_along(windows)) {
    win <- windows[[i]]
    progress_callback(i / n_tiles, sprintf("Tile %d / %d (rows %d-%d)...", i, n_tiles, win$row, win$row + win$nrows - 1L))
    tile_rasters <- list(
      crop_mask = crop_window(rasters$crop_mask, win),
      season_start = crop_window(rasters$season_start, win),
      season_end = crop_window(rasters$season_end, win)
    )
    tile_res <- Rwapor::wapor_run_seasonal_analysis(
      config = config,
      crop_params = crop_params,
      rasters = tile_rasters,
      progress_callback = NULL
    )
    if (!is.null(tile_res$seasonal_aeti$raster)) {
      tile_aeti[[i]] <- tile_res$seasonal_aeti$raster
    }
    if (!is.null(tile_res$adequacy_etc)) {
      tile_adeq[[i]] <- tile_res$adequacy_etc
    }
    if (!is.null(tile_res$seasonal_biomass_t)) {
      tile_biomass[[i]] <- tile_res$seasonal_biomass_t
    } else if (!is.null(tile_res$seasonal_biomass)) {
      tile_biomass[[i]] <- tile_res$seasonal_biomass
    }
  }

  merge_tiles <- function(xs) {
    xs <- Filter(Negate(is.null), xs)
    if (!length(xs)) return(NULL)
    if (length(xs) == 1L) return(xs[[1]])
    tryCatch(
      terra::merge(terra::sprc(xs)),
      error = function(e) {
        out <- xs[[1]]
        for (j in seq_along(xs)[-1]) {
          out <- terra::merge(out, xs[[j]])
        }
        out
      }
    )
  }

  merged_aeti <- merge_tiles(tile_aeti)
  merged_adeq <- merge_tiles(tile_adeq)
  merged_biomass <- merge_tiles(tile_biomass)

  saved_files <- list()
  if (!is.null(merged_aeti)) {
    saved_files$seasonal_aeti <- write_out(merged_aeti, file.path(output_dir, "seasonal_aeti.tif"))
  }
  if (!is.null(merged_biomass)) {
    saved_files$seasonal_biomass <- write_out(merged_biomass, file.path(output_dir, "seasonal_biomass.tif"))
  }
  if (!is.null(merged_adeq)) {
    saved_files$adequacy_etc <- write_out(merged_adeq, file.path(output_dir, "adequacy_etc.tif"))
  }

  progress_callback(1.0, "Tiled seasonal processing complete.")
  list(
    results = list(
      seasonal_aeti = list(raster = merged_aeti),
      seasonal_biomass = merged_biomass,
      adequacy_etc = merged_adeq
    ),
    saved_files = saved_files,
    n_tiles = n_tiles
  )
}
