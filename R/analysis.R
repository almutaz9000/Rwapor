# =============================================================================
# Analysis Functions: Crop Mask, Season Rasters, Crop Classes, Kc Curves
# =============================================================================

#' Load a Crop Mask Raster
#'
#' Reads a crop mask raster from disk. Values are expected to be integer
#' class codes.
#'
#' @param path Character. File path to the crop mask raster.
#' @return A SpatRaster with integer class values.
#' @export
wapor_load_crop_mask <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Crop mask file not found: %s", path), call. = FALSE)
  }
  r <- terra::rast(path)
  
  # Ensure CRS robustness
  if (!nzchar(terra::crs(r))) {
    ext_r <- terra::ext(r)
    if (ext_r$xmin >= -180 && ext_r$xmax <= 180 && ext_r$ymin >= -90 && ext_r$ymax <= 90) {
      suppressWarnings(terra::crs(r) <- "EPSG:4326")
    }
  }

  if (terra::nlyr(r) > 1) {
    warning("Crop mask has multiple layers; using the first layer.", call. = FALSE)
    r <- r[[1]]
  }
  r
}

#' Load a Season Raster (Start or End)
#'
#' Reads a season start or end raster from disk. Values should be integer
#' Julian day-of-year values.
#'
#' @param path Character. File path to the season raster.
#' @return A SpatRaster with integer Julian date values.
#' @export
wapor_load_season_raster <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Season raster file not found: %s", path), call. = FALSE)
  }
  r <- terra::rast(path)
  
  # Ensure CRS robustness
  if (!nzchar(terra::crs(r))) {
    ext_r <- terra::ext(r)
    if (ext_r$xmin >= -180 && ext_r$xmax <= 180 && ext_r$ymin >= -90 && ext_r$ymax <= 90) {
      suppressWarnings(terra::crs(r) <- "EPSG:4326")
    }
  }

  if (terra::nlyr(r) > 1) {
    warning("Season raster has multiple layers; using the first layer.", call. = FALSE)
    r <- r[[1]]
  }
  r
}

#' Harmonize a Raster to a Template Grid
#'
#' Reprojects and resamples a source raster to match the CRS, extent,
#' resolution, and alignment of a template raster. Handles cases where
#' input is larger than template by cropping first, and validates spatial
#' overlap before resampling.
#'
#' @param x SpatRaster. The raster to harmonize.
#' @param template SpatRaster. The target geometry (CRS, extent, resolution).
#' @param method Character. Resampling method. Default is "near" (nearest-neighbor),
#'   which is required for categorical data like crop masks and integer season dates.
#'   Use "bilinear" for continuous data.
#' @return A SpatRaster aligned to the template.
#' @export
wapor_harmonize_raster <- function(x, template, method = "near") {
  if (!inherits(x, "SpatRaster")) {
    stop("'x' must be a SpatRaster", call. = FALSE)
  }
  if (!inherits(template, "SpatRaster")) {
    stop("'template' must be a SpatRaster", call. = FALSE)
  }

  # Short-circuit if geometries already match
  if (compare_geom(x, template)) {
    return(x)
  }

  # Ensure CRS is set on both rasters
  x_crs <- terra::crs(x)
  t_crs <- terra::crs(template)

  # Set default CRS if missing (assume WGS84 for geographic coordinates)
  if (!nzchar(x_crs)) {
    x_ext <- terra::ext(x)
    if (x_ext$xmin >= -180 && x_ext$xmax <= 180 && x_ext$ymin >= -90 && x_ext$ymax <= 90) {
      suppressWarnings(terra::crs(x) <- "EPSG:4326")
      x_crs <- terra::crs(x)
    }
  }
  if (!nzchar(t_crs)) {
    t_ext <- terra::ext(template)
    if (t_ext$xmin >= -180 && t_ext$xmax <= 180 && t_ext$ymin >= -90 && t_ext$ymax <= 90) {
      suppressWarnings(terra::crs(template) <- "EPSG:4326")
      t_crs <- terra::crs(template)
    }
  }

  # Reproject if CRS differs
  if (nzchar(x_crs) && nzchar(t_crs) && x_crs != t_crs) {
    x <- terra::project(x, t_crs, method = method)
  }

  # Check if projection already aligned geometries perfectly
  if (compare_geom(x, template)) {
    return(x)
  }

  # Check for spatial overlap before resampling
  x_ext <- terra::ext(x)
  t_ext <- terra::ext(template)

  # Check overlap
  has_overlap <- !(x_ext$xmax <= t_ext$xmin || x_ext$xmin >= t_ext$xmax ||
                   x_ext$ymax <= t_ext$ymin || x_ext$ymin >= t_ext$ymax)

  if (!has_overlap) {
    stop(sprintf(
      paste0(
        "No spatial overlap between input raster and template.\n",
        "  Input extent: [%.4f, %.4f, %.4f, %.4f]\n",
        "  Template extent: [%.4f, %.4f, %.4f, %.4f]\n",
        "Please ensure all input rasters cover the same geographic area."
      ),
      x_ext$xmin, x_ext$ymin, x_ext$xmax, x_ext$ymax,
      t_ext$xmin, t_ext$ymin, t_ext$xmax, t_ext$ymax
    ), call. = FALSE)
  }

  # If input is larger than template, crop first to reduce memory usage
  if (x_ext$xmin < t_ext$xmin || x_ext$xmax > t_ext$xmax ||
      x_ext$ymin < t_ext$ymin || x_ext$ymax > t_ext$ymax) {
    x <- tryCatch(
      terra::crop(x, template, snap = "out"),
      error = function(e) x  # Fallback: keep original if crop fails
    )
  }

  # Short-circuit if crop already aligned geometries
  if (compare_geom(x, template)) {
    return(x)
  }

  # Resample to match template grid
  x <- terra::resample(x, template, method = method)
  x
}

#' Harmonize Crop Mask to AETI Geometry
#'
#' Convenience wrapper that harmonizes a crop mask raster to match
#' the AETI raster geometry using nearest-neighbor resampling.
#'
#' @param crop_mask SpatRaster. The crop mask raster (integer class values).
#' @param target_raster SpatRaster. The AETI raster defining the target geometry.
#' @return A harmonized SpatRaster.
#' @export
wapor_harmonize_crop_mask <- function(crop_mask, target_raster) {
  result <- wapor_harmonize_raster(crop_mask, target_raster, method = "near")

  # Validate non-empty overlap
  vals <- terra::values(result, na.rm = TRUE)
  if (length(vals) == 0) {
    stop("Harmonized crop mask has no valid pixels. Check spatial overlap with AETI.",
         call. = FALSE)
  }
  result
}

#' Extract Unique Crop Classes from Crop Mask
#'
#' Extracts unique integer class values and computes summary statistics
#' (pixel count, approximate area) for each class.
#'
#' @param crop_mask SpatRaster. A harmonized crop mask raster.
#' @param exclude_nodata Logical. If TRUE (default), filters out common nodata
#'   values (0, 255, -9999, -32768) from the class list.
#' @param min_pixels Integer. Minimum pixel count for a class to be included.
#'   Default is 10. This helps filter out very small spurious classes.
#' @param nodata_values Numeric vector. Values to treat as NoData.
#' @return A data.frame with columns: class_value, pixel_count, area_ha.
#' @export
wapor_extract_crop_classes <- function(crop_mask, exclude_nodata = TRUE, min_pixels = 10, nodata_values = c(0, 255, -9999, -32768, 65535, -3.4e+38)) {
  if (!inherits(crop_mask, "SpatRaster")) {
    stop("'crop_mask' must be a SpatRaster", call. = FALSE)
  }
  # Get pixel counts
  freq_tbl <- terra::freq(crop_mask)
  freq_tbl <- freq_tbl[!is.na(freq_tbl$value), , drop = FALSE]

  if (nrow(freq_tbl) == 0) {
    warning("Crop mask raster contains only NA values.", call. = FALSE)
    return(data.frame(class_value = integer(0), pixel_count = integer(0), area_ha = numeric(0)))
  }

  # Filter out common nodata values
  if (exclude_nodata) {
    freq_tbl_filtered <- freq_tbl[!freq_tbl$value %in% nodata_values, , drop = FALSE]
    if (nrow(freq_tbl_filtered) == 0) {
       warning(sprintf("All found values (%s) were filtered out as nodata. Check if your valid classes overlap with: %s",
                       paste(unique(freq_tbl$value), collapse = ", "),
                       paste(nodata_values, collapse = ", ")), call. = FALSE)
    }
    freq_tbl <- freq_tbl_filtered
  }

  # Filter by minimum pixel count
  if (min_pixels > 0 && nrow(freq_tbl) > 0) {
    freq_tbl_filtered <- freq_tbl[freq_tbl$count >= min_pixels, , drop = FALSE]
    if (nrow(freq_tbl_filtered) == 0 && nrow(freq_tbl) > 0) {
       warning(sprintf("All classes were filtered out by min_pixels (%d). Largest class has %d pixels.",
                       min_pixels, max(freq_tbl$count)), call. = FALSE)
    }
    freq_tbl <- freq_tbl_filtered
  }

  # Return empty data.frame if no valid classes
  if (nrow(freq_tbl) == 0) {
    return(data.frame(class_value = integer(0), pixel_count = integer(0), area_ha = numeric(0)))
  }

  # Ensure CRS for expanse calculation
  if (!nzchar(terra::crs(crop_mask))) {
    ext_r <- terra::ext(crop_mask)
    if (ext_r$xmin >= -180 && ext_r$xmax <= 180 && ext_r$ymin >= -90 && ext_r$ymax <= 90) {
      suppressWarnings(terra::crs(crop_mask) <- "EPSG:4326")
    }
  }

  # Compute areas with error handling
  area_tbl <- tryCatch({
    terra::expanse(crop_mask, unit = "ha", byValue = TRUE)
  }, error = function(e) {
    # Fallback to pixel counts if expanse fails
    ft <- terra::freq(crop_mask)
    data.frame(layer = ft$layer, value = ft$value, area = ft$count)
  })

  # Filter area_tbl to match freq_tbl classes
  area_tbl <- area_tbl[area_tbl$value %in% freq_tbl$value, , drop = FALSE]

  # Merge freq and area
  res <- merge(
    data.frame(class_value = as.integer(freq_tbl$value), pixel_count = as.integer(freq_tbl$count)),
    data.frame(class_value = as.integer(area_tbl$value), area_ha = round(area_tbl$area, 2)),
    by = "class_value",
    all = TRUE
  )

  res[, c("class_value", "pixel_count", "area_ha")]
}

#' Build Crop Assignment Table
#'
#' Creates a data.frame for each crop class extracted from the mask,
#' pre-populated with NA parameters that can be filled by crop defaults
#' or user input.
#'
#' @param class_values Integer vector of unique crop class values.
#' @param crop_defaults Optional data.frame of defaults (same format as FAO_CROP_DEFAULTS).
#' @return A data.frame with one row per class, columns for all crop parameters.
#' @export
wapor_build_crop_assignments <- function(class_values, crop_defaults = NULL) {
  n <- length(class_values)
  tbl <- data.frame(
    class_value  = as.integer(class_values),
    crop_label   = rep(NA_character_, n),
    kc_ini       = rep(NA_real_, n),
    kc_mid       = rep(NA_real_, n),
    kc_end       = rep(NA_real_, n),
    l_ini_days   = rep(NA_integer_, n),
    l_mid_days   = rep(NA_integer_, n),
    l_late_days  = rep(NA_integer_, n),
    max_height_m = rep(NA_real_, n),
    MC           = rep(NA_real_, n),
    fc           = rep(NA_real_, n),
    AOT          = rep(NA_real_, n),
    HI           = rep(NA_real_, n),
    stringsAsFactors = FALSE
  )
  tbl
}


# =============================================================================
# Season Date Logic
# =============================================================================

#' Convert a Date to Continuous Julian Index
#'
#' Converts a date into a continuous Julian day index relative to a
#' reference year. Dates in the reference year map to 1..365/366.
#' Dates in the following year map to 366/367..730/731.
#'
#' @param date Date or character in "YYYY-MM-DD" format.
#' @param reference_year Integer. The season reference year.
#' @return Integer. Continuous Julian day index.
#' @export
#' @examples
#' wapor_continuous_julian("2023-03-15", 2023)
#' wapor_continuous_julian("2024-01-15", 2023)  # cross-year
wapor_continuous_julian <- function(date, reference_year) {
  if (is.character(date)) date <- as.Date(date)
  ref_start <- as.Date(sprintf("%04d-01-01", reference_year))
  ref_year_length <- ifelse(
    lubridate::leap_year(reference_year), 366L, 365L
  )
  day_offset <- as.integer(date - ref_start) + 1L
  day_offset
}

#' Build Daily Season Mask
#'
#' For each analysis date, creates a raster mask where each pixel is 1
#' if the date falls inside that pixel's season (between start_jd and
#' end_jd), or 0 otherwise.
#'
#' @param dates Date vector. The dates to evaluate.
#' @param start_raster SpatRaster. Pixel-wise season start Julian days.
#' @param end_raster SpatRaster. Pixel-wise season end Julian days
#'   (may exceed 365/366 for cross-year seasons).
#' @param reference_year Integer. The season reference year.
#' @return A SpatRaster with one layer per date, values 0 or 1.
#' @export
wapor_build_season_mask <- function(dates, start_raster, end_raster,
                                           reference_year) {
  if (!inherits(start_raster, "SpatRaster") || !inherits(end_raster, "SpatRaster")) {
    stop("start_raster and end_raster must be SpatRaster objects", call. = FALSE)
  }
  if (is.character(dates)) dates <- as.Date(dates)
  if (length(dates) == 0) {
    return(terra::rast())
  }

  # Optimization: wapor_continuous_julian naturally supports vectors of dates.
  # Passing the entire vector directly upfront eliminates the R-level vapply loop and redundant date-parsing overhead.
  jd_values <- wapor_continuous_julian(dates, reference_year = reference_year)

  # Optimization: SpatRaster compared to numeric vector produces multi-layer SpatRaster.
  # Doing this in a single vectorized step fully avoids the R-level lapply loop and terra::ifel
  # overhead, letting the C++ backend do the comparisons in a single pass.
  in_season <- (start_raster <= jd_values) & (end_raster >= jd_values)

  # Casting the boolean SpatRaster to a 0/1 integer SpatRaster efficiently using multiplication.
  # This avoids the conditional branch evaluation overhead of terra::ifel().
  result <- in_season * 1L
  names(result) <- as.character(dates)
  result
}


# =============================================================================
# Dekadal Season Weights
# =============================================================================

#' Build a Dekad Table for a Date Range
#'
#' Creates a data.frame of dekadal periods covering a date range,
#' with start date, end date, and number of days per dekad.
#'
#' @param start_date Date or character. Start of range.
#' @param end_date Date or character. End of range.
#' @return A data.frame with columns: dekad_start, dekad_end, n_days.
#' @keywords internal
#' @noRd
build_dekad_table <- function(start_date, end_date) {
  if (is.character(start_date)) start_date <- as.Date(start_date)
  if (is.character(end_date)) end_date <- as.Date(end_date)

  dekads <- list()
  current <- start_date
  while (current <= end_date) {
    yr <- as.integer(format(current, "%Y"))
    mo <- as.integer(format(current, "%m"))
    dy <- as.integer(format(current, "%d"))

    if (dy <= 10) {
      d_start <- as.Date(sprintf("%04d-%02d-01", yr, mo))
      d_end   <- as.Date(sprintf("%04d-%02d-10", yr, mo))
    } else if (dy <= 20) {
      d_start <- as.Date(sprintf("%04d-%02d-11", yr, mo))
      d_end   <- as.Date(sprintf("%04d-%02d-20", yr, mo))
    } else {
      d_start <- as.Date(sprintf("%04d-%02d-21", yr, mo))
      d_end   <- as.Date(sprintf("%04d-%02d-%02d", yr, mo,
                                  lubridate::days_in_month(current)))
    }
    # Store the unclipped standard dekad start as the key for matching
    d_key <- d_start

    # Clamp to the requested range for weighting
    d_start <- max(d_start, start_date)
    d_end   <- min(d_end, end_date)

    dekads[[length(dekads) + 1]] <- data.frame(
      dekad_start = d_start, 
      dekad_end = d_end,
      dekad_key = d_key,
      n_days = as.integer(d_end - d_start) + 1L,
      stringsAsFactors = FALSE
    )
    current <- d_end + 1L
  }
  do.call(rbind, dekads)
}

#' Build Dekadal Season Weights and Days
#'
#' For each dekad in a given date range, computes:
#' 1. A per-pixel fractional weight (0-1) representing the portion of the dekad
#'    falling inside the pixel's growing season.
#' 2. A per-pixel count of absolute days (0-11) falling inside the season.
#'
#' @param start_date Date or character. Start of the analysis date range.
#' @param end_date Date or character. End of the analysis date range.
#' @param start_raster SpatRaster. Pixel-wise season start Julian days.
#' @param end_raster SpatRaster. Pixel-wise season end Julian days.
#' @param reference_year Integer. The season reference year.
#' @return A list with components:
#'   \describe{
#'     \item{weights}{SpatRaster with one layer per dekad (fraction 0-1)}
#'     \item{days}{SpatRaster with one layer per dekad (absolute days)}
#'     \item{dekad_table}{data.frame of dekad periods}
#'   }
#' @export
wapor_build_season_weights <- function(start_date, end_date,
                                              start_raster, end_raster,
                                              reference_year) {
  # Handle cross-year seasons (e.g. Nov-to-May): if end DOY < start DOY,
  # the raster stores raw day-of-year values that wrap around the year
  # boundary. Add the reference year's length to bring end into continuous
  # Julian day space before computing overlaps.
  ref_days <- ifelse(lubridate::leap_year(as.integer(reference_year)), 366L, 365L)
  end_raster <- terra::ifel(end_raster < start_raster,
                             end_raster + ref_days, end_raster)

  dekad_tbl <- build_dekad_table(start_date, end_date)

  # Pre-calculate all dekad boundary continuous Julian days upfront as vectors
  # to avoid calling wapor_continuous_julian inside the lapply loop.
  d_starts_jd <- wapor_continuous_julian(dekad_tbl$dekad_start, reference_year)
  d_ends_jd   <- wapor_continuous_julian(dekad_tbl$dekad_end, reference_year)

  # Analytical overlap calculation:
  # Overlap = max(0, min(dekad_end, season_end) - max(dekad_start, season_start) + 1)
  layers <- lapply(seq_len(nrow(dekad_tbl)), function(i) {
    d <- dekad_tbl[i, ]

    d_start_jd <- d_starts_jd[i]
    d_end_jd   <- d_ends_jd[i]
    
    # Calculate overlap using terra::clamp (robust for SpatRaster/scalar)
    o_start <- terra::clamp(start_raster, lower = d_start_jd)
    o_end   <- terra::clamp(end_raster,   upper = d_end_jd)
    
    overlap_days <- terra::clamp(o_end - o_start + 1, lower = 0)
    
    # Weight is fraction of dekad days
    fraction <- overlap_days / d$n_days
    
    list(days = overlap_days, fraction = fraction)
  })

  weights <- terra::rast(lapply(layers, `[[`, "fraction"))
  days    <- terra::rast(lapply(layers, `[[`, "days"))
  
  names(weights) <- paste0("dekad_", seq_len(nrow(dekad_tbl)))
  names(days)    <- paste0("dekad_", seq_len(nrow(dekad_tbl)))

  list(weights = weights, days = days, dekad_table = dekad_tbl)
}



# =============================================================================
# Total Season Duration and Development Stage
# =============================================================================

#' Compute Total Season Days Raster
#'
#' For each pixel, computes total_days = end_jd - start_jd + 1.
#' When `reference_year` is supplied, cross-year seasons are handled
#' automatically: pixels where `end_raster < start_raster` (e.g. a
#' Nov-to-May season stored as raw day-of-year values) have the
#' reference-year length added to `end_raster` before the subtraction.
#'
#' @param start_raster SpatRaster. Pixel-wise season start Julian days.
#' @param end_raster SpatRaster. Pixel-wise season end Julian days.
#' @param reference_year Integer or NULL. When supplied, corrects
#'   cross-year seasons where `end_raster` DOY < `start_raster` DOY.
#' @return A SpatRaster of total season days per pixel.
#' @export
wapor_season_days <- function(start_raster, end_raster, reference_year = NULL) {
  if (!is.null(reference_year)) {
    ref_days <- ifelse(lubridate::leap_year(as.integer(reference_year)), 366L, 365L)
    end_raster <- terra::ifel(end_raster < start_raster,
                               end_raster + ref_days, end_raster)
  }
  end_raster - start_raster + 1L
}

#' Compute Development Stage Length Raster
#'
#' Derives l_dev dynamically: l_dev = total_days - (l_ini + l_mid + l_late).
#'
#' @param total_days_raster SpatRaster. Total season days per pixel.
#' @param l_ini_days Integer. Length of initial stage.
#' @param l_mid_days Integer. Length of mid-season stage.
#' @param l_late_days Integer. Length of late-season stage.
#' @return A SpatRaster of development stage days per pixel.
#' @export
wapor_season_ldev <- function(total_days_raster, l_ini_days,
                                       l_mid_days, l_late_days) {
  fixed_sum <- as.integer(l_ini_days) + as.integer(l_mid_days) + as.integer(l_late_days)
  ldev <- total_days_raster - fixed_sum
  ldev
}


# =============================================================================
# Kc Curve Generation
# =============================================================================

#' Build Daily Kc Curve
#'
#' Generates a daily Kc curve based on the four-stage FAO-56 model:
#' constant initial, linear development, constant mid-season, linear late.
#'
#' @param kc_ini Numeric. Kc during initial stage.
#' @param kc_mid Numeric. Kc during mid-season stage.
#' @param kc_end Numeric. Kc during end/late stage.
#' @param l_ini Integer. Initial stage length (days).
#' @param l_dev Integer. Development stage length (days).
#' @param l_mid Integer. Mid-season stage length (days).
#' @param l_late Integer. Late-season stage length (days).
#' @return Numeric vector of daily Kc values.
#' @export
#' @examples
#' kc <- wapor_build_kc(0.4, 1.15, 0.30, 30, 60, 40, 30)
#' plot(kc, type = "l", ylab = "Kc", xlab = "Day")
wapor_build_kc <- function(kc_ini, kc_mid, kc_end,
                                  l_ini, l_dev, l_mid, l_late) {
  l_ini  <- as.integer(l_ini)
  l_dev  <- as.integer(l_dev)
  l_mid  <- as.integer(l_mid)
  l_late <- as.integer(l_late)
  total  <- l_ini + l_dev + l_mid + l_late

  if (total <= 0) return(numeric(0))
  if (l_dev < 0) {
    warning("l_dev is negative; clamping to 0", call. = FALSE)
    l_dev <- 0L
    total <- l_ini + l_mid + l_late
  }

  kc <- numeric(total)
  idx <- 0L

  # Initial stage: constant kc_ini
  if (l_ini > 0) {
    kc[(idx + 1):(idx + l_ini)] <- kc_ini
    idx <- idx + l_ini
  }

  # Development stage: linear kc_ini -> kc_mid
  if (l_dev > 0) {
    kc[(idx + 1):(idx + l_dev)] <- seq(kc_ini, kc_mid, length.out = l_dev + 1)[-1]
    idx <- idx + l_dev
  }

  # Mid-season stage: constant kc_mid
  if (l_mid > 0) {
    kc[(idx + 1):(idx + l_mid)] <- kc_mid
    idx <- idx + l_mid
  }

  # Late stage: linear kc_mid -> kc_end
  if (l_late > 0) {
    kc[(idx + 1):(idx + l_late)] <- seq(kc_mid, kc_end, length.out = l_late + 1)[-1]
  }

  kc
}

#' Build Kc Curves by Crop Class
#'
#' Generates daily Kc curves for each crop class, optionally grouped
#' by unique season duration patterns.
#'
#' @param crop_assignment data.frame with crop parameters per class.
#'   Must include columns: class_value, kc_ini, kc_mid, kc_end,
#'   l_ini_days, l_mid_days, l_late_days.
#' @param total_days Integer or named integer vector of total season days per class.
#'   If a single value, applied to all classes.
#' @return A named list of numeric vectors (daily Kc values), one per class.
#' @export
wapor_build_kc_by_class <- function(crop_assignment, total_days) {
  if (!is.data.frame(crop_assignment) || nrow(crop_assignment) == 0) {
    stop("'crop_assignment' must be a non-empty data.frame", call. = FALSE)
  }

  result <- list()
  for (i in seq_len(nrow(crop_assignment))) {
    row <- crop_assignment[i, ]
    cls <- as.character(row$class_value)

    td <- if (length(total_days) == 1) total_days else total_days[cls]
    l_dev <- td - (row$l_ini_days + row$l_mid_days + row$l_late_days)

    if (is.na(l_dev) || l_dev < 0) {
      warning(sprintf("Class %s: l_dev=%s (total=%s, ini+mid+late=%s). Skipping.",
                       cls, l_dev, td,
                       row$l_ini_days + row$l_mid_days + row$l_late_days),
              call. = FALSE)
      result[[cls]] <- numeric(0)
      next
    }

    result[[cls]] <- wapor_build_kc(
      kc_ini  = row$kc_ini,
      kc_mid  = row$kc_mid,
      kc_end  = row$kc_end,
      l_ini   = row$l_ini_days,
      l_dev   = l_dev,
      l_mid   = row$l_mid_days,
      l_late  = row$l_late_days
    )
  }
  result
}

#' Aggregate Daily Kc to Dekadal Mean Kc
#'
#' Takes a daily Kc vector and a dekad table, computes the mean Kc
#' for each dekad period using a fast vectorized algorithm.
#'
#' @param kc_daily Numeric vector of daily Kc values.
#' @param dekad_table data.frame with columns dekad_start, dekad_end, n_days.
#' @param season_start Date. The first day of the season.
#' @return Numeric vector of mean Kc per dekad.
#' @export
wapor_aggregate_kc <- function(kc_daily, dekad_table, season_start) {
  n_dekads <- nrow(dekad_table)
  if (n_dekads == 0) return(numeric(0))

  total_kc_days <- length(kc_daily)
  if (total_kc_days == 0) return(numeric(n_dekads))

  if (is.character(season_start)) season_start <- as.Date(season_start)

  d_start <- as.Date(dekad_table$dekad_start)
  d_end   <- as.Date(dekad_table$dekad_end)

  # Days relative to season start (1-indexed)
  day_starts <- as.integer(d_start - season_start) + 1L
  day_ends   <- as.integer(d_end - season_start) + 1L

  # Identify out-of-bounds or inverted intervals
  invalid_mask <- is.na(day_starts) | is.na(day_ends) |
    (day_starts > total_kc_days) | (day_ends < 1L) | (day_starts > day_ends)

  # Clamp indices to valid range 1..total_kc_days for cumsum lookup
  idx_starts <- pmax(1L, pmin(total_kc_days, day_starts))
  idx_ends   <- pmax(1L, pmin(total_kc_days, day_ends))

  # Vectorized O(1) interval sum and count via cumulative sums
  kc_na <- is.na(kc_daily)
  kc_clean <- kc_daily
  kc_clean[kc_na] <- 0

  csum <- c(0, cumsum(kc_clean))
  counts <- c(0L, cumsum(as.integer(!kc_na)))

  sum_vals <- csum[idx_ends + 1L] - csum[idx_starts]
  cnt_vals <- counts[idx_ends + 1L] - counts[idx_starts]

  means <- ifelse(cnt_vals == 0L, NaN, sum_vals / cnt_vals)
  means[invalid_mask] <- 0

  means
}

#' Scan Local Folder for Available Variables
#'
#' Scans a download folder to find which WaPOR/AgERA5 variables are available
#' locally, along with their date ranges.
#'
#' @param folder Character. Path to the download folder.
#' @return A data.frame with columns: variable, file_count, min_date, max_date, folder_path.
#'   Returns empty data.frame if no variables found.
#' @export
wapor_scan_local <- function(folder) {

  if (!dir.exists(folder)) {
    return(data.frame(
      variable = character(0),
      file_count = integer(0),
      min_date = character(0),
      max_date = character(0),
      folder_path = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # List all subdirectories (each should be a variable like L1-AETI-D)
  subdirs <- list.dirs(folder, full.names = FALSE, recursive = FALSE)

  # Filter to likely variable folders (match pattern like L1-AETI-D, L2-NPP-M, AGERA5-ET0-E)
  # Note: E = daily (AgERA5), D = dekadal, M = monthly, Y = yearly
  var_pattern <- "^(L[123]-[A-Z0-9]+-[DMYA]|AGERA5-[A-Z0-9]+-[DMYE])$"
  var_folders <- subdirs[grepl(var_pattern, subdirs)]

  if (length(var_folders) == 0) {
    return(data.frame(
      variable = character(0),
      file_count = integer(0),
      min_date = character(0),
      max_date = character(0),
      folder_path = character(0),
      stringsAsFactors = FALSE
    ))
  }

  results <- lapply(var_folders, function(var) {
    var_path <- file.path(folder, var)
    tif_files <- list.files(var_path, pattern = "\\.tif$", full.names = FALSE)

    if (length(tif_files) == 0) {
      return(NULL)
    }

    # Extract dates from filenames (pattern: *.YYYY-MM-DD.tif or *.YYYYMMDD.tif)
    date_patterns <- c(
      "\\.(\\d{4}-\\d{2}-\\d{2})\\.tif$",  # YYYY-MM-DD
      "\\.(\\d{4}\\d{2}\\d{2})\\.tif$"      # YYYYMMDD
    )

    dates <- character(0)
    for (pattern in date_patterns) {
      matches <- regmatches(tif_files, regexec(pattern, tif_files))
      extracted <- sapply(matches, function(m) if (length(m) > 1) m[2] else NA_character_)
      extracted <- extracted[!is.na(extracted)]
      if (length(extracted) > 0) {
        # Normalize to YYYY-MM-DD
        if (nchar(extracted[1]) == 8) {
          extracted <- gsub("^(\\d{4})(\\d{2})(\\d{2})$", "\\1-\\2-\\3", extracted)
        }
        dates <- c(dates, extracted)
      }
    }

    if (length(dates) == 0) {
      # Fallback: just count files
      return(data.frame(
        variable = var,
        file_count = length(tif_files),
        min_date = NA_character_,
        max_date = NA_character_,
        folder_path = var_path,
        stringsAsFactors = FALSE
      ))
    }

    dates <- sort(unique(dates))

    data.frame(
      variable = var,
      file_count = length(tif_files),
      min_date = dates[1],
      max_date = dates[length(dates)],
      folder_path = var_path,
      stringsAsFactors = FALSE
    )
  })

  results <- results[!sapply(results, is.null)]
  if (length(results) == 0) {
    return(data.frame(
      variable = character(0),
      file_count = integer(0),
      min_date = character(0),
      max_date = character(0),
      folder_path = character(0),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, results)
}

#' Check if two SpatRasters have identical geometry
#'
#' Internal helper to short-circuit harmonization if rasters already match.
#'
#' @param r1 SpatRaster 1
#' @param r2 SpatRaster 2
#' @return Logical
#' @keywords internal
#' @noRd
compare_geom <- function(r1, r2) {
  if (is.null(r1) || is.null(r2)) return(FALSE)
  # terra::compareGeom is fast and checks crs, ext, res, rowcol
  tryCatch(
    terra::compareGeom(r1, r2, stopOnError = FALSE, crs = TRUE, res = TRUE, ext = TRUE, rowcol = TRUE),
    error = function(e) FALSE
  )
}

#' Exported Geometry Comparison
#' @param r1 SpatRaster. First raster to compare.
#' @param r2 SpatRaster. Second raster to compare.
#' @return Logical.
#' @export
wapor_compare_geom <- function(r1, r2) {
  compare_geom(r1, r2)
}

#' Get Local Raster Paths for a Variable and Date Range
#'
#' Returns file paths for locally available rasters matching a variable
#' and date range. For dekadal/monthly data, includes any time step that
#' overlaps with the analysis period (not just those starting within it).
#'
#' @param folder Character. Path to the download folder.
#' @param variable Character. Variable code (e.g., "L1-AETI-D").
#' @param start_date Character or Date. Start of date range.
#' @param end_date Character or Date. End of date range.
#' @return Character vector of full file paths, sorted by date.
#' @export
wapor_local_rasters <- function(folder, variable, start_date, end_date) {
  var_path <- file.path(folder, variable)

  if (!dir.exists(var_path)) {
    warning(sprintf("Variable folder not found: %s", var_path), call. = FALSE)
    return(character(0))
  }

  if (is.character(start_date)) start_date <- as.Date(start_date)
  if (is.character(end_date)) end_date <- as.Date(end_date)

  tif_files <- list.files(var_path, pattern = "\\.tif$", full.names = TRUE)

  if (length(tif_files) == 0) {
    return(character(0))
  }

  # Determine temporal resolution from variable name
  var_parts <- strsplit(variable, "-")[[1]]
  tres_code <- if (length(var_parts) >= 3) var_parts[length(var_parts)] else "D"

  # Extract dates and filter by range using vectorized parsing
  parsed <- wapor_parse_dates(tif_files, tres = tres_code)

  file_dates <- data.frame(
    path = tif_files,
    file_start = as.Date(parsed$start_date),
    file_end = as.Date(parsed$end_date),
    stringsAsFactors = FALSE
  )

  # Filter by overlap with analysis period (not just start date within period)
  # A file overlaps if: file_start <= end_date AND file_end >= start_date
  file_dates <- file_dates[
    !is.na(file_dates$file_start) &
    file_dates$file_start <= end_date &
    file_dates$file_end >= start_date,
  ]

  # Sort by start date
  file_dates <- file_dates[order(file_dates$file_start), ]

  file_dates$path
}

#' Check for Local Raster Files
#'
#' Given a set of WaPOR URLs and a local folder, checks which files exist
#' locally following the standard naming convention.
#'
#' @param urls Character vector of WaPOR URLs.
#' @param var Character. WaPOR variable code (e.g., "L1-AETI-D").
#' @param folder Character. Path to the local analysis folder.
#' @return A list with components:
#'   \describe{
#'     \item{optimized_paths}{Character vector of paths to use in rast() (local paths or /vsicurl/ URLs).}
#'     \item{missing_dates}{Character vector of dates (YYYY-MM-DD) for missing dekads.}
#'     \item{found_count}{Integer. Number of dekads found locally.}
#'   }
#' @export
wapor_check_local <- function(urls, var, folder) {
  if (length(urls) == 0) return(list(optimized_paths = character(0), missing_dates = character(0), found_count = 0L))

  # Normalize folder path (handle potential issues with trailing slashes, etc.)
  folder <- normalizePath(folder, winslash = "/", mustWork = FALSE)

  # Standard naming components
  parts <- strsplit(basename(urls[1]), "\\.")[[1]]
  product_base <- if (length(parts) >= 3) {
    paste(parts[1:(length(parts)-2)], collapse = ".")
  } else {
    var
  }

  tres_code <- strsplit(var, "-")[[1]][3]
  var_folder <- file.path(folder, var)

  # Get list of all .tif files in the variable folder for flexible matching
  existing_files <- character(0)
  if (dir.exists(var_folder)) {
    existing_files <- list.files(var_folder, pattern = "\\.tif$", full.names = TRUE)
    # Also normalize these paths for consistent comparison
    if (length(existing_files) > 0) {
      existing_files <- normalizePath(existing_files, winslash = "/", mustWork = FALSE)
    }
  }

  # Vectorized date parsing for all URLs
  date_infos <- wapor_parse_dates(urls, tres = tres_code)
  raw_dates <- date_infos$raw_date
  dash_dates <- date_infos$start_date

  # Generate candidate filenames matrix (N urls x 4 candidates)
  # Candidates: standard.raw, bb_prefix.raw, standard.dash, bb_prefix.dash
  cand_matrix <- cbind(
    file.path(var_folder, paste0(product_base, ".", raw_dates, ".tif")),
    file.path(var_folder, paste0("bb_", product_base, ".", raw_dates, ".tif")),
    file.path(var_folder, paste0(product_base, ".", dash_dates, ".tif")),
    file.path(var_folder, paste0("bb_", product_base, ".", dash_dates, ".tif"))
  )

  # Normalize all candidate paths at once (vectorized)
  cand_matrix <- matrix(
    normalizePath(as.vector(cand_matrix), winslash = "/", mustWork = FALSE),
    nrow = nrow(cand_matrix), ncol = ncol(cand_matrix)
  )

  # Check existence for all candidates in one batch (as.vector preserves order)
  exists_vec <- file.exists(as.vector(cand_matrix))
  exists_mat <- matrix(exists_vec, nrow = nrow(cand_matrix), ncol = ncol(cand_matrix))

  optimized_paths <- character(length(urls))
  missing_indices <- logical(length(urls))
  found_count <- 0L

  for (i in seq_along(urls)) {
    # Find first candidate that exists
    found_idx <- which(exists_mat[i, ])
    if (length(found_idx) > 0) {
      optimized_paths[i] <- cand_matrix[i, found_idx[1]]
      found_count <- found_count + 1L
    } else {
      # Fallback: search by date pattern in existing files
      found <- FALSE
      if (length(existing_files) > 0) {
        date_pattern <- paste0("\\.", dash_dates[i], "\\.tif$")
        matches <- grep(date_pattern, existing_files, value = TRUE)
        if (length(matches) > 0) {
          optimized_paths[i] <- matches[1]
          found_count <- found_count + 1L
          found <- TRUE
        }
      }

      if (!found) {
        optimized_paths[i] <- if (grepl("^/vsicurl/", urls[i])) urls[i] else paste0("/vsicurl/", urls[i])
        missing_indices[i] <- TRUE
      }
    }
  }

  missing_dates <- dash_dates[missing_indices]

  list(optimized_paths = optimized_paths, missing_dates = missing_dates, found_count = found_count)
}
