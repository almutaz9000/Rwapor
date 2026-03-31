# =============================================================================
# Analysis Validation Functions
# =============================================================================

#' Validate Analysis Configuration
#'
#' Checks analysis configuration for common errors before running the pipeline.
#'
#' @param config List. Analysis configuration (see wapor_analysis_pipeline).
#' @param crop_mask SpatRaster or NULL. Crop mask raster.
#' @param season_start SpatRaster or NULL. Season start raster.
#' @param season_end SpatRaster or NULL. Season end raster.
#' @return A list with `valid` (logical) and `errors` (character vector).
#' @export
wapor_validate_analysis_config <- function(config, crop_mask = NULL, 
                                           season_start = NULL, 
                                           season_end = NULL) {
  errors <- character()
  
  # Check required fields
  if (is.null(config$ref_year)) {
    errors <- c(errors, "Reference year is required")
  } else if (config$ref_year < 2000 || config$ref_year > 2030) {
    errors <- c(errors, "Reference year must be between 2000 and 2030")
  }
  
  if (is.null(config$period) || length(config$period) != 2) {
    errors <- c(errors, "Period must be a vector of 2 dates")
  } else {
    start <- as.Date(config$period[1])
    end <- as.Date(config$period[2])
    if (end < start) {
      errors <- c(errors, "End date must be after start date")
    }
  }
  
  if (is.null(config$aeti_var)) {
    errors <- c(errors, "AETI variable is required")
  }
  
  if (is.null(config$ret_var)) {
    errors <- c(errors, "RET variable is required")
  }
  
  if (is.null(config$indicators) || length(config$indicators) == 0) {
    errors <- c(errors, "At least one indicator must be selected")
  }
  
  # Validate crop parameters
  if (!is.null(config$crop_params)) {
    param_errors <- wapor_validate_crop_params(config$crop_params)
    if (length(param_errors) > 0) {
      errors <- c(errors, param_errors)
    }
  }
  
  # Validate raster compatibility
  if (!is.null(crop_mask) && !is.null(season_start)) {
    if (!.check_raster_overlap(crop_mask, season_start)) {
      errors <- c(errors, "Crop mask and season start raster do not overlap spatially")
    }
  }
  
  if (!is.null(crop_mask) && !is.null(season_end)) {
    if (!.check_raster_overlap(crop_mask, season_end)) {
      errors <- c(errors, "Crop mask and season end raster do not overlap spatially")
    }
  }
  
  list(valid = length(errors) == 0, errors = errors)
}

#' Validate Crop Parameters
#'
#' Checks crop parameter data.frame for valid ranges and required columns.
#'
#' @param crop_params data.frame. Crop parameters.
#' @return Character vector of error messages (empty if valid).
#' @export
wapor_validate_crop_params <- function(crop_params) {
  errors <- character()
  
  if (!is.data.frame(crop_params)) {
    return("Crop parameters must be a data.frame")
  }
  
  if (nrow(crop_params) == 0) {
    return("Crop parameters must have at least one row")
  }
  
  # Check required columns
  required_cols <- c("class_value", "kc_ini", "kc_mid", "kc_end",
                     "l_ini_days", "l_mid_days", "l_late_days")
  missing_cols <- setdiff(required_cols, names(crop_params))
  if (length(missing_cols) > 0) {
    errors <- c(errors, sprintf("Missing required columns: %s", 
                                paste(missing_cols, collapse = ", ")))
  }
  
  # Validate Kc ranges
  if ("kc_ini" %in% names(crop_params)) {
    if (any(crop_params$kc_ini < 0.05 | crop_params$kc_ini > 1.5, na.rm = TRUE)) {
      errors <- c(errors, "kc_ini must be between 0.05 and 1.5")
    }
  }
  
  if ("kc_mid" %in% names(crop_params)) {
    if (any(crop_params$kc_mid < 0.1 | crop_params$kc_mid > 2.0, na.rm = TRUE)) {
      errors <- c(errors, "kc_mid must be between 0.1 and 2.0")
    }
  }
  
  if ("kc_end" %in% names(crop_params)) {
    if (any(crop_params$kc_end < 0.05 | crop_params$kc_end > 1.5, na.rm = TRUE)) {
      errors <- c(errors, "kc_end must be between 0.05 and 1.5")
    }
  }
  
  # Validate stage lengths
  if (all(c("l_ini_days", "l_mid_days", "l_late_days") %in% names(crop_params))) {
    if (any(crop_params$l_ini_days < 1, na.rm = TRUE)) {
      errors <- c(errors, "l_ini_days must be >= 1")
    }
    if (any(crop_params$l_mid_days < 1, na.rm = TRUE)) {
      errors <- c(errors, "l_mid_days must be >= 1")
    }
    if (any(crop_params$l_late_days < 1, na.rm = TRUE)) {
      errors <- c(errors, "l_late_days must be >= 1")
    }
  }
  
  # Validate production parameters if present
  if ("HI" %in% names(crop_params)) {
    if (any(crop_params$HI < 0 | crop_params$HI > 1, na.rm = TRUE)) {
      errors <- c(errors, "HI (Harvest Index) must be between 0 and 1")
    }
  }
  
  if ("MC" %in% names(crop_params)) {
    if (any(crop_params$MC < 0 | crop_params$MC > 1, na.rm = TRUE)) {
      errors <- c(errors, "MC (Moisture Content) must be between 0 and 1")
    }
  }
  
  if ("fc" %in% names(crop_params)) {
    if (any(crop_params$fc <= 0 | crop_params$fc > 2, na.rm = TRUE)) {
      errors <- c(errors, "fc (Light use efficiency factor) must be between 0 and 2")
    }
  }
  
  if ("AOT" %in% names(crop_params)) {
    if (any(crop_params$AOT < 0 | crop_params$AOT > 1, na.rm = TRUE)) {
      errors <- c(errors, "AOT (Above-ground over total biomass) must be between 0 and 1")
    }
  }
  
  errors
}

#' Validate Data Coverage for Analysis Period
#'
#' Checks if local data covers the requested analysis period.
#'
#' @param folder Character. Path to local data folder.
#' @param variables Character vector. Variable names to check.
#' @param period Character vector c(start_date, end_date).
#' @param l3_code Character. L3 region code (optional).
#' @return A list with `complete` (logical) and `missing` (list of missing dates per variable).
#' @export
wapor_validate_data_coverage <- function(folder, variables, period, l3_code = NULL) {
  if (!dir.exists(folder)) {
    return(list(complete = FALSE, missing = list(), 
                error = "Folder does not exist"))
  }
  
  missing_info <- list()
  
  for (var in variables) {
    urls <- wapor_generate_urls(var, l3_region = l3_code, period = period)
    check <- wapor_check_local(urls, var, folder)
    
    if (length(check$missing_dates) > 0) {
      missing_info[[var]] <- check$missing_dates
    }
  }
  
  list(
    complete = length(missing_info) == 0,
    missing = missing_info
  )
}

#' Check Raster Spatial Overlap
#'
#' Tests if two rasters have spatial overlap (after reprojection if needed).
#'
#' @param r1 SpatRaster. First raster.
#' @param r2 SpatRaster. Second raster.
#' @return Logical. TRUE if rasters overlap.
.check_raster_overlap <- function(r1, r2) {
  tryCatch({
    # Get extents in same CRS
    ext1 <- terra::ext(r1)
    crs1 <- terra::crs(r1)
    
    ext2 <- terra::ext(r2)
    crs2 <- terra::crs(r2)
    
    # If CRS differ, project second to first
    if (crs1 != crs2 && nzchar(crs1) && nzchar(crs2)) {
      poly2 <- terra::as.polygons(ext2, crs = crs2)
      poly2_proj <- terra::project(poly2, crs1)
      ext2 <- terra::ext(poly2_proj)
    }
    
    # Check overlap
    overlap <- !(ext1$xmax < ext2$xmin || ext1$xmin > ext2$xmax ||
                  ext1$ymax < ext2$ymin || ext1$ymin > ext2$ymax)
    
    return(overlap)
  }, error = function(e) {
    warning(sprintf("Could not check raster overlap: %s", e$message))
    return(TRUE)  # Assume valid if check fails
  })
}

#' Pre-Flight Analysis Validation
#'
#' Comprehensive validation before running analysis. Returns detailed
#' diagnostic information.
#'
#' @param config List. Analysis configuration.
#' @param data_source Character. "api" or "local".
#' @param folder Character. Local data folder (for local mode).
#' @param crop_mask SpatRaster or path.
#' @param season_start SpatRaster or path.
#' @param season_end SpatRaster or path.
#' @return A list with validation results and recommendations.
#' @export
wapor_preflight_check <- function(config, data_source = "api", folder = NULL,
                                   crop_mask = NULL, season_start = NULL,
                                   season_end = NULL) {
  
  results <- list(
    overall = "pending",
    checks = list(),
    errors = character(),
    warnings = character(),
    recommendations = character()
  )
  
  # 1. Configuration validation
  config_valid <- wapor_validate_analysis_config(config, crop_mask, 
                                                 season_start, season_end)
  results$checks$config <- list(
    passed = config_valid$valid,
    issues = config_valid$errors
  )
  if (!config_valid$valid) {
    results$errors <- c(results$errors, config_valid$errors)
  }
  
  # 2. Data availability (local mode only)
  if (data_source == "local") {
    if (is.null(folder) || !nzchar(folder)) {
      results$errors <- c(results$errors, "Local mode requires folder path")
      results$checks$data_coverage <- list(passed = FALSE)
    } else {
      required_vars <- c(config$aeti_var, config$ret_var)
      if ("agg_pcp" %in% config$indicators) {
        required_vars <- c(required_vars, config$precip_var)
      }
      if (any(c("agg_biomass_kg", "yield_npp") %in% config$indicators)) {
        required_vars <- c(required_vars, config$npp_var)
      }
      
      coverage <- wapor_validate_data_coverage(
        folder, required_vars, config$period, config$l3_code
      )
      
      results$checks$data_coverage <- list(
        passed = coverage$complete,
        missing = coverage$missing
      )
      
      if (!coverage$complete) {
        # Build detailed message about missing data
        missing_details <- vapply(names(coverage$missing), function(var) {
          n_missing <- length(coverage$missing[[var]])
          sprintf("%s (%d timesteps)", var, n_missing)
        }, character(1))
        
        results$warnings <- c(results$warnings,
          sprintf("Some local data is missing for: %s", 
                  paste(missing_details, collapse = ", "))
        )
        results$recommendations <- c(results$recommendations,
          "Options: (1) Download missing data via Download tab, (2) Adjust Analysis Period to match available data, or (3) Switch to API mode to stream data directly"
        )
        results$recommendations <- c(results$recommendations,
          "Note: Analysis can proceed with partial data coverage if your season falls within the available dates"
        )
      }
    }
  }
  
  # 3. Crop mask validation
  if (!is.null(crop_mask)) {
    if (is.character(crop_mask)) {
      if (!file.exists(crop_mask)) {
        results$errors <- c(results$errors, "Crop mask file not found")
        results$checks$crop_mask <- list(passed = FALSE)
      } else {
        cm <- tryCatch(terra::rast(crop_mask), error = function(e) NULL)
        if (is.null(cm)) {
          results$errors <- c(results$errors, "Failed to load crop mask")
          results$checks$crop_mask <- list(passed = FALSE)
        } else {
          results$checks$crop_mask <- .validate_crop_mask_raster(cm, config$crop_params)
        }
      }
    } else if (inherits(crop_mask, "SpatRaster")) {
      results$checks$crop_mask <- .validate_crop_mask_raster(crop_mask, config$crop_params)
    }
  }
  
  # 4. Season raster validation
  if (!is.null(season_start) && !is.null(season_end)) {
    season_check <- .validate_season_rasters(season_start, season_end, config$ref_year)
    results$checks$season_rasters <- season_check
    if (!season_check$passed) {
      results$errors <- c(results$errors, season_check$errors)
    }
    if (length(season_check$warnings) > 0) {
      results$warnings <- c(results$warnings, season_check$warnings)
    }
  }
  
  # 5. Stage length validation
  if (!is.null(config$crop_params)) {
    total_fixed <- config$crop_params$l_ini_days + 
                   config$crop_params$l_mid_days + 
                   config$crop_params$l_late_days
    
    season_days <- as.numeric(difftime(
      as.Date(config$period[2]), 
      as.Date(config$period[1]), 
      units = "days"
    ))
    
    if (any(total_fixed >= season_days)) {
      results$warnings <- c(results$warnings,
        sprintf("Some crop classes have stage lengths >= season duration (%d days)", 
                season_days)
      )
      results$recommendations <- c(results$recommendations,
        "Ensure L_dev will be positive (total days - stage sum > 0)"
      )
    }
  }
  
  # Overall status
  if (length(results$errors) > 0) {
    results$overall <- "failed"
  } else if (length(results$warnings) > 0) {
    results$overall <- "warning"
  } else {
    results$overall <- "passed"
  }
  
  results
}

.validate_crop_mask_raster <- function(cm, crop_params) {
  issues <- character()
  warnings <- character()
  
  # Check for data
  if (terra::global(cm, "notNA")[[1]] == 0) {
    issues <- c(issues, "Crop mask contains no valid data")
    return(list(passed = FALSE, issues = issues, warnings = warnings))
  }
  
  # Extract unique values
  unique_vals <- unique(terra::values(cm, mat = FALSE))
  unique_vals <- unique_vals[!is.na(unique_vals)]
  
  if (length(unique_vals) == 0) {
    issues <- c(issues, "Crop mask has no non-NA values")
    return(list(passed = FALSE, issues = issues, warnings = warnings))
  }
  
  # Check if crop param classes exist in mask
  if (!is.null(crop_params)) {
    param_classes <- crop_params$class_value
    missing_classes <- setdiff(param_classes, unique_vals)
    
    if (length(missing_classes) > 0) {
      warnings <- c(warnings,
        sprintf("Crop parameters defined for classes not in mask: %s",
                paste(missing_classes, collapse = ", "))
      )
    }
    
    unmapped_classes <- setdiff(unique_vals, param_classes)
    if (length(unmapped_classes) > 0) {
      warnings <- c(warnings,
        sprintf("Crop mask contains unmapped classes: %s",
                paste(unmapped_classes, collapse = ", "))
      )
    }
  }
  
  list(
    passed = length(issues) == 0,
    issues = issues,
    warnings = warnings,
    unique_values = unique_vals
  )
}

.validate_season_rasters <- function(start_r, end_r, ref_year) {
  errors <- character()
  warnings <- character()
  
  # Load if paths
  if (is.character(start_r)) {
    if (!file.exists(start_r)) {
      return(list(passed = FALSE, errors = "Season start file not found", warnings = character()))
    }
    start_r <- terra::rast(start_r)
  }
  
  if (is.character(end_r)) {
    if (!file.exists(end_r)) {
      return(list(passed = FALSE, errors = "Season end file not found", warnings = character()))
    }
    end_r <- terra::rast(end_r)
  }
  
  # Check for valid data
  start_mean <- tryCatch(terra::global(start_r, "mean", na.rm = TRUE)$mean,
                         error = function(e) NaN)
  if (is.nan(start_mean) || is.na(start_mean)) {
    errors <- c(errors, "Season start raster contains no valid data")
  }
  
  end_mean <- tryCatch(terra::global(end_r, "mean", na.rm = TRUE)$mean,
                       error = function(e) NaN)
  if (is.nan(end_mean) || is.na(end_mean)) {
    errors <- c(errors, "Season end raster contains no valid data")
  }
  
  if (length(errors) > 0) {
    return(list(passed = FALSE, errors = errors, warnings = warnings))
  }
  
  # Check Julian day ranges
  start_range <- terra::global(start_r, c("min", "max"), na.rm = TRUE)
  end_range <- terra::global(end_r, c("min", "max"), na.rm = TRUE)
  
  if (start_range$min < 1) {
    warnings <- c(warnings, 
      sprintf("Season start has values < 1 (min = %.1f)", start_range$min))
  }
  
  if (end_range$max > 500) {
    warnings <- c(warnings,
      sprintf("Season end has very large values (max = %.1f), check if continuous Julian days are intended",
              end_range$max))
  }
  
  # Check geometry match
  if (!terra::compareGeom(start_r, end_r, stopOnError = FALSE)) {
    warnings <- c(warnings, "Season start and end rasters have different geometries")
  }
  
  list(
    passed = length(errors) == 0,
    errors = errors,
    warnings = warnings
  )
}
