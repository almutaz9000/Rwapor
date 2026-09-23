# R/anomaly.R
# =============================================================================
# Spatial Anomaly and Hotspot Diagnostics
# =============================================================================

#' Calculate Temporal Z-Score Anomaly Stack
#'
#' Computes pixel-wise standard normalized anomalies (Z-scores) across
#' a multi-layer SpatRaster time series: Z = (X - Mean) / SD.
#'
#' @param stack SpatRaster. Multi-layer raster stack (e.g. multi-year seasonal AETI).
#' @return A SpatRaster of Z-scores with the same number of layers as input.
#' @export
#' @examples
#' r1 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=400, sd=50))
#' r2 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=350, sd=50))
#' r3 <- terra::rast(nrows=5, ncols=5, vals=rnorm(25, mean=450, sd=50))
#' s <- c(r1, r2, r3)
#' z <- wapor_calc_zscore(s)
wapor_calc_zscore <- function(stack) {
  if (!inherits(stack, "SpatRaster")) {
    stop("'stack' must be a SpatRaster", call. = FALSE)
  }
  if (terra::nlyr(stack) < 2) {
    stop("'stack' must contain at least 2 layers for temporal anomaly calculation", call. = FALSE)
  }

  mean_r <- terra::app(stack, fun = "mean", na.rm = TRUE)
  sd_r   <- terra::app(stack, fun = "sd", na.rm = TRUE)

  # Avoid division by zero
  sd_safe <- terra::ifel(sd_r == 0, NA, sd_r)
  z_stack <- (stack - mean_r) / sd_safe
  names(z_stack) <- paste0("zscore_", names(stack))
  z_stack
}

#' Classify Spatial Hotspots from Z-Score Anomaly
#'
#' Identifies severe deficit / surplus hotspots based on statistical significance thresholds
#' (e.g., +/- 1.96 corresponding to 95% confidence interval).
#'
#' @param zscore_layer SpatRaster. Single-layer raster of Z-scores.
#' @param low Numeric. Lower threshold for severe deficit (default: -1.96).
#' @param high Numeric. Upper threshold for severe surplus (default: 1.96).
#' @return A SpatRaster with classified values:
#'   * -2: Severe Deficit (Z < low)
#'   * -1: Moderate Deficit (low <= Z < -1.0)
#'   *  0: Normal (-1.0 <= Z <= 1.0)
#'   *  1: Moderate Surplus (1.0 < Z <= high)
#'   *  2: Severe Surplus (Z > high)
#' @export
#' @examples
#' z <- terra::rast(nrows=5, ncols=5, vals=seq(-2.5, 2.5, length.out=25))
#' h <- wapor_calc_spatial_hotspots(z)
wapor_calc_spatial_hotspots <- function(zscore_layer, low = -1.96, high = 1.96) {
  if (!inherits(zscore_layer, "SpatRaster")) {
    stop("'zscore_layer' must be a SpatRaster", call. = FALSE)
  }
  if (terra::nlyr(zscore_layer) > 1) {
    warning("Input has multiple layers; using the first layer.", call. = FALSE)
    zscore_layer <- zscore_layer[[1]]
  }

  out <- terra::ifel(zscore_layer < low, -2L,
          terra::ifel(zscore_layer < -1.0, -1L,
          terra::ifel(zscore_layer <= 1.0, 0L,
          terra::ifel(zscore_layer <= high, 1L, 2L))))
  names(out) <- "hotspot_class"
  out
}

#' Calculate Anomaly Relative to a Baseline Climatology
#'
#' @param current SpatRaster. Current observation raster.
#' @param baseline_mean SpatRaster. Historical baseline mean raster.
#' @param baseline_sd SpatRaster. Optional historical baseline standard deviation.
#' @return If baseline_sd is provided, returns Z-score anomaly raster.
#'   Otherwise, returns absolute difference (current - baseline_mean).
#' @export
#' @examples
#' curr <- terra::rast(nrows=5, ncols=5, vals=450)
#' base_m <- terra::rast(nrows=5, ncols=5, vals=400)
#' diff_r <- wapor_calc_anomaly_baseline(curr, base_m)
wapor_calc_anomaly_baseline <- function(current, baseline_mean, baseline_sd = NULL) {
  if (!inherits(current, "SpatRaster") || !inherits(baseline_mean, "SpatRaster")) {
    stop("'current' and 'baseline_mean' must be SpatRaster objects", call. = FALSE)
  }

  diff_r <- current - baseline_mean
  if (is.null(baseline_sd)) {
    names(diff_r) <- "anomaly_abs"
    return(diff_r)
  }

  if (!inherits(baseline_sd, "SpatRaster")) {
    stop("'baseline_sd' must be a SpatRaster", call. = FALSE)
  }
  sd_safe <- terra::ifel(baseline_sd == 0, NA, baseline_sd)
  z_r <- diff_r / sd_safe
  names(z_r) <- "anomaly_zscore"
  z_r
}

#' Calculate per-pixel temporal linear trend
#'
#' @param stack Multi-layer SpatRaster ordered in time.
#' @param times Optional numeric time values, defaulting to layer sequence.
#' @return A list containing SpatRaster layers `slope`, `intercept`, and `r2`.
#' @export
linear_trend <- function(stack, times = NULL) {
  if (!inherits(stack, "SpatRaster")) stop("'stack' must be a SpatRaster", call. = FALSE)
  n <- terra::nlyr(stack)
  if (n < 2L) stop("'stack' must contain at least two layers", call. = FALSE)
  t <- if (is.null(times)) seq_len(n) else as.numeric(times)
  if (length(t) != n || anyNA(t) || anyDuplicated(t)) stop("'times' must contain unique, non-missing values for every layer", call. = FALSE)
  # Closed-form least squares from per-pixel running sums, so every step is
  # terra layer arithmetic (C++, block-wise) instead of an R call per pixel.
  # Times are centred on their overall mean to limit cancellation.
  t0 <- mean(t)
  tc <- t - t0
  cnt <- st <- sy <- stt <- sty <- syy <- NULL
  add <- function(acc, x) if (is.null(acc)) x else acc + x
  for (i in seq_len(n)) {
    yi <- stack[[i]]
    ok <- !is.na(yi)
    y0 <- terra::ifel(ok, yi, 0)
    cnt <- add(cnt, ok)
    st <- add(st, ok * tc[i])
    stt <- add(stt, ok * tc[i]^2)
    sy <- add(sy, y0)
    sty <- add(sty, y0 * tc[i])
    syy <- add(syy, y0 * y0)
  }
  den <- cnt * stt - st * st
  valid <- cnt >= 2 & den > 0
  slope <- terra::ifel(valid, (cnt * sty - st * sy) / den, NA)
  intercept_c <- (sy - slope * st) / cnt
  ss_tot <- syy - sy * sy / cnt
  ss_res <- syy - 2 * intercept_c * sy - 2 * slope * sty +
    cnt * intercept_c^2 + 2 * intercept_c * slope * st + slope^2 * stt
  # A constant series has ss_tot == 0; allow for rounding in the sums.
  r2 <- terra::ifel(valid & ss_tot > 1e-12 * syy, 1 - ss_res / ss_tot, NA)
  # Shift the intercept from centred time back to the original time origin.
  intercept <- terra::ifel(valid, intercept_c - slope * t0, NA)
  out <- list(slope = slope, intercept = intercept, r2 = r2)
  for (nm in names(out)) names(out[[nm]]) <- nm
  out
}

# Compatibility names matching the public design specification.
zscore_anomaly <- wapor_calc_zscore
spatial_hotspots <- wapor_calc_spatial_hotspots
anomaly_vs_baseline <- wapor_calc_anomaly_baseline
