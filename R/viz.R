# Publication-ready visualization helpers.

.wapor_require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for publication plots.", call. = FALSE)
  }
}

#' Plot a raster indicator
#' @param x SpatRaster or numeric matrix.
#' @param indicator Character indicator name.
#' @param title Optional title.
#' @param save Optional output path. PNG is written at `dpi`.
#' @param dpi Resolution for saved raster output.
#' @return A ggplot object, invisibly if `save` is supplied.
#' @export
wapor_plot_map <- function(x, indicator = "value", title = NULL, save = NULL, dpi = 300) {
  .wapor_require_ggplot2()
  if (inherits(x, "SpatRaster")) {
    d <- as.data.frame(x, xy = TRUE, na.rm = TRUE)
    names(d)[3] <- "value"
  } else {
    m <- as.matrix(x)
    d <- expand.grid(x = seq_len(ncol(m)), y = seq_len(nrow(m)))
    d$value <- as.vector(t(m[nrow(m):1, , drop = FALSE]))
  }
  p <- ggplot2::ggplot(d, ggplot2::aes_string("x", "y", fill = "value")) +
    ggplot2::geom_raster() + ggplot2::coord_equal() +
    ggplot2::scale_fill_gradient(low = "#2c7bb6", high = "#d7191c", na.value = "transparent") +
    ggplot2::labs(title = title %||% indicator, fill = indicator) +
    ggplot2::theme_minimal()
  if (!is.null(save)) ggplot2::ggsave(save, p, width = 8, height = 6, dpi = dpi)
  p
}

#' Plot several raster indicators side by side
#' @param arrays Non-empty list of SpatRaster objects or numeric matrices.
#' @param titles Optional character vector of panel titles.
#' @param indicator Character indicator name used for labels and palettes.
#' @param suptitle Optional overall title.
#' @param save Optional output path.
#' @param dpi Resolution for saved output.
#' @return A combined ggplot or patchwork object.
#' @export
wapor_plot_comparison <- function(arrays, titles = NULL, indicator = "value", suptitle = NULL, save = NULL, dpi = 300) {
  .wapor_require_ggplot2()
  if (!is.list(arrays) || !length(arrays)) stop("'arrays' must be a non-empty list.", call. = FALSE)
  plots <- Map(function(x, ttl) wapor_plot_map(x, indicator, ttl), arrays,
               titles %||% names(arrays) %||% rep("", length(arrays)))
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
  p <- ggplot2::ggplot(d, ggplot2::aes_string("day", "kc")) + ggplot2::geom_line(linewidth = 0.8) +
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
