#' Convert DataFrame Values Between Temporal Units
#'
#' Converts statistical values (mean, min, max, median) in a data frame
#' from one temporal unit to another. Commonly used to convert dekadal
#' values to monthly or annual totals.
#'
#' @param df A data.frame containing columns to convert. Must have:
#'   * At least one of: `mean`, `min`, `max`, `median`
#'   * `start_date`: Date string for calculating conversion factors
#'   * `number_of_days`: Number of days in the source period
#'
#'   Must also have a `units` attribute specifying the source unit
#'   (e.g., "mm/day", "mm/dekad").
#' @param unit_conversion Character. Target temporal unit. One of:
#'   * "none": No conversion (returns input unchanged)
#'   * "day": Convert to daily rate
#'   * "dekad": Convert to 10-day total
#'   * "month": Convert to monthly total
#'   * "year": Convert to annual total
#'
#' @return The input data.frame with converted values. The following
#'   attributes are updated:
#'   * `units`: New unit string (e.g., "mm/month")
#'   * `original_units`: Original unit string before conversion
#'
#' @details
#' Conversion factors:
#' * day -> dekad: multiply by number_of_days
#' * day -> month: multiply by days in month
#' * day -> year: multiply by 365
#' * dekad -> month: multiply by 3
#' * month -> year: multiply by 12
#'
#' @export
#'
#' @importFrom lubridate days_in_month ymd
#'
#' @examples
#' # Create sample data
#' df <- data.frame(
#'   mean = c(2.5, 3.0, 2.8),
#'   min = c(1.0, 1.5, 1.2),
#'   max = c(4.0, 4.5, 4.2),
#'   start_date = c("2023-01-01", "2023-01-11", "2023-01-21"),
#'   number_of_days = c(10, 10, 11)
#' )
#' attr(df, "units") <- "mm/day"
#'
#' # Convert to monthly totals
#' df_monthly <- df_unit_convertor(df, "month")
#' attr(df_monthly, "units")
#' # [1] "mm/month"
df_unit_convertor <- function(df, unit_conversion) {
  # Input validation
  if (!is.data.frame(df)) {
    stop("'df' must be a data.frame", call. = FALSE)
  }

  valid_conversions <- c("none", "day", "dekad", "month", "year")
  if (!unit_conversion %in% valid_conversions) {
    stop(
      sprintf("'unit_conversion' must be one of: %s", paste(valid_conversions, collapse = ", ")),
      call. = FALSE
    )
  }

  if (unit_conversion == "none") {
    return(df)
  }

  source_unit <- attr(df, "units")
  if (is.null(source_unit)) {
    warning("No 'units' attribute found on data.frame. Cannot perform conversion.", call. = FALSE)
    return(df)
  }

  parts <- strsplit(source_unit, "/")[[1]]
  source_time <- parts[length(parts)]

  # Validate required columns
  if (!"start_date" %in% names(df)) {
    stop("'df' must have a 'start_date' column for unit conversion", call. = FALSE)
  }
  if (!"number_of_days" %in% names(df)) {
    stop("'df' must have a 'number_of_days' column for unit conversion", call. = FALSE)
  }

  # Calculate conversion factors
  days_in_current_month <- lubridate::days_in_month(lubridate::ymd(df$start_date))
  num_days <- df$number_of_days

  # Use helper function from utils.R if available, otherwise inline logic
  factor <- vapply(seq_len(nrow(df)), function(i) {
    calculate_conversion_factor(
      source_time,
      unit_conversion,
      num_days[i],
      days_in_current_month[i]
    )
  }, numeric(1))

  # Apply conversion to statistical columns
  stat_cols <- c("mean", "min", "max", "median")
  existing_cols <- intersect(names(df), stat_cols)

  if (length(existing_cols) == 0) {
    warning("No statistical columns (mean, min, max, median) found to convert", call. = FALSE)
    return(df)
  }

  df[existing_cols] <- df[existing_cols] * factor

  # Update attributes
  attr(df, "original_units") <- source_unit
  new_unit <- paste0(paste(parts[-length(parts)], collapse = "/"), "/", unit_conversion)
  attr(df, "units") <- new_unit

  return(df)
}

#' Convert Raster Values Between Temporal Units
#'
#' Converts raster layer values from one temporal unit to another.
#' Each layer is converted individually based on its date information.
#'
#' @param r A `SpatRaster` object from the terra package.
#' @param variable Character. Variable name to determine temporal resolution
#'   (e.g., "L1-AETI-D" where "D" indicates dekadal data).
#' @param urls Character vector. URLs corresponding to each raster layer,
#'   used to extract date information for conversion factors.
#' @param unit_conversion Character. Target temporal unit. One of:
#'   * "none": No conversion (returns input unchanged)
#'   * "day": Convert to daily rate
#'   * "dekad": Convert to 10-day total
#'   * "month": Convert to monthly total
#'   * "year": Convert to annual total
#'
#' @return The input `SpatRaster` with converted values.
#'
#' @details
#' The function determines the source temporal unit from the variable name:
#' * "D" suffix -> dekadal source
#' * "M" suffix -> monthly source
#' * "A" suffix -> annual source
#' * "E" suffix -> daily source
#'
#' @export
#'
#' @importFrom terra nlyr
#' @importFrom lubridate days_in_month ymd
#'
#' @examples
#' \dontrun{
#' # Load raster and convert dekadal to monthly
#' r <- terra::rast(urls)
#' r_monthly <- raster_unit_convertor(
#'   r,
#'   variable = "L1-AETI-D",
#'   urls = urls,
#'   unit_conversion = "month"
#' )
#' }
raster_unit_convertor <- function(r, variable, urls, unit_conversion) {
  # Input validation
  if (!inherits(r, "SpatRaster")) {
    stop("'r' must be a SpatRaster object from the terra package", call. = FALSE)
  }

  valid_conversions <- c("none", "day", "dekad", "month", "year")
  if (!unit_conversion %in% valid_conversions) {
    stop(
      sprintf("'unit_conversion' must be one of: %s", paste(valid_conversions, collapse = ", ")),
      call. = FALSE
    )
  }

  if (unit_conversion == "none") {
    return(r)
  }

  if (length(urls) != terra::nlyr(r)) {
    stop(
      sprintf("Number of URLs (%d) must match number of raster layers (%d)",
              length(urls), terra::nlyr(r)),
      call. = FALSE
    )
  }

  # Extract temporal resolution from variable name
  parts <- strsplit(variable, "-")[[1]]
  tres <- tail(parts, 1)

  # Map temporal resolution code to unit name
  source_time <- switch(
    tres,
    "D" = "dekad",
    "M" = "month",
    "A" = "year",
    "E" = "day",
    stop(sprintf("Unknown temporal resolution code: %s", tres), call. = FALSE)
  )

  # Apply conversion to each layer
  for (i in seq_len(terra::nlyr(r))) {
    url <- urls[i]
    date_info <- get_date_info(url, tres)

    days_in_current_month <- lubridate::days_in_month(lubridate::ymd(date_info$start_date))
    num_days <- date_info$number_of_days

    factor <- calculate_conversion_factor(
      source_time,
      unit_conversion,
      num_days,
      days_in_current_month
    )

    if (factor != 1) {
      r[[i]] <- r[[i]] * factor
    }
  }

  return(r)
}
