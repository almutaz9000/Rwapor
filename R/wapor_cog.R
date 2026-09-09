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

  drivers <- tryCatch(terra::gdal(drivers = TRUE)$name, error = function(e) character(0))
  use_cog <- length(drivers) && "COG" %in% drivers

  if (isTRUE(use_cog)) {
    terra::writeRaster(
      x,
      filename,
      overwrite = overwrite,
      filetype = "COG",
      gdal = c("COMPRESS=LZW", "OVERVIEWS=AUTO"),
      ...
    )
  } else {
    terra::writeRaster(
      x,
      filename,
      overwrite = overwrite,
      gdal = c("TILED=YES", "COMPRESS=LZW", "COPY_SRC_OVERVIEWS=YES"),
      ...
    )
  }
  invisible(filename)
}
