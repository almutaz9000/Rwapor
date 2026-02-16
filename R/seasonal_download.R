#' Download and Match Seasonal Rasters
#'
#' Internal helper that handles the shared download-and-match logic for
#' seasonal mode in both \code{wapor_map} and \code{wapor_ts}. Builds an
#' optimal download plan, fetches rasters at mixed temporal resolutions,
#' matches them to the plan, computes per-layer multipliers, and crops
#' to the region.
#'
#' @param variable Character. Single variable name (e.g., "L2-AETI-D").
#' @param period Character vector of length 2. Date range as
#'   \code{c(start_date, end_date)} in "YYYY-MM-DD" format.
#' @param l3_code Character or NULL. L3 region code extracted from
#'   \code{parse_region()}.
#' @param reg_info List from \code{parse_region()} with \code{$type} and
#'   \code{$value}.
#'
#' @return A list with components:
#'   \describe{
#'     \item{groups}{A list of lists, one per temporal code that had
#'       downloadable data. Each inner list has:
#'       \itemize{
#'         \item \code{code}: Character temporal code ("A", "M", "D", "E")
#'         \item \code{raster}: A cropped \code{SpatRaster} (may be multi-layer)
#'         \item \code{multipliers}: Numeric vector of length
#'           \code{terra::nlyr(raster)}. For daily-rate codes (D, E) this is
#'           \code{overlap_days}; for period-total codes (M, A) this is
#'           \code{weight}.
#'       }
#'     }
#'     \item{plan}{The data.frame from \code{plan_wapor_time_slices()}}
#'   }
#'
#' @keywords internal
#' @noRd
download_seasonal_rasters <- function(variable, period, l3_code, reg_info) {
  var_parts <- strsplit(variable, "-")[[1]]
  base_var <- paste(var_parts[-length(var_parts)], collapse = "-")

  avail <- get_available_temporal_codes(variable)
  message(sprintf("Building seasonal plan for %s (%s to %s)", variable, period[1], period[2]))
  message(sprintf("Available temporal resolutions: %s", paste(avail, collapse = ", ")))

  plan <- plan_wapor_time_slices(period[1], period[2], avail = avail)

  if (nrow(plan) == 0) {
    stop("Seasonal plan is empty. Check your date range and variable.", call. = FALSE)
  }

  message(sprintf("Plan: %d raster(s) to download", nrow(plan)))

  groups <- list()

  for (code in unique(plan$code)) {
    code_rows <- plan[plan$code == code, ]
    var_for_code <- paste0(base_var, "-", code)

    code_period <- c(
      format(min(code_rows$slice_start), "%Y-%m-%d"),
      format(max(code_rows$slice_end), "%Y-%m-%d")
    )

    message(sprintf("Downloading %d %s raster(s) from %s...",
                     nrow(code_rows), code, var_for_code))

    urls <- wapor_generate_urls(var_for_code, l3_region = l3_code, period = code_period)

    if (length(urls) == 0) {
      warning(sprintf("No URLs found for %s. Skipping.", var_for_code), call. = FALSE)
      next
    }

    # Parse each URL to get start_date for matching to plan rows
    url_start_dates <- vapply(urls, function(u) {
      get_date_info(u, tres = code)$start_date
    }, character(1))

    # Match plan rows to URLs and compute multipliers
    matched_urls <- character(0)
    matched_multipliers <- numeric(0)

    for (i in seq_len(nrow(code_rows))) {
      row <- code_rows[i, ]
      target_start <- format(row$slice_start, "%Y-%m-%d")
      idx <- which(url_start_dates == target_start)

      if (length(idx) >= 1) {
        matched_urls <- c(matched_urls, urls[idx[1]])
        # D and E rasters are daily rates: multiply by overlap_days to get total
        # M and A rasters are period totals: multiply by weight to prorate
        if (code %in% c("D", "E")) {
          matched_multipliers <- c(matched_multipliers, row$overlap_days)
        } else {
          matched_multipliers <- c(matched_multipliers, row$weight)
        }
      } else {
        warning(sprintf("No URL found for %s period %s. Skipping.", code, row$period_id),
                call. = FALSE)
      }
    }

    if (length(matched_urls) == 0) next

    # Load rasters via vsicurl
    vsicurl_urls <- paste0("/vsicurl/", matched_urls)
    r <- tryCatch({
      terra::rast(vsicurl_urls)
    }, error = function(e) {
      warning(sprintf("Failed to load %s rasters: %s", var_for_code, e$message),
              call. = FALSE)
      return(NULL)
    })

    if (is.null(r)) next

    # Crop to region (crop only — wapor_map applies mask separately)
    if (reg_info$type == "vector") {
      vect_data <- reg_info$value
      vect_crs <- sf::st_crs(vect_data)
      if (!is.na(vect_crs) && vect_crs$epsg != 4326) {
        vect_data <- sf::st_transform(vect_data, 4326)
      }
      v <- terra::vect(vect_data)
      r <- terra::crop(r, v)
    } else if (reg_info$type == "bbox") {
      ext <- terra::ext(reg_info$value[c("xmin", "xmax", "ymin", "ymax")])
      r <- terra::crop(r, ext)
    }

    groups[[length(groups) + 1]] <- list(
      code = code,
      raster = r,
      multipliers = matched_multipliers
    )
  }

  list(groups = groups, plan = plan)
}
