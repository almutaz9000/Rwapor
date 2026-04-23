# R/analysis_engine.R

#' Run Seasonal Analysis Engine
#'
#' Standalone function that performs the seasonal analysis workflow.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop class parameters (Kc, HI, etc.).
#' @param rasters List of terra::SpatRaster objects (mask, start, end).
#' @param aoi_region Optional numeric vector for the region bbox.
#' @param progress_callback Optional function(value, detail) for updates.
#' @return List of results (SpatRaster objects and summary tables).
#' @export
wapor_run_seasonal_analysis <- function(config, crop_params, rasters, aoi_region = NULL, progress_callback = NULL) {
  
  if (is.null(progress_callback)) progress_callback <- function(v, d) NULL
  
  # Handle multi-period list
  if (is.list(config$period) && length(config$period) > 1) {
    periods <- config$period
    all_results <- list()
    n_p <- length(periods)
    
    for (i in seq_along(periods)) {
      p_name <- names(periods)[i] %||% sprintf("Season_%d", i)
      progress_callback(i / n_p, sprintf("Processing %s...", p_name))
      
      # Create a shallow copy of config with the single period
      p_config <- config
      p_config$period <- periods[[i]]
      
      # Auto-derive ref_year for this season if needed
      if (is.null(p_config$ref_year)) {
        p_config$ref_year <- as.integer(format(as.Date(p_config$period[1]), "%Y"))
      }
      
      # Smart-Linking: Look for season-specific masks in folder/seasonal_masks
      p_rasters <- rasters
      if (!is.null(config$folder)) {
        # Check both the folder itself and the 'seasonal_masks' subfolder
        mask_dirs <- c(config$folder, file.path(config$folder, "seasonal_masks"))
        for (m_dir in mask_dirs) {
          s_start_path <- file.path(m_dir, paste0(p_name, "_start.tif"))
          s_end_path   <- file.path(m_dir, paste0(p_name, "_end.tif"))
          s_mask_path  <- file.path(m_dir, paste0(p_name, "_mask.tif"))
          
          if (file.exists(s_start_path)) {
            p_rasters$season_start <- terra::rast(s_start_path)
            p_config$use_season_rasters <- TRUE
          }
          if (file.exists(s_end_path)) {
            p_rasters$season_end <- terra::rast(s_end_path)
            p_config$use_season_rasters <- TRUE
          }
          if (file.exists(s_mask_path)) {
            p_rasters$crop_mask <- terra::rast(s_mask_path)
            p_config$use_crop_mask <- TRUE
          }
        }
      }
      
      # Recursive call for single period
      all_results[[p_name]] <- wapor_run_seasonal_analysis(
        config = p_config, 
        crop_params = crop_params, 
        rasters = p_rasters, 
        aoi_region = aoi_region, 
        progress_callback = NULL # Suppress sub-progress
      )
    }
    return(all_results)
  }

  # 1. Resolve basic params
  period      <- config$period
  ref_year    <- config$ref_year %||% as.integer(format(as.Date(period[1]), "%Y"))
  aeti_var    <- config$aeti_var
  ret_var     <- config$ret_var
  precip_var  <- config$precip_var
  npp_var     <- config$npp_var
  t_var       <- config$t_var
  l3_code     <- config$l3_code
  indicators  <- config$indicators
  use_local   <- config$data_source == "local"
  folder      <- config$folder
  use_incremental <- isTRUE(config$incremental)
  
  # 2. Get template and harmonize
  progress_callback(0.05, "Getting reference raster...")
  
  template_r <- NULL
  reg_info   <- if (!is.null(aoi_region)) Rwapor::wapor_parse_region(aoi_region) else NULL
  
  if (use_local) {
    # Prefer AETI for template, fallback to others
    template_var <- if (!is.null(aeti_var) && nchar(aeti_var) > 0) aeti_var else precip_var
    paths <- Rwapor::wapor_local_rasters(folder, template_var, period[1], period[2])
    if (length(paths) == 0) stop(sprintf("No local files found for %s to use as template.", template_var))
    template_r <- terra::rast(paths[1])
  } else {
    template_var <- if (!is.null(aeti_var) && nchar(aeti_var) > 0) aeti_var else precip_var
    urls <- Rwapor::wapor_generate_urls(template_var, l3_region = l3_code, period = period)
    if (length(urls) == 0) stop(sprintf("No data found for %s.", template_var))
    template_r <- terra::rast(paste0("/vsicurl/", urls[1]))
  }
  
  if (!is.null(reg_info)) {
    template_r <- Rwapor::wapor_crop_to_region(template_r, reg_info, do_mask = (reg_info$type == "vector"))
  }
  
  progress_callback(0.10, "Harmonizing inputs...")
  
  # Harmonize mask
  h_mask <- if (isTRUE(config$use_crop_mask)) {
    Rwapor::wapor_harmonize_crop_mask(rasters$crop_mask, template_r)
  } else {
    # If no mask used, treat entire area as class 1
    template_r[[1]] * 0 + 1L
  }
  
  # Harmonize season rasters
  h_start <- if (isTRUE(config$use_season_rasters)) {
    Rwapor::wapor_harmonize_raster(rasters$season_start, template_r, method = "near")
  } else {
    template_r * 0 + Rwapor::wapor_continuous_julian(period[1], ref_year)
  }
  
  h_end <- if (isTRUE(config$use_season_rasters)) {
    Rwapor::wapor_harmonize_raster(rasters$season_end, template_r, method = "near")
  } else {
    template_r * 0 + Rwapor::wapor_continuous_julian(period[2], ref_year)
  }
  
  # 3. Build Weights
  progress_callback(0.15, "Building season weights...")
  sw <- Rwapor::wapor_build_season_weights(period[1], period[2], h_start, h_end, ref_year)
  season_weights <- sw$weights
  dekad_table    <- sw$dekad_table
  target_dates   <- dekad_table$dekad_key
  
  # 4. Resolve and Load Stacks
  progress_callback(0.20, "Building raster stacks...")
  
  # Helpers (internal to engine)
  .resolve_paths <- function(var, use_local, folder, period, l3_code) {
    if (is.null(var) || nchar(var) == 0) return(NULL)
    if (use_local) {
      paths <- Rwapor::wapor_local_rasters(folder, var, period[1], period[2])
      if (length(paths) == 0) return(NULL)
      paths
    } else {
      urls <- Rwapor::wapor_generate_urls(var, l3_region = l3_code, period = period)
      if (length(urls) == 0) return(NULL)
      paste0("/vsicurl/", urls)
    }
  }
  
  .load_and_harmonize <- function(var, paths, template, reg_info, method = "near") {
    if (is.null(paths)) return(NULL)
    stack <- terra::rast(paths)
    if (!is.null(reg_info)) {
      stack <- Rwapor::wapor_crop_to_region(stack, reg_info, do_mask = (reg_info$type == "vector"))
    }
    Rwapor::wapor_harmonize_raster(stack, template, method = method)
  }
  
  # Align helper
  .align_to_weights <- function(s, targets) {
    if (is.null(s)) return(NULL)
    nms <- names(s)
    extract_ymd <- function(nm) {
      m <- regmatches(nm, regexpr("\\d{4}-\\d{2}-\\d{2}", nm))
      if (length(m)) return(m)
      m <- regmatches(nm, regexpr("(?<![0-9])\\d{12}(?![0-9])", nm, perl = TRUE))
      if (length(m)) return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
      m <- regmatches(nm, regexpr("(?<![0-9])\\d{8}(?![0-9])", nm, perl = TRUE))
      if (length(m)) return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
      NA_character_
    }
    found <- vapply(nms, extract_ymd, character(1), USE.NAMES = FALSE)
    idx <- match(as.character(targets), found)
    if (any(is.na(idx))) stop("Missing data for some dekads in the analysis period.")
    s[[idx]]
  }

  # Loading logic
  stacks <- list()
  if (any(c("agg_aeti", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "green_water", "blue_water", "beneficial_fraction") %in% indicators)) {
    progress_callback(0.25, sprintf("Loading %s...", aeti_var %||% "AETI"))
    p <- .resolve_paths(aeti_var, use_local, folder, period, l3_code)
    stacks$aeti <- .align_to_weights(.load_and_harmonize(aeti_var, p, template_r, reg_info, "bilinear"), target_dates)
  }
  if (any(c("agg_ret", "etc", "adequacy_etc") %in% indicators)) {
    progress_callback(0.30, sprintf("Loading %s...", ret_var %||% "RET"))
    p <- .resolve_paths(ret_var, use_local, folder, period, l3_code)
    stacks$ret <- .align_to_weights(.load_and_harmonize(ret_var, p, template_r, reg_info), target_dates)
  }
  if (any(c("agg_pcp", "peff", "green_water", "blue_water") %in% indicators)) {
    progress_callback(0.35, sprintf("Loading %s...", precip_var %||% "PCP"))
    p <- .resolve_paths(precip_var, use_local, folder, period, l3_code)
    stacks$precip <- .align_to_weights(.load_and_harmonize(precip_var, p, template_r, reg_info), target_dates)
  }
  if (any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp") %in% indicators)) {
    progress_callback(0.40, sprintf("Loading %s...", npp_var %||% "NPP"))
    p <- .resolve_paths(npp_var, use_local, folder, period, l3_code)
    stacks$npp <- .align_to_weights(.load_and_harmonize(npp_var, p, template_r, reg_info), target_dates)
  }
  if (any(c("agg_t", "beneficial_fraction") %in% indicators)) {
    progress_callback(0.42, sprintf("Loading %s...", t_var %||% "Transpiration"))
    p <- .resolve_paths(t_var, use_local, folder, period, l3_code)
    stacks$t <- .align_to_weights(.load_and_harmonize(t_var, p, template_r, reg_info, "bilinear"), target_dates)
  }

  # 5. Calculations
  progress_callback(0.40, "Performing aggregations...")
  
  # Calculate mask stats (area-weighted means in dashboard depend on this)
  progress_callback(0.45, "Calculating class statistics...")
  mask_stats <- terra::freq(h_mask)
  # terra::freq returns [layer, value, count]
  names(mask_stats) <- c("layer", "class_value", "pixel_count")
  
  # Calculate approximate area in ha (assuming lonlat WGS84 for now)
  res_xy <- terra::res(template_r)
  pixel_area_ha <- if (terra::is.lonlat(template_r)) {
    (res_xy[1] * 111320) * (res_xy[2] * 111320 * cos(terra::ext(template_r)$ymin * pi / 180)) / 10000
  } else {
    (res_xy[1] * res_xy[2]) / 10000
  }
  mask_stats$area_ha <- mask_stats$pixel_count * pixel_area_ha

  results <- list(
    h_mask = h_mask,
    h_start = h_start,
    h_end = h_end,
    template_r = template_r,
    dekad_table = dekad_table,
    mask_class_stats = mask_stats,
    valid_crop_mask = h_mask # Exported for visualization/stats in mod_analysis
  )
  
  # Multipliers
  aeti_mult   <- if (!is.null(stacks$aeti))   Rwapor:::analysis_layer_multipliers(aeti_var, dekad_table)   else NULL
  ret_mult    <- if (!is.null(stacks$ret))    Rwapor:::analysis_layer_multipliers(ret_var, dekad_table)    else NULL
  precip_mult <- if (!is.null(stacks$precip)) Rwapor:::analysis_layer_multipliers(precip_var, dekad_table) else NULL
  npp_mult    <- if (!is.null(stacks$npp))    Rwapor:::analysis_layer_multipliers(npp_var, dekad_table)    else NULL
  t_mult      <- if (!is.null(stacks$t))      Rwapor:::analysis_layer_multipliers(t_var, dekad_table)      else NULL

  # Aggregates
  if (!is.null(stacks$aeti)) {
    results$seasonal_aeti <- Rwapor::wapor_calc_seasonal_aeti(stacks$aeti, season_weights, h_mask, aeti_mult, incremental = use_incremental)
  }
  if (!is.null(stacks$ret)) {
    results$seasonal_ret <- Rwapor::wapor_calc_seasonal_ret(stacks$ret, season_weights, h_mask, ret_mult, incremental = use_incremental)
  }
  if ("agg_pcp" %in% indicators && !is.null(stacks$precip)) {
    results$seasonal_pcp <- Rwapor::wapor_masked_sum(stacks$precip, season_weights, precip_mult, incremental = use_incremental)
  }
  if ("agg_t" %in% indicators && !is.null(stacks$t)) {
    # T is a flux (mm/day), same as AETI
    results$seasonal_t <- Rwapor::wapor_calc_seasonal_aeti(stacks$t, season_weights, h_mask, t_mult, incremental = use_incremental)
  }
  if (any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp") %in% indicators) && !is.null(stacks$npp)) {
    results$seasonal_biomass_kg <- Rwapor::wapor_masked_sum(stacks$npp, season_weights, npp_mult, incremental = use_incremental) * 22.222
    results$seasonal_biomass_t  <- results$seasonal_biomass_kg / 1000
    results$seasonal_biomass    <- results$seasonal_biomass_kg
  }

  # 5. Derived Indicators
  progress_callback(0.60, "Computing derived indicators...")

  # ETc
  if ("etc" %in% indicators || "adequacy_etc" %in% indicators) {
    if (is.null(stacks$ret)) stop("RET stack is required for ETc/Adequacy.")
    
    profile_table <- wapor_build_season_profile_table(h_mask, h_start, h_end, crop_params$class_value)
    if (nrow(profile_table) > 0) {
      # This is the complex logic from mod_analysis.R
      # For now, I'll implement the per-profile ETc calculation
      
      kc_profiles <- list()
      profile_table$kc_key <- NA_character_
      for (i in seq_len(nrow(profile_table))) {
        profile_row <- profile_table[i, ]
        cp <- crop_params[crop_params$class_value == profile_row$class_value, , drop = FALSE]
        if (nrow(cp) == 0) next

        fixed_sum <- cp$l_ini_days + cp$l_mid_days + cp$l_late_days
        l_dev     <- as.integer(profile_row$total_days - fixed_sum)
        if (l_dev < 0L) l_dev <- 0L

        kc_daily <- Rwapor::wapor_build_kc(
          kc_ini = cp$kc_ini[1], kc_mid = cp$kc_mid[1], kc_end = cp$kc_end[1],
          L_ini = cp$l_ini_days[1], L_dev = l_dev, L_mid = cp$l_mid_days[1], L_late = cp$l_late_days[1]
        )
        season_start_date <- as.Date(sprintf("%04d-01-01", ref_year)) + profile_row$start_jd - 1L
        kc_dekad <- Rwapor::wapor_aggregate_kc(kc_daily, dekad_table, season_start_date)
        kc_key   <- paste(round(kc_dekad, 6), collapse = ",")
        profile_table$kc_key[i] <- kc_key
        if (is.null(kc_profiles[[kc_key]])) kc_profiles[[kc_key]] <- kc_dekad
      }

      unique_etc_rasters <- list()
      for (key in names(kc_profiles)) {
        unique_etc_rasters[[key]] <- Rwapor::wapor_calc_seasonal_etc(stacks$ret, season_weights, kc_profiles[[key]], layer_multipliers = ret_mult)
      }

      etc_by_class <- list()
      for (j in seq_len(nrow(crop_params))) {
        cls <- as.character(crop_params$class_value[j])
        class_profiles <- profile_table[profile_table$class_value == as.integer(cls), , drop = FALSE]
        if (nrow(class_profiles) == 0) next

        class_etc <- NULL
        for (i in seq_len(nrow(class_profiles))) {
          key <- class_profiles$kc_key[i]
          profile_mask <- terra::ifel((h_mask == as.integer(cls)) & (h_start == class_profiles$start_jd[i]) & (h_end == class_profiles$end_jd[i]), 1L, NA)
          profile_etc  <- unique_etc_rasters[[key]] * profile_mask
          class_etc    <- if (is.null(class_etc)) profile_etc else terra::cover(class_etc, profile_etc)
        }
        etc_by_class[[cls]] <- list(etc_seasonal = class_etc)
      }
      results$etc_by_class <- etc_by_class
    }
  }

  # Adequacy ETc
  if ("adequacy_etc" %in% indicators && !is.null(results$seasonal_aeti) && !is.null(results$etc_by_class)) {
    all_etc <- lapply(results$etc_by_class, function(x) x$etc_seasonal)
    if (length(all_etc) > 0) {
      combined_etc <- all_etc[[1]]
      if (length(all_etc) > 1) {
        for (k in seq_along(all_etc)[-1]) combined_etc <- terra::cover(combined_etc, all_etc[[k]])
      }
      results$adequacy_etc <- Rwapor::wapor_calc_adequacy_etc(results$seasonal_aeti$raster, combined_etc)
    }
  }

  # Adequacy P95
  if ("adequacy_p95" %in% indicators && !is.null(results$seasonal_aeti)) {
    p95_table <- Rwapor::wapor_calc_p95_aeti(results$seasonal_aeti$raster, h_mask)
    results$p95_table <- p95_table
    results$adequacy_p95 <- Rwapor::wapor_calc_adequacy_p95(results$seasonal_aeti$raster, h_mask, p95_table)
  }

  # Beneficial Fraction (T/AETI)
  if ("beneficial_fraction" %in% indicators && !is.null(results$seasonal_aeti) && !is.null(results$seasonal_t)) {
    results$beneficial_fraction <- Rwapor::wapor_calc_beneficial_fraction(results$seasonal_t$raster, results$seasonal_aeti$raster)
  }

  # Peff (simplified seasonal estimate)
  if ("agg_peff" %in% indicators && !is.null(stacks$precip)) {
     # Simplified USDA-SCS on seasonal total if monthly AGERA5 not fully parsed here
     # ... (Implementation can be expanded as needed)
  }

  # Green/Blue Water
  if (any(c("green_water", "blue_water") %in% indicators) && !is.null(results$seasonal_aeti) && !is.null(stacks$precip)) {
     if (is.null(results$seasonal_pcp)) {
        results$seasonal_pcp <- Rwapor::wapor_masked_sum(stacks$precip, season_weights, precip_mult, incremental = use_incremental)
     }
     peff_raster <- terra::ifel(results$seasonal_pcp <= 250, results$seasonal_pcp * (125 - 0.2 * results$seasonal_pcp) / 125, 125 + 0.1 * results$seasonal_pcp)
     if ("green_water" %in% indicators) results$green_water <- Rwapor::wapor_calc_green_water(results$seasonal_aeti$raster, peff_raster)
     if ("blue_water" %in% indicators)  results$blue_water <- Rwapor::wapor_calc_blue_water(results$seasonal_aeti$raster, peff_raster)
  }

  # Yield and CWP/BWP...
  if ("yield_npp" %in% indicators && !is.null(results$seasonal_biomass)) {
    yield_layers <- list()
    for (j in seq_len(nrow(crop_params))) {
      cls <- as.character(crop_params$class_value[j])
      cp <- crop_params[j, ]
      class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
      yield_rast <- (cp$HI * cp$AOT * cp$fc * (results$seasonal_biomass / (1 - cp$MC))) / 1000
      yield_layers[[cls]] <- yield_rast * class_mask
    }
    results$yield_by_class <- yield_layers
  }

  # 6. Cleanup & Return
  progress_callback(0.95, "Finalizing...")
  results$crop_params <- crop_params
  return(results)
}

#' Internal helper to load and harmonize (internal usage)
#' @keywords internal
wapor_load_and_harmonize <- function(paths, template, reg_info, method = "near") {
  if (is.null(paths)) return(NULL)
  stack <- terra::rast(paths)
  if (!is.null(reg_info)) {
    stack <- Rwapor::wapor_crop_to_region(stack, reg_info, do_mask = (reg_info$type == "vector"))
  }
  Rwapor::wapor_harmonize_raster(stack, template, method = method)
}
