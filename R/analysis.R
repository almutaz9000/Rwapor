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
rwapor_load_crop_mask <- function(path) {
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
rwapor_load_season_raster <- function(path) {
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
#' resolution, and alignment of a template raster.
#'
#' @param x SpatRaster. The raster to harmonize.
#' @param template SpatRaster. The target geometry (CRS, extent, resolution).
#' @param method Character. Resampling method. Default is "near" (nearest-neighbor),
#'   which is required for categorical data like crop masks and integer season dates.
#' @return A SpatRaster aligned to the template.
#' @export
rwapor_harmonize_to_template <- function(x, template, method = "near") {
  if (!inherits(x, "SpatRaster")) {
    stop("'x' must be a SpatRaster", call. = FALSE)
  }
  if (!inherits(template, "SpatRaster")) {
    stop("'template' must be a SpatRaster", call. = FALSE)
  }

  # Reproject if CRS differs
  x_crs <- terra::crs(x)
  t_crs <- terra::crs(template)
  if (nzchar(x_crs) && nzchar(t_crs) && x_crs != t_crs) {
    x <- terra::project(x, t_crs, method = method)
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
rwapor_harmonize_crop_mask <- function(crop_mask, target_raster) {
  result <- rwapor_harmonize_to_template(crop_mask, target_raster, method = "near")

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
#' @return A data.frame with columns: class_value, pixel_count, area_ha.
#' @export
rwapor_extract_crop_classes <- function(crop_mask, exclude_nodata = TRUE, min_pixels = 10) {
  if (!inherits(crop_mask, "SpatRaster")) {
    stop("'crop_mask' must be a SpatRaster", call. = FALSE)
  }
  # Get pixel counts
  freq_tbl <- terra::freq(crop_mask)
  freq_tbl <- freq_tbl[!is.na(freq_tbl$value), , drop = FALSE]

  # Filter out common nodata values
  if (exclude_nodata) {
    nodata_values <- c(0, 255, -9999, -32768, 65535, -3.4e+38)
    freq_tbl <- freq_tbl[!freq_tbl$value %in% nodata_values, , drop = FALSE]
  }

  # Filter by minimum pixel count
  if (min_pixels > 0) {
    freq_tbl <- freq_tbl[freq_tbl$count >= min_pixels, , drop = FALSE]
  }

  # Return empty data.frame if no valid classes

  if (nrow(freq_tbl) == 0) {
    warning("No valid crop classes found in mask after filtering.", call. = FALSE)
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
rwapor_build_crop_assignment_table <- function(class_values, crop_defaults = NULL) {
  n <- length(class_values)
  tbl <- data.frame(
    class_value  = as.integer(class_values),
    crop_label   = rep(NA_character_, n),
    Kc_ini       = rep(NA_real_, n),
    Kc_mid       = rep(NA_real_, n),
    Kc_end       = rep(NA_real_, n),
    L_ini_days   = rep(NA_integer_, n),
    L_mid_days   = rep(NA_integer_, n),
    L_late_days  = rep(NA_integer_, n),
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
#' rwapor_continuous_julian("2023-03-15", 2023)
#' rwapor_continuous_julian("2024-01-15", 2023)  # cross-year
rwapor_continuous_julian <- function(date, reference_year) {
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
rwapor_build_season_mask_daily <- function(dates, start_raster, end_raster,
                                           reference_year) {
  if (!inherits(start_raster, "SpatRaster") || !inherits(end_raster, "SpatRaster")) {
    stop("start_raster and end_raster must be SpatRaster objects", call. = FALSE)
  }
  if (is.character(dates)) dates <- as.Date(dates)

  jd_values <- vapply(dates, rwapor_continuous_julian,
                       reference_year = reference_year, FUN.VALUE = integer(1))

  masks <- lapply(jd_values, function(jd) {
    # For each pixel: 1 if start_jd <= jd <= end_jd, else 0
    in_season <- (start_raster <= jd) & (end_raster >= jd)
    terra::ifel(in_season, 1L, 0L)
  })

  result <- terra::rast(masks)
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
    # Clamp to the requested range
    d_start <- max(d_start, start_date)
    d_end   <- min(d_end, end_date)

    dekads[[length(dekads) + 1]] <- data.frame(
      dekad_start = d_start, dekad_end = d_end,
      n_days = as.integer(d_end - d_start) + 1L,
      stringsAsFactors = FALSE
    )
    current <- d_end + 1L
  }
  do.call(rbind, dekads)
}

#' Build Dekadal Season Weights
#'
#' For each dekad in a given date range, computes a per-pixel fractional
#' weight representing how many days of that dekad fall inside the pixel's
#' growing season.
#'
#' @param start_date Date or character. Start of the analysis date range.
#' @param end_date Date or character. End of the analysis date range.
#' @param start_raster SpatRaster. Pixel-wise season start Julian days.
#' @param end_raster SpatRaster. Pixel-wise season end Julian days.
#' @param reference_year Integer. The season reference year.
#' @return A list with components:
#'   \describe{
#'     \item{weights}{SpatRaster with one layer per dekad (values 0-1)}
#'     \item{dekad_table}{data.frame of dekad periods}
#'   }
#' @export
rwapor_build_season_weights_dekad <- function(start_date, end_date,
                                              start_raster, end_raster,
                                              reference_year) {
  dekad_tbl <- build_dekad_table(start_date, end_date)

  weight_layers <- lapply(seq_len(nrow(dekad_tbl)), function(i) {
    d <- dekad_tbl[i, ]
    # Generate all dates in this dekad
    all_dates <- seq.Date(d$dekad_start, d$dekad_end, by = "day")
    # Build daily mask and average to get fraction
    daily_mask <- rwapor_build_season_mask_daily(
      all_dates, start_raster, end_raster, reference_year
    )
    # Mean across days gives the fraction of active days
    terra::app(daily_mask, fun = "mean", na.rm = TRUE)
  })

  weights <- terra::rast(weight_layers)
  names(weights) <- paste0("dekad_", seq_len(nrow(dekad_tbl)))

  list(weights = weights, dekad_table = dekad_tbl)
}


# =============================================================================
# Total Season Duration and Development Stage
# =============================================================================

#' Compute Total Season Days Raster
#'
#' For each pixel, computes total_days = end_jd - start_jd + 1.
#'
#' @param start_raster SpatRaster. Pixel-wise season start Julian days.
#' @param end_raster SpatRaster. Pixel-wise season end Julian days.
#' @return A SpatRaster of total season days per pixel.
#' @export
rwapor_compute_total_days_raster <- function(start_raster, end_raster) {
  end_raster - start_raster + 1L
}

#' Compute Development Stage Length Raster
#'
#' Derives L_dev dynamically: L_dev = total_days - (L_ini + L_mid + L_late).
#'
#' @param total_days_raster SpatRaster. Total season days per pixel.
#' @param L_ini_days Integer. Length of initial stage.
#' @param L_mid_days Integer. Length of mid-season stage.
#' @param L_late_days Integer. Length of late-season stage.
#' @return A SpatRaster of development stage days per pixel.
#' @export
rwapor_compute_ldev_raster <- function(total_days_raster, L_ini_days,
                                       L_mid_days, L_late_days) {
  fixed_sum <- as.integer(L_ini_days) + as.integer(L_mid_days) + as.integer(L_late_days)
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
#' @param Kc_ini Numeric. Kc during initial stage.
#' @param Kc_mid Numeric. Kc during mid-season stage.
#' @param Kc_end Numeric. Kc during end/late stage.
#' @param L_ini Integer. Initial stage length (days).
#' @param L_dev Integer. Development stage length (days).
#' @param L_mid Integer. Mid-season stage length (days).
#' @param L_late Integer. Late-season stage length (days).
#' @return Numeric vector of daily Kc values.
#' @export
#' @examples
#' kc <- rwapor_build_daily_kc(0.4, 1.15, 0.30, 30, 60, 40, 30)
#' plot(kc, type = "l", ylab = "Kc", xlab = "Day")
rwapor_build_daily_kc <- function(Kc_ini, Kc_mid, Kc_end,
                                  L_ini, L_dev, L_mid, L_late) {
  L_ini  <- as.integer(L_ini)
  L_dev  <- as.integer(L_dev)
  L_mid  <- as.integer(L_mid)
  L_late <- as.integer(L_late)
  total  <- L_ini + L_dev + L_mid + L_late

  if (total <= 0) return(numeric(0))
  if (L_dev < 0) {
    warning("L_dev is negative; clamping to 0", call. = FALSE)
    L_dev <- 0L
    total <- L_ini + L_mid + L_late
  }

  kc <- numeric(total)
  idx <- 0L

  # Initial stage: constant Kc_ini
  if (L_ini > 0) {
    kc[(idx + 1):(idx + L_ini)] <- Kc_ini
    idx <- idx + L_ini
  }

  # Development stage: linear Kc_ini -> Kc_mid
  if (L_dev > 0) {
    kc[(idx + 1):(idx + L_dev)] <- seq(Kc_ini, Kc_mid, length.out = L_dev + 1)[-1]
    idx <- idx + L_dev
  }

  # Mid-season stage: constant Kc_mid
  if (L_mid > 0) {
    kc[(idx + 1):(idx + L_mid)] <- Kc_mid
    idx <- idx + L_mid
  }

  # Late stage: linear Kc_mid -> Kc_end
  if (L_late > 0) {
    kc[(idx + 1):(idx + L_late)] <- seq(Kc_mid, Kc_end, length.out = L_late + 1)[-1]
  }

  kc
}

#' Build Kc Curves by Crop Class
#'
#' Generates daily Kc curves for each crop class, optionally grouped
#' by unique season duration patterns.
#'
#' @param crop_assignment data.frame with crop parameters per class.
#'   Must include columns: class_value, Kc_ini, Kc_mid, Kc_end,
#'   L_ini_days, L_mid_days, L_late_days.
#' @param total_days Integer or named integer vector of total season days per class.
#'   If a single value, applied to all classes.
#' @return A named list of numeric vectors (daily Kc values), one per class.
#' @export
rwapor_build_kc_by_class <- function(crop_assignment, total_days) {
  if (!is.data.frame(crop_assignment) || nrow(crop_assignment) == 0) {
    stop("'crop_assignment' must be a non-empty data.frame", call. = FALSE)
  }

  result <- list()
  for (i in seq_len(nrow(crop_assignment))) {
    row <- crop_assignment[i, ]
    cls <- as.character(row$class_value)

    td <- if (length(total_days) == 1) total_days else total_days[cls]
    L_dev <- td - (row$L_ini_days + row$L_mid_days + row$L_late_days)

    if (is.na(L_dev) || L_dev < 0) {
      warning(sprintf("Class %s: L_dev=%s (total=%s, ini+mid+late=%s). Skipping.",
                       cls, L_dev, td,
                       row$L_ini_days + row$L_mid_days + row$L_late_days),
              call. = FALSE)
      result[[cls]] <- numeric(0)
      next
    }

    result[[cls]] <- rwapor_build_daily_kc(
      Kc_ini  = row$Kc_ini,
      Kc_mid  = row$Kc_mid,
      Kc_end  = row$Kc_end,
      L_ini   = row$L_ini_days,
      L_dev   = L_dev,
      L_mid   = row$L_mid_days,
      L_late  = row$L_late_days
    )
  }
  result
}

#' Aggregate Daily Kc to Dekadal Mean Kc
#'
#' Takes a daily Kc vector and a dekad table, computes the mean Kc
#' for each dekad period.
#'
#' @param kc_daily Numeric vector of daily Kc values.
#' @param dekad_table data.frame with columns dekad_start, dekad_end, n_days.
#' @param season_start Date. The first day of the season.
#' @return Numeric vector of mean Kc per dekad.
#' @export
rwapor_aggregate_kc_dekad <- function(kc_daily, dekad_table, season_start) {
  if (is.character(season_start)) season_start <- as.Date(season_start)
  total_kc_days <- length(kc_daily)

  vapply(seq_len(nrow(dekad_table)), function(i) {
    d <- dekad_table[i, ]
    # Days relative to season start (1-indexed)
    day_start <- as.integer(d$dekad_start - season_start) + 1L
    day_end   <- as.integer(d$dekad_end - season_start) + 1L

    # Clamp to valid range
    day_start <- max(1L, day_start)
    day_end   <- min(total_kc_days, day_end)

    if (day_start > total_kc_days || day_end < 1 || day_start > day_end) {
      return(0)
    }
    mean(kc_daily[day_start:day_end], na.rm = TRUE)
  }, numeric(1))
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
rwapor_scan_local_variables <- function(folder) {

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

  # Filter to likely variable folders (match pattern like L1-AETI-D, L2-NPP-M, AGERA5-ET0-D)
  var_pattern <- "^(L[123]-[A-Z]+-[DMY]|AGERA5-[A-Z0-9]+-[DMY])$"
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

#' Get Local Raster Paths for a Variable and Date Range
#'
#' Returns file paths for locally available rasters matching a variable
#' and date range.
#'
#' @param folder Character. Path to the download folder.
#' @param variable Character. Variable code (e.g., "L1-AETI-D").
#' @param start_date Character or Date. Start of date range.
#' @param end_date Character or Date. End of date range.
#' @return Character vector of full file paths, sorted by date.
#' @export
rwapor_get_local_rasters <- function(folder, variable, start_date, end_date) {
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

  # Extract dates and filter by range
  date_patterns <- c(
    "\\.(\\d{4}-\\d{2}-\\d{2})\\.tif$",
    "\\.(\\d{4}\\d{2}\\d{2})\\.tif$"
  )

  file_dates <- data.frame(path = tif_files, date = as.Date(NA), stringsAsFactors = FALSE)

  for (i in seq_along(tif_files)) {
    f <- basename(tif_files[i])
    for (pattern in date_patterns) {
      m <- regmatches(f, regexec(pattern, f))[[1]]
      if (length(m) > 1) {
        date_str <- m[2]
        if (nchar(date_str) == 8) {
          date_str <- gsub("^(\\d{4})(\\d{2})(\\d{2})$", "\\1-\\2-\\3", date_str)
        }
        file_dates$date[i] <- as.Date(date_str)
        break
      }
    }
  }

  # Filter by date range
  file_dates <- file_dates[!is.na(file_dates$date), ]
  file_dates <- file_dates[file_dates$date >= start_date & file_dates$date <= end_date, ]

  # Sort by date
  file_dates <- file_dates[order(file_dates$date), ]

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
rwapor_check_local_files <- function(urls, var, folder) {
  if (length(urls) == 0) return(list(optimized_paths = character(0), missing_dates = character(0), found_count = 0L))
  
  # Standard naming components
  parts <- strsplit(basename(urls[1]), "\\.")[[1]]
  product_base <- if (length(parts) >= 3) {
    paste(parts[1:(length(parts)-2)], collapse = ".")
  } else {
    var
  }
  
  tres_code <- strsplit(var, "-")[[1]][3]
  var_folder <- file.path(folder, var)
  
  optimized_paths <- character(length(urls))
  missing_dates <- character(0)
  found_count <- 0L
  
  for (i in seq_along(urls)) {
    u <- urls[i]
    date_str <- get_date_info(u, tres = tres_code)$start_date
    # Check for both bbox (bb_) and standard versions
    f1 <- file.path(var_folder, paste0(product_base, ".", date_str, ".tif"))
    f2 <- file.path(var_folder, paste0("bb_", product_base, ".", date_str, ".tif"))
    
    if (file.exists(f1)) {
      optimized_paths[i] <- f1
      found_count <- found_count + 1L
    } else if (file.exists(f2)) {
      optimized_paths[i] <- f2
      found_count <- found_count + 1L
    } else {
      optimized_paths[i] <- if (grepl("^/vsicurl/", u)) u else paste0("/vsicurl/", u)
      missing_dates <- c(missing_dates, date_str)
    }
  }
  
  list(optimized_paths = optimized_paths, missing_dates = missing_dates, found_count = found_count)
}
