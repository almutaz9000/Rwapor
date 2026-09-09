# R/viz.R
# =============================================================================
# Publication maps and figures for WaPOR indicators (ggplot2 / tidyterra)
# =============================================================================

.wapor_viz_cmaps <- c(
  agg_aeti = "YlGnBu", agg_ret = "YlGnBu", agg_t = "YlGn", agg_pcp = "Blues",
  etc = "YlGnBu", peff = "Blues", green_water = "Greens", blue_water = "Blues",
  adequacy_etc = "RdYlGn", adequacy_p95 = "RdYlGn", beneficial_fraction = "viridis",
  biomass = "YlGn", yield = "YlOrBr", cwp = "viridis", bwp = "viridis",
  variability_aeti = "magma", seasonal_aeti = "YlGnBu", seasonal_ret = "YlGnBu"
)

.wapor_viz_labels <- c(
  agg_aeti = "Seasonal AETI (mm)", agg_ret = "Seasonal RET (mm)",
  agg_t = "Seasonal T (mm)", agg_pcp = "Seasonal precipitation (mm)",
  etc = "Seasonal ETc (mm)", peff = "Effective precipitation (mm)",
  green_water = "Green water (mm)", blue_water = "Blue water (mm)",
  adequacy_etc = "Adequacy (AETI/ETc)", adequacy_p95 = "Adequacy (AETI/P95)",
  beneficial_fraction = "Beneficial fraction", biomass = "Biomass (t/ha)",
  yield = "Yield (t/ha)", cwp = "CWP (kg/m3)", bwp = "BWP (kg/m3)",
  variability_aeti = "AETI std (mm)", seasonal_aeti = "Seasonal AETI (mm)",
  seasonal_ret = "Seasonal RET (mm)"
)

.wapor_require_suggests <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop(
      sprintf("Install %s to use publication plots.", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
}

.wapor_finite_values <- function(r) {
  vals <- terra::values(r, mat = FALSE)
  vals[is.finite(vals)]
}

.wapor_percentile_limits <- function(r, probs = c(2, 98), vmin = NULL, vmax = NULL) {
  finite <- .wapor_finite_values(r)
  if (!length(finite)) {
    return(c(if (is.null(vmin)) NA_real_ else vmin, if (is.null(vmax)) NA_real_ else vmax))
  }
  qs <- stats::quantile(finite, probs = probs / 100, names = FALSE, na.rm = TRUE)
  c(if (is.null(vmin)) qs[1] else vmin, if (is.null(vmax)) qs[2] else vmax)
}

.wapor_fill_scale <- function(indicator, limits, cmap = NULL) {
  pal <- cmap
  if (is.null(pal) || !nzchar(pal)) {
    pal <- if (!is.null(indicator) && indicator %in% names(.wapor_viz_cmaps)) {
      unname(.wapor_viz_cmaps[[indicator]])
    } else {
      "viridis"
    }
  }
  label <- if (!is.null(indicator) && indicator %in% names(.wapor_viz_labels)) {
    unname(.wapor_viz_labels[[indicator]])
  } else {
    ""
  }
  if (identical(pal, "viridis") || identical(pal, "magma")) {
    ggplot2::scale_fill_viridis_c(
      option = if (identical(pal, "magma")) "magma" else "viridis",
      limits = limits,
      name = label,
      na.value = "grey90"
    )
  } else {
    ggplot2::scale_fill_distiller(
      palette = pal,
      direction = 1,
      limits = limits,
      name = label,
      na.value = "grey90"
    )
  }
}

.wapor_save_plot <- function(p, filename, dpi) {
  if (is.null(filename) || !nzchar(filename)) return(invisible(NULL))
  dir_name <- dirname(filename)
  if (!dir.exists(dir_name)) {
    dir.create(dir_name, recursive = TRUE, showWarnings = FALSE)
  }
  ggplot2::ggsave(filename, p, dpi = dpi, width = 8, height = 6, bg = "white")
  invisible(filename)
}

#' Plot a single WaPOR indicator raster
#'
#' Color limits default to the 2nd and 98th percentiles so outliers do not
#' stretch the scale. Titles should name the indicator and season, not the
#' processing method.
#'
#' @param r SpatRaster, single layer.
#' @param indicator Optional key used for colormap and legend (`agg_aeti`,
#'   `green_water`, `adequacy_etc`, ...).
#' @param title Optional plot title.
#' @param cmap Optional RColorBrewer palette or `"viridis"` / `"magma"`.
#' @param vmin,vmax Optional color limits. Unset values use percentiles.
#' @param filename Optional path to write a PNG.
#' @param dpi Output resolution when `filename` is set. Default `300`.
#' @return A ggplot object.
#' @export
#' @examples
#' \dontrun{
#' r <- terra::rast(nrows = 20, ncols = 20, vals = 1:400)
#' wapor_plot_map(r, indicator = "agg_aeti", title = "Seasonal AETI")
#' }
wapor_plot_map <- function(r, indicator = NULL, title = NULL, cmap = NULL,
                           vmin = NULL, vmax = NULL, filename = NULL, dpi = 300) {
  .wapor_require_suggests(c("ggplot2", "tidyterra"))
  if (!inherits(r, "SpatRaster")) {
    stop("'r' must be a SpatRaster", call. = FALSE)
  }
  if (terra::nlyr(r) > 1L) {
    r <- r[[1]]
  }
  limits <- .wapor_percentile_limits(r, vmin = vmin, vmax = vmax)
  p <- ggplot2::ggplot() +
    tidyterra::geom_spatraster(data = r, maxcell = 5e5) +
    .wapor_fill_scale(indicator, limits, cmap) +
    ggplot2::coord_sf(expand = FALSE) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank()
    )
  if (!is.null(title) && nzchar(title)) {
    p <- p + ggplot2::ggtitle(title)
  }
  .wapor_save_plot(p, filename, dpi)
  p
}

#' Multi-panel comparison of the same indicator
#'
#' Uses a shared 2nd/98th percentile scale across panels so seasons or
#' regions are directly comparable.
#'
#' @param rasters List of SpatRaster objects.
#' @param titles Character vector of panel titles (same length as `rasters`).
#' @param indicator Optional indicator key for colormap and legend.
#' @param filename Optional path to write a PNG.
#' @param dpi Output resolution when `filename` is set. Default `300`.
#' @return A ggplot / patchwork object.
#' @export
wapor_plot_comparison <- function(rasters, titles, indicator = NULL,
                                  filename = NULL, dpi = 300) {
  .wapor_require_suggests(c("ggplot2", "tidyterra", "patchwork"))
  if (!is.list(rasters) || !length(rasters)) {
    stop("'rasters' must be a non-empty list of SpatRasters", call. = FALSE)
  }
  if (length(titles) != length(rasters)) {
    stop("'titles' must have the same length as 'rasters'", call. = FALSE)
  }
  finite <- unlist(lapply(rasters, .wapor_finite_values), use.names = FALSE)
  limits <- if (length(finite)) {
    stats::quantile(finite, probs = c(0.02, 0.98), names = FALSE, na.rm = TRUE)
  } else {
    c(NA_real_, NA_real_)
  }
  plots <- lapply(seq_along(rasters), function(i) {
    wapor_plot_map(
      rasters[[i]],
      indicator = indicator,
      title = titles[[i]],
      vmin = limits[1],
      vmax = limits[2]
    )
  })
  p <- patchwork::wrap_plots(plots, ncol = min(3L, length(plots)))
  .wapor_save_plot(p, filename, dpi)
  p
}

#' Line chart of a WaPOR time series data frame
#'
#' @param df data.frame with a date column and a value column.
#' @param value Character. Value column name. Default `"mean"`.
#' @param group Optional grouping column (one line per group).
#' @param date_col Date column name. Default `"start_date"`.
#' @param title Optional title.
#' @param ylabel Optional y-axis label.
#' @param filename Optional path to write a PNG.
#' @param dpi Output resolution when `filename` is set. Default `300`.
#' @return A ggplot object.
#' @export
wapor_plot_timeseries <- function(df, value = "mean", group = NULL,
                                  date_col = "start_date", title = NULL,
                                  ylabel = NULL, filename = NULL, dpi = 300) {
  .wapor_require_suggests("ggplot2")
  if (!is.data.frame(df)) {
    stop("'df' must be a data.frame", call. = FALSE)
  }
  if (!date_col %in% names(df) || !value %in% names(df)) {
    stop(sprintf("'df' must contain columns '%s' and '%s'", date_col, value), call. = FALSE)
  }
  plot_df <- df
  plot_df$.date <- as.Date(plot_df[[date_col]])
  plot_df$.value <- plot_df[[value]]
  aes_map <- if (!is.null(group) && group %in% names(plot_df)) {
    plot_df$.group <- plot_df[[group]]
    ggplot2::aes(x = .date, y = .value, colour = .group, group = .group)
  } else {
    ggplot2::aes(x = .date, y = .value, group = 1)
  }
  p <- ggplot2::ggplot(plot_df, aes_map) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.4) +
    ggplot2::labs(x = "Date", y = ylabel %||% value, title = title, colour = group) +
    ggplot2::theme_minimal(base_size = 11)
  .wapor_save_plot(p, filename, dpi)
  p
}
