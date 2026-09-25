# Grid of small maps, one panel per polygon unit (farm, scheme, block, ...).

# `.data` is the ggplot2/rlang pronoun used inside aes().
utils::globalVariables(".data")

# Legend key height of the grid plots. ggplot2 (>= 3.5) draws a colour bar
# 5 times legend.key.height long, so 1.2 * legend_size lines gives
# legend_size times the default bar. One row of panels (or a panel with its
# own scale) gets a "null" unit instead: the bar stretches to the panel height
# and is never taller than the plot. Class legends keep one key per class.
.wapor_colourbar_key_height <- function(discrete, legend_size, shared = TRUE, n_rows = 2) {
  if (discrete) return(ggplot2::unit(0.8 * legend_size / if (shared) 1 else 3, "lines"))
  if (!shared || n_rows <= 1) return(ggplot2::unit(1, "null"))
  ggplot2::unit(1.2 * legend_size, "lines")
}

#' Plot a raster as a grid of small maps, one per polygon unit
#'
#' Groups `polygons` into units by `id_col` (for example parcels grouped by
#' farm) and draws one panel per unit: the raster cropped to the unit's extent
#' plus `buffer`, with every polygon outline of the unit drawn on top. Panels
#' are laid out `per_page` to a page, and each page can be saved as a PNG.
#'
#' The shared colour scale (and the percentile classes) are computed from all
#' pixels of `x`, not only the pixels inside the panels, so the panels use the
#' same colours as a map of the whole raster. Crop `x` first to limit the scale
#' to an area of interest.
#'
#' @param x SpatRaster or raster file path. Only the first layer is drawn.
#' @param polygons sf object, SpatVector or vector file path. Reprojected to the
#'   CRS of `x`.
#' @param id_col Name of the column that groups polygons into units; one panel
#'   per unique value. Polygons with a missing id are dropped with a warning.
#' @param label_col Optional column whose first value per unit is added to the
#'   panel title (for example the crop type).
#' @param per_page,ncol Panels per page and per row.
#' @param title Page title. Defaults to the layer name of `x`. With several
#'   pages, "(page i of n)" is appended.
#' @param legend_title Colour bar title. Defaults to `title`.
#' @param common_scale `TRUE` (default): one colour scale shared by all panels.
#'   `FALSE`: every panel has its own scale (needs the patchwork package).
#' @param scale `"continuous"` gradient, `"percentile"` classes at the `probs`
#'   quantiles of `x`, or `"breaks"` classes at your `breaks`.
#' @param limits Range of the continuous scale: `NULL` (2nd to 98th
#'   percentile, values outside are drawn in the end colours), `"full"`
#'   (minimum to maximum) or two numbers.
#' @param probs Quantiles used as class limits when `scale = "percentile"`.
#' @param breaks Class limits when `scale = "breaks"` (at least two).
#' @param palette A [grDevices::hcl.pals()] palette name or a vector of colours.
#' @param reverse Reverse the palette direction.
#' @param line_width,line_colour Polygon outline width and colour.
#' @param buffer Margin around each unit, in metres. Converted to degrees
#'   (1 degree = 111,320 m) when `x` has a longitude/latitude CRS.
#' @param square `TRUE` (default): square panels centred on the unit.
#'   `FALSE`: each panel keeps the shape of its unit (needs patchwork).
#' @param mask_outside Hide pixels outside the unit's polygons.
#' @param legend_size Colour bar length relative to the ggplot2 default
#'   (3 = three times longer, about the height of an 8-class legend). A single
#'   row of panels, and every panel with its own scale, gets a colour bar as
#'   tall as its panels instead, so the bar is never taller than the plot.
#' @param out_dir Optional folder. Every page is saved as
#'   `<prefix>_page<i>.png`.
#' @param prefix File name prefix for saved pages.
#' @param width,height,dpi Size (inches) and resolution of saved pages.
#' @return A named list of ggplot (or patchwork) objects, one per page
#'   (`page_1`, `page_2`, ...), invisibly when `out_dir` is supplied.
#' @examples
#' \dontrun{
#' pages <- wapor_plot_polygon_grid(
#'   "seasonal_aeti.tif", "parcels.gpkg", id_col = "farm",
#'   label_col = "crop", title = "Seasonal AETI", legend_title = "AETI (mm)",
#'   out_dir = "figures", prefix = "aeti_farms"
#' )
#' pages$page_1
#'
#' # Adequacy in fixed classes, own colours
#' wapor_plot_polygon_grid(
#'   adequacy, parcels, id_col = "farm", scale = "breaks",
#'   breaks = c(0.68, 0.8, 1, 1.2),
#'   palette = c("#d73027", "#fc8d59", "#fee08b", "#91bfdb", "#4575b4"),
#'   reverse = FALSE
#' )
#' }
#' @export
wapor_plot_polygon_grid <- function(x, polygons, id_col, label_col = NULL,
                                    per_page = 24, ncol = 6, title = NULL, legend_title = NULL,
                                    common_scale = TRUE,
                                    scale = c("continuous", "percentile", "breaks"),
                                    limits = NULL,
                                    probs = c(0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98),
                                    breaks = NULL,
                                    palette = "YlGnBu", reverse = TRUE,
                                    line_width = 0.4, line_colour = "black",
                                    buffer = 40, square = TRUE, mask_outside = FALSE,
                                    legend_size = 3,
                                    out_dir = NULL, prefix = "polygon_grid",
                                    width = 12, height = 9.5, dpi = 300) {
  .wapor_require_ggplot2()
  scale <- match.arg(scale)

  # Inputs ------------------------------------------------------------------
  if (is.character(x)) x <- terra::rast(x)
  if (!inherits(x, "SpatRaster")) stop("'x' must be a SpatRaster or a raster file path.", call. = FALSE)
  if (terra::nlyr(x) > 1) {
    warning(sprintf("'x' has %d layers; only the first ('%s') is drawn.", terra::nlyr(x), names(x)[1]),
            call. = FALSE)
  }
  x <- x[[1]]
  if (is.character(polygons)) polygons <- sf::st_read(polygons, quiet = TRUE)
  if (inherits(polygons, "SpatVector")) polygons <- sf::st_as_sf(polygons)
  if (!inherits(polygons, "sf")) stop("'polygons' must be sf, a SpatVector or a vector file path.", call. = FALSE)
  if (!is.character(id_col) || length(id_col) != 1) stop("'id_col' must be one column name.", call. = FALSE)
  for (col in c(id_col, label_col)) {
    if (!col %in% names(polygons)) stop(sprintf("Column '%s' not found in 'polygons'.", col), call. = FALSE)
  }
  is_count <- function(v) is.numeric(v) && length(v) == 1 && is.finite(v) && v >= 1
  if (!is_count(per_page) || !is_count(ncol)) stop("'per_page' and 'ncol' must be positive numbers.", call. = FALSE)
  if (scale == "breaks" && length(breaks) < 2) stop("scale = 'breaks' needs at least two 'breaks'.", call. = FALSE)
  if (scale == "percentile" && (length(probs) < 2 || any(probs < 0 | probs > 1))) {
    stop("'probs' must be at least two values between 0 and 1.", call. = FALSE)
  }
  if (!is.null(limits) && !identical(limits, "full") && !(is.numeric(limits) && length(limits) == 2)) {
    stop("'limits' must be NULL, \"full\" or two numbers.", call. = FALSE)
  }
  use_patchwork <- !common_scale || !square
  if (use_patchwork && !requireNamespace("patchwork", quietly = TRUE)) {
    stop("common_scale = FALSE and square = FALSE need the 'patchwork' package: install.packages(\"patchwork\")",
         call. = FALSE)
  }

  missing_id <- is.na(polygons[[id_col]])
  if (all(missing_id)) stop(sprintf("Column '%s' has no non-missing values.", id_col), call. = FALSE)
  if (any(missing_id)) {
    warning(sprintf("%d polygon(s) with a missing '%s' dropped.", sum(missing_id), id_col), call. = FALSE)
    polygons <- polygons[!missing_id, ]
  }
  polygons <- sf::st_transform(polygons, terra::crs(x))
  polygons$.unit <- as.character(polygons[[id_col]])
  ids <- sort(unique(polygons$.unit))
  labels <- if (is.null(label_col)) ids else vapply(ids, function(i)
    paste(i, polygons[[label_col]][polygons$.unit == i][1]), character(1))
  names(labels) <- ids
  title <- title %||% names(x)
  legend_title <- legend_title %||% title
  res <- terra::res(x)
  if (terra::is.lonlat(x)) buffer <- buffer / 111320

  # Colours and scales ------------------------------------------------------
  colours_n <- function(n) {
    if (length(palette) == 1 && palette %in% grDevices::hcl.pals()) {
      return(grDevices::hcl.colors(n, palette, rev = reverse))
    }
    cols <- grDevices::colorRampPalette(palette)(n)
    if (reverse) rev(cols) else cols
  }
  squish <- function(v, range = c(0, 1), ...) pmin(pmax(v, range[1]), range[2])
  fmt <- function(v) format(signif(v, 3), trim = TRUE, big.mark = ",")

  # Build the fill scale from a set of values. Returns the ggplot scale and a
  # function giving the fill value of each pixel (numeric, or a class factor).
  make_fill <- function(v) {
    v <- v[is.finite(v)]
    if (!length(v)) v <- 0
    if (scale == "continuous") {
      lim <- if (is.null(limits)) unname(stats::quantile(v, c(0.02, 0.98)))
             else if (identical(limits, "full")) range(v) else sort(limits)
      if (diff(lim) == 0) lim <- lim + c(-0.5, 0.5)
      return(list(discrete = FALSE, fill = function(value) value,
                  scale = ggplot2::scale_fill_gradientn(colours = colours_n(9), limits = lim, oob = squish,
                                                        name = legend_title, na.value = "transparent")))
    }
    br <- if (scale == "percentile") unique(unname(stats::quantile(v, probs))) else sort(unique(breaks))
    cuts <- c(if (min(v) < br[1]) -Inf, br, if (max(v) > br[length(br)]) Inf)
    if (length(cuts) < 2) cuts <- c(-Inf, br, Inf)
    lo <- utils::head(cuts, -1)
    hi <- cuts[-1]
    lev <- ifelse(is.infinite(lo), paste("<", fmt(hi)),
                  ifelse(is.infinite(hi), paste(">", fmt(lo)), paste(fmt(lo), "to", fmt(hi))))
    list(discrete = TRUE,
         fill = function(value) factor(lev[findInterval(value, cuts, rightmost.closed = TRUE, all.inside = TRUE)],
                                       levels = lev),
         scale = ggplot2::scale_fill_manual(values = stats::setNames(colours_n(length(lev)), lev), limits = lev,
                                            drop = FALSE, name = legend_title,
                                            guide = ggplot2::guide_legend(reverse = TRUE)))
  }
  all_values <- function(r) {
    if (terra::ncell(r) > 5e6) terra::spatSample(r, 1e6, "regular", na.rm = TRUE)[, 1]
    else terra::values(r, na.rm = TRUE)[, 1]
  }
  legend_theme <- function(fill, shared, n_rows = 2) {
    ggplot2::theme(legend.key.height = .wapor_colourbar_key_height(fill$discrete, legend_size, shared, n_rows),
                   legend.key.width = ggplot2::unit(if (shared) 1.2 else 0.8, "lines"))
  }

  # One unit: extent, pixels and outlines -----------------------------------
  units <- lapply(ids, function(i) {
    geom <- polygons[polygons$.unit == i, ]
    bb <- sf::st_bbox(geom)
    e <- unname(c(bb["xmin"] - buffer, bb["xmax"] + buffer, bb["ymin"] - buffer, bb["ymax"] + buffer))
    if (square) {
      half <- max(e[2] - e[1], e[4] - e[3]) / 2
      e <- c(mean(e[1:2]) - half, mean(e[1:2]) + half, mean(e[3:4]) - half, mean(e[3:4]) + half)
    }
    # A unit outside the raster gets an empty panel (outline only).
    r <- tryCatch(terra::crop(x, terra::ext(e), snap = "out"), error = function(err) NULL)
    if (!is.null(r) && mask_outside) r <- terra::mask(r, terra::vect(geom))
    px <- if (is.null(r)) data.frame() else terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)
    px <- if (nrow(px)) stats::setNames(px[, 1:3], c("x", "y", "value"))
          else data.frame(x = numeric(0), y = numeric(0), value = numeric(0))
    polys <- suppressWarnings(sf::st_cast(sf::st_cast(geom, "MULTIPOLYGON"), "POLYGON"))
    xy <- as.data.frame(sf::st_coordinates(polys))
    list(id = i, extent = e, pixels = px,
         outline = data.frame(x = xy$X, y = xy$Y, ring = paste(xy$L2, xy$L1)))
  })
  names(units) <- ids

  shared_fill <- if (common_scale) make_fill(all_values(x)) else NULL

  base_theme <- ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(axis.text = ggplot2::element_blank(), axis.title = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank(),
                   panel.border = ggplot2::element_rect(colour = "grey70", fill = NA))

  # Facet page: common scale and square panels, no extra package needed
  facet_page <- function(page_ids, page_title) {
    tag <- function(d, i) if (nrow(d)) cbind(d, .panel = labels[[i]]) else NULL
    px <- do.call(rbind, lapply(page_ids, function(i) tag(units[[i]]$pixels, i)))
    if (is.null(px)) px <- data.frame(x = numeric(0), y = numeric(0), value = numeric(0), .panel = character(0))
    px$fill <- shared_fill$fill(px$value)
    ol <- do.call(rbind, lapply(page_ids, function(i) tag(units[[i]]$outline, i)))
    corners <- do.call(rbind, lapply(page_ids, function(i)
      data.frame(x = units[[i]]$extent[1:2], y = units[[i]]$extent[3:4], .panel = labels[[i]])))
    lv <- unname(labels[page_ids])
    px$.panel <- factor(px$.panel, levels = lv)
    ol$.panel <- factor(ol$.panel, levels = lv)
    corners$.panel <- factor(corners$.panel, levels = lv)

    ggplot2::ggplot() +
      ggplot2::geom_blank(data = corners, ggplot2::aes(.data$x, .data$y)) +
      ggplot2::geom_tile(data = px, ggplot2::aes(.data$x, .data$y, fill = .data$fill),
                         width = res[1], height = res[2]) +
      ggplot2::geom_path(data = ol, ggplot2::aes(.data$x, .data$y, group = .data$ring),
                         colour = line_colour, linewidth = line_width) +
      ggplot2::facet_wrap(~.panel, ncol = ncol, scales = "free", drop = FALSE) +
      shared_fill$scale +
      ggplot2::scale_x_continuous(expand = c(0, 0)) +
      ggplot2::scale_y_continuous(expand = c(0, 0)) +
      ggplot2::labs(title = page_title) +
      base_theme +
      ggplot2::theme(aspect.ratio = 1, strip.text = ggplot2::element_text(size = 7)) +
      legend_theme(shared_fill, shared = TRUE, n_rows = ceiling(length(page_ids) / ncol))
  }

  # Patchwork page: one plot per unit (own scale, or panels with true shape)
  unit_plot <- function(u) {
    fill <- shared_fill %||% make_fill(u$pixels$value)
    u$pixels$fill <- fill$fill(u$pixels$value)
    ggplot2::ggplot() +
      ggplot2::geom_tile(data = u$pixels, ggplot2::aes(.data$x, .data$y, fill = .data$fill),
                         width = res[1], height = res[2]) +
      ggplot2::geom_path(data = u$outline, ggplot2::aes(.data$x, .data$y, group = .data$ring),
                         colour = line_colour, linewidth = line_width) +
      fill$scale +
      ggplot2::coord_equal(xlim = u$extent[1:2], ylim = u$extent[3:4], expand = FALSE) +
      ggplot2::labs(title = labels[[u$id]]) +
      base_theme +
      ggplot2::theme(plot.title = ggplot2::element_text(size = 7, hjust = 0.5)) +
      (if (common_scale) legend_theme(fill, shared = TRUE) else
         legend_theme(fill, shared = FALSE) +
           ggplot2::theme(legend.title = ggplot2::element_blank(),
                          legend.text = ggplot2::element_text(size = 6)))
  }
  patch_page <- function(page_ids, page_title) {
    patchwork::wrap_plots(lapply(units[page_ids], unit_plot), ncol = ncol) +
      patchwork::plot_layout(guides = if (common_scale) "collect" else "keep") +
      patchwork::plot_annotation(title = page_title)
  }

  # Pages -------------------------------------------------------------------
  pages_ids <- split(ids, ceiling(seq_along(ids) / per_page))
  n_pages <- length(pages_ids)
  pages <- lapply(seq_len(n_pages), function(k) {
    page_title <- if (n_pages > 1) sprintf("%s (page %d of %d)", title, k, n_pages) else title
    if (use_patchwork) patch_page(pages_ids[[k]], page_title) else facet_page(pages_ids[[k]], page_title)
  })
  names(pages) <- paste0("page_", seq_len(n_pages))

  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    for (k in seq_len(n_pages)) {
      ggplot2::ggsave(file.path(out_dir, sprintf("%s_page%d.png", prefix, k)), pages[[k]],
                      width = width, height = height, dpi = dpi, bg = "white")
    }
    return(invisible(pages))
  }
  pages
}
