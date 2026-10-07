# Grid of small maps: one row per polygon unit, one column per raster layer
# (season, year, month, ...).

#' Plot selected polygon units over several raster layers
#'
#' Draws a grid of small maps with one row per polygon unit (for example a
#' farm) and one column per layer of `x` (for example one seasonal AETI map per
#' season). Every panel of a row shows the same unit at the same size: the
#' layer cropped to the unit's square extent plus `buffer`, with all polygon
#' outlines of the unit on top. All panels share one colour scale, computed
#' from all pixels of all layers of `x`, so colours can be compared between
#' units and between layers.
#'
#' `scale = "percentile_stretch"` keeps one continuous gradient but anchors its
#' colours at the `probs` quantiles of `x` instead of spreading them evenly
#' between the limits: the colour changes fastest where most pixels are, so
#' differences stand out more. The colour bar ticks are the anchor values.
#'
#' @param x SpatRaster (or raster file path) with one layer per column.
#' @param polygons sf object, SpatVector or vector file path. Reprojected to the
#'   CRS of `x`.
#' @param id_col Name of the column that groups polygons into units.
#' @param ids Units to draw, one row each, in this order. Defaults to all units
#'   (sorted).
#' @param row_labels Row titles, one per `ids`, unique. Defaults to `ids`.
#' @param col_labels Column titles, one per layer of `x`. Defaults to the layer
#'   names.
#' @param title Plot title.
#' @param legend_title Colour bar title. Defaults to `title`.
#' @param scale `"continuous"` gradient spread evenly between `limits`, or
#'   `"percentile_stretch"` gradient anchored at the `probs` quantiles.
#' @param limits Range of the continuous scale: `NULL` (2nd to 98th
#'   percentile, values outside are drawn in the end colours), `"full"`
#'   (minimum to maximum) or two numbers. Not used for `"percentile_stretch"`,
#'   whose range is the first to last quantile.
#' @param probs Quantiles used as colour anchors when
#'   `scale = "percentile_stretch"` (at least two, distinct values).
#' @param palette A [grDevices::hcl.pals()] palette name or a vector of colours.
#' @param reverse Reverse the palette direction.
#' @param line_width,line_colour Polygon outline width and colour.
#' @param buffer Margin around each unit, in metres. Converted to degrees
#'   (1 degree = 111,320 m) when `x` has a longitude/latitude CRS.
#' @param legend_size Colour bar length relative to the ggplot2 default. With a
#'   single row the colour bar is as tall as the panels.
#' @param out_file Optional PNG path to save the plot.
#' @param width,height,dpi Size (inches) and resolution of the saved plot.
#'   `height = NULL` sizes it from the number of rows and columns.
#' @return A ggplot object, invisibly when `out_file` is supplied.
#' @seealso [wapor_plot_polygon_grid()] for one panel per unit and one layer.
#' @examples
#' \dontrun{
#' seasons <- terra::rast(c("aeti_2018.tif", "aeti_2019.tif", "aeti_2020.tif"))
#' names(seasons) <- c("2018/2019", "2019/2020", "2020/2021")
#' wapor_plot_polygon_seasons(
#'   seasons, "parcels.gpkg", id_col = "farm", ids = c("F053", "F008", "F058"),
#'   row_labels = c("F053 above ETc", "F008 changes", "F058 below ETc"),
#'   title = "Seasonal AETI", legend_title = "Seasonal AETI\n(mm)",
#'   scale = "percentile_stretch", out_file = "sample_farms.png"
#' )
#' }
#' @export
wapor_plot_polygon_seasons <- function(x, polygons, id_col, ids = NULL, row_labels = NULL,
                                       col_labels = NULL, title = NULL, legend_title = NULL,
                                       scale = c("continuous", "percentile_stretch"),
                                       limits = NULL,
                                       probs = c(0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98),
                                       palette = "YlGnBu", reverse = TRUE,
                                       line_width = 0.4, line_colour = "black",
                                       buffer = 40, legend_size = 3,
                                       out_file = NULL, width = 14, height = NULL, dpi = 300) {
  .wapor_require_ggplot2()
  scale <- match.arg(scale)

  # Inputs ------------------------------------------------------------------
  if (is.character(x)) x <- terra::rast(x)
  if (!inherits(x, "SpatRaster")) stop("'x' must be a SpatRaster or a raster file path.", call. = FALSE)
  if (is.character(polygons)) polygons <- sf::st_read(polygons, quiet = TRUE)
  if (inherits(polygons, "SpatVector")) polygons <- sf::st_as_sf(polygons)
  if (!inherits(polygons, "sf")) stop("'polygons' must be sf, a SpatVector or a vector file path.", call. = FALSE)
  if (!is.character(id_col) || length(id_col) != 1) stop("'id_col' must be one column name.", call. = FALSE)
  if (!id_col %in% names(polygons)) stop(sprintf("Column '%s' not found in 'polygons'.", id_col), call. = FALSE)
  if (!is.null(limits) && !identical(limits, "full") && !(is.numeric(limits) && length(limits) == 2)) {
    stop("'limits' must be NULL, \"full\" or two numbers.", call. = FALSE)
  }
  if (scale == "percentile_stretch" && (length(probs) < 2 || any(probs < 0 | probs > 1))) {
    stop("'probs' must be at least two values between 0 and 1.", call. = FALSE)
  }

  polygons <- polygons[!is.na(polygons[[id_col]]), ]
  polygons <- sf::st_transform(polygons, terra::crs(x))
  polygons$.unit <- as.character(polygons[[id_col]])
  ids <- if (is.null(ids)) sort(unique(polygons$.unit)) else as.character(ids)
  unknown <- setdiff(ids, polygons$.unit)
  if (length(unknown)) stop(sprintf("Unknown unit(s) in 'ids': %s.", paste(unknown, collapse = ", ")), call. = FALSE)
  if (anyDuplicated(ids)) stop("'ids' must not repeat a unit.", call. = FALSE)
  row_labels <- if (is.null(row_labels)) ids else as.character(row_labels)
  if (length(row_labels) != length(ids) || anyDuplicated(row_labels)) {
    stop("'row_labels' must give one unique label per unit in 'ids'.", call. = FALSE)
  }
  n_cols <- terra::nlyr(x)
  col_labels <- if (is.null(col_labels)) names(x) else as.character(col_labels)
  if (length(col_labels) != n_cols || anyDuplicated(col_labels)) {
    stop(sprintf("'col_labels' must give one unique label per layer of 'x' (%d).", n_cols), call. = FALSE)
  }
  legend_title <- legend_title %||% title
  if (terra::is.lonlat(x)) buffer <- buffer / 111320
  res <- terra::res(x)

  # Pixels and outlines of each unit on a 0-1 frame (its square extent), so
  # every panel of a row shows the unit at the same size -------------------
  frame <- lapply(seq_along(ids), function(k) {
    geom <- polygons[polygons$.unit == ids[k], ]
    bb <- sf::st_bbox(geom)
    half <- max(bb["xmax"] - bb["xmin"], bb["ymax"] - bb["ymin"]) / 2 + buffer
    x0 <- unname((bb["xmin"] + bb["xmax"]) / 2 - half)
    y0 <- unname((bb["ymin"] + bb["ymax"]) / 2 - half)
    size <- 2 * half
    # A unit outside the raster keeps its row, with outlines only.
    r <- tryCatch(terra::crop(x, terra::ext(x0, x0 + size, y0, y0 + size), snap = "out"),
                  error = function(err) NULL)
    d <- if (is.null(r)) data.frame() else terra::as.data.frame(r, xy = TRUE, na.rm = FALSE)
    px <- if (nrow(d)) {
      data.frame(.row = row_labels[k], .col = rep(col_labels, each = nrow(d)),
                 x = (d$x - x0) / size, y = (d$y - y0) / size,
                 w = res[1] / size, h = res[2] / size,
                 value = unlist(d[, 2 + seq_len(n_cols)], use.names = FALSE))
    } else NULL
    polys <- suppressWarnings(sf::st_cast(sf::st_cast(geom, "MULTIPOLYGON"), "POLYGON"))
    xy <- as.data.frame(sf::st_coordinates(polys))
    list(pixels = if (is.null(px)) NULL else px[is.finite(px$value), , drop = FALSE],
         outline = data.frame(.row = row_labels[k], ring = paste(xy$L2, xy$L1),
                              x = (xy$X - x0) / size, y = (xy$Y - y0) / size))
  })
  px <- do.call(rbind, lapply(frame, `[[`, "pixels"))
  if (is.null(px)) px <- data.frame(.row = character(0), .col = character(0), x = numeric(0), y = numeric(0),
                                    w = numeric(0), h = numeric(0), value = numeric(0))
  ol <- do.call(rbind, lapply(frame, `[[`, "outline"))
  px$.row <- factor(px$.row, levels = row_labels)
  px$.col <- factor(px$.col, levels = col_labels)
  ol$.row <- factor(ol$.row, levels = row_labels)

  # Colour scale from all pixels of all layers ------------------------------
  colours_n <- function(n) {
    if (length(palette) == 1 && palette %in% grDevices::hcl.pals()) {
      return(grDevices::hcl.colors(n, palette, rev = reverse))
    }
    cols <- grDevices::colorRampPalette(palette)(n)
    if (reverse) rev(cols) else cols
  }
  squish <- function(v, range = c(0, 1), ...) pmin(pmax(v, range[1]), range[2])
  fmt <- function(v) format(signif(v, 3), trim = TRUE, big.mark = ",")
  v <- if (terra::ncell(x) * n_cols > 5e6) {
    as.vector(as.matrix(terra::spatSample(x, ceiling(1e6 / n_cols), "regular", na.rm = FALSE)))
  } else {
    as.vector(terra::values(x))
  }
  v <- v[is.finite(v)]
  if (!length(v)) v <- 0

  fill_scale <- if (scale == "continuous") {
    lim <- if (is.null(limits)) unname(stats::quantile(v, c(0.02, 0.98)))
           else if (identical(limits, "full")) range(v) else sort(limits)
    if (diff(lim) == 0) lim <- lim + c(-0.5, 0.5)
    ggplot2::scale_fill_gradientn(colours = colours_n(9), limits = lim, oob = squish,
                                  name = legend_title, na.value = "transparent")
  } else {
    anchors <- unname(stats::quantile(v, sort(probs)))
    if (anyDuplicated(anchors)) {
      stop("The 'probs' quantiles of 'x' are not distinct; use fewer or wider 'probs'.", call. = FALSE)
    }
    ggplot2::scale_fill_gradientn(colours = colours_n(length(anchors)),
                                  values = (anchors - anchors[1]) / diff(range(anchors)),
                                  limits = range(anchors), oob = squish,
                                  breaks = anchors, labels = fmt,
                                  name = legend_title, na.value = "transparent")
  }

  # Plot --------------------------------------------------------------------
  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(data = px, ggplot2::aes(.data$x, .data$y, fill = .data$value,
                                               width = .data$w, height = .data$h)) +
    ggplot2::geom_path(data = ol, ggplot2::aes(.data$x, .data$y, group = .data$ring),
                       colour = line_colour, linewidth = line_width) +
    ggplot2::facet_grid(.row ~ .col, switch = "y", drop = FALSE) +
    fill_scale +
    ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(aspect.ratio = 1, axis.text = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank(),
                   panel.border = ggplot2::element_rect(colour = "grey70", fill = NA),
                   strip.text.x = ggplot2::element_text(size = 8),
                   strip.text.y.left = ggplot2::element_text(size = 8, angle = 0, hjust = 1),
                   strip.placement = "outside",
                   legend.key.height = .wapor_colourbar_key_height(FALSE, legend_size, TRUE, length(ids)),
                   legend.key.width = ggplot2::unit(1.2, "lines"))

  if (!is.null(out_file)) {
    if (is.null(height)) height <- 1 + length(ids) * min(1.6, (width - 3.5) / n_cols)
    dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
    ggplot2::ggsave(out_file, p, width = width, height = height, dpi = dpi, bg = "white")
    return(invisible(p))
  }
  p
}
