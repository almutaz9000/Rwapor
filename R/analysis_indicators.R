# =============================================================================
# Analysis Indicator Functions: ETc, Adequacy, Peff, CWP/BWP
# =============================================================================

#' Apply Season-Masked Sum
#'
#' Computes weighted sum of a raster time series using per-dekad season weights.
#'
#' @param x SpatRaster. Multi-layer raster (e.g., dekadal AETI or RET).
#' @param weights SpatRaster. Season weights (0-1), same number of layers as x.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#'   Use this for rate variables stored per day where a weighted sum must be
#'   multiplied by the full slice length.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#'   Recommended for very long seasons or low RAM. Default FALSE.
#' @return A single-layer SpatRaster of weighted sums.
#' @export
wapor_masked_sum <- function(x, weights, layer_multipliers = NULL, incremental = FALSE) {
  if (terra::nlyr(x) != terra::nlyr(weights)) {
    stop(sprintf("Layer count mismatch: x has %d layers, weights has %d layers",
                 terra::nlyr(x), terra::nlyr(weights)), call. = FALSE)
  }

  if (is.null(layer_multipliers)) {
    layer_multipliers <- rep(1, terra::nlyr(x))
  }
  if (length(layer_multipliers) != terra::nlyr(x)) {
    stop(sprintf("layer_multipliers length (%d) must match x layers (%d)",
                 length(layer_multipliers), terra::nlyr(x)), call. = FALSE)
  }

  if (incremental) {
    total <- NULL
    for (i in seq_len(terra::nlyr(x))) {
      current <- x[[i]] * (weights[[i]] * layer_multipliers[i])
      if (is.null(total)) total <- current else total <- total + current
    }
    return(total)
  }

  # Multiply each layer by its weight and sum (faster but uses more peak disk/RAM)
  weighted <- x * weights
  if (!all(layer_multipliers == 1)) {
    weighted <- weighted * layer_multipliers
  }
  # Optimization: terra::sum() is significantly faster than terra::app(..., fun="sum")
  # as it uses a dedicated C++ implementation for layer-wise summation.
  terra::sum(weighted, na.rm = TRUE)
}

#' Compute Seasonal AETI with Season Mask
#'
#' Applies dekadal season weights to AETI rasters and optionally
#' summarizes by crop class.
#'
#' @param aeti_dekad SpatRaster. Dekadal AETI layers.
#' @param season_weights SpatRaster. Dekadal season weights (0-1).
#' @param crop_mask SpatRaster. Optional crop mask for per-class summaries.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#' @return A list with:
#'   \describe{
#'     \item{raster}{SpatRaster of seasonal AETI per pixel}
#'     \item{by_class}{data.frame of mean seasonal AETI per crop class (if crop_mask provided)}
#'   }
#' @export
wapor_calc_seasonal_aeti <- function(aeti_dekad, season_weights,
                                             crop_mask = NULL, layer_multipliers = NULL,
                                             incremental = FALSE) {
  seasonal_aeti <- wapor_masked_sum(
    aeti_dekad,
    season_weights,
    layer_multipliers = layer_multipliers,
    incremental = incremental
  )

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
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#' @return A list with raster and by_class components (same as AETI version).
#' @export
wapor_calc_seasonal_ret <- function(ret_dekad, season_weights,
                                            crop_mask = NULL, layer_multipliers = NULL,
                                            incremental = FALSE) {
  seasonal_ret <- wapor_masked_sum(
    ret_dekad,
    season_weights,
    layer_multipliers = layer_multipliers,
    incremental = incremental
  )

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
wapor_calc_etc <- function(ret_dekad, kc_dekad) {
  ret_dekad * kc_dekad
}

#' Compute Seasonal ETc Incrementally
#'
#' Avoids building a full multi-layer ETc stack by accumulating
#' RET * season_weight * kc layer-by-layer. This is significantly more
#' memory-efficient for long seasons.
#'
#' @param ret_dekad SpatRaster. Dekadal RET layers.
#' @param season_weights SpatRaster. Dekadal season weights (0-1).
#' @param kc_dekad Numeric vector. Dekadal Kc values.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#'   Default FALSE.
#' @return A single-layer SpatRaster of seasonal ETc (weighted sum).
#' @export
wapor_calc_seasonal_etc <- function(ret_dekad, season_weights, kc_dekad,
                                                 layer_multipliers = NULL,
                                                 incremental = FALSE) {
  n_layers <- terra::nlyr(ret_dekad)
  if (length(kc_dekad) != n_layers) {
    stop(sprintf("kc_dekad length (%d) must match ret_dekad layers (%d)",
                 length(kc_dekad), n_layers), call. = FALSE)
  }
  if (terra::nlyr(season_weights) != n_layers) {
    stop(sprintf("season_weights layers (%d) must match ret_dekad layers (%d)",
                 terra::nlyr(season_weights), n_layers), call. = FALSE)
  }
  if (is.null(layer_multipliers)) {
    layer_multipliers <- rep(1, n_layers)
  }
  if (length(layer_multipliers) != n_layers) {
    stop(sprintf("layer_multipliers length (%d) must match ret_dekad layers (%d)",
                 length(layer_multipliers), n_layers), call. = FALSE)
  }

  if (incremental) {
    total <- NULL
    for (i in seq_len(n_layers)) {
      # Accumulate: term = RET_i * (weight_i * Kc_i * multiplier_i)
      # Parentheses ensure numeric scalars are combined before multiplying with rasters
      term <- ret_dekad[[i]] * (season_weights[[i]] * (kc_dekad[i] * layer_multipliers[i]))

      if (is.null(total)) {
        total <- term
      } else {
        total <- total + term
      }
    }
    return(total)
  }

  # Optimization: Vectorized stack multiplication and specialized summation.
  # Multiplying the entire stack by a weight vector and then using terra::sum
  # is significantly faster than an R-level loop as it executes in a single C++ pass.
  # We use na.rm = FALSE to ensure strict NA propagation (scientific integrity).
  combined_multipliers <- kc_dekad * layer_multipliers
  weighted <- ret_dekad * (season_weights * combined_multipliers)
  terra::sum(weighted, na.rm = FALSE)
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
wapor_calc_adequacy_etc <- function(aeti_seasonal, etc_seasonal) {
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
wapor_calc_p95_aeti <- function(aeti_seasonal, crop_mask,
                                       min_pixels = 30L) {
  # Fast grouped quantile calculation using terra::zonal
  # Note: zonal only works with functions that return a single value
  p95_vals <- terra::zonal(aeti_seasonal, crop_mask, fun = function(x) {
    x <- x[!is.na(x)]
    if (length(x) < min_pixels) return(NA_real_)
    stats::quantile(x, 0.95, na.rm = TRUE)
  })

  # Count valid analysis pixels, not just mask pixels.
  valid_count_rast <- terra::ifel(is.na(aeti_seasonal), 0L, 1L)
  count_vals <- terra::zonal(valid_count_rast, crop_mask, fun = "sum", na.rm = TRUE)
  count_vals <- as.data.frame(count_vals)
  names(count_vals)[seq_len(min(2, ncol(count_vals)))] <- c("class_value", "n_pixels")[seq_len(min(2, ncol(count_vals)))]
  
  # Merge results
  result <- data.frame(
    class_value = as.integer(p95_vals[[1]]),
    p95_aeti    = as.numeric(p95_vals[[2]]),
    stringsAsFactors = FALSE
  )
  
  # Add counts and valid flag
  result <- merge(result, count_vals[, c("class_value", "n_pixels")], by = "class_value", all.x = TRUE)
  
  result$n_pixels <- as.integer(result$n_pixels)
  result$valid <- !is.na(result$p95_aeti) & result$n_pixels >= min_pixels
  
  result[, c("class_value", "p95_aeti", "n_pixels", "valid")]
}

#' Compute P95-Based Adequacy
#'
#' Adequacy_P95 = Seasonal_AETI / P95(Seasonal_AETI within crop class)
#'
#' @param aeti_seasonal SpatRaster. Seasonal AETI raster.
#' @param crop_mask SpatRaster. Crop mask.
#' @param p95_table data.frame. Output from wapor_calc_p95_aeti().
#' @return A SpatRaster of P95-based adequacy.
#' @export
wapor_calc_adequacy_p95 <- function(aeti_seasonal, crop_mask, p95_table) {
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
wapor_aggregate_precip <- function(precip_ts) {
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
#' wapor_calc_peff_usda(c(50, 120, 300))
wapor_calc_peff_usda <- function(p_monthly) {
  ifelse(p_monthly <= 250,
         p_monthly * (125 - 0.2 * p_monthly) / 125,
         125 + 0.1 * p_monthly)
}

#' Compute Seasonal Effective Precipitation
#'
#' Sums monthly Peff values over the season months, pro-rating the first and 
#' last months if they are only partially within the season dates.
#'
#' @param peff_monthly data.frame with columns: year, month, peff_mm.
#' @param start_date Date or character. Start of season.
#' @param end_date Date or character. End of season.
#' @param season_months Integer vector. Legacy month numbers.
#' @param season_year Integer. Legacy season year.
#' @return Numeric. Total seasonal effective precipitation in mm.
#' @export
wapor_calc_peff <- function(peff_monthly, start_date = NULL,
                                      end_date = NULL, season_months = NULL,
                                      season_year = NULL) {
  if (!is.null(start_date) && !is.null(end_date)) {
    s_date <- as.Date(start_date)
    e_date <- as.Date(end_date)
    
    # Create month-start dates for comparison
    peff_monthly$date <- as.Date(sprintf("%04d-%02d-01", peff_monthly$year, peff_monthly$month))
    peff_monthly$days_in_month <- lubridate::days_in_month(peff_monthly$date)
    
    # Filter months that fall within the interval (at least partially)
    month_start_s <- lubridate::floor_date(s_date, "month")
    month_start_e <- lubridate::floor_date(e_date, "month")
    
    peff_monthly$overlap_days <- vapply(seq_len(nrow(peff_monthly)), function(i) {
      m_start <- peff_monthly$date[i]
      m_end <- m_start + (peff_monthly$days_in_month[i] - 1)
      
      overlap_start <- max(m_start, s_date)
      overlap_end   <- min(m_end, e_date)
      
      diff <- as.integer(overlap_end - overlap_start) + 1L
      max(0L, diff)
    }, integer(1))
    
    # Pro-rate: seasonal_peff = sum(peff_monthly * (overlap_days / days_in_month))
    subset_df <- peff_monthly[peff_monthly$overlap_days > 0, ]
    sum(subset_df$peff_mm * (subset_df$overlap_days / subset_df$days_in_month), na.rm = TRUE)
  } else {
    # Legacy support
    subset_df <- peff_monthly[peff_monthly$year == season_year &
                                peff_monthly$month %in% season_months, ]
    sum(subset_df$peff_mm, na.rm = TRUE)
  }
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
#' wapor_calc_cwp(5000, 400)  # 5000 kg/ha, 400 mm -> kg/m3
wapor_calc_cwp <- function(yield_value, aeti_mm, yield_unit = "kg/ha") {
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
#' wapor_calc_bwp(12000, 400)  # 12000 kg/ha biomass, 400 mm -> kg/m3
wapor_calc_bwp <- function(biomass_value, aeti_mm, biomass_unit = "kg/ha") {
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

# =============================================================================
# Green and Blue Water Consumption
# =============================================================================

#' Compute Green Water Consumption
#'
#' Green water = min(AETI, Peff) — the portion of actual evapotranspiration
#' sourced from effective precipitation (rainfall stored in the soil).
#'
#' @param aeti_seasonal SpatRaster or numeric. Seasonal AETI (mm).
#' @param peff_seasonal SpatRaster or numeric. Seasonal effective precipitation (mm).
#' @return SpatRaster or numeric. Green water consumption (mm).
#' @export
#' @examples
#' wapor_calc_green_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 200 mm green water
wapor_calc_green_water <- function(aeti_seasonal, peff_seasonal) {
  if (inherits(aeti_seasonal, "SpatRaster")) {
    terra::ifel(aeti_seasonal <= peff_seasonal, aeti_seasonal, peff_seasonal)
  } else {
    pmin(aeti_seasonal, peff_seasonal)
  }
}

#' Compute Blue Water Consumption
#'
#' Blue water = max(0, AETI - Peff) — the portion of actual evapotranspiration
#' sourced from irrigation (surface water or groundwater).
#'
#' @param aeti_seasonal SpatRaster or numeric. Seasonal AETI (mm).
#' @param peff_seasonal SpatRaster or numeric. Seasonal effective precipitation (mm).
#' @return SpatRaster or numeric. Blue water consumption (mm).
#' @export
#' @examples
#' wapor_calc_blue_water(350, 200)  # 350 mm AETI, 200 mm Peff -> 150 mm blue water
wapor_calc_blue_water <- function(aeti_seasonal, peff_seasonal) {
  diff_val <- aeti_seasonal - peff_seasonal
  if (inherits(diff_val, "SpatRaster")) {
    terra::ifel(diff_val > 0, diff_val, 0)
  } else {
    pmax(diff_val, 0)
  }
}


#' Convert NPP to Total Biomass Production (TBP)
#'
#' Converts seasonal NPP (gC/m2) to TBP (kgDM/ha) using the
#' factor 22.222.
#'
#' @param npp_gc_m2 Numeric. Seasonal sum of NPP in gC/m2.
#' @return Numeric. TBP in kgDM/ha.
#' @export
wapor_convert_npp_tbp <- function(npp_gc_m2) {
  npp_gc_m2 * 22.222
}

#' Calculate Crop Yield from NPP
#'
#' Implementation of the provided yield formula based on NPP:
#' AGBM = (aot * fc * (NPP * 22.222 / (1 - MC))) / 1000
#' CropYield = HI * AGBM
#'
#' @param npp_gc_m2 Numeric. Seasonal sum of NPP in gC/m2.
#' @param mc Numeric. Moisture content (0-1).
#' @param fc Numeric. Light use efficiency correction factor.
#' @param aot Numeric. Above ground over total biomass production ratio.
#' @param hi Numeric. Harvest index.
#' @return Numeric. Crop yield in t/ha.
#' @export
wapor_calc_yield_npp <- function(npp_gc_m2, mc, fc, aot, hi) {
  # NPP * 22.222 converts gC/m2 to kgDM/ha (DMP)
  dmp <- npp_gc_m2 * 22.222
  # Calculate Above Ground Biomass (ton/ha)
  agbm <- (aot * fc * (dmp / (1 - mc))) / 1000
  # Calculate Yield
  yield <- hi * agbm
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
wapor_prepare_ts <- function(region, aeti_var, ret_var, precip_var,
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
wapor_merge_ts <- function(aeti_ts, ret_ts, precip_ts) {
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
