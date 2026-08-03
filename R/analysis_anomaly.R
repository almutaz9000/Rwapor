# =============================================================================
# Spatial Anomaly Detection Functions
# =============================================================================

#' Detect AETI Anomalies Relative to Class Median
#'
#' Identifies pixels where AETI is significantly below the class median,
#' indicating potential water stress or irrigation failures.
#'
#' @param aeti_seasonal SpatRaster. Seasonal AETI raster.
#' @param crop_mask SpatRaster. Crop mask with integer class values.
#' @param threshold Numeric. Fraction of median below which pixels are flagged (default 0.5 = 50%).
#' @param min_pixels Integer. Minimum pixels per class to compute reliable median (default 30).
#' @return A list with:
#'   \describe{
#'     \item{anomaly_map}{SpatRaster. 1 = anomaly, 0 = normal, NA = excluded}
#'     \item{anomaly_stats}{data.frame. Per-class anomaly statistics}
#'     \item{threshold_raster}{SpatRaster. Threshold values per class}
#'   }
#' @export
#' @examples
#' \dontrun{
#' anomalies <- wapor_detect_aeti_anomalies(seasonal_aeti, crop_mask, threshold = 0.6)
#' plot(anomalies$anomaly_map, main = "Water Stress Anomalies")
#' }
wapor_detect_aeti_anomalies <- function(aeti_seasonal, crop_mask, 
                                        threshold = 0.5, min_pixels = 30) {
  
  if (!inherits(aeti_seasonal, "SpatRaster")) {
    stop("aeti_seasonal must be a SpatRaster", call. = FALSE)
  }
  
  if (!inherits(crop_mask, "SpatRaster")) {
    stop("crop_mask must be a SpatRaster", call. = FALSE)
  }
  
  if (threshold <= 0 || threshold >= 1) {
    stop("threshold must be between 0 and 1", call. = FALSE)
  }
  
  # Compute per-class medians
  class_medians <- terra::zonal(aeti_seasonal, crop_mask, fun = "median", na.rm = TRUE)
  names(class_medians) <- c("class_value", "median_aeti")
  
  # Count valid pixels per class
  # Optimization: Using unary logical operator `!is.na()` is significantly faster
  # than `terra::ifel(is.na(...))` as it avoids conditional branch evaluation overhead.
  valid_count_rast <- !is.na(aeti_seasonal)
  class_counts <- terra::zonal(valid_count_rast, crop_mask, fun = "sum", na.rm = TRUE)
  names(class_counts) <- c("class_value", "pixel_count")
  
  # Filter classes with sufficient data
  stats <- merge(class_medians, class_counts, by = "class_value")
  stats$valid <- stats$pixel_count >= min_pixels
  stats$threshold_value <- stats$median_aeti * threshold
  
  # Build threshold raster (median * threshold per class)
  threshold_raster <- terra::classify(
    crop_mask,
    rcl = cbind(stats$class_value, stats$threshold_value)
  )
  
  # Identify anomalies: AETI < threshold_value
  anomaly_map <- terra::ifel(
    aeti_seasonal < threshold_raster & !is.na(aeti_seasonal),
    1L, 0L
  )
  
  # Mask out classes with insufficient data
  invalid_classes <- stats$class_value[!stats$valid]
  if (length(invalid_classes) > 0) {
    for (cls in invalid_classes) {
      anomaly_map <- terra::ifel(crop_mask == cls, NA, anomaly_map)
    }
  }
  
  # Compute anomaly statistics per class
  anomaly_counts <- terra::zonal(anomaly_map, crop_mask, fun = "sum", na.rm = TRUE)
  names(anomaly_counts) <- c("class_value", "anomaly_pixels")
  
  stats <- merge(stats, anomaly_counts, by = "class_value", all.x = TRUE)
  stats$anomaly_pixels[is.na(stats$anomaly_pixels)] <- 0L
  stats$anomaly_fraction <- stats$anomaly_pixels / stats$pixel_count
  
  # Compute mean AETI for anomaly pixels
  aeti_in_anomaly <- aeti_seasonal * anomaly_map
  anomaly_means <- terra::zonal(aeti_in_anomaly, crop_mask, fun = "mean", na.rm = TRUE)
  names(anomaly_means) <- c("class_value", "mean_anomaly_aeti")
  
  stats <- merge(stats, anomaly_means, by = "class_value", all.x = TRUE)
  
  list(
    anomaly_map = anomaly_map,
    anomaly_stats = stats[, c("class_value", "median_aeti", "threshold_value",
                              "pixel_count", "anomaly_pixels", "anomaly_fraction",
                              "mean_anomaly_aeti", "valid")],
    threshold_raster = threshold_raster
  )
}

#' Detect Multi-Indicator Anomalies
#'
#' Combines multiple indicators to identify areas with compound stress
#' (e.g., low AETI + low adequacy + low yield).
#'
#' @param indicators List with SpatRasters: aeti, adequacy, yield (optional).
#' @param crop_mask SpatRaster. Crop mask.
#' @param thresholds Named numeric vector. Thresholds per indicator 
#'   (e.g., c(aeti = 0.5, adequacy = 0.7)).
#' @return A list with compound anomaly map and statistics.
#' @export
wapor_detect_compound_anomalies <- function(indicators, crop_mask, 
                                            thresholds = c(aeti = 0.5, adequacy = 0.7)) {
  
  if (!is.list(indicators)) {
    stop("indicators must be a list of SpatRasters", call. = FALSE)
  }
  
  # Initialize compound anomaly as logical raster
  compound_anomaly <- NULL
  detected_indicators <- character()
  
  # Check AETI
  if ("aeti" %in% names(indicators) && "aeti" %in% names(thresholds)) {
    aeti_result <- wapor_detect_aeti_anomalies(
      indicators$aeti, crop_mask, threshold = thresholds["aeti"]
    )
    compound_anomaly <- if (is.null(compound_anomaly)) {
      aeti_result$anomaly_map == 1
    } else {
      compound_anomaly & (aeti_result$anomaly_map == 1)
    }
    detected_indicators <- c(detected_indicators, "AETI")
  }
  
  # Check adequacy
  if ("adequacy" %in% names(indicators) && "adequacy" %in% names(thresholds)) {
    adequacy_median <- terra::zonal(indicators$adequacy, crop_mask, fun = "median", na.rm = TRUE)
    names(adequacy_median) <- c("class_value", "median_adequacy")
    
    adequacy_threshold_raster <- terra::classify(
      crop_mask,
      rcl = cbind(adequacy_median$class_value, 
                  adequacy_median$median_adequacy * thresholds["adequacy"])
    )
    
    adequacy_anomaly <- indicators$adequacy < adequacy_threshold_raster
    
    compound_anomaly <- if (is.null(compound_anomaly)) {
      adequacy_anomaly
    } else {
      compound_anomaly & adequacy_anomaly
    }
    detected_indicators <- c(detected_indicators, "Adequacy")
  }
  
  # Convert to integer raster
  if (!is.null(compound_anomaly)) {
    compound_anomaly <- terra::ifel(compound_anomaly, 1L, 0L)
  } else {
    stop("No valid indicators found in input list", call. = FALSE)
  }
  
  # Compute statistics
  anomaly_counts <- terra::zonal(compound_anomaly, crop_mask, fun = "sum", na.rm = TRUE)
  names(anomaly_counts) <- c("class_value", "compound_anomaly_pixels")
  
  # Optimization: Using unary logical operator `!is.na()` is significantly faster
  # than `terra::ifel(is.na(...))` as it avoids conditional branch evaluation overhead.
  class_counts <- terra::zonal(
    !is.na(compound_anomaly),
    crop_mask, fun = "sum", na.rm = TRUE
  )
  names(class_counts) <- c("class_value", "total_pixels")
  
  stats <- merge(anomaly_counts, class_counts, by = "class_value")
  stats$compound_anomaly_fraction <- stats$compound_anomaly_pixels / stats$total_pixels
  
  list(
    compound_anomaly_map = compound_anomaly,
    stats = stats,
    indicators_used = detected_indicators,
    thresholds = thresholds
  )
}

#' Relative Anomaly Detection
#'
#' Flags pixels that deviate significantly from the class mean using z-scores.
#'
#' @param value_raster SpatRaster. Values to check for anomalies.
#' @param crop_mask SpatRaster. Crop mask.
#' @param z_threshold Numeric. Z-score threshold for flagging (default 2 = 2 std devs).
#' @param direction Character. "below" (default), "above", or "both".
#' @return A list with anomaly map and z-score raster.
#' @export
wapor_detect_zscore_anomalies <- function(value_raster, crop_mask, 
                                          z_threshold = 2, direction = "below") {
  
  # Compute per-class mean and SD
  class_means <- terra::zonal(value_raster, crop_mask, fun = "mean", na.rm = TRUE)
  names(class_means) <- c("class_value", "mean_value")
  
  class_sds <- terra::zonal(value_raster, crop_mask, fun = "sd", na.rm = TRUE)
  names(class_sds) <- c("class_value", "sd_value")
  
  stats <- merge(class_means, class_sds, by = "class_value")
  
  # Build mean and SD rasters
  mean_raster <- terra::classify(crop_mask, cbind(stats$class_value, stats$mean_value))
  sd_raster <- terra::classify(crop_mask, cbind(stats$class_value, stats$sd_value))
  
  # Compute z-scores
  z_score <- (value_raster - mean_raster) / sd_raster
  
  # Flag anomalies based on direction
  if (direction == "below") {
    anomaly_map <- terra::ifel(z_score < -z_threshold, 1L, 0L)
  } else if (direction == "above") {
    anomaly_map <- terra::ifel(z_score > z_threshold, 1L, 0L)
  } else if (direction == "both") {
    anomaly_map <- terra::ifel(abs(z_score) > z_threshold, 1L, 0L)
  } else {
    stop("direction must be 'below', 'above', or 'both'", call. = FALSE)
  }
  
  list(
    anomaly_map = anomaly_map,
    z_score_raster = z_score,
    stats = stats,
    threshold = z_threshold,
    direction = direction
  )
}

#' Spatial Hotspot Analysis
#'
#' Identifies spatial clusters of low AETI values using local neighborhood analysis.
#'
#' @param aeti_seasonal SpatRaster. Seasonal AETI raster.
#' @param window_size Integer. Size of focal window (default 5 = 5x5 pixels).
#' @param threshold Numeric. Fraction of focal median below which center pixel is flagged.
#' @return A list with hotspot map and focal statistics.
#' @export
wapor_detect_spatial_hotspots <- function(aeti_seasonal, window_size = 5, 
                                          threshold = 0.5) {
  
  if (!inherits(aeti_seasonal, "SpatRaster")) {
    stop("aeti_seasonal must be a SpatRaster", call. = FALSE)
  }
  
  # Compute focal median
  w <- matrix(1, nrow = window_size, ncol = window_size)
  focal_median <- terra::focal(aeti_seasonal, w = w, fun = "median", na.rm = TRUE)
  
  # Flag pixels below threshold * focal_median
  hotspot_map <- terra::ifel(
    aeti_seasonal < (focal_median * threshold) & !is.na(aeti_seasonal),
    1L, 0L
  )
  
  # Compute hotspot cluster sizes using connected components
  # This requires additional processing - simplified version:
  hotspot_count <- terra::global(hotspot_map, "sum", na.rm = TRUE)$sum
  total_pixels <- terra::global(!is.na(aeti_seasonal), "sum", na.rm = TRUE)$sum
  
  list(
    hotspot_map = hotspot_map,
    focal_median = focal_median,
    hotspot_pixel_count = hotspot_count,
    hotspot_fraction = hotspot_count / total_pixels,
    window_size = window_size,
    threshold = threshold
  )
}
