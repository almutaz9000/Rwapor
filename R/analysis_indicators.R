# =============================================================================
# Analysis Indicator Functions: ETc, Adequacy, Peff, CWP/BWP
# =============================================================================

#' Apply Season-Masked Sum
#'
#' Computes weighted sum of a raster time series using per-dekad season weights.
#'
#' @param x SpatRaster. Multi-layer raster (e.g., dekadal AETI or RET).
#' @param weights SpatRaster. Season weights (0-1), same number of layers as x.
#' @return A single-layer SpatRaster of weighted sums.
#' @export
rwapor_apply_masked_sum <- function(x, weights) {
  if (terra::nlyr(x) != terra::nlyr(weights)) {
    stop(sprintf("Layer count mismatch: x has %d layers, weights has %d layers",
                 terra::nlyr(x), terra::nlyr(weights)), call. = FALSE)
  }
  # Multiply each layer by its weight and sum
  weighted <- x * weights
  terra::app(weighted, fun = "sum", na.rm = TRUE)
}

#' Compute Seasonal AETI with Season Mask
#'
#' Applies dekadal season weights to AETI rasters and optionally
#' summarizes by crop class.
#'
#' @param aeti_dekad SpatRaster. Dekadal AETI layers.
#' @param season_weights SpatRaster. Dekadal season weights (0-1).
#' @param crop_mask SpatRaster. Optional crop mask for per-class summaries.
#' @return A list with:
#'   \describe{
#'     \item{raster}{SpatRaster of seasonal AETI per pixel}
#'     \item{by_class}{data.frame of mean seasonal AETI per crop class (if crop_mask provided)}
#'   }
#' @export
rwapor_calc_seasonal_aeti_masked <- function(aeti_dekad, season_weights,
                                             crop_mask = NULL) {
  seasonal_aeti <- rwapor_apply_masked_sum(aeti_dekad, season_weights)

  by_class <- NULL
  if (!is.null(crop_mask)) {
    by_class <- terra::zonal(seasonal_aeti, crop_mask, fun = "mean", na.rm = TRUE)
    names(by_class) <- c("class_value", "mean_seasonal_aeti")
  }

  list(raster = seasonal_aeti, by_class = by_class)
}

#' Compute Seasonal RET with Season Mask
#'
#' Applies dekadal season weights to RET rasters and optionally
#' summarizes by crop class.
#'
#' @param ret_dekad SpatRaster. Dekadal RET layers.
#' @param season_weights SpatRaster. Dekadal season weights (0-1).
#' @param crop_mask SpatRaster. Optional crop mask for per-class summaries.
#' @return A list with raster and by_class components (same as AETI version).
#' @export
rwapor_calc_seasonal_ret_masked <- function(ret_dekad, season_weights,
                                            crop_mask = NULL) {
  seasonal_ret <- rwapor_apply_masked_sum(ret_dekad, season_weights)

  by_class <- NULL
  if (!is.null(crop_mask)) {
    by_class <- terra::zonal(seasonal_ret, crop_mask, fun = "mean", na.rm = TRUE)
    names(by_class) <- c("class_value", "mean_seasonal_ret")
  }

  list(raster = seasonal_ret, by_class = by_class)
}


# =============================================================================
# ETc Computation
# =============================================================================

#' Compute Dekadal ETc from RET and Kc
#'
#' ETc = RET * Kc for each dekad. Both inputs should have the same
#' number of layers (one per dekad).
#'
#' @param ret_dekad SpatRaster. Dekadal RET layers.
#' @param kc_dekad SpatRaster or numeric vector. Dekadal Kc values.
#'   If a numeric vector, each value is applied uniformly to the
#'   corresponding layer.
#' @return A SpatRaster of dekadal ETc.
#' @export
rwapor_calc_etc_dekad <- function(ret_dekad, kc_dekad) {
  if (is.numeric(kc_dekad)) {
    if (length(kc_dekad) != terra::nlyr(ret_dekad)) {
      stop(sprintf("kc_dekad length (%d) must match ret_dekad layers (%d)",
                   length(kc_dekad), terra::nlyr(ret_dekad)), call. = FALSE)
    }
    # Multiply each layer by corresponding scalar Kc
    layers <- lapply(seq_len(terra::nlyr(ret_dekad)), function(i) {
      ret_dekad[[i]] * kc_dekad[i]
    })
    return(terra::rast(layers))
  }

  # Both are SpatRaster
  if (terra::nlyr(ret_dekad) != terra::nlyr(kc_dekad)) {
    stop("ret_dekad and kc_dekad must have the same number of layers",
         call. = FALSE)
  }
  ret_dekad * kc_dekad
}


# =============================================================================
# Adequacy Indicators
# =============================================================================

#' Compute ETc-Based Adequacy
#'
#' Adequacy_ETc = Seasonal_AETI / Seasonal_ETc
#'
#' @param aeti_seasonal SpatRaster or numeric. Seasonal AETI.
#' @param etc_seasonal SpatRaster or numeric. Seasonal ETc.
#' @return SpatRaster or numeric of adequacy ratio.
#' @export
rwapor_calc_adequacy_etc <- function(aeti_seasonal, etc_seasonal) {
  # Avoid division by zero
  if (inherits(etc_seasonal, "SpatRaster")) {
    etc_safe <- terra::ifel(etc_seasonal == 0, NA, etc_seasonal)
  } else {
    etc_safe <- ifelse(etc_seasonal == 0, NA, etc_seasonal)
  }
  aeti_seasonal / etc_safe
}

#' Compute P95 of AETI Within Crop Class
#'
#' Extracts the 95th percentile of seasonal AETI for each crop class.
#'
#' @param aeti_seasonal SpatRaster. Seasonal AETI raster.
#' @param crop_mask SpatRaster. Crop mask with integer class values.
#' @param min_pixels Integer. Minimum pixel count to compute P95.
#'   Classes with fewer pixels return NA. Default 30.
#' @return A data.frame with columns: class_value, p95_aeti, n_pixels, valid.
#' @export
rwapor_calc_class_p95_aeti <- function(aeti_seasonal, crop_mask,
                                       min_pixels = 30L) {
  classes <- terra::freq(crop_mask)
  classes <- classes[!is.na(classes$value), , drop = FALSE]

  result <- data.frame(
    class_value = as.integer(classes$value),
    p95_aeti    = NA_real_,
    n_pixels    = as.integer(classes$count),
    valid       = FALSE,
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(result))) {
    cls <- result$class_value[i]
    if (result$n_pixels[i] < min_pixels) next

    # Extract AETI values for this class
    mask_i <- terra::ifel(crop_mask == cls, 1L, NA)
    aeti_masked <- aeti_seasonal * mask_i
    vals <- terra::values(aeti_masked, na.rm = TRUE)
    if (length(vals) >= min_pixels) {
      result$p95_aeti[i] <- as.numeric(stats::quantile(vals, 0.95, na.rm = TRUE))
      result$valid[i] <- TRUE
    }
  }
  result
}

#' Compute P95-Based Adequacy
#'
#' Adequacy_P95 = Seasonal_AETI / P95(Seasonal_AETI within crop class)
#'
#' @param aeti_seasonal SpatRaster. Seasonal AETI raster.
#' @param crop_mask SpatRaster. Crop mask.
#' @param p95_table data.frame. Output from rwapor_calc_class_p95_aeti().
#' @return A SpatRaster of P95-based adequacy.
#' @export
rwapor_calc_adequacy_p95 <- function(aeti_seasonal, crop_mask, p95_table) {
  # Build a raster of P95 values mapped from crop class
  p95_rast <- terra::classify(
    crop_mask,
    rcl = cbind(p95_table$class_value, p95_table$p95_aeti)
  )
  # Avoid division by zero
  p95_safe <- terra::ifel(p95_rast == 0 | is.na(p95_rast), NA, p95_rast)
  aeti_seasonal / p95_safe
}


# =============================================================================
# Effective Precipitation (FAO USDA Monthly Method)
# =============================================================================

#' Aggregate Precipitation to Monthly Totals
#'
#' @param precip_ts data.frame with columns: date, value (daily or dekadal precip).
#' @return A data.frame with columns: year, month, p_monthly_mm.
#' @export
rwapor_aggregate_precip_monthly <- function(precip_ts) {
  if (!all(c("date", "value") %in% names(precip_ts))) {
    stop("precip_ts must have 'date' and 'value' columns", call. = FALSE)
  }
  precip_ts$date <- as.Date(precip_ts$date)
  precip_ts$year <- as.integer(format(precip_ts$date, "%Y"))
  precip_ts$month <- as.integer(format(precip_ts$date, "%m"))

  monthly <- stats::aggregate(value ~ year + month, data = precip_ts, FUN = sum,
                               na.rm = TRUE)
  names(monthly)[3] <- "p_monthly_mm"
  monthly[order(monthly$year, monthly$month), ]
}

#' Compute Monthly Effective Precipitation (FAO USDA Method)
#'
#' Applies the USDA SCS formula from FAO:
#' - If P <= 250 mm/month: Peff = P * (125 - 0.2 * P) / 125
#' - If P > 250 mm/month:  Peff = 125 + 0.1 * P
#'
#' @param p_monthly Numeric vector of monthly precipitation in mm.
#' @return Numeric vector of monthly effective precipitation in mm.
#' @export
#' @examples
#' rwapor_calc_peff_usda_monthly(c(50, 120, 300))
rwapor_calc_peff_usda_monthly <- function(p_monthly) {
  ifelse(p_monthly <= 250,
         p_monthly * (125 - 0.2 * p_monthly) / 125,
         125 + 0.1 * p_monthly)
}

#' Compute Seasonal Effective Precipitation
#'
#' Sums monthly Peff values over the season months or a specific date interval.
#'
#' @param peff_monthly data.frame with columns: year, month, peff_mm.
#' @param start_date Date or character. Optional start of season.
#' @param end_date Date or character. Optional end of season.
#' @param season_months Integer vector. Legacy month numbers.
#' @param season_year Integer. Legacy season year.
#' @return Numeric. Total seasonal effective precipitation in mm.
#' @export
rwapor_calc_peff_seasonal <- function(peff_monthly, start_date = NULL,
                                      end_date = NULL, season_months = NULL,
                                      season_year = NULL) {
  if (!is.null(start_date) && !is.null(end_date)) {
    # Use explicit dates
    s_date <- as.Date(start_date)
    e_date <- as.Date(end_date)
    
    # Create month-start dates for comparison
    peff_monthly$date <- as.Date(sprintf("%04d-%02d-01", peff_monthly$year, peff_monthly$month))
    
    # Filter months that fall within the interval (at least partially)
    # We include a month if its start is between s_date and e_date 
    # OR if s_date/e_date fall within that month.
    # Simplified: match months whose first day is between floored-start and floored-end.
    month_start_s <- lubridate::floor_date(s_date, "month")
    month_start_e <- lubridate::floor_date(e_date, "month")
    
    subset_df <- peff_monthly[peff_monthly$date >= month_start_s & 
                                peff_monthly$date <= month_start_e, ]
  } else {
    # Legacy support
    subset_df <- peff_monthly[peff_monthly$year == season_year &
                                peff_monthly$month %in% season_months, ]
  }
  sum(subset_df$peff_mm, na.rm = TRUE)
}


# =============================================================================
# Crop and Biomass Water Productivity
# =============================================================================

#' Compute Crop Water Productivity
#'
#' CWP = Yield / AETI, with unit conversion to kg/m3.
#' AETI in mm is equivalent to l/m2; 1 mm = 10 m3/ha.
#'
#' @param yield_value Numeric. Yield (scalar or raster).
#' @param aeti_mm Numeric. Seasonal AETI in mm (scalar or raster).
#' @param yield_unit Character. Unit of yield: "kg/ha" (default) or "t/ha".
#' @return Numeric or SpatRaster. CWP in kg/m3.
#' @export
#' @examples
#' rwapor_calc_cwp(5000, 400)  # 5000 kg/ha, 400 mm -> kg/m3
rwapor_calc_cwp <- function(yield_value, aeti_mm, yield_unit = "kg/ha") {
  # Convert yield to kg/ha if needed
  if (tolower(yield_unit) == "t/ha") {
    yield_value <- yield_value * 1000
  }
  # Convert AETI from mm to m3/ha: 1 mm = 10 m3/ha
  aeti_m3_ha <- aeti_mm * 10

  # Avoid division by zero
  if (inherits(aeti_m3_ha, "SpatRaster")) {
    aeti_safe <- terra::ifel(aeti_m3_ha == 0, NA, aeti_m3_ha)
  } else {
    aeti_safe <- ifelse(aeti_m3_ha == 0, NA, aeti_m3_ha)
  }
  yield_value / aeti_safe
}

#' Compute Biomass Water Productivity
#'
#' BWP = Biomass / AETI, with unit conversion to kg/m3.
#'
#' @param biomass_value Numeric. Biomass (scalar or raster).
#' @param aeti_mm Numeric. Seasonal AETI in mm (scalar or raster).
#' @param biomass_unit Character. Unit: "kg/ha" (default) or "t/ha".
#' @return Numeric or SpatRaster. BWP in kg/m3.
#' @export
#' @examples
#' rwapor_calc_bwp(12000, 400)  # 12000 kg/ha biomass, 400 mm -> kg/m3
rwapor_calc_bwp <- function(biomass_value, aeti_mm, biomass_unit = "kg/ha") {
  if (tolower(biomass_unit) == "t/ha") {
    biomass_value <- biomass_value * 1000
  }
  aeti_m3_ha <- aeti_mm * 10
  if (inherits(aeti_m3_ha, "SpatRaster")) {
    aeti_safe <- terra::ifel(aeti_m3_ha == 0, NA, aeti_m3_ha)
  } else {
    aeti_safe <- ifelse(aeti_m3_ha == 0, NA, aeti_m3_ha)
  }
  biomass_value / aeti_safe
}

#' Convert NPP to Total Biomass Production (TBP)
#'
#' Converts seasonal NPP (gC/m2) to TBP (kgDM/ha) using the
#' factor 22.222.
#'
#' @param npp_gc_m2 Numeric. Seasonal sum of NPP in gC/m2.
#' @return Numeric. TBP in kgDM/ha.
#' @export
rwapor_convert_npp_to_tbp <- function(npp_gc_m2) {
  npp_gc_m2 * 22.222
}

#' Calculate Crop Yield from NPP
#'
#' Implementation of the provided yield formula based on NPP:
#' AGBM = (AOT * fc * (NPP * 22.222 / (1 - MC))) / 1000
#' CropYield = HI * AGBM
#'
#' @param npp_gc_m2 Numeric. Seasonal sum of NPP in gC/m2.
#' @param MC Numeric. Moisture content (0-1).
#' @param fc Numeric. Light use efficiency correction factor.
#' @param AOT Numeric. Above ground over total biomass production ratio.
#' @param HI Numeric. Harvest index.
#' @return Numeric. Crop yield in t/ha.
#' @export
rwapor_calc_yield_npp <- function(npp_gc_m2, MC, fc, AOT, HI) {
  # NPP * 22.222 converts gC/m2 to kgDM/ha (DMP)
  dmp <- npp_gc_m2 * 22.222
  # Calculate Above Ground Biomass (ton/ha)
  agbm <- (AOT * fc * (dmp / (1 - MC))) / 1000
  # Calculate Yield
  yield <- HI * agbm
  yield
}


# =============================================================================
# Analysis Time Series Helpers
# =============================================================================

#' Prepare Analysis Time Series Data
#'
#' Uses the existing wapor_ts() function to fetch AETI, RET, and precipitation
#' time series for the analysis AOI.
#'
#' @param region Region definition (bbox, vector file, or L3 code).
#' @param aeti_var Character. AETI variable name (e.g., "L1-AETI-D").
#' @param ret_var Character. RET variable name (e.g., "L1-RET-D").
#' @param precip_var Character. Precipitation variable name (e.g., "L1-PCP-D").
#' @param period Character vector of length 2: c(start_date, end_date).
#' @return A list with data.frames: aeti_ts, ret_ts, precip_ts.
#' @export
rwapor_prepare_analysis_ts <- function(region, aeti_var, ret_var, precip_var,
                                       period) {
  aeti_ts <- wapor_ts(region = region, variable = aeti_var, period = period,
                       unit_conversion = "none")
  ret_ts <- wapor_ts(region = region, variable = ret_var, period = period,
                      unit_conversion = "none")
  precip_ts <- wapor_ts(region = region, variable = precip_var, period = period,
                         unit_conversion = "none")
  list(aeti_ts = aeti_ts, ret_ts = ret_ts, precip_ts = precip_ts)
}

#' Merge Analysis Time Series on Common Time Axis
#'
#' Joins AETI, RET, and precipitation data.frames on their start_date column.
#'
#' @param aeti_ts data.frame from wapor_ts().
#' @param ret_ts data.frame from wapor_ts().
#' @param precip_ts data.frame from wapor_ts().
#' @return A merged data.frame.
#' @export
rwapor_merge_analysis_timeseries <- function(aeti_ts, ret_ts, precip_ts) {
  # Rename value columns to avoid collision
  aeti_sub <- data.frame(
    start_date = aeti_ts$start_date,
    end_date   = aeti_ts$end_date,
    aeti_mean  = aeti_ts$mean,
    stringsAsFactors = FALSE
  )
  ret_sub <- data.frame(
    start_date = ret_ts$start_date,
    ret_mean   = ret_ts$mean,
    stringsAsFactors = FALSE
  )
  precip_sub <- data.frame(
    start_date  = precip_ts$start_date,
    precip_mean = precip_ts$mean,
    stringsAsFactors = FALSE
  )

  merged <- merge(aeti_sub, ret_sub, by = "start_date", all = TRUE)
  merged <- merge(merged, precip_sub, by = "start_date", all = TRUE)
  merged[order(as.Date(merged$start_date)), ]
}
