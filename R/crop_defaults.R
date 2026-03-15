#' FAO Crop Default Parameters
#'
#' A data.frame containing default crop coefficients and growth stage lengths
#' for common crops, sourced from FAO Irrigation and Drainage Paper 56.
#'
#' @format A data.frame with columns:
#' \describe{
#'   \item{crop_name}{Character. Name of the crop}
#'   \item{region}{Character. Reference region for the growth parameters}
#'   \item{Kc_ini}{Numeric. Crop coefficient during initial stage}
#'   \item{Kc_mid}{Numeric. Crop coefficient during mid-season stage}
#'   \item{Kc_end}{Numeric. Crop coefficient during late/end stage}
#'   \item{L_ini_days}{Integer. Length of initial growth stage in days}
#'   \item{L_mid_days}{Integer. Length of mid-season stage in days}
#'   \item{L_late_days}{Integer. Length of late-season stage in days}
#'   \item{max_height_m}{Numeric. Maximum crop height in meters}
#'   \item{notes}{Character. Additional notes}
#' }
#'
#' @details
#' Note that L_dev (development stage) is not stored here. It is derived
#' dynamically as: L_dev = total_season_days - (L_ini + L_mid + L_late).
#' Total season length comes from the user-supplied season start/end rasters.
#'
#' @export
FAO_CROP_DEFAULTS <- data.frame(
  crop_name    = c("Winter Wheat",  "Sorghum",       "Sugarbeet"),
  region       = c("Mediterranean", "USA/Med",       "Mediterranean"),
  Kc_ini       = c(0.4,             0.3,             0.35),
  Kc_mid       = c(1.15,            1.05,            1.20),
  Kc_end       = c(0.30,            0.55,            0.70),
  L_ini_days   = c(30L,             20L,             25L),
  L_mid_days   = c(40L,             40L,             50L),
  L_late_days  = c(30L,             30L,             50L),

  max_height_m = c(1.0,             1.5,             0.5),
  notes        = c("FAO-56 Table 12, non-frozen soils",
                    "FAO-56 Table 12, grain sorghum",
                    "FAO-56 Table 12"),
  stringsAsFactors = FALSE
)

#' List Available Crop Profiles
#'
#' Returns the names of all saved crop profiles in the FAO defaults dataset.
#'
#' @return Character vector of crop names.
#' @export
#' @examples
#' rwapor_list_crops()
rwapor_list_crops <- function() {
  FAO_CROP_DEFAULTS$crop_name
}

#' Get Crop Default Parameters
#'
#' Retrieves the default crop parameters for a named crop from the
#' FAO defaults dataset.
#'
#' @param crop_name Character. Name of the crop (case-insensitive partial match).
#' @return A single-row data.frame with crop parameters, or NULL if not found.
#' @export
#' @examples
#' rwapor_get_crop_defaults("Winter Wheat")
rwapor_get_crop_defaults <- function(crop_name) {
  if (!is.character(crop_name) || length(crop_name) != 1) {
    stop("'crop_name' must be a single character string", call. = FALSE)
  }
  idx <- which(tolower(FAO_CROP_DEFAULTS$crop_name) == tolower(crop_name))
  if (length(idx) == 0) {
    idx <- grep(crop_name, FAO_CROP_DEFAULTS$crop_name, ignore.case = TRUE)
  }
  if (length(idx) == 0) return(NULL)
  FAO_CROP_DEFAULTS[idx[1], , drop = FALSE]
}

#' Validate Crop Default Parameters
#'
#' Checks that a crop defaults data.frame has valid structure and values.
#'
#' @param df A data.frame with crop parameters (same columns as FAO_CROP_DEFAULTS).
#' @return TRUE invisibly if valid; stops with an error otherwise.
#' @export
#' @examples
#' rwapor_validate_crop_defaults(FAO_CROP_DEFAULTS)
rwapor_validate_crop_defaults <- function(df) {
  required_cols <- c("crop_name", "Kc_ini", "Kc_mid", "Kc_end",
                     "L_ini_days", "L_mid_days", "L_late_days")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing, collapse = ", ")),
         call. = FALSE)
  }
  if (nrow(df) == 0) {
    stop("Crop defaults data.frame is empty", call. = FALSE)
  }
  if (any(is.na(df$Kc_ini) | is.na(df$Kc_mid) | is.na(df$Kc_end))) {
    stop("Kc values must not be NA", call. = FALSE)
  }
  if (any(df$Kc_ini < 0 | df$Kc_mid < 0 | df$Kc_end < 0)) {
    stop("Kc values must be non-negative", call. = FALSE)
  }
  if (any(is.na(df$L_ini_days) | is.na(df$L_mid_days) | is.na(df$L_late_days))) {
    stop("Stage length values must not be NA", call. = FALSE)
  }
  if (any(df$L_ini_days < 0 | df$L_mid_days < 0 | df$L_late_days < 0)) {
    stop("Stage lengths must be non-negative", call. = FALSE)
  }
  invisible(TRUE)
}
