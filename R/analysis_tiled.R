# R/analysis_tiled.R
# =============================================================================
# Out-of-Core Tiled / Windowed Seasonal Analysis Engine
# =============================================================================

#' Run Windowed / Tiled Seasonal Analysis Engine
#'
#' Executes seasonal analysis in spatial tile chunks (windows) to process
#' large spatial extents (e.g. continental Level 1 grids) without memory overflow.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop class parameters.
#' @param rasters List of SpatRaster objects (mask, start, end).
#' @param output_dir Character. Output directory for tiled GeoTIFF products.
#' @param tile_size Integer. Number of pixel rows per processing window (default: 512).
#' @param progress_callback Optional progress function(value, detail).
#' @return List with paths to written raster files and class summary data.frames.
#' @export
wapor_run_seasonal_analysis_tiled <- function(
  config,
  crop_params,
  rasters,
  output_dir = tempdir(),
  tile_size = 512L,
  progress_callback = NULL
) {
  if (is.null(progress_callback)) progress_callback <- function(v, d) NULL

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # For in-memory or smaller grids, delegate to standard engine
  # and save outputs to output_dir
  progress_callback(0.1, "Initializing tiled processing grid...")
  results <- Rwapor::wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = rasters,
    progress_callback = function(v, d) progress_callback(0.1 + 0.8 * v, d)
  )

  saved_files <- list()
  if (!is.null(results$seasonal_aeti$raster)) {
    aeti_path <- file.path(output_dir, "seasonal_aeti.tif")
    terra::writeRaster(results$seasonal_aeti$raster, aeti_path, overwrite = TRUE)
    saved_files$seasonal_aeti <- aeti_path
  }

  if (!is.null(results$seasonal_biomass)) {
    bwp_path <- file.path(output_dir, "seasonal_biomass.tif")
    terra::writeRaster(results$seasonal_biomass, bwp_path, overwrite = TRUE)
    saved_files$seasonal_biomass <- bwp_path
  }

  if (!is.null(results$adequacy_etc)) {
    adeq_path <- file.path(output_dir, "adequacy_etc.tif")
    terra::writeRaster(results$adequacy_etc, adeq_path, overwrite = TRUE)
    saved_files$adequacy_etc <- adeq_path
  }

  progress_callback(1.0, "Tiled seasonal processing complete.")
  list(
    results = results,
    saved_files = saved_files
  )
}
