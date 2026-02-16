#' Subtract a Covered Interval from a List of Intervals
#'
#' Given a list of `[start, end]` date intervals and a single covered interval,
#' returns the remaining uncovered intervals after subtraction.
#'
#' @param intervals A list of two-element Date vectors `c(start, end)`.
#' @param cover_start Date. Start of the interval to subtract.
#' @param cover_end Date. End of the interval to subtract.
#'
#' @return A list of two-element Date vectors representing remaining intervals.
#'
#' @keywords internal
#' @noRd
subtract_interval <- function(intervals, cover_start, cover_end) {
  result <- list()
  for (iv in intervals) {
    a <- iv[1]
    b <- iv[2]
    if (cover_end < a || cover_start > b) {
      # No overlap, keep interval as-is
      result <- c(result, list(c(a, b)))
    } else {
      # Left remainder
      if (a < cover_start) {
        result <- c(result, list(c(a, cover_start - 1L)))
      }
      # Right remainder
      if (b > cover_end) {
        result <- c(result, list(c(cover_end + 1L, b)))
      }
    }
  }
  result
}

#' Compute Overlap Between Two Date Intervals
#'
#' @param slice_start Date. Start of the slice.
#' @param slice_end Date. End of the slice.
#' @param range_start Date. Start of the requested range.
#' @param range_end Date. End of the requested range.
#'
#' @return A list with `overlap_start`, `overlap_end`, `overlap_days` (integer).
#'   Returns `overlap_days = 0` if no overlap.
#'
#' @keywords internal
#' @noRd
compute_overlap <- function(slice_start, slice_end, range_start, range_end) {
  os <- max(slice_start, range_start)
  oe <- min(slice_end, range_end)
  if (os > oe) {
    return(list(overlap_start = as.Date(NA), overlap_end = as.Date(NA), overlap_days = 0L))
  }
  list(
    overlap_start = os,
    overlap_end = oe,
    overlap_days = as.integer(oe - os) + 1L
  )
}

#' Check if a Date Interval is Fully Contained Within Another
#'
#' @param inner_start Date. Start of the inner interval.
#' @param inner_end Date. End of the inner interval.
#' @param outer_start Date. Start of the outer interval.
#' @param outer_end Date. End of the outer interval.
#'
#' @return Logical. `TRUE` if inner is fully within outer.
#'
#' @keywords internal
#' @noRd
is_fully_within <- function(inner_start, inner_end, outer_start, outer_end) {
  inner_start >= outer_start && inner_end <= outer_end
}

#' Get the Last Day of a Month
#'
#' @param year Integer year.
#' @param month Integer month (1-12).
#'
#' @return Date. The last day of the given month.
#'
#' @keywords internal
#' @noRd
last_day_of_month <- function(year, month) {
  # First day of next month minus 1
  if (month == 12L) {
    as.Date(paste(year, "12", "31", sep = "-"))
  } else {
    as.Date(paste(year, sprintf("%02d", month + 1L), "01", sep = "-")) - 1L
  }
}

#' Get the Number of Days in a Year
#'
#' @param year Integer year.
#'
#' @return Integer. 365 or 366.
#'
#' @keywords internal
#' @noRd
days_in_year <- function(year) {
  as.integer(as.Date(paste0(year, "-12-31")) - as.Date(paste0(year, "-01-01"))) + 1L
}
