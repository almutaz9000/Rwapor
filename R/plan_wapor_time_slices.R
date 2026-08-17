#' Plan Optimal WaPOR Time Slices for Seasonal Aggregation
#'
#' Builds an optimized download plan for aggregating WaPOR raster data over a
#' date range. The plan minimizes the number of rasters to download by preferring
#' coarser temporal resolutions (annual > monthly > dekadal > daily) for periods
#' that are fully covered.
#'
#' This function does **not** download any data. It returns a plan (data frame)
#' describing which rasters to download and how much of each slice overlaps the
#' requested season.
#'
#' Final aggregation is resolved downstream from variable metadata:
#' period totals use weighted sums, daily-rate products use overlap-day
#' multipliers, and state variables can use time-weighted means.
#'
#' **Approximation note:** When fractional weights are applied to monthly (`M`)
#' or annual (`A`) slices, downstream aggregation assumes uniform daily
#' distribution within the slice. Dekadal (`D`) fractional weights involve a
#' smaller approximation. Daily (`E`) slices always have `weight = 1`.
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
#' plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("A", "M", "D"))
#' print(plan)
#'
#' # Downstream seasonal aggregation uses the plan together with variable metadata.
#'
#' # Plan for a multi-year range
#' plan <- wapor_plan_time_slices("2018-01-01", "2023-06-22", avail = c("A", "M", "D"))
#' print(plan)
#'
#' # If only monthly data is available
#' plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M"))
#' print(plan)
wapor_plan_time_slices <- function(start_date, end_date,
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
        # Optimization: Direct list assignment avoiding c(list, list) copies
        plan_rows[[length(plan_rows) + 1L]] <- list(
          code = "A", period_id = as.character(y),
          slice_start = s, slice_end = e
        )
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
          # Optimization: Direct list assignment avoiding c(list, list) copies
          plan_rows[[length(plan_rows) + 1L]] <- list(
            code = "M", period_id = format(m_start, "%Y-%m"),
            slice_start = m_start, slice_end = m_end
          )
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
            # Optimization: Direct list assignment avoiding c(list, list) copies
            plan_rows[[length(plan_rows) + 1L]] <- list(
              code = "D",
              period_id = sprintf("%04d-%02d-D%d", yr, mo, dk$idx),
              slice_start = dk$s, slice_end = dk$e
            )
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
        # Optimization: Direct list assignment avoiding c(list, list) copies
        plan_rows[[length(plan_rows) + 1L]] <- list(
          code = "E", period_id = format(d, "%Y-%m-%d"),
          slice_start = d, slice_end = d
        )
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
            # Optimization: Direct list assignment avoiding c(list, list) copies
            plan_rows[[length(plan_rows) + 1L]] <- list(
              code = "M", period_id = format(m_start, "%Y-%m"),
              slice_start = m_start, slice_end = m_end
            )
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
            # Optimization: Direct list assignment avoiding c(list, list) copies
            plan_rows[[length(plan_rows) + 1L]] <- list(
              code = "A", period_id = as.character(y),
              slice_start = s, slice_end = e
            )
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

  # Optimization: Fully vectorized creation of output data.frame from plan_rows list
  # Avoids creating single-row data frames and calling do.call(rbind, ...)
  n_plan <- length(plan_rows)
  code_vec <- character(n_plan)
  period_id_vec <- character(n_plan)
  slice_start_vec <- rep(start_date, n_plan)
  slice_end_vec <- rep(end_date, n_plan)

  for (i in seq_len(n_plan)) {
    pr <- plan_rows[[i]]
    code_vec[i] <- pr$code
    period_id_vec[i] <- pr$period_id
    slice_start_vec[i] <- pr$slice_start
    slice_end_vec[i] <- pr$slice_end
  }

  s_days <- as.integer(slice_end_vec - slice_start_vec) + 1L

  # Vectorized overlap computation using pmax/pmin
  os <- pmax(slice_start_vec, start_date)
  oe <- pmin(slice_end_vec, end_date)
  no_ov <- os > oe

  os[no_ov] <- as.Date(NA)
  oe[no_ov] <- as.Date(NA)

  ov_days <- rep(0L, n_plan)
  ov_days[!no_ov] <- as.integer(oe[!no_ov] - os[!no_ov]) + 1L

  plan <- data.frame(
    code = code_vec,
    period_id = period_id_vec,
    slice_start = slice_start_vec,
    slice_end = slice_end_vec,
    overlap_start = os,
    overlap_end = oe,
    weight = ov_days / s_days,
    slice_days = s_days,
    overlap_days = ov_days,
    stringsAsFactors = FALSE
  )

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
#' wapor_temporal_codes("L1-AETI-D")
#' # [1] "A" "M" "D"
#'
#' wapor_temporal_codes("L2-NPP-D")
#' # [1] "M" "D"
wapor_temporal_codes <- function(variable) {
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


