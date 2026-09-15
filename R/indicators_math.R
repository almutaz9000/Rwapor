# =============================================================================
# Indicator math (terra-free): numeric vectors and matrices only
# =============================================================================

NPP_TO_TBP <- 22.222

wapor_math_safe_divide <- function(num, den) {
  num <- as.numeric(num)
  den <- as.numeric(den)
  den_safe <- den
  den_safe[den == 0] <- NA_real_
  num / den_safe
}

#' ETc-based adequacy: AETI / ETc
#' @keywords internal
#' @export
wapor_math_adequacy_etc <- function(aeti_seasonal, etc_seasonal) {
  wapor_math_safe_divide(aeti_seasonal, etc_seasonal)
}

#' Beneficial fraction: T / AETI
#' @keywords internal
#' @export
wapor_math_beneficial_fraction <- function(t_seasonal, aeti_seasonal) {
  wapor_math_safe_divide(t_seasonal, aeti_seasonal)
}

#' USDA-SCS effective precipitation from monthly totals (mm)
#' @keywords internal
#' @export
wapor_math_peff_usda <- function(p_monthly) {
  p <- as.numeric(p_monthly)
  ifelse(p <= 250, p * (125 - 0.2 * p) / 125, 125 + 0.1 * p)
}

#' Green water = min(AETI, Peff)
#' @keywords internal
#' @export
wapor_math_green_water <- function(aeti_seasonal, peff_seasonal) {
  pmin(as.numeric(aeti_seasonal), as.numeric(peff_seasonal))
}

#' Blue water = max(0, AETI - Peff)
#' @keywords internal
#' @export
wapor_math_blue_water <- function(aeti_seasonal, peff_seasonal) {
  pmax(as.numeric(aeti_seasonal) - as.numeric(peff_seasonal), 0)
}

#' NPP (gC/m2) to biomass (kg DM/ha)
#' @keywords internal
#' @export
wapor_math_npp_to_biomass <- function(npp_gc_m2) {
  as.numeric(npp_gc_m2) * NPP_TO_TBP
}

#' Crop yield (t/ha) from seasonal NPP
#' @keywords internal
#' @export
wapor_math_yield_from_npp <- function(npp_gc_m2, mc, fc, aot, hi) {
  dmp <- wapor_math_npp_to_biomass(npp_gc_m2)
  agbm <- (aot * fc * (dmp / (1 - mc))) / 1000
  hi * agbm
}

#' Crop water productivity in kg/m3
#' @keywords internal
#' @export
wapor_math_cwp <- function(yield_value, aeti_mm, yield_unit = "kg/ha") {
  y <- as.numeric(yield_value)
  if (tolower(yield_unit) == "t/ha") {
    y <- y * 1000
  }
  wapor_math_safe_divide(y, as.numeric(aeti_mm) * 10)
}

#' Biomass water productivity in kg/m3
#' @keywords internal
#' @export
wapor_math_bwp <- function(biomass_value, aeti_mm, biomass_unit = "kg/ha") {
  wapor_math_cwp(biomass_value, aeti_mm, yield_unit = biomass_unit)
}

#' Area-weighted mean of a numeric matrix or vector
#' @keywords internal
#' @export
wapor_math_area_weighted_mean <- function(values, area = NULL) {
  v <- as.numeric(values)
  finite <- !is.na(v)
  if (!any(finite)) {
    return(NA_real_)
  }
  if (is.null(area)) {
    return(mean(v[finite]))
  }
  w <- as.numeric(area)[finite]
  v <- v[finite]
  total <- sum(w)
  if (total <= 0) {
    return(NA_real_)
  }
  sum(v * w) / total
}

#' Mean of values within each crop-mask class
#' @keywords internal
#' @export
wapor_math_zonal_mean_by_class <- function(values, crop_mask, area = NULL) {
  values <- as.matrix(values)
  crop_mask <- as.matrix(crop_mask)
  area_mat <- if (is.null(area)) NULL else as.matrix(area)
  classes <- unique(as.numeric(crop_mask[!is.na(crop_mask)]))
  out <- list()
  for (cls in classes) {
    m <- (crop_mask == cls) & !is.na(values)
    key <- as.character(as.integer(cls))
    if (!any(m)) {
      out[[key]] <- NA_real_
    } else if (is.null(area_mat)) {
      out[[key]] <- mean(values[m])
    } else {
      w <- area_mat[m]
      total <- sum(w)
      out[[key]] <- if (total > 0) sum(values[m] * w) / total else NA_real_
    }
  }
  out
}
