# Raster mask construction and harmonization helpers.

#' Rasterize Polygons to a Mask on a Template Grid
#'
#' Turns polygons (for example crop fields) into a mask on the grid of a WaPOR
#' raster. The polygons are reprojected to the template's CRS first: rasterizing
#' lon/lat polygons directly on a UTM grid (WaPOR Level 3) gives an empty mask.
#'
#' @param polygons `sf`, `SpatVector`, or a vector file path.
#' @param template `SpatRaster` whose grid the mask gets.
#' @param field Optional polygon attribute to write into the mask instead of `value`.
#' @param value Value of mask cells when `field` is `NULL`. Default `1`.
#' @param touches Logical. Include every cell a polygon touches, not only cells
#'   whose centre is inside. Ignored with `fraction = TRUE`.
#' @param fraction Logical. Return the fraction of each cell covered by the
#'   polygons (0 to 1; overlapping or adjacent polygons are merged first)
#'   instead of a binary mask. Use it as `weights` in [wapor_zonal_stats()],
#'   especially at 100 m and 300 m, where most cells along field borders are mixed.
#'
#' @return A `SpatRaster` named `crop_mask` (cells outside are `NA` for a binary
#'   mask, `0` for a fraction). Attribute `"area_ratio"` is the mask area
#'   divided by the polygon area.
#'
#' @details
#' Area check: a warning is given when the mask area differs from the polygon
#' area by more than 10% and the polygons cover at least 25 cells. For smaller
#' polygons a centre-based mask is too coarse for the check to mean anything;
#' use `fraction = TRUE` there.
#'
#' @seealso [wapor_harmonize_mask()], [wapor_zonal_stats()].
#' @export
#' @examples
#' template <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200,
#'                         ymin = 3600000, ymax = 3600200, crs = "EPSG:32636")
#' field <- sf::st_sf(id = 1, geometry = sf::st_as_sfc(sf::st_bbox(
#'   c(xmin = 700030, ymin = 3600030, xmax = 700130, ymax = 3600130), crs = 32636)))
#' m <- wapor_rasterize_mask(field, template, fraction = TRUE)
#' attr(m, "area_ratio")
wapor_rasterize_mask <- function(polygons, template, field = NULL, value = 1L, touches = FALSE, fraction = FALSE) {
  if (!inherits(template, "SpatRaster")) stop("template must be a terra SpatRaster", call. = FALSE)
  p <- if (is.character(polygons) && length(polygons) == 1L) sf::st_read(polygons, quiet = TRUE) else polygons
  if (inherits(p, "SpatVector")) p <- sf::st_as_sf(p)
  if (!inherits(p, "sf")) stop("polygons must be sf, SpatVector, or a vector file path", call. = FALSE)
  p <- sf::st_make_valid(p)
  p <- sf::st_transform(p, terra::crs(template))
  if (!is.null(field) && !field %in% names(p)) stop(sprintf("field '%s' is not present in polygons", field), call. = FALSE)
  template <- template[[1]]
  merged <- sf::st_sf(geometry = sf::st_union(sf::st_geometry(p)))
  # Planar cell areas on a projected grid, as the polygon area is planar there too; on a
  # lon/lat grid both are ellipsoidal.
  cell_area <- terra::cellSize(template, unit = "m", transform = FALSE)
  if (isTRUE(fraction)) {
    # One pass over the merged polygons: cells shared by adjacent polygons add up.
    out <- exactextractr::coverage_fraction(template, merged)[[1L]]
    raster_area <- terra::global(out * cell_area, "sum", na.rm = TRUE)[1, 1]
  } else {
    out <- terra::rasterize(terra::vect(p), template, field = if (is.null(field)) value else field, touches = touches, background = NA)
    raster_area <- terra::global(terra::ifel(is.na(out), 0, 1) * cell_area, "sum", na.rm = TRUE)[1, 1]
  }
  names(out) <- "crop_mask"
  poly_area <- .wapor_zone_area_ha(merged, isTRUE(terra::is.lonlat(template))) * 1e4
  ratio <- if (is.finite(poly_area) && poly_area > 0) raster_area / poly_area else NA_real_
  attr(out, "area_ratio") <- ratio
  if (is.finite(ratio) && (ratio < .9 || ratio > 1.1)) {
    cells <- poly_area / terra::global(cell_area, "mean", na.rm = TRUE)[1, 1]
    if (cells >= 25) warning(sprintf("rasterized mask area is %.0f%% of the polygon area", 100 * ratio), call. = FALSE)
  }
  out
}

#' Bring a Classified Map onto a Template Grid as a Mask and a Fraction
#'
#' For a crop or land cover map at any resolution, gives the fraction of each
#' template cell that belongs to the requested class or classes, and a mask of
#' the cells where that fraction reaches `min_fraction`.
#'
#' @param crop_map Classified `SpatRaster` (class codes).
#' @param template `SpatRaster` whose grid the result gets.
#' @param class Class code or codes to keep.
#' @param min_fraction Smallest fraction of a template cell that must belong to
#'   the class for the cell to enter the mask. Default `0.5`, a majority rule
#'   (a heuristic, not a published threshold; choose it for your map).
#' @param value Value of mask cells. Default `NULL`: `1` for one class, the code
#'   of the winning class for several.
#' @param return_fraction Logical. Return the fraction as well. Default `TRUE`.
#'
#' @return With `return_fraction = TRUE` a list with `mask` (layer `crop_mask`,
#'   `NA` outside) and `fraction` (layer `fraction`, 0 to 1); otherwise the mask.
#'
#' @details
#' Each class is turned into a 0/1 raster (cells of another class and cells
#' without data are 0) and averaged onto the template grid. With several
#' classes the class with the largest fraction wins the cell, ties go to the
#' first class given, and `fraction` holds the winner's fraction.
#'
#' The fraction is the recommended `weights` input of [wapor_zonal_stats()] at
#' Level 1 and Level 2.
#'
#' @seealso [wapor_rasterize_mask()], [wapor_zonal_stats()].
#' @export
#' @examples
#' map <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
#'                    crs = "EPSG:32636", vals = c(1, 1, 1, 2))
#' cell <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
#'                     crs = "EPSG:32636")
#' terra::values(wapor_harmonize_mask(map, cell, class = 1)$fraction)
wapor_harmonize_mask <- function(crop_map, template, class, min_fraction = .5, value = NULL, return_fraction = TRUE) {
  if (!inherits(crop_map, "SpatRaster") || !inherits(template, "SpatRaster")) stop("crop_map and template must be terra SpatRaster objects", call. = FALSE)
  if (!is.numeric(min_fraction) || length(min_fraction) != 1L || min_fraction < 0 || min_fraction > 1) stop("min_fraction must be between 0 and 1", call. = FALSE)
  cls <- as.numeric(class); if (!length(cls) || any(!is.finite(cls))) stop("class must contain finite numeric class values", call. = FALSE)
  crop_map <- crop_map[[1]]
  same_crs <- identical(terra::crs(crop_map), terra::crs(template))
  fr <- lapply(cls, function(k) {
    binary <- terra::ifel(!is.na(crop_map) & crop_map == k, 1, 0)   # no data counts as "not this class"
    if (same_crs) terra::resample(binary, template, method = "average") else terra::project(binary, template, method = "average")
  })
  if (length(fr) == 1L) {
    frac <- fr[[1L]]
    mask <- terra::ifel(frac >= min_fraction, if (is.null(value)) 1L else value, NA)
  } else {
    stack <- terra::rast(fr)
    frac <- terra::app(stack, max, na.rm = TRUE)
    winner <- terra::which.max(stack)                               # ties go to the first class
    win_value <- if (is.null(value)) terra::subst(winner, seq_along(cls), cls) else winner * 0 + value
    mask <- terra::ifel(frac >= min_fraction, win_value, NA)
  }
  names(mask) <- "crop_mask"; names(frac) <- "fraction"
  if (return_fraction) list(mask = mask, fraction = frac) else mask
}
