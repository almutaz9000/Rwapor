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
#' @keywords internal
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
# Monthly & Seasonal Aggregation
# =============================================================================

#' Compute Monthly Weighted Raster Series
#'
#' Aggregates a dekadal raster stack into per-month rasters using season weights
#' and optional per-layer multipliers.
#'
#' @param x SpatRaster. Multi-layer raster stack.
#' @param season_weights SpatRaster. Per-layer season weights.
#' @param dekad_table data.frame. Must include either `dekad_start` or `dekad_key`.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer.
#' @param summary_mask Optional SpatRaster mask for mean summaries.
#' @param summary_value_name Character. Name of the summary column to create.
#' @return A list with `rasters` and `summary` entries.
#' @export
wapor_calc_monthly_weighted_rasters <- function(x, season_weights, dekad_table,
                                                layer_multipliers = NULL,
                                                incremental = FALSE,
                                                summary_mask = NULL,
                                                summary_value_name = "mean_mm") {
  n_layers <- terra::nlyr(x)
  if (terra::nlyr(season_weights) != n_layers) {
    stop(sprintf("season_weights layers (%d) must match x layers (%d)",
                 terra::nlyr(season_weights), n_layers), call. = FALSE)
  }
  if (!is.data.frame(dekad_table) || nrow(dekad_table) != n_layers) {
    stop("dekad_table must be a data.frame with one row per raster layer", call. = FALSE)
  }
  if (is.null(layer_multipliers)) {
    layer_multipliers <- rep(1, n_layers)
  }
  if (length(layer_multipliers) != n_layers) {
    stop(sprintf("layer_multipliers length (%d) must match x layers (%d)",
                 length(layer_multipliers), n_layers), call. = FALSE)
  }

  layer_dates <- if ("dekad_start" %in% names(dekad_table)) {
    as.Date(dekad_table$dekad_start)
  } else if ("dekad_key" %in% names(dekad_table)) {
    as.Date(dekad_table$dekad_key)
  } else {
    stop("dekad_table must contain either 'dekad_start' or 'dekad_key'", call. = FALSE)
  }

  month_keys <- format(layer_dates, "%Y-%m")
  monthly_rasters <- list()

  for (month_key in unique(month_keys)) {
    idx <- which(month_keys == month_key)
    monthly_rasters[[month_key]] <- wapor_masked_sum(
      terra::subset(x, idx),
      terra::subset(season_weights, idx),
      layer_multipliers = layer_multipliers[idx],
      incremental = incremental
    )
  }

  monthly_summary <- data.frame(
    month_key = names(monthly_rasters),
    year = as.integer(substr(names(monthly_rasters), 1, 4)),
    month = as.integer(substr(names(monthly_rasters), 6, 7)),
    stringsAsFactors = FALSE
  )
  monthly_summary[[summary_value_name]] <- vapply(
    monthly_rasters,
    function(r) wapor_masked_global_mean(r, summary_mask),
    numeric(1)
  )

  list(rasters = monthly_rasters, summary = monthly_summary)
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
#' @return A single-layer SpatRaster of seasonal ETc (weighted sum).
#' @export
wapor_calc_seasonal_etc <- function(ret_dekad, season_weights, kc_dekad,
                                                 layer_multipliers = NULL) {
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

  total <- NULL
  for (i in seq_len(n_layers)) {
    # Accumulate: term = RET_i * (weight_i * Kc_i)
    # The parentheses ensure we scale the weight (scalar) before multiplying rasters
    term <- ret_dekad[[i]] * (season_weights[[i]] * kc_dekad[i] * layer_multipliers[i])
    
    if (is.null(total)) {
      total <- term
    } else {
      total <- total + term
    }
  }
  total
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
  if (!inherits(aeti_seasonal, "SpatRaster") && !inherits(etc_seasonal, "SpatRaster")) {
    return(wapor_math_adequacy_etc(aeti_seasonal, etc_seasonal))
  }
  etc_safe <- terra::ifel(etc_seasonal == 0, NA, etc_seasonal)
  aeti_seasonal / etc_safe
}

#' Compute Beneficial Fraction
#'
#' Beneficial Fraction = Transpiration (T) / Actual Evapotranspiration (AETI)
#'
#' @param t_seasonal SpatRaster or numeric. Seasonal Transpiration (mm).
#' @param aeti_seasonal SpatRaster or numeric. Seasonal AETI (mm).
#' @return SpatRaster or numeric of beneficial fraction (0-1).
#' @export
wapor_calc_beneficial_fraction <- function(t_seasonal, aeti_seasonal) {
  if (!inherits(t_seasonal, "SpatRaster") && !inherits(aeti_seasonal, "SpatRaster")) {
    return(wapor_math_beneficial_fraction(t_seasonal, aeti_seasonal))
  }
  aeti_safe <- terra::ifel(aeti_seasonal == 0, NA, aeti_seasonal)
  t_seasonal / aeti_safe
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

# Compute Seasonal Effective Precipitation Raster
#
# Aggregates weighted precipitation layers to monthly totals per pixel, applies
# the USDA SCS effective precipitation formula month-by-month, then returns both
# the monthly rasters and the seasonal total.
wapor_calc_monthly_precip_peff_rasters <- function(precip_stack, season_weights, dekad_table,
                                                   layer_multipliers = NULL,
                                                   incremental = FALSE,
                                                   summary_mask = NULL) {
  monthly_pcp <- wapor_calc_monthly_weighted_rasters(
    precip_stack,
    season_weights,
    dekad_table,
    layer_multipliers = layer_multipliers,
    incremental = incremental,
    summary_mask = summary_mask,
    summary_value_name = "pcp_mean_mm"
  )

  monthly_peff <- monthly_pcp
  monthly_peff$rasters <- lapply(monthly_peff$rasters, function(r) {
    terra::ifel(
      r <= 250,
      r * (125 - 0.2 * r) / 125,
      125 + 0.1 * r
    )
  })
  monthly_peff$summary$peff_mean_mm <- vapply(
    monthly_peff$rasters,
    function(r) wapor_masked_global_mean(r, summary_mask),
    numeric(1)
  )

  total_peff <- monthly_peff$rasters[[1]]
  if (length(monthly_peff$rasters) > 1) {
    for (i in 2:length(monthly_peff$rasters)) {
      total_peff <- total_peff + monthly_peff$rasters[[i]]
    }
  }

  list(
    monthly_pcp = monthly_pcp$rasters,
    monthly_peff = monthly_peff$rasters,
    rasters = list(pcp = monthly_pcp$rasters, peff = monthly_peff$rasters),
    seasonal_peff = total_peff,
    summary = {
      out <- monthly_pcp$summary
      out$peff_mean_mm <- monthly_peff$summary$peff_mean_mm
      out
    }
  )
}

# Aggregates weighted precipitation layers to monthly totals per pixel, applies
# the USDA SCS effective precipitation formula month-by-month, then sums the
# monthly Peff rasters across the season.
wapor_calc_seasonal_peff_raster <- function(precip_stack, season_weights, dekad_table,
                                            layer_multipliers = NULL,
                                            incremental = FALSE) {
  wapor_calc_monthly_precip_peff_rasters(
    precip_stack = precip_stack,
    season_weights = season_weights,
    dekad_table = dekad_table,
    layer_multipliers = layer_multipliers,
    incremental = incremental
  )$seasonal_peff
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
  if (!inherits(yield_value, "SpatRaster") && !inherits(aeti_mm, "SpatRaster")) {
    return(wapor_math_cwp(yield_value, aeti_mm, yield_unit = yield_unit))
  }
  if (tolower(yield_unit) == "t/ha") {
    yield_value <- yield_value * 1000
  }
  aeti_m3_ha <- aeti_mm * 10
  aeti_safe <- terra::ifel(aeti_m3_ha == 0, NA, aeti_m3_ha)
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
  if (!inherits(biomass_value, "SpatRaster") && !inherits(aeti_mm, "SpatRaster")) {
    return(wapor_math_bwp(biomass_value, aeti_mm, biomass_unit = biomass_unit))
  }
  if (tolower(biomass_unit) == "t/ha") {
    biomass_value <- biomass_value * 1000
  }
  aeti_m3_ha <- aeti_mm * 10
  aeti_safe <- terra::ifel(aeti_m3_ha == 0, NA, aeti_m3_ha)
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
  if (!inherits(aeti_seasonal, "SpatRaster") && !inherits(peff_seasonal, "SpatRaster")) {
    return(wapor_math_green_water(aeti_seasonal, peff_seasonal))
  }
  terra::ifel(aeti_seasonal <= peff_seasonal, aeti_seasonal, peff_seasonal)
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
  if (!inherits(aeti_seasonal, "SpatRaster") && !inherits(peff_seasonal, "SpatRaster")) {
    return(wapor_math_blue_water(aeti_seasonal, peff_seasonal))
  }
  diff_val <- aeti_seasonal - peff_seasonal
  terra::ifel(diff_val > 0, diff_val, 0)
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
  if (inherits(npp_gc_m2, "SpatRaster")) {
    return(npp_gc_m2 * 22.222)
  }
  wapor_math_npp_to_biomass(npp_gc_m2)
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
  if (inherits(npp_gc_m2, "SpatRaster")) {
    dmp <- npp_gc_m2 * 22.222
    agbm <- (aot * fc * (dmp / (1 - mc))) / 1000
    return(hi * agbm)
  }
  wapor_math_yield_from_npp(npp_gc_m2, mc = mc, fc = fc, aot = aot, hi = hi)
}


#' Apply Season-Masked Weighted Standard Deviation
#'
#' Computes weighted standard deviation of a raster time series using per-dekad season weights.
#'
#' @param x SpatRaster. Multi-layer raster.
#' @param weights SpatRaster. Season weights (0-1), same number of layers as x.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#'   Default FALSE.
#' @return A single-layer SpatRaster of weighted standard deviations.
#' @keywords internal
wapor_masked_std <- function(x, weights, layer_multipliers = NULL, incremental = FALSE) {
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

  # Sum of weights
  sum_weights <- terra::app(weights, fun = "sum", na.rm = TRUE)
  sum_weights_safe <- terra::ifel(sum_weights == 0, NA, sum_weights)

  # Weighted mean
  weighted_sum <- wapor_masked_sum(x, weights, layer_multipliers = layer_multipliers, incremental = incremental)
  weighted_mean <- weighted_sum / sum_weights_safe

  # Weighted sum of squared differences
  sum_sq_diff <- NULL
  for (i in seq_len(terra::nlyr(x))) {
    v_i <- x[[i]] * layer_multipliers[i]
    diff_sq <- weights[[i]] * ((v_i - weighted_mean) ^ 2)
    if (is.null(sum_sq_diff)) {
      sum_sq_diff <- diff_sq
    } else {
      sum_sq_diff <- sum_sq_diff + diff_sq
    }
  }

  weighted_var <- sum_sq_diff / sum_weights_safe
  weighted_std <- sqrt(weighted_var)
  
  return(weighted_std)
}

#' Compute Seasonal Standard Deviation (Variability)
#'
#' Applies dekadal season weights to compute weighted standard deviation of rasters,
#' and optionally summarizes by crop class.
#'
#' @param x SpatRaster. Dekadal layers of any variable.
#' @param season_weights SpatRaster. Dekadal season weights (0-1).
#' @param crop_mask SpatRaster. Optional crop mask for per-class summaries.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer to save memory.
#' @return A list with:
#'   \describe{
#'     \item{raster}{SpatRaster of seasonal weighted standard deviation per pixel}
#'     \item{by_class}{data.frame of mean seasonal standard deviation per crop class (if crop_mask provided)}
#'   }
#' @export
wapor_calc_seasonal_std <- function(x, season_weights,
                                    crop_mask = NULL, layer_multipliers = NULL,
                                    incremental = FALSE) {
  seasonal_std <- wapor_masked_std(
    x,
    season_weights,
    layer_multipliers = layer_multipliers,
    incremental = incremental
  )

  by_class <- NULL
  if (!is.null(crop_mask)) {
    by_class <- terra::zonal(seasonal_std, crop_mask, fun = "mean", na.rm = TRUE)
    names(by_class) <- c("class_value", "mean_seasonal_std")
  }

  list(raster = seasonal_std, by_class = by_class)
}

#' Compute Monthly Weighted Standard Deviation Raster Series
#'
#' Aggregates a dekadal raster stack into per-month standard deviations using season weights
#' and optional per-layer multipliers.
#'
#' @param x SpatRaster. Multi-layer raster stack.
#' @param season_weights SpatRaster. Per-layer season weights.
#' @param dekad_table data.frame. Must include either `dekad_start` or `dekad_key`.
#' @param layer_multipliers Optional numeric vector of per-layer multipliers.
#' @param incremental Logical. If TRUE, performs aggregation layer-by-layer.
#' @param summary_mask Optional SpatRaster mask for mean summaries.
#' @param summary_value_name Character. Name of the summary column to create.
#' @return A list with `rasters` and `summary` entries.
#' @export
wapor_calc_monthly_weighted_std_rasters <- function(x, season_weights, dekad_table,
                                                    layer_multipliers = NULL,
                                                    incremental = FALSE,
                                                    summary_mask = NULL,
                                                    summary_value_name = "std_mm") {
  n_layers <- terra::nlyr(x)
  if (terra::nlyr(season_weights) != n_layers) {
    stop(sprintf("season_weights layers (%d) must match x layers (%d)",
                 terra::nlyr(season_weights), n_layers), call. = FALSE)
  }
  if (!is.data.frame(dekad_table) || nrow(dekad_table) != n_layers) {
    stop("dekad_table must be a data.frame with one row per raster layer", call. = FALSE)
  }
  if (is.null(layer_multipliers)) {
    layer_multipliers <- rep(1, n_layers)
  }
  if (length(layer_multipliers) != n_layers) {
    stop(sprintf("layer_multipliers length (%d) must match x layers (%d)",
                 length(layer_multipliers), n_layers), call. = FALSE)
  }

  layer_dates <- if ("dekad_start" %in% names(dekad_table)) {
    as.Date(dekad_table$dekad_start)
  } else if ("dekad_key" %in% names(dekad_table)) {
    as.Date(dekad_table$dekad_key)
  } else {
    stop("dekad_table must contain either 'dekad_start' or 'dekad_key'", call. = FALSE)
  }

  month_keys <- format(layer_dates, "%Y-%m")
  monthly_rasters <- list()

  for (month_key in unique(month_keys)) {
    idx <- which(month_keys == month_key)
    monthly_rasters[[month_key]] <- wapor_masked_std(
      terra::subset(x, idx),
      terra::subset(season_weights, idx),
      layer_multipliers = layer_multipliers[idx],
      incremental = incremental
    )
  }

  monthly_summary <- data.frame(
    month_key = names(monthly_rasters),
    year = as.integer(substr(names(monthly_rasters), 1, 4)),
    month = as.integer(substr(names(monthly_rasters), 6, 7)),
    stringsAsFactors = FALSE
  )
  monthly_summary[[summary_value_name]] <- vapply(
    monthly_rasters,
    function(r) wapor_masked_global_mean(r, summary_mask),
    numeric(1)
  )

  list(rasters = monthly_rasters, summary = monthly_summary)
}

#' Summarise a raster by crop-mask class
#'
#' @param r SpatRaster.
#' @param crop_mask SpatRaster of integer class values.
#' @param class_stats Optional data.frame with a `class_value` column to merge.
#' @param var_name Character. Used to name the mean column `mean_<var_name>`.
#' @return data.frame of class means, or `NULL` if inputs are missing.
#' @keywords internal
wapor_summary_by_class <- function(r, crop_mask, class_stats = NULL, var_name = "value") {
  if (is.null(r) || is.null(crop_mask) || !inherits(r, "SpatRaster")) {
    return(NULL)
  }
  by_class <- terra::zonal(r, crop_mask, fun = "mean", na.rm = TRUE)
  names(by_class) <- c("class_value", paste0("mean_", var_name))
  if (is.data.frame(class_stats) && "class_value" %in% names(class_stats)) {
    by_class <- merge(by_class, class_stats, by = "class_value", all.x = TRUE)
  }
  by_class
}

#' USDA-SCS effective precipitation from monthly rasters
#'
#' @param monthly_rasters Named list of monthly precipitation SpatRasters (mm).
#' @return List with `monthly` (Peff rasters) and `seasonal` (sum of monthly Peff).
#' @keywords internal
wapor_calc_peff <- function(monthly_rasters) {
  if (is.null(monthly_rasters) || !length(monthly_rasters)) {
    stop("'monthly_rasters' must be a non-empty list of SpatRasters", call. = FALSE)
  }
  monthly <- lapply(monthly_rasters, function(r) {
    if (!inherits(r, "SpatRaster")) {
      stop("Each monthly layer must be a SpatRaster", call. = FALSE)
    }
    terra::ifel(r <= 250, r * (125 - 0.2 * r) / 125, 125 + 0.1 * r)
  })
  seasonal <- monthly[[1]]
  if (length(monthly) > 1L) {
    for (i in 2:length(monthly)) {
      seasonal <- seasonal + monthly[[i]]
    }
  }
  list(monthly = monthly, seasonal = seasonal)
}

#' Spatial coefficient of variation
#'
#' @param r SpatRaster (typically seasonal AETI).
#' @param crop_mask Optional SpatRaster mask / class raster.
#' @return List with `overall` CV and optional `by_class` table.
#' @keywords internal
wapor_calc_cv <- function(r, crop_mask = NULL) {
  if (!inherits(r, "SpatRaster")) {
    stop("'r' must be a SpatRaster", call. = FALSE)
  }
  target <- if (is.null(crop_mask)) {
    r
  } else {
    r * terra::ifel(is.na(crop_mask), NA, 1L)
  }
  mu <- terra::global(target, "mean", na.rm = TRUE)$mean
  sdv <- terra::global(target, "sd", na.rm = TRUE)$sd
  overall <- if (is.na(mu) || mu == 0) NA_real_ else sdv / mu

  by_class <- NULL
  if (!is.null(crop_mask)) {
    z_mean <- terra::zonal(target, crop_mask, fun = "mean", na.rm = TRUE)
    z_sd <- terra::zonal(target, crop_mask, fun = "sd", na.rm = TRUE)
    by_class <- data.frame(
      class_value = z_mean[[1]],
      cv = ifelse(z_mean[[2]] == 0, NA_real_, z_sd[[2]] / z_mean[[2]]),
      stringsAsFactors = FALSE
    )
  }
  list(overall = overall, by_class = by_class)
}

#' Spatial Theil T inequality index
#'
#' Theil's T = mean( (x / xbar) * log(x / xbar) ) for positive finite values.
#'
#' @param r SpatRaster.
#' @param crop_mask Optional SpatRaster mask / class raster.
#' @return List with `overall` Theil T and optional `by_class` table.
#' @keywords internal
wapor_calc_theil <- function(r, crop_mask = NULL) {
  if (!inherits(r, "SpatRaster")) {
    stop("'r' must be a SpatRaster", call. = FALSE)
  }
  theil_t <- function(vals) {
    vals <- vals[is.finite(vals) & vals > 0]
    if (!length(vals)) return(NA_real_)
    xbar <- mean(vals)
    if (!is.finite(xbar) || xbar <= 0) return(NA_real_)
    mean((vals / xbar) * log(vals / xbar))
  }
  target <- if (is.null(crop_mask)) {
    r
  } else {
    r * terra::ifel(is.na(crop_mask), NA, 1L)
  }
  overall <- theil_t(terra::values(target, mat = FALSE))

  by_class <- NULL
  if (!is.null(crop_mask)) {
    classes <- sort(unique(terra::values(crop_mask, mat = FALSE)))
    classes <- classes[is.finite(classes)]
    by_class <- data.frame(
      class_value = classes,
      theil = vapply(classes, function(cls) {
        m <- terra::ifel(crop_mask == cls, target, NA)
        theil_t(terra::values(m, mat = FALSE))
      }, numeric(1)),
      stringsAsFactors = FALSE
    )
  }
  list(overall = overall, by_class = by_class)
}
