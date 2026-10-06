# Raster mask construction and harmonization helpers.

#' Rasterize polygon masks on a template grid.
#' @param polygons sf, SpatVector, or vector file path.
#' @param template Template terra SpatRaster.
#' @param field Optional polygon attribute to rasterize.
#' @param value Constant value when `field` is NULL.
#' @param touches Include cells touched by polygons.
#' @param fraction Return covered fractions instead of a binary raster.
#' @return A SpatRaster named `crop_mask`; fraction rasters carry `area_ratio`.
#' @export
wapor_rasterize_mask <- function(polygons, template, field = NULL, value = 1L, touches = FALSE, fraction = FALSE) {
  if (!inherits(template, "SpatRaster")) stop("template must be a terra SpatRaster", call. = FALSE)
  p <- if (is.character(polygons) && length(polygons) == 1L) sf::st_read(polygons, quiet = TRUE) else polygons
  if (inherits(p, "SpatVector")) p <- sf::st_as_sf(p)
  if (!inherits(p, "sf")) stop("polygons must be sf, SpatVector, or a vector file path", call. = FALSE)
  p <- sf::st_make_valid(p)
  p <- sf::st_transform(p, terra::crs(template))
  if (!is.null(field) && !field %in% names(p)) stop(sprintf("field '%s' is not present in polygons", field), call. = FALSE)
  if (fraction) {
    fr <- exactextractr::coverage_fraction(template, p)
    out <- if (length(fr) == 1L) fr[[1L]] else terra::app(terra::rast(fr), max, na.rm = TRUE)
    names(out) <- "crop_mask"
    poly_area <- as.numeric(sf::st_area(sf::st_union(p)))
    raster_area <- sum(terra::values(out)[,1] * terra::values(terra::cellSize(template, unit="m"))[,1], na.rm=TRUE)
    ratio <- if (poly_area > 0) raster_area/poly_area else NA_real_
    attr(out, "area_ratio") <- ratio
    if (is.finite(ratio) && ratio < .9 || is.finite(ratio) && ratio > 1.1) {
      cells <- poly_area / stats::median(terra::values(terra::cellSize(template, unit="m"))[,1], na.rm=TRUE)
      if (cells >= 25) warning("rasterized mask area differs from polygon area by more than 10%", call. = FALSE)
    }
    return(out)
  }
  out <- terra::rasterize(terra::vect(p), template, field = if (is.null(field)) value else field, touches = touches, background = NA)
  names(out) <- "crop_mask"
  out
}

#' Harmonize a categorical crop map to a template grid.
#' @param crop_map Categorical SpatRaster.
#' @param template Template SpatRaster.
#' @param class Class value or values to retain.
#' @param min_fraction Majority fraction threshold.
#' @param value Value for retained mask cells.
#' @param return_fraction Return fraction rasters as well as the binary mask.
#' @return A mask raster, or `list(mask, fraction)`.
#' @export
wapor_harmonize_mask <- function(crop_map, template, class, min_fraction = .5, value = NULL, return_fraction = TRUE) {
  if (!inherits(crop_map, "SpatRaster") || !inherits(template, "SpatRaster")) stop("crop_map and template must be terra SpatRaster objects", call. = FALSE)
  if (!is.numeric(min_fraction) || length(min_fraction) != 1L || min_fraction < 0 || min_fraction > 1) stop("min_fraction must be between 0 and 1", call. = FALSE)
  cls <- as.numeric(class); if (!length(cls) || any(!is.finite(cls))) stop("class must contain finite numeric class values", call. = FALSE)
  fr <- lapply(cls, function(k) {
    binary <- terra::ifel(crop_map == k, 1, 0)
    same_grid <- identical(terra::crs(crop_map), terra::crs(template))
    if (same_grid) terra::resample(binary, template, method = "average") else terra::project(binary, template, method = "average")
  })
  if (length(fr) == 1L) {
    frac <- fr[[1L]]; mask <- terra::ifel(frac >= min_fraction, if (is.null(value)) 1L else value, NA)
  } else {
    stack <- terra::rast(fr); mx <- terra::app(stack, max, na.rm = TRUE); win <- terra::which.max(stack); frac <- mx; mask <- terra::ifel(mx >= min_fraction, if (is.null(value)) 1L else value, NA); names(frac) <- "fraction"
    # Keep only the requested class's winning cells; ties go to the first class.
    mask <- terra::ifel(win >= 1 & mx >= min_fraction, if (is.null(value)) 1L else value, NA)
  }
  names(mask) <- "crop_mask"; names(frac) <- "fraction"
  if (return_fraction) list(mask = mask, fraction = frac) else mask
}
