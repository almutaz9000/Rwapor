#' Plan Optimal WaPOR Time Slices for Seasonal Aggregation
#'
#' Builds an optimized download plan for aggregating WaPOR raster data over a
#' date range. The plan minimizes the number of rasters to download by preferring
#' coarser temporal resolutions (annual > monthly > dekadal > daily) for periods
#' that are fully covered.
#'
#' This function does **not** download any data. It returns a plan (data frame)
#' describing which rasters to download and how to weight them for computing a
#' seasonal sum.
#'
#' **Aggregation rule:** `seasonal_sum = sum(raster_value * weight)` across all
#' rows in the plan. This assumes each raster value represents a **total** over
#' its time slice (as is typical for WaPOR aggregated ET layers).
#'
#' **Approximation note:** When fractional weights are applied to monthly (`M`)
#' or annual (`A`) slices, the calculation assumes uniform daily distribution
#' within the slice. Dekadal (`D`) fractional weights involve a smaller
#' approximation. Daily (`E`) slices always have `weight = 1`.
#'
#' @param start_date Character string `"YYYY-MM-DD"` or a Date object.
#' @param end_date Character string `"YYYY-MM-DD"` or a Date object.
#' @param avail Character vector of available temporal codes for the variable.
#'   Must be a subset of `c("A", "M", "D", "E")`. For example, L2 AETI
#'   typically has `c("A", "M", "D")`.
#' @param inclusive Logical. If `TRUE` (default), both `start_date` and
#'   `end_date` are included in the range. If `FALSE`, the range is treated
#'   as half-open `[start_date, end_date)`.
#'
#' @return A data.frame with one row per raster to download, sorted by
#'   `slice_start`. Columns:
#'   \describe{
#'     \item{code}{Temporal resolution code: `"A"`, `"M"`, `"D"`, or `"E"`.}
#'     \item{period_id}{Identifier for the time slice, e.g. `"2022"`, `"2023-04"`,
#'       `"2022-10-D2"`, `"2022-10-13"`.}
#'     \item{slice_start}{Date. Start of the raster slice.}
#'     \item{slice_end}{Date. End of the raster slice.}
#'     \item{overlap_start}{Date. Start of the overlap with the requested range.}
#'     \item{overlap_end}{Date. End of the overlap with the requested range.}
#'     \item{weight}{Numeric in \eqn{[0, 1]}. `overlap_days / slice_days`.}
#'     \item{slice_days}{Integer. Total days in the slice.}
#'     \item{overlap_days}{Integer. Days of overlap with the requested range.}
#'   }
#'
#' @export
#'
#' @examples
#' # Plan for L2 AETI (no daily data) over a partial season
#' plan <- plan_wapor_time_slices("2022-10-13", "2023-04-17", avail = c("A", "M", "D"))
#' print(plan)
#'
#' # Seasonal sum would be: sum(downloaded_raster_values * plan$weight)
#'
#' # Plan for a multi-year range
#' plan <- plan_wapor_time_slices("2018-01-01", "2023-06-22", avail = c("A", "M", "D"))
#' print(plan)
#'
#' # If only monthly data is available
#' plan <- plan_wapor_time_slices("2022-10-13", "2023-04-17", avail = c("M"))
#' print(plan)
plan_wapor_time_slices <- function(start_date, end_date,
                                   avail = c("A", "M", "D", "E"),
                                   inclusive = TRUE) {
  # --- Input validation ---
  start_date <- tryCatch(as.Date(start_date), error = function(e) {
    stop("'start_date' must be a valid date string (YYYY-MM-DD) or Date object", call. = FALSE)
  })
  end_date <- tryCatch(as.Date(end_date), error = function(e) {
    stop("'end_date' must be a valid date string (YYYY-MM-DD) or Date object", call. = FALSE)
  })

  if (!is.logical(inclusive) || length(inclusive) != 1) {
    stop("'inclusive' must be a single logical value", call. = FALSE)
  }
  if (!inclusive) {
    end_date <- end_date - 1L
  }

  if (start_date > end_date) {
    stop("'start_date' must be on or before 'end_date'", call. = FALSE)
  }

  valid_codes <- c("A", "M", "D", "E")
  if (!is.character(avail) || length(avail) == 0) {
    stop("'avail' must be a non-empty character vector", call. = FALSE)
  }
  bad <- setdiff(avail, valid_codes)
  if (length(bad) > 0) {
    stop(sprintf("Invalid temporal codes in 'avail': %s. Must be subset of {A, M, D, E}",
                 paste(bad, collapse = ", ")), call. = FALSE)
  }

  # --- Build plan via greedy decomposition ---
  intervals <- list(c(start_date, end_date))
  plan_rows <- list()

  # Step 1: Fill full years with A

  if ("A" %in% avail) {
    y_start <- as.integer(format(start_date, "%Y"))
    y_end <- as.integer(format(end_date, "%Y"))
    for (y in y_start:y_end) {
      s <- as.Date(paste0(y, "-01-01"))
      e <- as.Date(paste0(y, "-12-31"))
      if (is_fully_within(s, e, start_date, end_date)) {
        plan_rows <- c(plan_rows, list(list(
          code = "A", period_id = as.character(y),
          slice_start = s, slice_end = e
        )))
        intervals <- subtract_interval(intervals, s, e)
      }
    }
  }

  # Step 2: Fill full months with M
  if ("M" %in% avail && length(intervals) > 0) {
    for (iv in intervals) {
      a <- iv[1]; b <- iv[2]
      # Enumerate months
      cursor <- as.Date(paste0(format(a, "%Y-%m"), "-01"))
      while (cursor <= b) {
        yr <- as.integer(format(cursor, "%Y"))
        mo <- as.integer(format(cursor, "%m"))
        m_start <- cursor
        m_end <- last_day_of_month(yr, mo)
        if (is_fully_within(m_start, m_end, a, b)) {
          plan_rows <- c(plan_rows, list(list(
            code = "M", period_id = format(m_start, "%Y-%m"),
            slice_start = m_start, slice_end = m_end
          )))
        }
        # Advance to next month
        if (mo == 12L) {
          cursor <- as.Date(paste0(yr + 1L, "-01-01"))
        } else {
          cursor <- as.Date(paste(yr, sprintf("%02d", mo + 1L), "01", sep = "-"))
        }
      }
    }
    # Subtract all added M slices from intervals
    for (row in plan_rows) {
      if (row$code == "M") {
        intervals <- subtract_interval(intervals, row$slice_start, row$slice_end)
      }
    }
  }

  # Step 3: Fill with dekadal slices (D)
  if ("D" %in% avail && length(intervals) > 0) {
    new_intervals <- intervals
    for (iv in intervals) {
      a <- iv[1]; b <- iv[2]
      cursor <- as.Date(paste0(format(a, "%Y-%m"), "-01"))
      while (cursor <= b) {
        yr <- as.integer(format(cursor, "%Y"))
        mo <- as.integer(format(cursor, "%m"))
        month_end <- last_day_of_month(yr, mo)
        # Generate 3 dekads for this month
        dekads <- list(
          list(idx = 1L, s = as.Date(paste(yr, sprintf("%02d", mo), "01", sep = "-")),
               e = as.Date(paste(yr, sprintf("%02d", mo), "10", sep = "-"))),
          list(idx = 2L, s = as.Date(paste(yr, sprintf("%02d", mo), "11", sep = "-")),
               e = as.Date(paste(yr, sprintf("%02d", mo), "20", sep = "-"))),
          list(idx = 3L, s = as.Date(paste(yr, sprintf("%02d", mo), "21", sep = "-")),
               e = month_end)
        )
        for (dk in dekads) {
          ov <- compute_overlap(dk$s, dk$e, a, b)
          if (ov$overlap_days > 0L) {
            plan_rows <- c(plan_rows, list(list(
              code = "D",
              period_id = sprintf("%04d-%02d-D%d", yr, mo, dk$idx),
              slice_start = dk$s, slice_end = dk$e
            )))
            new_intervals <- subtract_interval(new_intervals, dk$s, dk$e)
          }
        }
        # Advance to next month
        if (mo == 12L) {
          cursor <- as.Date(paste0(yr + 1L, "-01-01"))
        } else {
          cursor <- as.Date(paste(yr, sprintf("%02d", mo + 1L), "01", sep = "-"))
        }
      }
    }
    intervals <- new_intervals
  }

  # Step 4: Fill remaining days with E
  if ("E" %in% avail && length(intervals) > 0) {
    for (iv in intervals) {
      a <- iv[1]; b <- iv[2]
      days_seq <- seq.Date(a, b, by = "day")
      for (d in days_seq) {
        d <- as.Date(d, origin = "1970-01-01")
        plan_rows <- c(plan_rows, list(list(
          code = "E", period_id = format(d, "%Y-%m-%d"),
          slice_start = d, slice_end = d
        )))
      }
    }
    intervals <- list()  # All covered
  }

  # Step 5: Handle remaining intervals with fractional coarser slices
  # If intervals remain (no finer resolution available), use the finest available
  if (length(intervals) > 0) {
    for (iv in intervals) {
      a <- iv[1]; b <- iv[2]
      if ("D" %in% avail) {
        # Should not happen because step 3 covers with D
        next
      } else if ("M" %in% avail) {
        # Use fractional monthly slices
        cursor <- as.Date(paste0(format(a, "%Y-%m"), "-01"))
        while (cursor <= b) {
          yr <- as.integer(format(cursor, "%Y"))
          mo <- as.integer(format(cursor, "%m"))
          m_start <- cursor
          m_end <- last_day_of_month(yr, mo)
          ov <- compute_overlap(m_start, m_end, a, b)
          if (ov$overlap_days > 0L) {
            plan_rows <- c(plan_rows, list(list(
              code = "M", period_id = format(m_start, "%Y-%m"),
              slice_start = m_start, slice_end = m_end
            )))
          }
          if (mo == 12L) {
            cursor <- as.Date(paste0(yr + 1L, "-01-01"))
          } else {
            cursor <- as.Date(paste(yr, sprintf("%02d", mo + 1L), "01", sep = "-"))
          }
        }
      } else if ("A" %in% avail) {
        # Use fractional annual slices
        y_s <- as.integer(format(a, "%Y"))
        y_e <- as.integer(format(b, "%Y"))
        for (y in y_s:y_e) {
          s <- as.Date(paste0(y, "-01-01"))
          e <- as.Date(paste0(y, "-12-31"))
          ov <- compute_overlap(s, e, a, b)
          if (ov$overlap_days > 0L) {
            plan_rows <- c(plan_rows, list(list(
              code = "A", period_id = as.character(y),
              slice_start = s, slice_end = e
            )))
          }
        }
      }
    }
  }

  # --- Build output data.frame ---
  if (length(plan_rows) == 0) {
    return(data.frame(
      code = character(0), period_id = character(0),
      slice_start = as.Date(character(0)), slice_end = as.Date(character(0)),
      overlap_start = as.Date(character(0)), overlap_end = as.Date(character(0)),
      weight = numeric(0), slice_days = integer(0), overlap_days = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  rows <- lapply(plan_rows, function(row) {
    s_days <- as.integer(row$slice_end - row$slice_start) + 1L
    ov <- compute_overlap(row$slice_start, row$slice_end, start_date, end_date)
    data.frame(
      code = row$code,
      period_id = row$period_id,
      slice_start = row$slice_start,
      slice_end = row$slice_end,
      overlap_start = ov$overlap_start,
      overlap_end = ov$overlap_end,
      weight = ov$overlap_days / s_days,
      slice_days = s_days,
      overlap_days = ov$overlap_days,
      stringsAsFactors = FALSE
    )
  })

  plan <- do.call(rbind, rows)

  # Remove zero-overlap rows
  plan <- plan[plan$overlap_days > 0L, , drop = FALSE]

  # Remove duplicates (same period_id and code)
  plan <- plan[!duplicated(plan[, c("code", "period_id")]), , drop = FALSE]

  # Sort by slice_start, then by code preference
  code_order <- c(A = 1L, M = 2L, D = 3L, E = 4L)
  plan <- plan[order(plan$slice_start, code_order[plan$code]), , drop = FALSE]
  rownames(plan) <- NULL

  # --- Validate coverage ---
  total_requested <- as.integer(end_date - start_date) + 1L
  total_overlap <- sum(plan$overlap_days)
  if (total_overlap != total_requested) {
    warning(
      sprintf(
        "Plan covers %d days but %d were requested (%s to %s). Difference: %d days.",
        total_overlap, total_requested,
        format(start_date), format(end_date),
        total_requested - total_overlap
      ),
      call. = FALSE
    )
  }

  plan
}


#' Get Available Temporal Codes for a Variable
#'
#' Determines which temporal resolutions (annual, monthly, dekadal, daily)
#' are available for a given WaPOR or AgERA5 variable by checking the
#' static metadata lists. For L3 variables, checks L2 equivalents as fallback.
#'
#' @param variable Character. Variable name (e.g., `"L2-AETI-D"`, `"L1-NPP-M"`).
#'
#' @return Character vector of available temporal codes (e.g., `c("A", "M", "D")`),
#'   ordered from coarsest to finest.
#'
#' @export
#'
#' @examples
#' get_available_temporal_codes("L1-AETI-D")
#' # [1] "A" "M" "D"
#'
#' get_available_temporal_codes("L2-NPP-D")
#' # [1] "M" "D"
get_available_temporal_codes <- function(variable) {
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string", call. = FALSE)
  }

  parts <- strsplit(variable, "-")[[1]]
  if (length(parts) < 3) {
    stop(sprintf("Invalid variable format '%s'. Expected 'LEVEL-VAR-TRES'", variable),
         call. = FALSE)
  }
  base <- paste(parts[-length(parts)], collapse = "-")

  all_vars <- c(names(WAPOR3_VARS), names(AGERA5_VARS))
  avail <- character(0)
  for (code in c("A", "M", "D", "E")) {
    if (paste0(base, "-", code) %in% all_vars) {
      avail <- c(avail, code)
    }
  }

  # Fallback for L3: check L2 equivalents
  if (length(avail) == 0 && parts[1] == "L3") {
    base_l2 <- sub("^L3", "L2", base)
    for (code in c("A", "M", "D", "E")) {
      if (paste0(base_l2, "-", code) %in% all_vars) {
        avail <- c(avail, code)
      }
    }
  }

  # Final fallback: use only the current temporal code
  if (length(avail) == 0) {
    tres <- parts[length(parts)]
    if (tres %in% c("A", "M", "D", "E")) {
      avail <- tres
    }
  }

  avail
}


