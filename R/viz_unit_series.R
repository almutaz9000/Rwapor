# Time series of many units (farms, schemes, ...) with an optional reference
# line such as the crop water demand (ETc).

#' Plot one time series per unit with a dashed reference line
#'
#' Draws one line per unit (for example the seasonal or monthly AETI of every
#' farm), optionally coloured by a group column, and an optional reference
#' series (for example ETc) as a black dashed line. Units above the reference
#' used more water than the reference in that period, units below used less.
#'
#' The time column may be a character or factor (for example seasons
#' `"2018/2019"`, kept in factor order or sorted), a Date or a number.
#'
#' @param data Data frame in long format: one row per unit and time step.
#' @param unit_col,time_col,value_col Names of the unit, time and value columns.
#' @param colour_col Optional column used to colour the lines (for example the
#'   crop type). `NULL` draws every line in grey.
#' @param reference Optional data frame with the columns `time_col` and
#'   `value_col`: one reference value per time step, drawn as a dashed line.
#' @param reference_label Legend label of the reference line.
#' @param title,x_label,y_label,colour_label Plot title, axis titles and colour
#'   legend title.
#' @param points Draw a point at every value.
#' @param alpha Transparency of the unit lines and points.
#' @param date_labels,date_breaks Axis labels and breaks when `time_col` is a
#'   Date (see [ggplot2::scale_x_date()]). `date_breaks = NULL` lets ggplot2
#'   choose.
#' @param out_file Optional PNG path to save the plot.
#' @param width,height,dpi Size (inches) and resolution of the saved plot.
#' @return A ggplot object, invisibly when `out_file` is supplied.
#' @examples
#' \dontrun{
#' farms <- data.frame(Name = rep(c("F001", "F002"), each = 3),
#'                     season = rep(c("2022/2023", "2023/2024", "2024/2025"), 2),
#'                     aeti_mm = c(900, 950, 1010, 1150, 1200, 1180),
#'                     main_type = rep(c("Orange", "Lemon"), each = 3))
#' etc <- data.frame(season = c("2022/2023", "2023/2024", "2024/2025"),
#'                   aeti_mm = c(1048, 1033, 1056))
#' wapor_plot_unit_series(farms, "Name", "season", "aeti_mm", colour_col = "main_type",
#'                        reference = etc, reference_label = "Seasonal ETc",
#'                        y_label = "Seasonal AETI and ETc (mm)")
#' }
#' @export
wapor_plot_unit_series <- function(data, unit_col, time_col, value_col, colour_col = NULL,
                                   reference = NULL, reference_label = "Reference",
                                   title = NULL, x_label = NULL, y_label = NULL, colour_label = NULL,
                                   points = TRUE, alpha = 0.6,
                                   date_labels = "%b %Y", date_breaks = NULL,
                                   out_file = NULL, width = 10, height = 5.5, dpi = 300) {
  .wapor_require_ggplot2()
  if (!is.data.frame(data)) stop("'data' must be a data frame.", call. = FALSE)
  cols <- c(unit_col, time_col, value_col, colour_col)
  missing <- setdiff(cols, names(data))
  if (length(missing)) stop(sprintf("Column(s) not found in 'data': %s.", paste(missing, collapse = ", ")),
                            call. = FALSE)
  if (!is.numeric(data[[value_col]])) stop(sprintf("'%s' must be numeric.", value_col), call. = FALSE)
  if (!is.null(reference)) {
    if (!is.data.frame(reference) || !all(c(time_col, value_col) %in% names(reference))) {
      stop(sprintf("'reference' must be a data frame with the columns '%s' and '%s'.", time_col, value_col),
           call. = FALSE)
    }
  }

  # Character times become a factor (sorted); the reference uses the same levels.
  time <- data[[time_col]]
  discrete <- is.character(time) || is.factor(time)
  if (discrete) {
    lev <- if (is.factor(time)) levels(time) else sort(unique(time))
    if (!is.null(reference)) lev <- union(lev, sort(unique(as.character(reference[[time_col]]))))
    data[[time_col]] <- factor(as.character(time), levels = lev)
    if (!is.null(reference)) reference[[time_col]] <- factor(as.character(reference[[time_col]]), levels = lev)
  }

  unit_aes <- if (is.null(colour_col)) {
    ggplot2::aes(.data[[time_col]], .data[[value_col]], group = .data[[unit_col]])
  } else {
    ggplot2::aes(.data[[time_col]], .data[[value_col]], group = .data[[unit_col]], colour = .data[[colour_col]])
  }
  fixed <- if (is.null(colour_col)) list(colour = "grey40") else list()

  p <- ggplot2::ggplot(data, unit_aes) +
    do.call(ggplot2::geom_line, c(list(linewidth = 0.4, alpha = alpha), fixed))
  if (points) p <- p + do.call(ggplot2::geom_point, c(list(size = 0.8, alpha = alpha), fixed))

  if (!is.null(reference)) {
    p <- p +
      ggplot2::geom_line(data = reference,
                         ggplot2::aes(.data[[time_col]], .data[[value_col]], group = 1,
                                      linetype = reference_label),
                         colour = "black", linewidth = 1, inherit.aes = FALSE) +
      ggplot2::scale_linetype_manual(values = "dashed", name = NULL) +
      ggplot2::guides(linetype = ggplot2::guide_legend(order = 1),
                      colour = ggplot2::guide_legend(order = 2))
    if (points) {
      p <- p + ggplot2::geom_point(data = reference, ggplot2::aes(.data[[time_col]], .data[[value_col]]),
                                   colour = "black", size = 1.8, inherit.aes = FALSE)
    }
  }

  if (inherits(data[[time_col]], "Date")) {
    p <- p + ggplot2::scale_x_date(date_labels = date_labels,
                                   date_breaks = date_breaks %||% ggplot2::waiver()) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  } else {
    p <- p + ggplot2::theme_minimal()
  }
  p <- p + ggplot2::labs(title = title, x = x_label, y = y_label %||% value_col,
                         colour = colour_label %||% colour_col)

  if (!is.null(out_file)) {
    dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
    ggplot2::ggsave(out_file, p, width = width, height = height, dpi = dpi, bg = "white")
    return(invisible(p))
  }
  p
}
