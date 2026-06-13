# =============================================================================
# Analysis Pipeline - Modularized Seasonal Crop Water Productivity Analysis
# =============================================================================

#' Run Complete Seasonal Crop Water Productivity Analysis
#'
#' This is the main analysis pipeline that orchestrates data loading,
#' harmonization, seasonal aggregation, and indicator computation. It can
#' be run from Shiny or standalone scripts.
#'
#' @param config List containing:
#'   \describe{
#'     \item{ref_year}{Integer. Reference year for season.}
#'     \item{period}{Character vector c(start_date, end_date).}
#'     \item{aeti_var}{Character. AETI variable name.}
#'     \item{ret_var}{Character. RET variable name.}
#'     \item{precip_var}{Character. Precipitation variable name (optional).}
#'     \item{npp_var}{Character. NPP variable name (optional).}
#'     \item{crop_params}{data.frame. Crop parameters per class.}
#'     \item{indicators}{Character vector. Selected indicators to compute.}
#'     \item{l3_code}{Character. L3 region code (if using L3 data).}
#'   }
#' @param data_source Character. "api" or "local".
#' @param folder Character. Path to local data folder (for local mode).
#' @param region Numeric vector or path. AOI definition (bbox or vector file).
#' @param crop_mask SpatRaster or path. Crop mask raster (optional).
#' @param season_start SpatRaster or path. Season start raster (optional).
#' @param season_end SpatRaster or path. Season end raster (optional).
#' @param incremental Logical. Use incremental aggregation (low-memory mode).
#' @param save_outputs Logical. Save rasters to folder.
#' @param output_folder Character. Path for saving outputs.
#' @param output_prefix Character. Prefix for output files.
#' @param log_file Character. Path to error log file (optional).
#' @param progress_callback Function. Callback for progress updates (optional).
#' @return A list with all computed indicators and metadata.
#' @export
wapor_analysis_pipeline <- function(config,
                                    data_source = "api",
                                    folder = NULL,
                                    region = NULL,
                                    crop_mask = NULL,
                                    season_start = NULL,
                                    season_end = NULL,
                                    incremental = FALSE,
                                    save_outputs = FALSE,
                                    output_folder = NULL,
                                    output_prefix = "analysis",
                                    log_file = NULL,
                                    progress_callback = NULL) {
  
  # Initialize progress tracking
  progress <- function(value, message = "") {
    if (!is.null(progress_callback)) {
      progress_callback(value, message)
    }
  }
  
  # Validate configuration
  progress(0.02, "Validating configuration...")
  validation <- wapor_validate_analysis_config(config, crop_mask, season_start, season_end)
  if (!validation$valid) {
    stop(paste("Configuration validation failed:", 
               paste(validation$errors, collapse = "; ")), call. = FALSE)
  }
  
  # Extract config
  ref_year <- config$ref_year
  period <- config$period
  aeti_var <- config$aeti_var
  ret_var <- config$ret_var
  precip_var <- config$precip_var %||% NULL
  npp_var <- config$npp_var %||% NULL
  crop_params <- config$crop_params
  indicators <- config$indicators
  l3_code <- config$l3_code %||% NULL
  
  # Load rasters from paths if needed
  progress(0.05, "Loading input rasters...")
  if (is.character(crop_mask)) crop_mask <- terra::rast(crop_mask)
  if (is.character(season_start)) season_start <- terra::rast(season_start)
  if (is.character(season_end)) season_end <- terra::rast(season_end)
  
  # Error handling wrapper
  tryCatch({
    
    # Step 1: Get template raster
    progress(0.10, sprintf("Loading reference AETI raster from %s...", 
                          ifelse(data_source == "local", "local files", "API")))
    template_result <- .load_template_raster(
      aeti_var, period, l3_code, region, 
      data_source, folder, crop_mask
    )
    template_r <- template_result$template
    reg_info <- template_result$reg_info
    final_region <- template_result$final_region
    
    # Step 2: Harmonize input rasters
    progress(0.15, "Harmonizing crop mask and season rasters...")
    harmonized <- .harmonize_input_rasters(
      template_r, crop_mask, season_start, season_end,
      ref_year, period
    )
    h_mask <- harmonized$h_mask
    h_start <- harmonized$h_start
    h_end <- harmonized$h_end
    
    # Validate harmonized inputs
    .validate_harmonized_rasters(h_mask, h_start, h_end, crop_params)
    
    # Step 3: Compute season metadata
    progress(0.20, "Computing season duration and weights...")
    total_days_r <- wapor_season_days(h_start, h_end, ref_year)
    mask_class_stats <- wapor_extract_crop_classes(h_mask, min_pixels = 0)
    valid_crop_mask <- .build_valid_class_mask(h_mask, crop_params$class_value)
    
    sw <- wapor_build_season_weights(period[1], period[2], h_start, h_end, ref_year)
    season_weights <- sw$weights
    dekad_table <- sw$dekad_table
    
    # Step 4: Load and harmonize variable stacks
    progress(0.30, "Loading and harmonizing data stacks...")
    stacks <- .load_variable_stacks(
      indicators, aeti_var, ret_var, precip_var, npp_var,
      period, l3_code, data_source, folder, 
      template_r, reg_info, dekad_table
    )
    
    # Step 5: Compute seasonal aggregations
    progress(0.50, "Computing seasonal aggregations...")
    results <- .compute_seasonal_aggregations(
      stacks, season_weights, dekad_table, h_mask,
      indicators, incremental,
      aeti_var, ret_var, precip_var, npp_var
    )
    
    # Step 6: Compute derived indicators
    progress(0.70, "Computing derived indicators...")
    results <- .compute_derived_indicators(
      results, indicators, stacks$ret_stack, season_weights,
      h_mask, h_start, h_end, crop_params, ref_year,
      dekad_table, incremental,
      ret_var
    )
    
    # Step 7: Attach metadata
    progress(0.85, "Finalizing results...")
    results$h_mask <- h_mask
    results$valid_crop_mask <- valid_crop_mask
    results$mask_class_stats <- mask_class_stats
    results$crop_params <- crop_params
    results$dekad_table <- dekad_table
    results$config <- config
    results$timestamp <- Sys.time()
    
    # Step 8: Save outputs if requested
    if (save_outputs && !is.null(output_folder)) {
      progress(0.90, sprintf("Saving outputs to %s...", output_folder))
      .save_analysis_outputs(
        results, output_folder, output_prefix, indicators
      )
    }
    
    progress(1.0, "Analysis complete!")
    return(results)
    
  }, error = function(e) {
    # Log error if log file specified
    if (!is.null(log_file)) {
      .log_analysis_error(e, config, log_file)
    }
    stop(sprintf("Analysis pipeline failed: %s", e$message), call. = FALSE)
  })
}


# =============================================================================
# Internal Pipeline Helper Functions
# =============================================================================

.load_template_raster <- function(aeti_var, period, l3_code, region, 
                                   data_source, folder, crop_mask) {
  final_reg <- region
  
  # Fallback to crop mask extent if no region specified
  if (is.null(final_reg) && !is.null(crop_mask)) {
    cm_ext <- terra::ext(crop_mask)
    cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(crop_mask))
    terra::values(cm_poly) <- NULL  # Clear NA attributes
    cm_poly_4326 <- wapor_safe_project(cm_poly, "EPSG:4326")
    e <- terra::ext(cm_poly_4326)
    final_reg <- c(e$xmin, e$ymin, e$xmax, e$ymax)
  }
  
  template_r <- NULL
  reg_info <- NULL
  
  if (data_source == "local") {
    local_paths <- wapor_local_rasters(folder, aeti_var, period[1], period[2])
    if (length(local_paths) == 0) {
      stop(sprintf("No local AETI files found for %s", aeti_var), call. = FALSE)
    }
    template_r <- terra::rast(local_paths[1])
    
    if (!is.null(final_reg)) {
      reg_info <- wapor_parse_region(final_reg)
      template_r <- .crop_to_region(template_r, reg_info)
    }
  } else {
    ref_urls <- wapor_generate_urls(aeti_var, l3_region = l3_code, period = period)
    if (length(ref_urls) == 0) {
      stop("No AETI data found for the specified period", call. = FALSE)
    }
    
    template_r <- terra::rast(paste0("/vsicurl/", ref_urls[1]))
    
    if (!is.null(final_reg)) {
      reg_info <- wapor_parse_region(final_reg)
      template_r <- .crop_to_region(template_r, reg_info)
    }
  }
  
  list(template = template_r, reg_info = reg_info, final_region = final_reg)
}

.harmonize_input_rasters <- function(template_r, crop_mask, season_start, 
                                      season_end, ref_year, period) {
  h_mask <- if (!is.null(crop_mask)) {
    wapor_harmonize_crop_mask(crop_mask, template_r)
  } else {
    terra::classify(template_r * 0 + 1, cbind(NA, NA))
  }
  
  h_start <- if (!is.null(season_start)) {
    wapor_harmonize_raster(season_start, template_r, method = "near")
  } else {
    template_r * 0 + wapor_continuous_julian(period[1], ref_year)
  }
  
  h_end <- if (!is.null(season_end)) {
    wapor_harmonize_raster(season_end, template_r, method = "near")
  } else {
    template_r * 0 + wapor_continuous_julian(period[2], ref_year)
  }
  
  list(h_mask = h_mask, h_start = h_start, h_end = h_end)
}

.validate_harmonized_rasters <- function(h_mask, h_start, h_end, crop_params) {
  # Check for valid data
  s_mean <- tryCatch(terra::global(h_start, "mean", na.rm = TRUE)$mean, 
                     error = function(e) NaN)
  if (is.nan(s_mean) || is.na(s_mean)) {
    stop("Season start raster contains no valid data", call. = FALSE)
  }
  
  e_mean <- tryCatch(terra::global(h_end, "mean", na.rm = TRUE)$mean,
                     error = function(e) NaN)
  if (is.nan(e_mean) || is.na(e_mean)) {
    stop("Season end raster contains no valid data", call. = FALSE)
  }
}

.build_valid_class_mask <- function(mask_rast, class_values) {
  if (is.null(mask_rast) || length(class_values) == 0) return(NULL)
  
  # Optimization: Vectorized class matching
  match_rast <- mask_rast %in% as.integer(class_values)
  terra::ifel(match_rast, 1L, NA)
}

.load_variable_stacks <- function(indicators, aeti_var, ret_var, precip_var, npp_var,
                                   period, l3_code, data_source, folder,
                                   template_r, reg_info, dekad_table) {
  
  need_aeti <- any(c("agg_aeti", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp") %in% indicators)
  need_ret <- any(c("agg_ret", "etc", "adequacy_etc") %in% indicators)
  need_precip <- any(c("agg_pcp", "agg_peff") %in% indicators)
  need_npp <- any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp") %in% indicators)
  
  # Resolve paths/URLs in parallel
  vars_to_resolve <- list()
  if (need_aeti) vars_to_resolve[["aeti"]] <- aeti_var
  if (need_ret) vars_to_resolve[["ret"]] <- ret_var
  if (need_precip && !is.null(precip_var)) vars_to_resolve[["precip"]] <- precip_var
  if (need_npp && !is.null(npp_var)) vars_to_resolve[["npp"]] <- npp_var
  
  resolved_paths <- future.apply::future_lapply(
    vars_to_resolve,
    function(v) {
      if (data_source == "local") {
        wapor_local_rasters(folder, v, period[1], period[2])
      } else {
        urls <- wapor_generate_urls(v, l3_region = l3_code, period = period)
        paste0("/vsicurl/", urls)
      }
    },
    future.seed = TRUE
  )
  
  # Load and harmonize stacks sequentially
  load_and_harmonize <- function(paths, name) {
    if (is.null(paths) || length(paths) == 0) return(NULL)
    stack <- terra::rast(paths)
    if (!is.null(reg_info)) {
      stack <- .crop_to_region(stack, reg_info)
    }
    stack <- wapor_harmonize_raster(stack, template_r, 
                                    method = ifelse(name == "aeti", "bilinear", "bilinear"))
    .align_stack_to_weights(stack, dekad_table$dekad_key)
  }
  
  list(
    aeti_stack = if (need_aeti) load_and_harmonize(resolved_paths[["aeti"]], "aeti") else NULL,
    ret_stack = if (need_ret) load_and_harmonize(resolved_paths[["ret"]], "ret") else NULL,
    precip_stack = if (need_precip) load_and_harmonize(resolved_paths[["precip"]], "precip") else NULL,
    npp_stack = if (need_npp) load_and_harmonize(resolved_paths[["npp"]], "npp") else NULL
  )
}

.align_stack_to_weights <- function(s, target_dates) {
  if (is.null(s)) return(NULL)
  nms <- names(s)
  
  extract_ymd <- function(nm) {
    m <- regmatches(nm, regexpr("\\d{4}-\\d{2}-\\d{2}", nm))
    if (length(m)) return(m)
    m <- regmatches(nm, regexpr("(?<![0-9])\\d{12}(?![0-9])", nm, perl = TRUE))
    if (length(m)) {
      return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
    }
    m <- regmatches(nm, regexpr("(?<![0-9])\\d{8}(?![0-9])", nm, perl = TRUE))
    if (length(m)) {
      return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
    }
    NA_character_
  }
  
  found_dates <- vapply(nms, extract_ymd, character(1), USE.NAMES = FALSE)
  indices <- match(as.character(target_dates), found_dates)
  
  if (any(is.na(indices))) {
    missing_idx <- which(is.na(indices))
    stop(sprintf("Missing data for dekad starting %s", target_dates[missing_idx[1]]), 
         call. = FALSE)
  }
  
  s[[indices]]
}

.compute_seasonal_aggregations <- function(stacks, season_weights, dekad_table, 
                                           h_mask, indicators, incremental,
                                           aeti_var, ret_var, precip_var, npp_var) {
  results <- list()
  
  analysis_layer_multipliers <- getFromNamespace("get_analysis_layer_multipliers", "Rwapor")
  
  if (!is.null(stacks$aeti_stack)) {
    lm <- analysis_layer_multipliers(aeti_var, dekad_table)
    results$seasonal_aeti <- wapor_calc_seasonal_aeti(
      stacks$aeti_stack, season_weights, h_mask,
      layer_multipliers = lm, incremental = incremental
    )
  }
  
  if (!is.null(stacks$ret_stack)) {
    lm <- analysis_layer_multipliers(ret_var, dekad_table)
    results$seasonal_ret <- wapor_calc_seasonal_ret(
      stacks$ret_stack, season_weights, h_mask,
      layer_multipliers = lm, incremental = incremental
    )
  }
  
  if ("agg_pcp" %in% indicators && !is.null(stacks$precip_stack)) {
    lm <- analysis_layer_multipliers(precip_var, dekad_table)
    results$seasonal_pcp <- wapor_masked_sum(
      stacks$precip_stack, season_weights,
      layer_multipliers = lm, incremental = incremental
    )
  }
  
  if (any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp") %in% indicators) && 
      !is.null(stacks$npp_stack)) {
    lm <- analysis_layer_multipliers(npp_var, dekad_table)
    results$seasonal_biomass_kg <- wapor_masked_sum(
      stacks$npp_stack, season_weights,
      layer_multipliers = lm, incremental = incremental
    ) * 22.222
    
    results$seasonal_biomass <- results$seasonal_biomass_kg
    results$seasonal_biomass_t <- results$seasonal_biomass_kg / 1000
    
    results$seasonal_biomass_by_class <- terra::zonal(
      results$seasonal_biomass_kg, h_mask, fun = "mean", na.rm = TRUE
    )
    names(results$seasonal_biomass_by_class) <- c("class_value", "mean_seasonal_biomass_kg")
    results$seasonal_biomass_by_class$mean_seasonal_biomass_t <-
      results$seasonal_biomass_by_class$mean_seasonal_biomass_kg / 1000
    results$seasonal_biomass_by_class$mean_seasonal_biomass <-
      results$seasonal_biomass_by_class$mean_seasonal_biomass_kg
  }
  
  results
}

.compute_derived_indicators <- function(results, indicators, ret_stack, season_weights,
                                        h_mask, h_start, h_end, crop_params, ref_year,
                                        dekad_table, incremental, ret_var) {
  
  # ETc computation
  if ("etc" %in% indicators || "adequacy_etc" %in% indicators) {
    etc_results <- .compute_etc_by_class(
      ret_stack, season_weights, h_mask, h_start, h_end,
      crop_params, ref_year, dekad_table, ret_var
    )
    results$kc_by_class <- etc_results$kc_by_class
    results$etc_by_class <- etc_results$etc_by_class
  }
  
  # Adequacy ETc
  if ("adequacy_etc" %in% indicators && !is.null(results$seasonal_aeti) && 
      !is.null(results$etc_by_class)) {
    all_etc <- lapply(results$etc_by_class, function(x) x$etc_seasonal)
    if (length(all_etc) > 0) {
      combined_etc <- all_etc[[1]]
      if (length(all_etc) > 1) {
        for (k in seq_along(all_etc)[-1]) {
          combined_etc <- terra::cover(combined_etc, all_etc[[k]])
        }
      }
      results$adequacy_etc <- wapor_calc_adequacy_etc(results$seasonal_aeti$raster, combined_etc)
    }
  }
  
  # Adequacy P95
  if ("adequacy_p95" %in% indicators && !is.null(results$seasonal_aeti)) {
    p95_table <- wapor_calc_p95_aeti(results$seasonal_aeti$raster, h_mask)
    results$p95_table <- p95_table
    results$adequacy_p95 <- wapor_calc_adequacy_p95(
      results$seasonal_aeti$raster, h_mask, p95_table
    )
  }
  
  # Yield from NPP
  if ("yield_npp" %in% indicators && !is.null(results$seasonal_biomass)) {
    yield_layers <- list()
    for (j in seq_len(nrow(crop_params))) {
      cls <- as.character(crop_params$class_value[j])
      cp <- crop_params[j, ]
      class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
      yield_rast <- (cp$HI * cp$AOT * cp$fc * 
                     (results$seasonal_biomass / (1 - cp$MC))) / 1000
      yield_layers[[cls]] <- yield_rast * class_mask
    }
    results$yield_by_class <- yield_layers
  }
  
  results
}

.compute_etc_by_class <- function(ret_stack, season_weights, h_mask, h_start, h_end,
                                  crop_params, ref_year, dekad_table, ret_var) {
  
  analysis_layer_multipliers <- getFromNamespace("get_analysis_layer_multipliers", "Rwapor")
  ret_layer_multipliers <- analysis_layer_multipliers(ret_var, dekad_table)
  
  # Build season profiles
  profile_table <- .build_season_profile_table(h_mask, h_start, h_end, crop_params$class_value)
  
  if (nrow(profile_table) == 0) {
    stop("No valid crop-season profiles found", call. = FALSE)
  }
  
  # Build Kc profiles
  kc_profiles <- list()
  profile_table$kc_key <- NA_character_
  
  for (i in seq_len(nrow(profile_table))) {
    profile_row <- profile_table[i, ]
    cp <- crop_params[crop_params$class_value == profile_row$class_value, , drop = FALSE]
    if (nrow(cp) == 0) next
    
    fixed_sum <- cp$l_ini_days + cp$l_mid_days + cp$l_late_days
    l_dev <- as.integer(profile_row$total_days - fixed_sum)
    if (l_dev < 0L) l_dev <- 0L
    
    kc_daily <- wapor_build_kc(
      kc_ini = cp$kc_ini[1], kc_mid = cp$kc_mid[1], kc_end = cp$kc_end[1],
      L_ini = cp$l_ini_days[1], L_dev = l_dev,
      L_mid = cp$l_mid_days[1], L_late = cp$l_late_days[1]
    )
    
    season_start_date <- as.Date(sprintf("%04d-01-01", ref_year)) + profile_row$start_jd - 1L
    kc_dekad <- wapor_aggregate_kc(kc_daily, dekad_table, season_start_date)
    kc_key <- paste(round(kc_dekad, 6), collapse = ",")
    profile_table$kc_key[i] <- kc_key
    
    if (is.null(kc_profiles[[kc_key]])) {
      kc_profiles[[kc_key]] <- kc_dekad
    }
  }
  
  # Compute unique ETc rasters
  unique_etc_rasters <- list()
  for (key in names(kc_profiles)) {
    unique_etc_rasters[[key]] <- wapor_calc_seasonal_etc(
      ret_stack, season_weights, kc_profiles[[key]],
      layer_multipliers = ret_layer_multipliers
    )
  }
  
  # Aggregate by class
  kc_by_class <- list()
  etc_by_class <- list()
  n_layers <- terra::nlyr(season_weights)
  
  for (j in seq_len(nrow(crop_params))) {
    cls <- as.character(crop_params$class_value[j])
    class_profiles <- profile_table[profile_table$class_value == as.integer(cls), , drop = FALSE]
    if (nrow(class_profiles) == 0) next
    
    class_etc <- NULL
    class_kc <- matrix(NA_real_, nrow = nrow(class_profiles), ncol = n_layers)
    
    for (i in seq_len(nrow(class_profiles))) {
      key <- class_profiles$kc_key[i]
      profile_mask <- terra::ifel(
        (h_mask == as.integer(cls)) &
          (h_start == class_profiles$start_jd[i]) &
          (h_end == class_profiles$end_jd[i]),
        1L, NA
      )
      profile_etc <- unique_etc_rasters[[key]] * profile_mask
      class_etc <- if (is.null(class_etc)) profile_etc else terra::cover(class_etc, profile_etc)
      class_kc[i, ] <- kc_profiles[[key]]
    }
    
    kc_by_class[[cls]] <- if (nrow(class_kc) == 1) {
      as.numeric(class_kc[1, ])
    } else {
      as.numeric(colSums(class_kc * class_profiles$pixel_count) / sum(class_profiles$pixel_count))
    }
    
    etc_by_class[[cls]] <- list(
      kc_dekad = kc_by_class[[cls]],
      etc_seasonal = class_etc
    )
  }
  
  list(kc_by_class = kc_by_class, etc_by_class = etc_by_class)
}

.build_season_profile_table <- function(crop_mask, start_raster, end_raster, class_values) {
  # Optimization: Using terra::crosstab(..., long = TRUE) is significantly more
  # memory-efficient than extracting all pixels into R via terra::values().
  
  # Round to integers for consistency and efficiency
  s <- terra::round(start_raster)
  e <- terra::round(end_raster)

  # Combine rasters for crosstab (mask, start, end)
  stk <- c(crop_mask, s, e)
  profile_df <- tryCatch({
    terra::crosstab(stk, long = TRUE)
  }, error = function(err) NULL)

  if (is.null(profile_df) || nrow(profile_df) == 0) {
    return(data.frame(
      class_value = integer(0), start_jd = integer(0), 
      end_jd = integer(0), total_days = integer(0), pixel_count = integer(0)
    ))
  }

  # Standardize names and types
  names(profile_df) <- c("class_value", "start_jd", "end_jd", "pixel_count")
  
  profile_df$class_value <- as.integer(profile_df$class_value)
  profile_df <- profile_df[profile_df$class_value %in% as.integer(class_values), , drop = FALSE]

  profile_df$start_jd    <- as.integer(profile_df$start_jd)
  profile_df$end_jd      <- as.integer(profile_df$end_jd)
  profile_df$pixel_count <- as.integer(profile_df$pixel_count)
  profile_df$total_days  <- profile_df$end_jd - profile_df$start_jd + 1L

  # Final filter for valid seasons and column reordering
  profile_df <- profile_df[profile_df$total_days > 0L, , drop = FALSE]
  profile_df <- profile_df[, c("class_value", "start_jd", "end_jd", "total_days", "pixel_count"), drop = FALSE]

  rownames(profile_df) <- NULL
  profile_df
}

.save_analysis_outputs <- function(results, output_folder, prefix, indicators) {
  if (!dir.exists(output_folder)) dir.create(output_folder, recursive = TRUE)
  
  # Save seasonal AETI
  if (!is.null(results$seasonal_aeti)) {
    terra::writeRaster(
      results$seasonal_aeti$raster,
      file.path(output_folder, paste0(prefix, "_seasonal_aeti.tif")),
      overwrite = TRUE
    )
  }
  
  # Save seasonal RET
  if (!is.null(results$seasonal_ret)) {
    terra::writeRaster(
      results$seasonal_ret$raster,
      file.path(output_folder, paste0(prefix, "_seasonal_ret.tif")),
      overwrite = TRUE
    )
  }
  
  # Save biomass
  if (!is.null(results$seasonal_biomass_kg) && 
      any(c("agg_biomass_kg", "yield_npp") %in% indicators)) {
    terra::writeRaster(
      results$seasonal_biomass_kg,
      file.path(output_folder, paste0(prefix, "_seasonal_biomass_kg_ha.tif")),
      overwrite = TRUE
    )
  }
  
  # Save adequacy
  if (!is.null(results$adequacy_etc)) {
    terra::writeRaster(
      results$adequacy_etc,
      file.path(output_folder, paste0(prefix, "_adequacy_etc.tif")),
      overwrite = TRUE
    )
  }
  
  # Save ETc by class
  if (!is.null(results$etc_by_class)) {
    for (cls in names(results$etc_by_class)) {
      terra::writeRaster(
        results$etc_by_class[[cls]]$etc_seasonal,
        file.path(output_folder, paste0(prefix, "_etc_class_", cls, ".tif")),
        overwrite = TRUE
      )
    }
  }
  
  # Save CSV summary
  if (!is.null(results$seasonal_aeti$by_class)) {
    utils::write.csv(
      results$seasonal_aeti$by_class,
      file.path(output_folder, paste0(prefix, "_summary.csv")),
      row.names = FALSE
    )
  }
}

.log_analysis_error <- function(e, config, log_file) {
  tryCatch({
    writeLines(c(
      sprintf("=== Analysis Error at %s ===", Sys.time()),
      sprintf("Error: %s", e$message),
      "",
      "Configuration:",
      sprintf("  Period: %s to %s", config$period[1], config$period[2]),
      sprintf("  AETI: %s", config$aeti_var),
      sprintf("  RET: %s", config$ret_var),
      sprintf("  Indicators: %s", paste(config$indicators, collapse = ", ")),
      "",
      "Traceback:",
      capture.output(traceback()),
      ""
    ), log_file, sep = "\n")
  }, error = function(log_err) {
    warning(sprintf("Failed to write error log: %s", log_err$message))
  })
}

.crop_to_region <- function(x, reg_info) {
  if (reg_info$type == "bbox") {
    terra::crop(x, reg_info$extent)
  } else if (reg_info$type == "vector") {
    terra::mask(terra::crop(x, reg_info$extent), reg_info$vector)
  } else {
    x
  }
}
