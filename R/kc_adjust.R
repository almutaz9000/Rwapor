#' Climate-Based Crop Coefficient (Kc) Adjustments
#'
#' Implementation of FAO Irrigation and Drainage Paper No. 56 (Allen et al., 1998)
#' equations for adjusting tabulated mid-season (Kc_mid) and late-season (Kc_end)
#' crop coefficients to local climatic conditions (wind speed, minimum relative
#' humidity, and crop height).

#' Adjust Crop Coefficients for Local Climate (FAO-56 Eq. 62 & 65)
#'
#' Adjusts tabulated `kc_mid` and `kc_end` values from FAO-56 Table 12 to account
#' for local climatic conditions where minimum relative humidity differs from 45%
#' or wind speed at 2 m differs from 2.0 m/s.
#'
#' @details
#' The tabulated values for Kc_mid and Kc_end in FAO-56 represent a sub-humid climate
#' with average daytime minimum relative humidity (RHmin) approx. 45% and calm to
#' moderate wind speeds (u2) approx. 2.0 m/s.
#'
#' For other conditions, FAO-56 specifies:
#'
#' **Mid-season adjustment (Eq. 62):**
#' \deqn{Kc_{mid} = Kc_{mid(Tab)} + [0.04(u_2 - 2) - 0.004(RH_{min} - 45)] \left(\frac{h}{3}\right)^{0.3}}
#'
#' **Late-season adjustment (Eq. 65):**
#' \deqn{Kc_{end} = Kc_{end(Tab)} + [0.04(u_2 - 2) - 0.004(RH_{min} - 45)] \left(\frac{h}{3}\right)^{0.3}}
#' (Applied only when \eqn{Kc_{end(Tab)} > 0.45}. If \eqn{Kc_{end(Tab)} \le 0.45}, no adjustment is made).
#'
#' @param kc_mid Numeric vector. Tabulated mid-season crop coefficient (from FAO-56 Table 12).
#' @param kc_end Numeric vector. Tabulated late-season crop coefficient (optional).
#' @param u2 Numeric vector. Mean daily wind speed at 2 m height during the stage (m/s).
#'   Valid range in FAO-56: 1.0 to 6.0 m/s.
#' @param rh_min Numeric vector. Mean daily minimum relative humidity during the stage (%).
#'   Valid range in FAO-56: 20% to 80%.
#' @param h Numeric vector. Mean plant height during the stage (m).
#'   Valid range in FAO-56: 0.1 to 10.0 m. Default is 1.0 m.
#' @param clamp_inputs Logical. If `TRUE` (default), clamps inputs to the FAO-56
#'   physical validity boundaries: \eqn{1.0 \le u_2 \le 6.0}, \eqn{20 \le RH_{min} \le 80},
#'   and \eqn{0.1 \le h \le 10.0}.
#'
#' @return A data.frame with:
#'   \item{kc_mid_tab}{Original tabulated Kc_mid}
#'   \item{kc_mid_adj}{Climatically adjusted Kc_mid}
#'   \item{kc_end_tab}{Original tabulated Kc_end (if provided)}
#'   \item{kc_end_adj}{Climatically adjusted Kc_end (if provided)}
#'   \item{delta_kc}{The computed climate adjustment offset}
#'
#' @references
#' Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). Crop evapotranspiration:
#' Guidelines for computing crop water requirements. FAO Irrigation and Drainage
#' Paper No. 56, Rome, Italy. Equations 62 & 65.
#'
#' @export
#' @examples
#' # FAO-56 Example 26: Arid, windy climate
#' # u2 = 3.2 m/s, RHmin = 30%, h = 2.5 m, Kc_mid(Tab) = 1.20
#' wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 3.2, rh_min = 30, h = 2.5)
#'
#' # FAO-56 Example 27: Humid, calm climate
#' # u2 = 1.5 m/s, RHmin = 60%, h = 2.0 m, Kc_mid(Tab) = 1.20
#' wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 1.5, rh_min = 60, h = 2.0)
#'
#' # With Kc_end (> 0.45 gets adjusted; <= 0.45 remains unadjusted)
#' wapor_adjust_kc_climate(kc_mid = 1.15, kc_end = 0.60, u2 = 4.0, rh_min = 25, h = 1.2)
#' wapor_adjust_kc_climate(kc_mid = 1.15, kc_end = 0.30, u2 = 4.0, rh_min = 25, h = 1.2)
wapor_adjust_kc_climate <- function(kc_mid,
                                    kc_end = NULL,
                                    u2,
                                    rh_min,
                                    h = 1.0,
                                    clamp_inputs = TRUE) {
  if (missing(kc_mid) || missing(u2) || missing(rh_min)) {
    stop("'kc_mid', 'u2', and 'rh_min' must all be provided", call. = FALSE)
  }

  if (!is.numeric(kc_mid) || any(is.na(kc_mid))) {
    stop("'kc_mid' must be numeric without NA", call. = FALSE)
  }
  if (!is.numeric(u2) || any(is.na(u2))) {
    stop("'u2' must be numeric without NA", call. = FALSE)
  }
  if (!is.numeric(rh_min) || any(is.na(rh_min))) {
    stop("'rh_min' must be numeric without NA", call. = FALSE)
  }
  if (!is.numeric(h) || any(is.na(h))) {
    stop("'h' must be numeric without NA", call. = FALSE)
  }

  # Warn if values are outside FAO-56 physical limits
  if (any(u2 < 1.0 | u2 > 6.0)) {
    warning("Wind speed 'u2' has values outside the FAO-56 validity range [1.0, 6.0 m/s].", call. = FALSE)
  }
  if (any(rh_min < 20.0 | rh_min > 80.0)) {
    warning("Relative humidity 'rh_min' has values outside the FAO-56 validity range [20%, 80%].", call. = FALSE)
  }
  if (any(h < 0.1 | h > 10.0)) {
    warning("Crop height 'h' has values outside the FAO-56 validity range [0.1, 10.0 m].", call. = FALSE)
  }

  # Clamp inputs to bounds if requested
  u2_eff     <- if (isTRUE(clamp_inputs)) pmin(pmax(u2, 1.0), 6.0) else u2
  rh_min_eff <- if (isTRUE(clamp_inputs)) pmin(pmax(rh_min, 20.0), 80.0) else rh_min
  h_eff      <- if (isTRUE(clamp_inputs)) pmin(pmax(h, 0.1), 10.0) else h

  # Calculate FAO-56 climate adjustment offset:
  # [0.04 * (u2 - 2) - 0.004 * (rh_min - 45)] * (h / 3)^0.3
  delta_kc <- (0.04 * (u2_eff - 2.0) - 0.004 * (rh_min_eff - 45.0)) * ((h_eff / 3.0)^0.3)

  # Mid-season adjustment (Eq. 62)
  kc_mid_adj <- round(pmax(0.1, kc_mid + delta_kc), 3)

  res <- data.frame(
    kc_mid_tab = kc_mid,
    kc_mid_adj = kc_mid_adj,
    delta_kc   = round(delta_kc, 4),
    stringsAsFactors = FALSE
  )

  # Late-season adjustment (Eq. 65) - only applies when Kc_end(Tab) > 0.45
  if (!is.null(kc_end)) {
    if (!is.numeric(kc_end) || any(is.na(kc_end))) {
      stop("'kc_end' must be numeric without NA if supplied", call. = FALSE)
    }
    kc_end_adj <- ifelse(
      kc_end > 0.45,
      pmax(0.1, kc_end + delta_kc),
      kc_end
    )
    res$kc_end_tab <- kc_end
    res$kc_end_adj <- round(kc_end_adj, 3)
  }

  res
}


#' Extract Daily Climate Time Series from AgERA5 via Rwapor
#'
#' Queries AgERA5 climate rasters for a specified Area of Interest (AOI) and date range
#' using [wapor_ts()] to obtain daily wind speed (\eqn{u_2}) and minimum relative humidity (\eqn{RH_{min}}).
#'
#' @param aoi Region spatial object (sf polygon, numeric bounding box `c(xmin, ymin, xmax, ymax)`,
#'   or path to vector file).
#' @param period Character vector of date range: `c("YYYY-MM-DD", "YYYY-MM-DD")`.
#' @param method_rh Method to derive minimum relative humidity:
#'   * `"hourly_rh"` (default): Uses midday/afternoon AgERA5 relative humidity
#'     (`AGERA5-RH12-E` and `AGERA5-RH15-E`, converted to percentage 0-100%).
#'   * `"tmin_tmax"`: Approximates RHmin from daily minimum and maximum temperatures
#'     (`AGERA5-TMIN-E` and `AGERA5-TMAX-E`) using the Tetens vapor pressure formulation.
#'
#' @return A data.frame with daily records:
#'   \item{date}{Date object}
#'   \item{u2}{Wind speed at 2 m (m/s)}
#'   \item{rh_min}{Minimum relative humidity (%)}
#'
#' @export
#' @examples
#' \dontrun{
#' aoi <- c(35.5, 31.8, 35.7, 32.2) # Jordan Valley bbox
#' clim <- wapor_extract_agera5_climate(aoi, period = c("2023-01-01", "2023-03-31"))
#' head(clim)
#' }
wapor_extract_agera5_climate <- function(aoi,
                                         period,
                                         method_rh = c("hourly_rh", "tmin_tmax")) {
  method_rh <- match.arg(method_rh)

  if (length(period) != 2) {
    stop("'period' must be a vector of two dates: c(start_date, end_date)", call. = FALSE)
  }

  # 1. Wind speed u2 (AGERA5-WS-E)
  ts_wind <- wapor_ts(
    region = aoi,
    variable = "AGERA5-WS-E",
    period = period,
    unit_conversion = "none"
  )

  if (nrow(ts_wind) == 0) {
    stop("No AgERA5 wind speed data found for the specified AOI and period.", call. = FALSE)
  }

  res_df <- data.frame(
    date = as.Date(ts_wind$start_date),
    u2   = ts_wind$mean,
    stringsAsFactors = FALSE
  )

  # 2. Minimum Relative Humidity (RHmin)
  if (method_rh == "hourly_rh") {
    # AgERA5 relative humidity at 12:00 and 15:00 UTC (raw values are 0-1)
    ts_rh12 <- wapor_ts(region = aoi, variable = "AGERA5-RH12-E", period = period, unit_conversion = "none")
    ts_rh15 <- wapor_ts(region = aoi, variable = "AGERA5-RH15-E", period = period, unit_conversion = "none")

    rh12_val <- if (nrow(ts_rh12) == nrow(res_df)) ts_rh12$mean else rep(NA_real_, nrow(res_df))
    rh15_val <- if (nrow(ts_rh15) == nrow(res_df)) ts_rh15$mean else rep(NA_real_, nrow(res_df))

    # Daily afternoon minimum RH in percent
    rh_min_frac <- pmin(rh12_val, rh15_val, na.rm = TRUE)
    res_df$rh_min <- pmin(100.0, pmax(0.0, rh_min_frac * 100.0))
  } else {
    # Temperature-based approximation (Tetens equation)
    ts_tmin <- wapor_ts(region = aoi, variable = "AGERA5-TMIN-E", period = period)
    ts_tmax <- wapor_ts(region = aoi, variable = "AGERA5-TMAX-E", period = period)

    tmin_c <- if (mean(ts_tmin$mean, na.rm = TRUE) > 100) ts_tmin$mean - 273.15 else ts_tmin$mean
    tmax_c <- if (mean(ts_tmax$mean, na.rm = TRUE) > 100) ts_tmax$mean - 273.15 else ts_tmax$mean

    # Saturation vapour pressure (kPa)
    e_tmin <- 0.6108 * exp((17.27 * tmin_c) / (tmin_c + 237.3))
    e_tmax <- 0.6108 * exp((17.27 * tmax_c) / (tmax_c + 237.3))
    res_df$rh_min <- pmin(100.0, pmax(0.0, (e_tmin / e_tmax) * 100.0))
  }

  res_df
}


#' Adjust Crop Parameters Table using AgERA5 Climate Data
#'
#' Automatically computes growth stage windows for each crop class and updates
#' `kc_mid` and `kc_end` in a crop parameters data frame using stage-specific mean
#' climate parameters from AgERA5.
#'
#' @param crop_params data.frame of crop parameters. Must contain columns:
#'   `kc_ini`, `kc_mid`, `kc_end`, `l_ini_days`, `l_mid_days`, `l_late_days`.
#'   May also contain `class_value`, `class_name`, `max_height_m` (or `height_m`).
#' @param aoi Region spatial object (sf polygon, bbox, or file path). Required
#'   if `climate_df` is not provided.
#' @param season_start Date or character `"YYYY-MM-DD"`. Season start date.
#' @param season_end Date or character `"YYYY-MM-DD"`. Season end date.
#' @param climate_df Optional data.frame of pre-extracted climate records with
#'   columns `date`, `u2`, and `rh_min` (as returned by [wapor_extract_agera5_climate()]).
#'   If provided, `aoi` is not queried.
#' @param method_rh Method for relative humidity: `"hourly_rh"` or `"tmin_tmax"`.
#'
#' @return An updated `crop_params` data.frame with:
#'   \item{kc_mid}{Updated climatically adjusted Kc_mid}
#'   \item{kc_end}{Updated climatically adjusted Kc_end}
#'   \item{kc_mid_tab}{Preserved original tabulated Kc_mid}
#'   \item{kc_end_tab}{Preserved original tabulated Kc_end}
#'   \item{u2_mid}{Mean wind speed during mid-season (m/s)}
#'   \item{rh_min_mid}{Mean minimum RH during mid-season (%)}
#'   \item{u2_late}{Mean wind speed during late-season (m/s)}
#'   \item{rh_min_late}{Mean minimum RH during late-season (%)}
#'
#' @export
#' @examples
#' # Prepare synthetic climate data
#' dates <- seq.Date(as.Date("2023-01-01"), as.Date("2023-04-30"), by = "day")
#' clim <- data.frame(
#'   date = dates,
#'   u2 = 3.5, # breezy
#'   rh_min = 28 # dry
#' )
#'
#' crop_df <- data.frame(
#'   class_value = 1,
#'   class_name = "Wheat",
#'   kc_ini = 0.40,
#'   kc_mid = 1.15,
#'   kc_end = 0.30,
#'   l_ini_days = 30L,
#'   l_mid_days = 40L,
#'   l_late_days = 30L,
#'   max_height_m = 1.0
#' )
#'
#' adj_crop_df <- wapor_adjust_crop_params_agera5(
#'   crop_params = crop_df,
#'   season_start = "2023-01-01",
#'   season_end = "2023-04-30",
#'   climate_df = clim
#' )
#' adj_crop_df
wapor_adjust_crop_params_agera5 <- function(crop_params,
                                           aoi = NULL,
                                           season_start,
                                           season_end,
                                           climate_df = NULL,
                                           method_rh = c("hourly_rh", "tmin_tmax")) {
  method_rh <- match.arg(method_rh)

  if (!is.data.frame(crop_params) || nrow(crop_params) == 0) {
    stop("'crop_params' must be a non-empty data.frame", call. = FALSE)
  }

  req_cols <- c("kc_ini", "kc_mid", "kc_end", "l_ini_days", "l_mid_days", "l_late_days")
  missing_cols <- setdiff(req_cols, names(crop_params))
  if (length(missing_cols) > 0) {
    stop(sprintf("'crop_params' is missing required columns: %s", paste(missing_cols, collapse = ", ")),
         call. = FALSE)
  }

  s_start <- as.Date(season_start)
  s_end   <- as.Date(season_end)
  if (is.na(s_start) || is.na(s_end) || s_end <= s_start) {
    stop("'season_start' and 'season_end' must be valid dates with season_end > season_start", call. = FALSE)
  }
  total_days <- as.integer(s_end - s_start) + 1L

  # Extract climate if not supplied
  if (is.null(climate_df)) {
    if (is.null(aoi)) {
      stop("Either 'climate_df' or 'aoi' must be provided", call. = FALSE)
    }
    climate_df <- wapor_extract_agera5_climate(
      aoi = aoi,
      period = c(as.character(s_start), as.character(s_end)),
      method_rh = method_rh
    )
  }

  if (!is.data.frame(climate_df) || !all(c("date", "u2", "rh_min") %in% names(climate_df))) {
    stop("'climate_df' must be a data.frame containing columns 'date', 'u2', and 'rh_min'", call. = FALSE)
  }

  climate_df$date <- as.Date(climate_df$date)
  adj_params <- crop_params

  # Store original tabulated values
  adj_params$kc_mid_tab <- adj_params$kc_mid
  adj_params$kc_end_tab <- adj_params$kc_end
  adj_params$u2_mid     <- NA_real_
  adj_params$rh_min_mid <- NA_real_
  adj_params$u2_late    <- NA_real_
  adj_params$rh_min_late<- NA_real_

  for (i in seq_len(nrow(adj_params))) {
    row <- adj_params[i, ]

    # Determine crop height
    h <- if ("max_height_m" %in% names(row) && !is.na(row$max_height_m)) {
      as.numeric(row$max_height_m)
    } else if ("height_m" %in% names(row) && !is.na(row$height_m)) {
      as.numeric(row$height_m)
    } else if ("h" %in% names(row) && !is.na(row$h)) {
      as.numeric(row$h)
    } else {
      1.0
    }

    sum_fixed <- row$l_ini_days + row$l_mid_days + row$l_late_days

    # Proportional stage scaling if season is short
    if (total_days < sum_fixed) {
      scale_factor <- total_days / (sum_fixed + 10)
      l_ini  <- max(1L, as.integer(round(row$l_ini_days * scale_factor)))
      l_mid  <- max(1L, as.integer(round(row$l_mid_days * scale_factor)))
      l_late <- max(1L, as.integer(round(row$l_late_days * scale_factor)))
      l_dev  <- max(0L, total_days - (l_ini + l_mid + l_late))
    } else {
      l_ini  <- as.integer(row$l_ini_days)
      l_mid  <- as.integer(row$l_mid_days)
      l_late <- as.integer(row$l_late_days)
      l_dev  <- as.integer(total_days - sum_fixed)
    }

    # Growth stage boundary calendar dates
    day_ini_end <- s_start + l_ini
    day_dev_end <- day_ini_end + l_dev
    day_mid_end <- day_dev_end + l_mid

    # 1. Mid-Season Stage Climate
    mid_sub <- climate_df[climate_df$date > day_dev_end & climate_df$date <= day_mid_end, ]
    u2_mid  <- if (nrow(mid_sub) > 0) mean(mid_sub$u2, na.rm = TRUE) else mean(climate_df$u2, na.rm = TRUE)
    rh_mid  <- if (nrow(mid_sub) > 0) mean(mid_sub$rh_min, na.rm = TRUE) else mean(climate_df$rh_min, na.rm = TRUE)

    # 2. Late-Season Stage Climate
    late_sub <- climate_df[climate_df$date > day_mid_end & climate_df$date <= s_end, ]
    u2_late  <- if (nrow(late_sub) > 0) mean(late_sub$u2, na.rm = TRUE) else u2_mid
    rh_late  <- if (nrow(late_sub) > 0) mean(late_sub$rh_min, na.rm = TRUE) else rh_mid

    # Calculate climate adjustment for mid and late stages
    adj_mid <- wapor_adjust_kc_climate(
      kc_mid = row$kc_mid,
      u2     = u2_mid,
      rh_min = rh_mid,
      h      = h
    )

    adj_end <- wapor_adjust_kc_climate(
      kc_mid = row$kc_mid,
      kc_end = row$kc_end,
      u2     = u2_late,
      rh_min = rh_late,
      h      = h
    )

    adj_params$kc_mid[i]     <- adj_mid$kc_mid_adj
    adj_params$kc_end[i]     <- adj_end$kc_end_adj
    adj_params$u2_mid[i]     <- round(u2_mid, 2)
    adj_params$rh_min_mid[i] <- round(rh_mid, 1)
    adj_params$u2_late[i]    <- round(u2_late, 2)
    adj_params$rh_min_late[i]<- round(rh_late, 1)
  }

  adj_params
}
