# Publication-ready visualization helpers.
utils::globalVariables(".data")

.wapor_require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for publication plots.", call. = FALSE)
  }
}

#' Aggregate a large SpatRaster to a bounded plotting grid
#' @keywords internal
#' @noRd
.wapor_plot_aggregate <- function(x, max_cells, aggregate_fun) {
  if (length(max_cells) != 1L || is.na(max_cells) || !is.finite(max_cells) || max_cells < 1) {
    stop("'max_cells' must be NULL or one finite positive number", call. = FALSE)
  }
  n <- terra::ncell(x)
  if (n <= max_cells) return(x)

  is_categorical <- any(terra::is.factor(x))
  if (is_categorical && is.null(aggregate_fun)) {
    stop("Large categorical rasters require an explicit 'aggregate_fun' (for example, 'modal').", call. = FALSE)
  }
  factor <- max(1L, as.integer(ceiling(sqrt(n / max_cells))))
  while (ceiling(terra::nrow(x) / factor) * ceiling(terra::ncol(x) / factor) > max_cells) {
    factor <- factor + 1L
  }
  fun <- aggregate_fun %||% "mean"
  terra::aggregate(x, fact = factor, fun = fun, na.rm = TRUE)
}

#' Select an indicator-aware fill scale
#' @keywords internal
#' @noRd
.wapor_plot_fill_scale <- function(indicator, limits = NULL) {
  key <- tolower(gsub("[^a-z0-9]+", "_", indicator))
  if (grepl("adequacy", key)) {
    return(ggplot2::scale_fill_gradient2(
      low = "#d73027", mid = "#f7f7f7", high = "#1a9850",
      midpoint = 1, limits = limits, na.value = "transparent"
    ))
  }
  if (grepl("anomaly|z_score|zscore", key)) {
    return(ggplot2::scale_fill_gradient2(
      low = "#2166ac", mid = "#f7f7f7", high = "#b2182b",
      midpoint = 0, limits = limits, na.value = "transparent"
    ))
  }
  colors <- if (grepl("cwp|bwp|water_productivity", key)) {
    if (requireNamespace("viridisLite", quietly = TRUE)) {
      viridisLite::viridis(256)
    } else {
      grDevices::hcl.colors(256, "Viridis")
    }
  } else {
    NULL
  }
  if (is.null(colors)) {
    ggplot2::scale_fill_viridis_c(limits = limits, na.value = "transparent")
  } else {
    ggplot2::scale_fill_gradientn(colours = colors, limits = limits, na.value = "transparent")
  }
}

#' Plot a raster indicator
#' @param x SpatRaster or numeric matrix.
#' @param indicator Character indicator name. Adequacy is centered at 1,
#'   anomalies at 0, and CWP/BWP use a viridis scale.
#' @param title Optional title.
#' @param save Optional output path. PNG is written at `dpi`.
#' @param dpi Resolution for saved raster output.
#' @param max_cells Maximum cells in a SpatRaster plot preview. Oversized
#'   continuous rasters are block-aggregated using the mean. Categorical
#'   rasters require an explicit `aggregate_fun`. Set to `NULL` to disable the
#'   limit.
#' @param aggregate_fun Optional aggregation function or terra-supported name
#'   (for example, `"modal"`) used when reducing an oversized raster.
#' @param limits Optional two-value fill scale limits, useful for comparing maps.
#' @param show_scale,show_north_arrow Add a scale bar or north arrow to a
#'   georeferenced SpatRaster plot. Requires `ggspatial`.
#' @return A ggplot object, invisibly if `save` is supplied.
#' @export
wapor_plot_map <- function(x, indicator = "value", title = NULL, save = NULL, dpi = 300,
                           max_cells = 1e6, aggregate_fun = NULL, limits = NULL,
                           show_scale = FALSE, show_north_arrow = FALSE) {
  .wapor_require_ggplot2()
  if (!is.character(indicator) || length(indicator) != 1L || is.na(indicator) || !nzchar(indicator)) {
    stop("'indicator' must be one non-empty character string", call. = FALSE)
  }
  if (!is.null(limits) && (length(limits) != 2L || anyNA(limits) ||
                           any(!is.finite(limits)) || limits[[1]] >= limits[[2]])) {
    stop("'limits' must be NULL or two finite, increasing numbers", call. = FALSE)
  }
  if (!is.null(max_cells) && (length(max_cells) != 1L || is.na(max_cells) ||
                              !is.finite(max_cells) || max_cells < 1)) {
    stop("'max_cells' must be NULL or one finite positive number", call. = FALSE)
  }

  map_crs <- NULL
  if (inherits(x, "SpatRaster")) {
    if (!is.null(max_cells)) x <- .wapor_plot_aggregate(x, max_cells, aggregate_fun)
    d <- as.data.frame(x, xy = TRUE, na.rm = TRUE)
    names(d)[3] <- "value"
    map_crs <- terra::crs(x)
  } else {
    m <- as.matrix(x)
    if (length(m) > (max_cells %||% Inf)) {
      stop("Large numeric matrices cannot be spatially aggregated automatically; reduce the matrix before plotting.", call. = FALSE)
    }
    d <- expand.grid(x = seq_len(ncol(m)), y = seq_len(nrow(m)))
    d$value <- as.vector(t(m[nrow(m):1, , drop = FALSE]))
  }
  if ((isTRUE(show_scale) || isTRUE(show_north_arrow)) &&
      (!inherits(x, "SpatRaster") || is.null(map_crs) || !nzchar(map_crs))) {
    stop("Scale bars and north arrows require a georeferenced SpatRaster", call. = FALSE)
  }
  if (isTRUE(show_scale) || isTRUE(show_north_arrow)) {
    if (!requireNamespace("ggspatial", quietly = TRUE)) {
      stop("Install 'ggspatial' to add map scale bars or north arrows", call. = FALSE)
    }
  }

  coord <- if (isTRUE(show_scale) || isTRUE(show_north_arrow)) {
    ggplot2::coord_sf(crs = sf::st_crs(map_crs), datum = NA)
  } else {
    ggplot2::coord_equal()
  }
  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data$x, y = .data$y, fill = .data$value)) +
    ggplot2::geom_raster() + coord +
    .wapor_plot_fill_scale(indicator, limits) +
    ggplot2::labs(title = title %||% indicator, fill = indicator) +
    ggplot2::theme_minimal()
  if (isTRUE(show_scale)) p <- p + ggspatial::annotation_scale(location = "bl", width_hint = 0.25)
  if (isTRUE(show_north_arrow)) {
    p <- p + ggspatial::annotation_north_arrow(
      location = "tr", which_north = "true",
      style = ggspatial::north_arrow_fancy_orienteering()
    )
  }
  if (!is.null(save)) ggplot2::ggsave(save, p, width = 8, height = 6, dpi = dpi)
  p
}

#' Find common display limits for comparison maps
#' @keywords internal
#' @noRd
.wapor_plot_comparison_limits <- function(arrays) {
  ranges <- lapply(arrays, function(x) {
    if (inherits(x, "SpatRaster")) {
      as.numeric(unlist(terra::global(x, fun = c("min", "max"), na.rm = TRUE), use.names = FALSE))
    } else {
      range(as.numeric(x), na.rm = TRUE)
    }
  })
  limits <- range(unlist(ranges), na.rm = TRUE)
  if (length(limits) == 2L && all(is.finite(limits)) && limits[[1]] == limits[[2]]) {
    delta <- max(abs(limits[[1]]) * 0.05, 0.5)
    limits <- limits + c(-delta, delta)
  }
  limits
}

#' Comparison Plot for Multiple Spatial Rasters or Matrices
#'
#' Plots multiple spatial raster layers or numeric matrices side-by-side with a shared color scale.
#'
#' @param arrays Non-empty list of SpatRaster objects or numeric matrices.
#' @param titles Optional character vector of panel titles.
#' @param indicator Character indicator name used for labels and palettes.
#' @param suptitle Optional overall title.
#' @param save Optional output path.
#' @param dpi Resolution for saved output.
#' @param limits Optional common fill limits. Defaults to the global range across
#'   all input maps so panels are directly comparable.
#' @param max_cells Maximum cells per SpatRaster preview. See [wapor_plot_map()].
#' @param aggregate_fun Optional reduction function for oversized rasters. See [wapor_plot_map()].
#' @return A combined ggplot or patchwork object.
#' @export
wapor_plot_comparison <- function(arrays, titles = NULL, indicator = "value", suptitle = NULL,
                                  save = NULL, dpi = 300, limits = NULL,
                                  max_cells = 1e6, aggregate_fun = NULL) {
  .wapor_require_ggplot2()
  if (!is.list(arrays) || !length(arrays)) stop("'arrays' must be a non-empty list.", call. = FALSE)
  if (is.null(limits)) limits <- .wapor_plot_comparison_limits(arrays)
  if (length(limits) != 2L || anyNA(limits) || any(!is.finite(limits)) || limits[[1]] >= limits[[2]]) {
    stop("Cannot derive finite common comparison limits; supply 'limits' explicitly.", call. = FALSE)
  }
  plot_titles <- titles %||% names(arrays) %||% rep("", length(arrays))
  if (length(plot_titles) != length(arrays)) stop("'titles' must match the number of maps.", call. = FALSE)
  plots <- Map(function(x, ttl) wapor_plot_map(
    x, indicator = indicator, title = ttl, limits = limits,
    max_cells = max_cells, aggregate_fun = aggregate_fun
  ), arrays, plot_titles)
  if (requireNamespace("patchwork", quietly = TRUE)) {
    p <- patchwork::wrap_plots(plots) + patchwork::plot_annotation(title = suptitle)
  } else {
    p <- plots[[1]]
    warning("Install 'patchwork' for multi-panel comparison; returning the first plot.", call. = FALSE)
  }
  if (!is.null(save)) ggplot2::ggsave(save, p, width = 10, height = 6, dpi = dpi)
  p
}

#' Plot a grouped time series
#' @param data Data frame containing the time and value columns.
#' @param value Character name of the numeric value column.
#' @param group Optional character name of a grouping column.
#' @param save Optional output path.
#' @param dpi Resolution for saved output.
#' @return A ggplot object.
#' @export
wapor_plot_timeseries <- function(data, value, group = NULL, save = NULL, dpi = 300) {
  .wapor_require_ggplot2()
  if (!is.data.frame(data) || !value %in% names(data)) stop("'data' must contain the value column.", call. = FALSE)
  xcol <- intersect(c("date", "start_date", "time", "period_id"), names(data))[1]
  if (is.na(xcol)) stop("Data must contain date, start_date, time, or period_id.", call. = FALSE)
  aes_args <- list(x = data[[xcol]], y = data[[value]])
  if (!is.null(group) && group %in% names(data)) aes_args$colour <- data[[group]]
  p <- ggplot2::ggplot(data, do.call(ggplot2::aes, aes_args)) + ggplot2::geom_line() + ggplot2::theme_minimal()
  if (!is.null(save)) ggplot2::ggsave(save, p, width = 8, height = 5, dpi = dpi)
  p
}

#' Plot a crop coefficient curve
#' @param kc_daily Numeric vector of daily crop coefficient values.
#' @param save Optional output path.
#' @param dpi Resolution for saved output.
#' @return A ggplot object.
#' @export
wapor_plot_kc_curve <- function(kc_daily, save = NULL, dpi = 300) {
  .wapor_require_ggplot2()
  d <- data.frame(day = seq_along(kc_daily), kc = as.numeric(kc_daily))
  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data$day, y = .data$kc)) + ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::labs(x = "Day after season start", y = "Kc") + ggplot2::theme_minimal()
  if (!is.null(save)) ggplot2::ggsave(save, p, width = 8, height = 5, dpi = dpi)
  p
}

#' Plot a z-score anomaly raster
#' @param zscore_array SpatRaster or numeric matrix of z-score values.
#' @param save Optional output path.
#' @param dpi Resolution for saved output.
#' @return A ggplot object.
#' @export
wapor_plot_anomaly <- function(zscore_array, save = NULL, dpi = 300) {
  wapor_plot_map(zscore_array, indicator = "z-score anomaly", title = "Spatial anomaly", save = save, dpi = dpi)
}
