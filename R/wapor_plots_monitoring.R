#' Plot raster time series for a farm
#'
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param variable WaPOR variable
#' @param date_range Optional date range c(start, end)
#' @return ggplot2 object or NULL
#' @export
wapor_plot_raster_timeseries <- function(con, farm_id, variable, date_range = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("ggplot2 package required for plotting")
    return(NULL)
  }

  # Query timeseries data
  query <- "
    SELECT
      start_date as date,
      mean_val as mean,
      min_val as min,
      max_val as max,
      std_val as std,
      p05_val as p05,
      p95_val as p95,
      threshold_pct,
      pixels_used,
      pixels_total
    FROM farm_timeseries
    WHERE farm_id = ? AND variable = ?
    ORDER BY start_date
  "

  df <- DBI::dbGetQuery(con, query, params = list(farm_id, variable))

  if (nrow(df) == 0) {
    message("No data found for farm_id=", farm_id, ", variable=", variable)
    return(NULL)
  }

  # Convert to Date
  df$date <- as.Date(df$date)

  # Filter by date range if provided
  if (!is.null(date_range) && length(date_range) == 2) {
    df <- df[df$date >= date_range[1] & df$date <= date_range[2], ]
  }

  if (nrow(df) == 0) {
    message("No data in specified date range")
    return(NULL)
  }

  # Create plot
  p <- ggplot2::ggplot(df, ggplot2::aes(x = date)) +
    # Ribbon for min-max range
    ggplot2::geom_ribbon(ggplot2::aes(ymin = min, ymax = max), alpha = 0.2, fill = "lightblue") +
    # Ribbon for std deviation
    ggplot2::geom_ribbon(ggplot2::aes(ymin = mean - std, ymax = mean + std),
                         alpha = 0.3, fill = "blue", na.rm = TRUE) +
    # Mean line
    ggplot2::geom_line(ggplot2::aes(y = mean), color = "darkblue", linewidth = 1) +
    # Points
    ggplot2::geom_point(ggplot2::aes(y = mean), color = "darkblue", size = 2) +
    # Labels
    ggplot2::labs(
      title = paste("Time Series:", farm_id, "-", variable),
      x = "Date",
      y = "Value",
      subtitle = sprintf("Blue line = mean, shaded = ±1 std, light = min-max range")
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )

  p
}

#' Plot raster time series for multiple farms and variables
#'
#' @param con DuckDB connection
#' @param farm_ids Vector of farm identifiers (or "all")
#' @param variables Vector of WaPOR variables
#' @param date_range Optional date range c(start, end)
#' @return ggplot2 object or NULL
#' @export
wapor_plot_raster_timeseries_multi <- function(con, farm_ids, variables, date_range = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("ggplot2 package required for plotting")
    return(NULL)
  }

  # Handle "all" farms
  if (length(farm_ids) == 1 && farm_ids[1] == "all") {
    farm_ids <- DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_timeseries")$farm_id
  }

  # Build query with multiple farms and variables
  placeholders_farms <- paste(rep("?", length(farm_ids)), collapse = ", ")
  placeholders_vars <- paste(rep("?", length(variables)), collapse = ", ")

  query <- sprintf("
    SELECT
      farm_id,
      variable,
      start_date as date,
      mean_val as mean,
      min_val as min,
      max_val as max,
      std_val as std,
      threshold_pct,
      pixels_used,
      pixels_total
    FROM farm_timeseries
    WHERE farm_id IN (%s) AND variable IN (%s)
    ORDER BY farm_id, variable, start_date
  ", placeholders_farms, placeholders_vars)

  df <- DBI::dbGetQuery(con, query, params = c(as.list(farm_ids), as.list(variables)))

  if (nrow(df) == 0) {
    message("No data found for selected farms and variables")
    return(NULL)
  }

  # Convert to Date
  df$date <- as.Date(df$date)

  # Filter by date range if provided
  if (!is.null(date_range) && length(date_range) == 2) {
    df <- df[df$date >= date_range[1] & df$date <= date_range[2], ]
  }

  if (nrow(df) == 0) {
    message("No data in specified date range")
    return(NULL)
  }

  # Add threshold info to subtitle
  threshold_info <- ""
  if (!is.null(df$threshold_pct) && !all(is.na(df$threshold_pct))) {
    avg_threshold <- mean(df$threshold_pct, na.rm = TRUE)
    if (!is.na(df$pixels_used[1])) {
      avg_pct <- mean(df$pixels_used / df$pixels_total * 100, na.rm = TRUE)
      threshold_info <- sprintf("(Avg threshold: %.1f%%, %.0f%% pixels retained)",
                               avg_threshold, avg_pct)
    } else {
      threshold_info <- sprintf("(Threshold: %.1f%%)", avg_threshold)
    }
  }

  # Create faceted plot
  # Strategy: Facet by variable (rows), color by farm
  n_farms <- length(unique(df$farm_id))
  n_vars <- length(unique(df$variable))

  p <- ggplot2::ggplot(df, ggplot2::aes(x = date, color = farm_id, fill = farm_id, group = farm_id)) +
    # Mean line
    ggplot2::geom_line(ggplot2::aes(y = mean), linewidth = 0.8) +
    ggplot2::geom_point(ggplot2::aes(y = mean), size = 1.5, alpha = 0.7) +
    # Labels
    ggplot2::labs(
      title = sprintf("Raster Time Series: %d Farm(s) × %d Variable(s)", n_farms, n_vars),
      x = "Date",
      y = "Value",
      subtitle = paste("Mean values from clipped rasters", threshold_info),
      color = "Farm ID",
      fill = "Farm ID"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 14),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position = if (n_farms > 10) "none" else "right",
      strip.text = ggplot2::element_text(face = "bold")
    )

  # Add faceting if multiple variables
  if (n_vars > 1) {
    p <- p + ggplot2::facet_wrap(~ variable, scales = "free_y", ncol = 1)
  }

  # Add std ribbons only if single farm (too cluttered otherwise)
  if (n_farms == 1 && !all(is.na(df$std))) {
    p <- p +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = mean - std, ymax = mean + std),
                           alpha = 0.2, color = NA)
  }

  p
}
