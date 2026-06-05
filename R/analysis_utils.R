# analysis_utils.R
# Internal helper functions for the Shiny analysis module (mod_analysis.R).
# These functions are non-reactive and handle raster/table manipulations.

#' Lazy raster guard for Shiny
#'
#' Checks that a SpatRaster stored in a reactiveVal still has valid layers
#' (temp-file pointers can go stale between upload and use).
#'
#' @param rv A reactiveVal containing a SpatRaster.
#' @param label Character. Label for the notification.
#' @param session Shiny session object for notifications.
#' @return The SpatRaster if valid, otherwise NULL.
#' @keywords internal
wapor_shiny_safe_rast <- function(rv, label = "raster", session = shiny::getDefaultReactiveDomain()) {
  r <- rv()
  if (is.null(r)) return(NULL)
  ok <- tryCatch({ terra::nlyr(r) > 0 }, error = function(e) FALSE)
  if (!ok) {
    if (!is.null(session)) {
      shiny::showNotification(
        sprintf("%s reference expired — please re-upload the file.", label),
        type = "warning", duration = 8
      )
    }
    rv(NULL)
    return(NULL)
  }
  r
}

#' Build a binary mask for specific crop class values
#'
#' @param mask_rast SpatRaster. The crop mask.
#' @param class_values Integer vector. Values to include in the mask.
#' @return A SpatRaster with 1 for matched classes and NA otherwise.
#' @keywords internal
wapor_build_class_mask <- function(mask_rast, class_values) {
  if (is.null(mask_rast) || length(class_values) == 0) return(NULL)

  # Optimization: Use terra's vectorized %in% operator for much faster
  # masking when multiple classes are selected.
  match_rast <- mask_rast %in% as.integer(class_values)

  terra::ifel(match_rast, 1L, NA)
}

#' Filter class stats to match active crop parameters
#'
#' @param res Analysis results list.
#' @return data.frame of filtered stats.
#' @keywords internal
wapor_filter_class_stats <- function(res) {
  if (is.null(res) || is.null(res$mask_class_stats) || is.null(res$crop_params)) {
    return(NULL)
  }

  stats <- res$mask_class_stats
  stats[stats$class_value %in% res$crop_params$class_value, , drop = FALSE]
}

#' Compute weighted mean over specific classes
#'
#' @param summary_tbl data.frame with class_value and the value to average.
#' @param class_stats data.frame with class_value and pixel_count.
#' @param value_col Character. Column name in summary_tbl to average.
#' @return Numeric weighted mean.
#' @keywords internal
wapor_weighted_class_mean <- function(summary_tbl, class_stats, value_col) {
  if (is.null(summary_tbl) || is.null(class_stats) || nrow(summary_tbl) == 0 || nrow(class_stats) == 0) {
    return(NA_real_)
  }

  merged <- merge(
    summary_tbl,
    class_stats[, c("class_value", "pixel_count"), drop = FALSE],
    by = "class_value",
    all = FALSE
  )
  merged <- merged[
    !is.na(merged[[value_col]]) & !is.na(merged$pixel_count) & merged$pixel_count > 0,
    ,
    drop = FALSE
  ]
  if (nrow(merged) == 0) {
    return(NA_real_)
  }

  stats::weighted.mean(merged[[value_col]], w = merged$pixel_count)
}

#' Compute masked global mean
#'
#' @param r SpatRaster.
#' @param mask_rast SpatRaster. Optional mask.
#' @return Numeric mean.
#' @keywords internal
wapor_masked_global_mean <- function(r, mask_rast = NULL) {
  if (is.null(r)) return(NA_real_)
  target <- if (is.null(mask_rast)) r else r * mask_rast
  terra::global(target, "mean", na.rm = TRUE)$mean
}

#' Build a table of unique season profiles (start/end combinations)
#'
#' @param crop_mask SpatRaster.
#' @param start_raster SpatRaster.
#' @param end_raster SpatRaster.
#' @param class_values Integer vector.
#' @return data.frame of profiles.
#' @keywords internal
wapor_build_season_profile_table <- function(crop_mask, start_raster, end_raster, class_values) {
  # Optimization: Use terra::crosstab instead of terra::values() to avoid
  # loading all pixels into R memory. This counts unique combinations in C++.
  # Using terra::round() ensures consistent integer-based grouping.

  stk <- terra::c(crop_mask, terra::round(start_raster), terra::round(end_raster))

  # Crosstab returns a data.frame with counts of unique combinations
  ct <- terra::crosstab(stk, long = TRUE, useNA = FALSE)

  if (is.null(ct) || nrow(ct) == 0) {
    return(data.frame(
      class_value = integer(0), start_jd = integer(0),
      end_jd = integer(0), total_days = integer(0), pixel_count = integer(0)
    ))
  }

  # Standardize names (crosstab names vary based on layer names)
  # First 3 columns are class, start, end. 4th is Freq (or similar)
  names(ct) <- c("class_value", "start_jd", "end_jd", "pixel_count")

  # Cast to integer and filter by requested class values
  ct$class_value <- as.integer(ct$class_value)
  ct$start_jd <- as.integer(ct$start_jd)
  ct$end_jd <- as.integer(ct$end_jd)
  ct$pixel_count <- as.integer(ct$pixel_count)

  ct <- ct[ct$class_value %in% as.integer(class_values), , drop = FALSE]

  if (nrow(ct) == 0) {
    return(data.frame(
      class_value = integer(0), start_jd = integer(0),
      end_jd = integer(0), total_days = integer(0), pixel_count = integer(0)
    ))
  }

  # Compute total days and filter valid seasons
  ct$total_days <- ct$end_jd - ct$start_jd + 1L
  ct <- ct[ct$total_days > 0, , drop = FALSE]

  # Final table order
  ct[, c("class_value", "start_jd", "end_jd", "total_days", "pixel_count")]
}

#' Generate an R script for standalone analysis
#'
#' Converts Shiny analysis parameters into a reproducible R script string.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop parameters.
#' @return Character string (the script).
#' @keywords internal
wapor_generate_shiny_script <- function(config, crop_params) {
  # 1. Resolve metadata
  ref_year    <- config$ref_year %||% 2023
  period      <- config$period %||% as.character(c(Sys.Date(), Sys.Date()))
  aeti_var    <- config$aeti_var %||% "L1-AETI-D"
  ret_var     <- config$ret_var  %||% "L1-RET-D"
  precip_var  <- config$precip_var %||% "L1-PCP-D"
  npp_var     <- config$npp_var    %||% "L1-NPP-D"
  folder      <- config$folder %||% "analysis_output"
  data_source <- config$data_source %||% "api"
  l3_region   <- if (any(grepl("^L3-", c(aeti_var, ret_var, precip_var, npp_var)))) config$l3_region else NULL

  indicators <- unique(c(config$agg_vars, config$derived_vars)) %||% character(0)

  # 2. Format Crop Parameters
  params_code <- "data.frame(class_value = integer(0))" # Fallback
  if (!is.null(crop_params) && nrow(crop_params) > 0) {
    cols <- character()
    for (col in names(crop_params)) {
      val <- if (is.character(crop_params[[col]])) {
        paste0("c(", paste(shQuote(crop_params[[col]]), collapse = ", "), ")")
      } else if (is.integer(crop_params[[col]])) {
        paste0("c(", paste(crop_params[[col]], collapse = "L, "), "L)")
      } else {
        paste0("c(", paste(crop_params[[col]], collapse = ", "), ")")
      }
      cols <- c(cols, sprintf("  %s = %s", col, val))
    }
    params_code <- paste0("data.frame(\n", paste(cols, collapse = ",\n"), "\n)")
  }

  # 3. Assemble Script
  script <- c(
    "library(Rwapor)",
    "library(terra)",
    "",
    "# [1] Configuration Settings",
    sprintf("ref_year <- %d", ref_year),
    sprintf("period <- c(\"%s\", \"%s\")", as.character(period[1]), as.character(period[2])),
    sprintf("output_folder <- %s", shQuote(folder)),
    sprintf("data_source <- %s  # %s", shQuote(data_source), if (data_source == "api") "requires internet" else "requires local files"),
    "",
    "# [2] Variables Selection",
    sprintf("aeti_var <- %s", shQuote(aeti_var)),
    sprintf("ret_var  <- %s", shQuote(ret_var)),
    sprintf("precip_var <- %s", shQuote(precip_var)),
    sprintf("npp_var    <- %s", shQuote(npp_var)),
    if (!is.null(l3_region)) sprintf("l3_region  <- %s", shQuote(l3_region)) else NULL,
    "",
    "# [3] Crop parameters & Kc curves",
    paste0("crop_params <- ", params_code),
    "",
    "# [4] Load Input Rasters",
    if (isTRUE(config$use_crop_mask)) {
      c("# Note: Provide the actual path to your crop mask GeoTIFF",
        "crop_mask <- wapor_load_crop_mask(\"path/to/your/crop_mask.tif\")")
    } else {
      "# Using entire area (no crop mask)"
    },
    if (isTRUE(config$use_season_rasters)) {
      c("# Note: Provide actual paths to your DOY rasters",
        "s_start <- wapor_load_season_raster(\"path/to/season_start.tif\")",
        "s_end   <- wapor_load_season_raster(\"path/to/season_end.tif\")")
    } else NULL,
    "",
    "# [5] Analysis Logic",
    "# Fetch a template and harmonize inputs",
    if (data_source == "api") {
      sprintf("urls <- wapor_generate_urls(aeti_var, %s, period = period)", if (!is.null(l3_region)) "l3_region = l3_region" else "l3_region = NULL")
    } else {
      "local_paths <- wapor_local_rasters(output_folder, aeti_var, period[1], period[2])"
    },
    "",
    if (data_source == "api") {
      "template_r <- terra::rast(paste0(\"/vsicurl/\", urls[1])) # Use first dekad as template"
    } else {
      "template_r <- terra::rast(local_paths[1])"
    },
    "",
    if (isTRUE(config$use_crop_mask)) {
      "h_mask <- wapor_harmonize_crop_mask(crop_mask, template_r)"
    } else {
      "h_mask <- terra::classify(template_r * 0 + 1, cbind(NA, NA))"
    },
    "",
    if (isTRUE(config$use_season_rasters)) {
      paste0("h_start <- wapor_harmonize_raster(s_start, template_r, method = \"near\")\n",
             "h_end   <- wapor_harmonize_raster(s_end, template_r, method = \"near\")")
    } else {
      paste0("# Continuous Julian days relative to ref_year handle cross-year seasons correctly\n",
             "h_start <- template_r * 0 + wapor_continuous_julian(period[1], ref_year)\n",
             "h_end   <- template_r * 0 + wapor_continuous_julian(period[2], ref_year)")
    },
    "",
    "sw <- wapor_build_season_weights(period[1], period[2], h_start, h_end, ref_year)",
    "season_weights <- sw$weights",
    "dekad_table    <- sw$dekad_table",
    "",
    "# [6] Load Variable Stacks",
    "# This step loads and harmonizes all layers to the template grid",
    if (any(indicators %in% c("agg_aeti", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp"))) {
      paste0("aeti_stack <- if (data_source == \"api\") {\n",
             "  urls <- wapor_generate_urls(aeti_var, ", if (!is.null(l3_region)) "l3_region = l3_region" else "l3_region = NULL", ", period = period)\n",
             "  terra::rast(paste0(\"/vsicurl/\", urls)) * 0.1 # scale by 0.1\n",
             "} else {\n",
             "  paths <- wapor_local_rasters(output_folder, aeti_var, period[1], period[2])\n",
             "  terra::rast(paths) * 0.1\n",
             "}")
    } else NULL,
    "",
    if (any(indicators %in% c("agg_ret", "etc", "adequacy_etc"))) {
      paste0("ret_stack <- if (data_source == \"api\") {\n",
             "  urls <- wapor_generate_urls(ret_var, ", if (!is.null(l3_region)) "l3_region = l3_region" else "l3_region = NULL", ", period = period)\n",
             "  terra::rast(paste0(\"/vsicurl/\", urls)) * 0.1\n",
             "} else {\n",
             "  paths <- wapor_local_rasters(output_folder, ret_var, period[1], period[2])\n",
             "  terra::rast(paths) * 0.1\n",
             "}")
    } else NULL,
    "",
    "# [7] Calculate Indicators",
    "results <- list()",
    if ("agg_aeti" %in% indicators) "results$seasonal_aeti <- wapor_calc_seasonal_aeti(aeti_stack, season_weights, h_mask)" else NULL,
    if ("agg_ret" %in% indicators) "results$seasonal_ret  <- wapor_calc_seasonal_ret(ret_stack, season_weights, h_mask)" else NULL,
    if ("etc" %in% indicators) {
      c("# Generate Kc curve based on season duration",
        "total_days_r <- h_end - h_start + 1",
        "mean_days <- terra::global(total_days_r, \"mean\", na.rm = TRUE)$mean",
        "l_dev <- as.integer(mean_days - (crop_params$l_ini_days + crop_params$l_mid_days + crop_params$l_late_days))",
        "kc_daily <- wapor_build_kc(crop_params$kc_ini, crop_params$kc_mid, crop_params$kc_end, crop_params$l_ini_days, l_dev, crop_params$l_mid_days, crop_params$l_late_days)",
        "kc_dekad <- wapor_aggregate_kc(kc_daily, dekad_table, period[1])",
        "results$etc <- wapor_calc_seasonal_etc(ret_stack, season_weights, kc_dekad)")
    } else NULL,
    "",
    "# [8] Save Results",
    "if (!dir.exists(output_folder)) dir.create(output_folder, recursive = TRUE)",
    "if (!is.null(results$seasonal_aeti)) terra::writeRaster(results$seasonal_aeti$raster, file.path(output_folder, \"seasonal_aeti.tif\"), overwrite = TRUE)",
    "if (!is.null(results$etc)) terra::writeRaster(results$etc, file.path(output_folder, \"seasonal_etc.tif\"), overwrite = TRUE)",
    "",
    "print(\"Analysis complete!\")"
  )

  return(paste(unlist(script[!vapply(script, is.null, logical(1))]), collapse = "\n"))
}

#' Save Analysis Rasters (Shiny Helper)
#'
#' @param results List of analysis results.
#' @param folder Path to output folder.
#' @param season_label Character label for the season.
#' @param indicators Character vector of indicators to save.
#' @export
wapor_shiny_save_analysis_rasters <- function(results, folder, season_label, indicators) {
  if (!dir.exists(folder)) dir.create(folder, recursive = TRUE)
  
  prefix <- if (nzchar(season_label)) {
    gsub("[^a-zA-Z0-9_-]", "_", season_label)
  } else "analysis"
  
  # Helper to write if exists
  .write <- function(r, suffix) {
    if (!is.null(r)) {
      terra::writeRaster(r, file.path(folder, paste0(prefix, "_", suffix, ".tif")), overwrite = TRUE)
    }
  }

  .write(results$seasonal_aeti$raster, "seasonal_aeti")
  .write(results$seasonal_ret$raster, "seasonal_ret")
  .write(results$seasonal_pcp, "seasonal_pcp")
  
  if (any(c("agg_biomass_kg", "yield_npp") %in% indicators)) {
    .write(results$seasonal_biomass_kg, "seasonal_biomass_kg_ha")
  }
  if (any(c("agg_biomass_t", "yield_npp") %in% indicators)) {
    .write(results$seasonal_biomass_t, "seasonal_biomass_t_ha")
  }

  .write(results$adequacy_etc, "adequacy_etc")
  .write(results$adequacy_p95, "adequacy_p95")
  .write(results$green_water, "green_water")
  .write(results$blue_water, "blue_water")
  
  if (!is.null(results$etc_by_class)) {
    for (cls in names(results$etc_by_class)) {
      .write(results$etc_by_class[[cls]]$etc_seasonal, paste0("etc_class_", cls))
    }
  }
}
