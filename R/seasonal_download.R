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
#'   \code{wapor_parse_region()}.
#' @param reg_info List from \code{wapor_parse_region()} with \code{$type} and
#'   \code{$value}.
#'
#' @return A list with components:
#'   \describe{
#'     \item{groups}{A list of lists, one per temporal code that had
#'       downloadable data. Each inner list has:
#'       \itemize{
#'         \item \code{code}: Character temporal code ("A", "M", "D", "E")
#'         \item \code{variable}: Source variable actually downloaded for that group
#'         \item \code{raster}: A cropped \code{SpatRaster} (may be multi-layer)
#'         \item \code{layer_ids}: Character vector aligned with raster layers
#'         \item \code{multipliers}: Numeric vector of length
#'           \code{terra::nlyr(raster)}. These are computed from metadata-aware
#'           seasonal semantics, not only from the temporal code suffix.
#'       }
#'     }
#'     \item{plan}{The data.frame from \code{wapor_plan_time_slices()}}
#'     \item{aggregation_rule}{Requested-variable aggregation rule used for the final seasonal result}
#'   }
#'
#' @keywords internal
#' @noRd
download_seasonal_rasters <- function(variable, period, l3_code, reg_info, folder, do_mask = FALSE) {
  var_parts <- strsplit(variable, "-")[[1]]
  base_var <- paste(var_parts[-length(var_parts)], collapse = "-")
  aggregation_rule <- get_seasonal_aggregation_rule(variable)

  avail <- wapor_temporal_codes(variable)
  message(sprintf("Building seasonal plan for %s (%s to %s)", variable, period[1], period[2]))
  message(sprintf("Available temporal resolutions: %s", paste(avail, collapse = ", ")))

  plan <- wapor_plan_time_slices(period[1], period[2], avail = avail)

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

    # Parse each URL to get start_date for matching to plan rows (Vectorized)
    url_start_dates <- wapor_parse_dates(urls, tres = code)$start_date

    # Match plan rows to URLs and compute multipliers (pre-allocated)
    n_rows <- nrow(code_rows)
    matched_urls <- character(n_rows)
    matched_idx <- integer(n_rows)
    match_count <- 0L

    for (i in seq_len(n_rows)) {
      row <- code_rows[i, ]
      target_start <- format(row$slice_start, "%Y-%m-%d")
      idx <- which(url_start_dates == target_start)

      if (length(idx) >= 1) {
        match_count <- match_count + 1L
        matched_urls[match_count] <- urls[idx[1]]
        matched_idx[match_count] <- i
      } else {
        warning(sprintf("No URL found for %s period %s. Skipping.", code, row$period_id),
                call. = FALSE)
      }
    }

    if (match_count == 0L) next
    matched_urls <- matched_urls[seq_len(match_count)]
    matched_rows <- code_rows[matched_idx[seq_len(match_count)], , drop = FALSE]
    matched_multipliers <- get_seasonal_multiplier_values(
      variable = var_for_code,
      plan_rows = matched_rows,
      aggregation_rule = aggregation_rule
    )
    layer_ids <- matched_rows$period_id

    # Load rasters via vsicurl
    t_code <- proc.time()
    vsicurl_urls <- paste0("/vsicurl/", matched_urls)
    r <- tryCatch({
      terra::rast(vsicurl_urls)
    }, error = function(e) {
      warning(sprintf("Failed to load %s rasters: %s", var_for_code, e$message),
              call. = FALSE)
      return(NULL)
    })

    if (is.null(r)) next

    # Crop to region; optionally mask to polygon boundary
    r <- wapor_crop_to_region(r, reg_info, do_mask = do_mask)
    
    # Temperature Conversion (Kelvin to Celsius for AgERA5 temperature variables)
    r <- wapor_convert_temperature(r, var_for_code)
    
    names(r) <- layer_ids
    message(sprintf("  %s: loaded and cropped %d layer(s) in %.1f seconds",
                    var_for_code, terra::nlyr(r), (proc.time() - t_code)[["elapsed"]]))

    groups[[paste0(code, "_group")]] <- list(
      code = code,
      variable = var_for_code,
      raster = r,
      layer_ids = layer_ids,
      multipliers = matched_multipliers
    )
  }

  list(groups = groups, plan = plan, aggregation_rule = aggregation_rule)
}
