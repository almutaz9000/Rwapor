#' FAO Crop Default Parameters
#'
#' A data.frame containing default crop coefficients and growth stage lengths
#' for common crops, sourced from FAO Irrigation and Drainage Paper 56.
#'
#' @format A data.frame with columns:
#' \describe{
#'   \item{crop_name}{Character. Name of the crop}
#'   \item{region}{Character. Reference region for the growth parameters}
#'   \item{kc_ini}{Numeric. Crop coefficient during initial stage}
#'   \item{kc_mid}{Numeric. Crop coefficient during mid-season stage}
#'   \item{kc_end}{Numeric. Crop coefficient during late/end stage}
#'   \item{l_ini_days}{Integer. Length of initial growth stage in days}
#'   \item{l_mid_days}{Integer. Length of mid-season stage in days}
#'   \item{l_late_days}{Integer. Length of late-season stage in days}
#'   \item{max_height_m}{Numeric. Maximum crop height in meters}
#'   \item{notes}{Character. Additional notes}
#' }
#'
#' @details
#' Note that l_dev (development stage) is not stored here. It is derived
#' dynamically as: l_dev = total_season_days - (l_ini + l_mid + l_late).
#' Total season length comes from the user-supplied season start/end rasters.
#'
#' @export
FAO_CROP_DEFAULTS <- data.frame(
  crop_name    = c("Winter Wheat",  "Sorghum",       "Sugarbeet",     "Maize",         "Rice",          "Cotton",        "Potato",        "Soybean",       "Sunflower",     "Barley",        "Alfalfa",       "Sugarcane"),
  region       = c("Mediterranean", "USA/Med",       "Mediterranean", "Sub-humid/Med", "Humid/Asia",    "Arid/Semi-arid","Temperate/Med", "Temperate/Hum", "Semi-arid/Med", "Temperate/Med", "Arid/Semi-arid","Tropical/Sub"),
  kc_ini       = c(0.40,            0.30,            0.35,            0.30,            1.05,            0.35,            0.50,            0.40,            0.35,            0.30,            0.40,            0.40),
  kc_mid       = c(1.15,            1.05,            1.20,            1.20,            1.20,            1.15,            1.15,            1.15,            1.15,            1.15,            1.20,            1.25),
  kc_end       = c(0.30,            0.55,            0.70,            0.35,            0.90,            0.50,            0.75,            0.50,            0.35,            0.25,            1.15,            0.75),
  l_ini_days   = c(30L,             20L,             25L,             20L,             30L,             30L,             25L,             20L,             25L,             20L,             10L,             35L),
  l_mid_days   = c(40L,             40L,             50L,             40L,             30L,             50L,             45L,             40L,             45L,             50L,             20L,             180L),
  l_late_days  = c(30L,             30L,             50L,             30L,             30L,             30L,             30L,             25L,             25L,             30L,             10L,             60L),

  max_height_m = c(1.0,             1.5,             0.5,             2.0,             1.0,             1.2,             0.6,             0.8,             2.0,             1.0,             0.7,             3.0),
  HI           = c(0.45,            0.40,            0.80,            0.50,            0.45,            0.35,            0.75,            0.35,            0.30,            0.45,            0.90,            0.80),
  MC           = c(0.12,            0.11,            0.15,            0.14,            0.14,            0.10,            0.80,            0.10,            0.10,            0.12,            0.15,            0.70),
  fc           = c(1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0,             1.0),
  AOT          = c(0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8,             0.8),
  notes        = c("FAO-56 Table 12, non-frozen soils",
                    "FAO-56 Table 12, grain sorghum",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12, grain maize",
                    "FAO-56 Table 12, paddy rice",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12",
                    "FAO-56 Table 12, cutting cycle",
                    "FAO-56 Table 12, virgin crop"),
  stringsAsFactors = FALSE
)

#' List Available Crop Profiles
#'
#' Returns the names of all saved crop profiles in the FAO defaults dataset.
#'
#' @return Character vector of crop names.
#' @export
#' @examples
#' wapor_list_crops()
wapor_list_crops <- function() {
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
#' wapor_crop_defaults("Winter Wheat")
wapor_crop_defaults <- function(crop_name) {
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
#' @keywords internal
#' @examples
#' \dontrun{
#' wapor_validate_crop_defaults(FAO_CROP_DEFAULTS)
#' }
wapor_validate_crop_defaults <- function(df) {
  required_cols <- c("crop_name", "kc_ini", "kc_mid", "kc_end",
                     "l_ini_days", "l_mid_days", "l_late_days")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing, collapse = ", ")),
         call. = FALSE)
  }
  if (nrow(df) == 0) {
    stop("Crop defaults data.frame is empty", call. = FALSE)
  }
  if (any(is.na(df$kc_ini) | is.na(df$kc_mid) | is.na(df$kc_end))) {
    stop("Kc values must not be NA", call. = FALSE)
  }
  if (any(df$kc_ini < 0 | df$kc_mid < 0 | df$kc_end < 0)) {
    stop("Kc values must be non-negative", call. = FALSE)
  }
  if (any(is.na(df$l_ini_days) | is.na(df$l_mid_days) | is.na(df$l_late_days))) {
    stop("Stage length values must not be NA", call. = FALSE)
  }
  if (any(df$l_ini_days < 0 | df$l_mid_days < 0 | df$l_late_days < 0)) {
    stop("Stage lengths must be non-negative", call. = FALSE)
  }
  invisible(TRUE)
}

#' Create Custom Crop Parameters for Analysis
#'
#' Builds a validated `crop_params` data.frame of crop growth and production
#' parameters for a specific raster class, without relying on FAO default datasets.
#'
#' @param class_value Integer. Raster class code in the crop mask.
#' @param crop_name Character. Descriptive name of the crop.
#' @param kc_ini Numeric. Initial stage crop coefficient (0.05 - 1.5).
#' @param kc_mid Numeric. Mid-season crop coefficient (0.1 - 2.0).
#' @param kc_end Numeric. Late/end stage crop coefficient (0.05 - 1.5).
#' @param l_ini_days Integer. Length of initial stage in days (>= 1).
#' @param l_mid_days Integer. Length of mid-season stage in days (>= 1).
#' @param l_late_days Integer. Length of late stage in days (>= 1).
#' @param max_height_m Numeric. Maximum crop height in meters (default: 1.0).
#' @param HI Numeric. Harvest Index (0.0 - 1.0, default: 0.45).
#' @param MC Numeric. Moisture Content of harvested crop (0.0 - 1.0, default: 0.12).
#' @param fc Numeric. Ground cover / light interception factor (default: 1.0).
#' @param AOT Numeric. Aboveground to total biomass ratio (default: 0.8).
#' @param region Character. Geographic or agronomic region description.
#' @param notes Character. User notes or metadata.
#' @return A validated single-row data.frame ready for use in `wapor_run_seasonal_analysis()`.
#' @export
#' @examples
#' cp <- wapor_create_crop_params(
#'   class_value = 1L,
#'   crop_name = "Local Durum Wheat",
#'   kc_ini = 0.35,
#'   kc_mid = 1.20,
#'   kc_end = 0.28,
#'   l_ini_days = 25L,
#'   l_mid_days = 45L,
#'   l_late_days = 30L,
#'   HI = 0.48
#' )
wapor_create_crop_params <- function(
  class_value = 1L,
  crop_name = "Custom Crop",
  kc_ini = 0.35,
  kc_mid = 1.15,
  kc_end = 0.35,
  l_ini_days = 25L,
  l_mid_days = 45L,
  l_late_days = 30L,
  max_height_m = 1.0,
  HI = 0.45,
  MC = 0.12,
  fc = 1.0,
  AOT = 0.8,
  region = "Custom",
  notes = "User customized"
) {
  df <- data.frame(
    class_value  = as.integer(class_value),
    crop_name    = as.character(crop_name),
    kc_ini       = as.numeric(kc_ini),
    kc_mid       = as.numeric(kc_mid),
    kc_end       = as.numeric(kc_end),
    l_ini_days   = as.integer(l_ini_days),
    l_mid_days   = as.integer(l_mid_days),
    l_late_days  = as.integer(l_late_days),
    max_height_m = as.numeric(max_height_m),
    HI           = as.numeric(HI),
    MC           = as.numeric(MC),
    fc           = as.numeric(fc),
    AOT          = as.numeric(AOT),
    region       = as.character(region),
    notes        = as.character(notes),
    stringsAsFactors = FALSE
  )
  errs <- wapor_validate_crop_params(df)
  if (length(errs) > 0) {
    stop(paste(errs, collapse = "\n"), call. = FALSE)
  }
  df
}

#' Customize Crop Parameters from FAO Defaults
#'
#' Copies an existing FAO default crop profile and allows selectively overriding
#' specific crop factors (Kc values, stage lengths, HI, MC, etc.) for a specific class code.
#'
#' @param base_crop Character. Name of the base FAO crop (e.g. "Winter Wheat", "Maize", "Potato").
#' @param class_value Integer. Target class value in the crop mask (default: 1L).
#' @param crop_name Character. Optional custom name (defaults to base_crop name).
#' @param kc_ini,kc_mid,kc_end Numeric. Optional Kc overrides.
#' @param l_ini_days,l_mid_days,l_late_days Integer. Optional stage length overrides.
#' @param max_height_m,HI,MC,fc,AOT Numeric. Optional production parameter overrides.
#' @param region,notes Character. Optional metadata overrides.
#' @return A single-row data.frame formatted for `crop_params`.
#' @export
#' @examples
#' custom_wheat <- wapor_custom_crop(
#'   base_crop = "Winter Wheat",
#'   class_value = 2L,
#'   crop_name = "High-Yield Irrigated Wheat",
#'   kc_mid = 1.25,
#'   HI = 0.52
#' )
wapor_custom_crop <- function(
  base_crop,
  class_value = 1L,
  crop_name = NULL,
  kc_ini = NULL,
  kc_mid = NULL,
  kc_end = NULL,
  l_ini_days = NULL,
  l_mid_days = NULL,
  l_late_days = NULL,
  max_height_m = NULL,
  HI = NULL,
  MC = NULL,
  fc = NULL,
  AOT = NULL,
  region = NULL,
  notes = NULL
) {
  base_df <- wapor_crop_defaults(base_crop)
  if (is.null(base_df)) {
    stop(sprintf("Base crop '%s' not found in FAO_CROP_DEFAULTS. Use wapor_list_crops() to view available crops.", base_crop), call. = FALSE)
  }

  wapor_create_crop_params(
    class_value  = class_value,
    crop_name    = crop_name %||% base_df$crop_name,
    kc_ini       = kc_ini %||% base_df$kc_ini,
    kc_mid       = kc_mid %||% base_df$kc_mid,
    kc_end       = kc_end %||% base_df$kc_end,
    l_ini_days   = l_ini_days %||% base_df$l_ini_days,
    l_mid_days   = l_mid_days %||% base_df$l_mid_days,
    l_late_days  = l_late_days %||% base_df$l_late_days,
    max_height_m = max_height_m %||% base_df$max_height_m,
    HI           = HI %||% base_df$HI,
    MC           = MC %||% base_df$MC,
    fc           = fc %||% base_df$fc,
    AOT          = AOT %||% base_df$AOT,
    region       = region %||% base_df$region,
    notes        = notes %||% paste0("Customized from FAO ", base_df$crop_name)
  )
}

#' Combine Multiple Crop Parameter Definitions
#'
#' Merges multiple single-crop parameter data.frames into a consolidated
#' multi-class `crop_params` data.frame, validating for duplicate class values.
#'
#' @param ... Multiple data.frames created by `wapor_create_crop_params()` or `wapor_custom_crop()`.
#' @return Combined, validated `crop_params` data.frame.
#' @export
#' @examples
#' c1 <- wapor_custom_crop("Winter Wheat", class_value = 1L)
#' c2 <- wapor_custom_crop("Maize", class_value = 2L)
#' params <- wapor_combine_crop_params(c1, c2)
wapor_combine_crop_params <- function(...) {
  dots <- list(...)
  if (length(dots) == 1 && is.list(dots[[1]]) && !is.data.frame(dots[[1]])) {
    dots <- dots[[1]]
  }
  if (length(dots) == 0) {
    stop("At least one crop parameter data.frame must be provided", call. = FALSE)
  }
  combined <- do.call(rbind, dots)
  if (any(duplicated(combined$class_value))) {
    dup_classes <- combined$class_value[duplicated(combined$class_value)]
    stop(sprintf("Duplicate class_value found in combined crop parameters: %s", paste(unique(dup_classes), collapse = ", ")), call. = FALSE)
  }
  errs <- wapor_validate_crop_params(combined)
  if (length(errs) > 0) {
    stop(paste(errs, collapse = "\n"), call. = FALSE)
  }
  combined
}
