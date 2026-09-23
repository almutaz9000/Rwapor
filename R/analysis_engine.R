# R/analysis_engine.R

#' Run Seasonal Analysis Engine
#'
#' Standalone function that performs the seasonal analysis workflow.
#'
#' @param config List of configuration parameters. Besides the variable codes,
#'   `period`, `data_source`, `folder` and `indicators`, it accepts:
#'   * `processing`: `"auto"` (default), `"memory"`, `"stream"` or `"tiled"`.
#'     See [wapor_plan_processing()].
#'   * `min_coverage`: share of season days a pixel must have data for
#'     (default `1`, every dekad). Pixels below it are `NA` rather than having
#'     missing dekads counted as zero.
#'   * `keep_intermediates`: keep `dekadal_stacks` and `season_weights` in the
#'     result. Defaults to `TRUE` in memory mode and `FALSE` otherwise.
#'   * `output_dir`: folder for stream and tiled outputs (default: a folder
#'     under [tempdir()]).
#'   * `reference_layer`, `resampling_method`: target grid and per-layer
#'     resampling (see Details).
#' @param crop_params data.frame of crop class parameters (Kc, HI, etc.).
#' @param rasters List of terra::SpatRaster objects (mask, start, end).
#' @param aoi_region Optional region (bbox, vector path or sf). When `NULL`,
#'   the extent of `rasters$crop_mask` (or the season rasters) is used.
#' @param progress_callback Optional function(value, detail) for updates.
#' @return List of results (SpatRaster objects and summary tables), including
#'   `coverage` (per-variable share of season days with data) and `processing`
#'   (the [wapor_plan_processing()] plan that ran).
#' @details
#' Alignment uses `config$reference_layer` (`"aeti"` default, also
#' `"crop_mask"`, `"ret"`, `"pcp"`, `"npp"`, `"template"`).
#'
#' Seasonal and monthly totals are summed at each source's native resolution
#' and then resampled once onto the analysis grid. With the default
#' nearest-neighbour resampling every output value is a raw server value or a
#' sum of raw values. Set `config$resampling_method` (for example
#' `c(ret = "bilinear")`) to interpolate instead. Crop mask and season rasters
#' always use nearest neighbour.
#' @export
wapor_run_seasonal_analysis <- function(config, crop_params, rasters, aoi_region = NULL, progress_callback = NULL) {

  if (is.null(progress_callback)) progress_callback <- function(v, d) NULL

  # Handle multi-period list
  if (is.list(config$period)) {
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

      if (!is.null(config$output_dir)) {
        p_config$output_dir <- file.path(config$output_dir, p_name)
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
  l3_mode     <- config$l3_mode %||% "select"
  # Normalize l3_code: for mosaic_all with a vector of codes, use NULL so
  # wapor_generate_urls returns all intersecting region data; for select mode
  # with a single code, pass it through; for mosaic_all with a single selected
  # code, pass the single code.
  if (identical(l3_mode, "mosaic_all") && is.character(l3_code) && length(l3_code) > 1L) {
    l3_code <- NULL
  }
  indicators  <- wapor_normalize_analysis_indicators(config$indicators)
  use_local   <- identical(config$data_source, "local")
  folder      <- config$folder
  processing  <- match.arg(config$processing %||% "auto", .wapor_processing_modes)
  min_coverage <- config$min_coverage %||% 1

  # An analysis without an AOI used the full extent of the first source file,
  # which for WaPOR L1 is the whole globe. Default to the crop mask extent.
  if (is.null(aoi_region)) {
    aoi_region <- .wapor_default_aoi(rasters)
  }

  # 2. Get template and harmonize
  progress_callback(0.05, "Getting reference raster...")

  template_r <- NULL
  reg_info   <- if (!is.null(aoi_region)) Rwapor::wapor_parse_region(aoi_region) else NULL
  reference_layer <- config$reference_layer %||% "aeti"
  reference_layer <- match.arg(
    reference_layer,
    c("aeti", "crop_mask", "ret", "pcp", "npp", "template")
  )
  resampling_method <- utils::modifyList(
    list(
      aeti = "near", crop_mask = "near", ret = "near",
      pcp = "near", npp = "near", t = "near",
      season_start = "near", season_end = "near"
    ),
    as.list(config$resampling_method %||% list())
  )
  get_resampling_method <- function(layer, default = "near") {
    resampling_method[[layer]] %||% default
  }

  if (identical(reference_layer, "crop_mask")) {
    if (is.null(rasters$crop_mask) || !inherits(rasters$crop_mask, "SpatRaster")) {
      stop("reference_layer = \"crop_mask\" requires rasters$crop_mask.", call. = FALSE)
    }
    template_r <- rasters$crop_mask
    if (terra::nlyr(template_r) > 1) template_r <- template_r[[1]]
  } else if (identical(reference_layer, "template") && inherits(config$template, "SpatRaster")) {
    template_r <- config$template
  } else {
    template_var <- switch(
      reference_layer,
      aeti = if (!is.null(aeti_var) && nchar(aeti_var) > 0) aeti_var else precip_var,
      ret = ret_var,
      pcp = precip_var,
      npp = npp_var,
      if (!is.null(aeti_var) && nchar(aeti_var) > 0) aeti_var else precip_var
    )
    if (use_local) {
      paths <- wapor_local_rasters(folder, template_var, period[1], period[2])
      if (length(paths) == 0) stop(sprintf("No local files found for %s to use as template.", template_var))
      template_r <- terra::rast(paths[1])
    } else {
      urls <- Rwapor::wapor_generate_urls(template_var, l3_region = l3_code, period = period)
      if (length(urls) == 0) stop(sprintf("No data found for %s.", template_var))
      template_r <- terra::rast(.wapor_resolve_remote_sources(urls[1])[[1]])
    }
  }

  if (terra::nlyr(template_r) > 1) template_r <- template_r[[1]]

  if (!is.null(reg_info)) {
    template_r <- Rwapor::wapor_crop_to_region(template_r, reg_info, do_mask = (reg_info$type == "vector"))
  }

  progress_callback(0.10, "Harmonizing inputs...")

  # Harmonize mask
  h_mask <- if (isTRUE(config$use_crop_mask)) {
    Rwapor::wapor_harmonize_raster(
      rasters$crop_mask, template_r, method = get_resampling_method("crop_mask", "near")
    )
  } else {
    # If no mask used, treat entire area as class 1
    template_r[[1]] * 0 + 1L
  }
  if (!is.null(reg_info) && identical(reg_info$type, "vector")) {
    h_mask <- .wapor_mask_to_region(h_mask, reg_info)
  }

  # Harmonize season rasters
  h_start <- if (isTRUE(config$use_season_rasters)) {
    Rwapor::wapor_harmonize_raster(rasters$season_start, template_r, method = get_resampling_method("season_start", "near"))
  } else {
    template_r * 0 + Rwapor::wapor_continuous_julian(period[1], ref_year)
  }

  h_end <- if (isTRUE(config$use_season_rasters)) {
    Rwapor::wapor_harmonize_raster(rasters$season_end, template_r, method = get_resampling_method("season_end", "near"))
  } else {
    template_r * 0 + Rwapor::wapor_continuous_julian(period[2], ref_year)
  }

  # 3. Resolve sources, aligned one per dekad
  progress_callback(0.15, "Resolving source rasters...")
  dekad_table <- build_dekad_table(period[1], period[2])
  target_dates <- dekad_table$dekad_key

  .resolve_paths <- function(var) {
    if (is.null(var) || !nzchar(var)) return(NULL)
    paths <- if (use_local) {
      wapor_local_rasters(folder, var, period[1], period[2])
    } else {
      urls <- Rwapor::wapor_generate_urls(var, l3_region = l3_code, period = period)
      if (length(urls) == 0) return(NULL)
      .wapor_resolve_remote_sources(urls)
    }
    if (!length(paths)) return(NULL)
    .wapor_align_paths_to_dekads(paths, target_dates)
  }

  needs <- list(
    aeti = any(c("agg_aeti", "etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "green_water", "blue_water", "beneficial_fraction") %in% indicators),
    ret = any(c("agg_ret", "etc", "adequacy_etc") %in% indicators),
    pcp = any(c("agg_pcp", "agg_peff", "green_water", "blue_water") %in% indicators),
    npp = any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp") %in% indicators),
    t = any(c("agg_t", "beneficial_fraction") %in% indicators),
    etc = any(c("etc", "adequacy_etc") %in% indicators)
  )
  var_codes <- list(aeti = aeti_var, ret = ret_var, pcp = precip_var, npp = npp_var, t = t_var)

  kernel_vars <- list()
  for (key in names(var_codes)) {
    if (!isTRUE(needs[[key]])) next
    paths <- .resolve_paths(var_codes[[key]])
    if (is.null(paths)) next
    kernel_vars[[key]] <- list(
      variable = var_codes[[key]],
      paths = paths,
      multipliers = get_analysis_layer_multipliers(var_codes[[key]], dekad_table),
      method = get_resampling_method(key, "near"),
      remote = !use_local
    )
  }
  if (isTRUE(needs$etc)) {
    if (is.null(kernel_vars$ret)) stop("RET stack is required for ETc/Adequacy.")
    kernel_vars$etc <- utils::modifyList(kernel_vars$ret, list(kc = TRUE))
  }

  # 4. Plan and aggregate
  progress_callback(0.20, "Planning processing...")
  output_dir <- config$output_dir %||% tempfile("run-", tmpdir = file.path(tempdir(), "rwapor-runs"))
  job <- .wapor_build_kernel_job(
    period = period, reference_year = ref_year, template = template_r,
    h_mask = h_mask, h_start = h_start, h_end = h_end,
    variables = kernel_vars, crop_params = crop_params,
    min_coverage = min_coverage, work_dir = file.path(output_dir, "job")
  )
  plan <- .wapor_plan_for_job(job, template_r, processing)
  if (!is.null(config$tile_size)) {
    plan$tile_size <- as.integer(config$tile_size)
  }
  # Hold terra's own processing (derived indicators, zonal statistics) to the
  # same budget; beyond it terra works block-wise through temporary files.
  # Derived rasters are also written to disk so the returned results are
  # file-backed instead of held in RAM.
  old_terra <- tryCatch(terra::terraOptions(print = FALSE), error = function(e) NULL)
  if (!identical(plan$mode, "memory") && !is.null(old_terra)) {
    # 8-byte files keep file-backed results identical to memory mode.
    terra::terraOptions(memmax = plan$budget_bytes / 1024^3, todisk = TRUE, datatype = "FLT8S")
    on.exit(terra::terraOptions(memmax = old_terra$memmax, todisk = old_terra$todisk,
                                datatype = old_terra$datatype), add = TRUE)
  }
  log_msg(sprintf("Processing mode: %s (%s).", plan$mode, plan$reasons[[length(plan$reasons)]]))

  run <- .wapor_run_kernel(
    job, template_r, plan,
    output_dir = output_dir,
    cog = isTRUE(config$cog),
    resume = isTRUE(config$resume),
    manifest_extra = config$manifest_extra %||% list(),
    progress_callback = function(v, d) progress_callback(0.20 + 0.40 * v, d)
  )
  agg <- run$rasters
  months <- names(job$month_targets)
  get_season <- function(key) agg[[paste0(key, "__season")]]
  get_months <- function(key) {
    if (is.null(agg[[paste0(key, "__season")]])) return(NULL)
    stats::setNames(lapply(months, function(m) agg[[paste0(key, "__", m)]]), months)
  }

  # 5. Calculations
  progress_callback(0.62, "Calculating class statistics...")
  mask_stats <- terra::freq(h_mask)
  # terra::freq returns [layer, value, count]
  names(mask_stats) <- c("layer", "class_value", "pixel_count")

  # Per-pixel area: latitude-aware on lon/lat grids, constant on projected grids.
  apply_area_weight <- if (is.null(config$area_weighted)) TRUE else isTRUE(config$area_weighted)
  pixel_area_r <- if (apply_area_weight) wapor_pixel_area_ha(template_r) else NULL
  if (apply_area_weight && !is.null(pixel_area_r)) {
    area_by_class <- as.data.frame(terra::zonal(pixel_area_r, h_mask, fun = "sum", na.rm = TRUE))
    names(area_by_class)[seq_len(min(2, ncol(area_by_class)))] <-
      c("class_value", "area_ha")[seq_len(min(2, ncol(area_by_class)))]
    mask_stats <- merge(mask_stats, area_by_class[, c("class_value", "area_ha"), drop = FALSE],
                        by = "class_value", all.x = TRUE)
  }

  valid_crop_mask <- terra::ifel(is.na(h_mask), NA, 1L)
  results <- list(
    h_mask = h_mask,
    h_start = h_start,
    h_end = h_end,
    template_r = template_r,
    dekad_table = dekad_table,
    mask_class_stats = mask_stats,
    valid_crop_mask = valid_crop_mask,
    pixel_area_ha = pixel_area_r
  )

  mult <- lapply(kernel_vars[intersect(names(kernel_vars), names(var_codes))], `[[`, "multipliers")
  aeti_mult   <- mult$aeti
  ret_mult    <- mult$ret
  precip_mult <- mult$pcp
  npp_mult    <- mult$npp
  t_mult      <- mult$t
  results$layer_multipliers <- Filter(Negate(is.null), mult)

  keep_intermediates <- config$keep_intermediates %||% identical(plan$mode, "memory")
  materialize_stacks <- function() {
    lapply(kernel_vars[intersect(names(kernel_vars), names(var_codes))], function(v) {
      .wapor_materialize_dekadal_stack(v$paths, template_r, reg_info, v$method, target_dates)
    })
  }
  materialize_weights <- function() {
    Rwapor::wapor_build_season_weights(period[1], period[2], h_start, h_end, ref_year)$weights
  }
  if (isTRUE(keep_intermediates)) {
    results$season_weights <- materialize_weights()
    stacks <- materialize_stacks()
    results$dekadal_stacks <- Filter(Negate(is.null), list(
      aeti = stacks$aeti, ret = stacks$ret, pcp = stacks$pcp, npp = stacks$npp, t = stacks$t
    ))
  }

  monthly_series <- function(key, value_name) {
    rasters_m <- get_months(key)
    if (is.null(rasters_m)) return(NULL)
    summary <- data.frame(
      month_key = months,
      year = as.integer(substr(months, 1, 4)),
      month = as.integer(substr(months, 6, 7)),
      stringsAsFactors = FALSE
    )
    summary[[value_name]] <- vapply(rasters_m, function(r) wapor_masked_global_mean(r, valid_crop_mask), numeric(1))
    list(rasters = rasters_m, summary = summary)
  }

  results$monthly_aeti <- monthly_series("aeti", "aeti_mean_mm")
  results$monthly_ret <- monthly_series("ret", "ret_mean_mm")
  results$monthly_t <- monthly_series("t", "t_mean_mm")
  if (!is.null(get_season("pcp"))) {
    pcp_m <- monthly_series("pcp", "pcp_mean_mm")
    peff_m <- lapply(pcp_m$rasters, .wapor_usda_peff)
    peff_summary <- pcp_m$summary
    peff_summary$peff_mean_mm <- vapply(peff_m, function(r) wapor_masked_global_mean(r, valid_crop_mask), numeric(1))
    results$monthly_precip_peff <- list(
      monthly_pcp = pcp_m$rasters,
      monthly_peff = peff_m,
      rasters = list(pcp = pcp_m$rasters, peff = peff_m),
      seasonal_peff = Reduce(`+`, peff_m),
      summary = peff_summary
    )
  }

  by_class_mean <- function(r, value_name) {
    out <- terra::zonal(r, h_mask, fun = "mean", na.rm = TRUE)
    names(out) <- c("class_value", value_name)
    out
  }

  # Aggregates
  if (!is.null(get_season("aeti"))) {
    results$seasonal_aeti <- list(raster = get_season("aeti"), by_class = by_class_mean(get_season("aeti"), "mean_seasonal_aeti"))
  }
  if (!is.null(get_season("ret"))) {
    results$seasonal_ret <- list(raster = get_season("ret"), by_class = by_class_mean(get_season("ret"), "mean_seasonal_ret"))
  }
  if (!is.null(get_season("pcp"))) {
    results$seasonal_pcp <- get_season("pcp")
  }
  if (!is.null(get_season("t"))) {
    # T is a flux (mm/day), same as AETI
    results$seasonal_t <- list(raster = get_season("t"), by_class = by_class_mean(get_season("t"), "mean_seasonal_aeti"))
  }
  if (!is.null(get_season("npp"))) {
    results$seasonal_biomass_kg <- get_season("npp") * 22.222
    results$seasonal_biomass_t  <- results$seasonal_biomass_kg / 1000
    results$seasonal_biomass    <- results$seasonal_biomass_kg
    results$seasonal_biomass_by_class <- terra::zonal(results$seasonal_biomass_kg, h_mask, fun = "mean", na.rm = TRUE)
    names(results$seasonal_biomass_by_class) <- c("class_value", "mean_seasonal_biomass_kg")
    results$seasonal_biomass_by_class$mean_seasonal_biomass_t <-
      results$seasonal_biomass_by_class$mean_seasonal_biomass_kg / 1000
    results$seasonal_biomass_by_class$mean_seasonal_biomass <-
      results$seasonal_biomass_by_class$mean_seasonal_biomass_kg
  }

  # Derived Indicators
  progress_callback(0.70, "Computing derived indicators...")

  # ETc: the kernel already applied each pixel's own Kc profile.
  combined_etc <- get_season("etc")
  if (!is.null(combined_etc)) {
    classes <- intersect(as.integer(crop_params$class_value), job$profiles$class_value)
    results$etc_by_class <- stats::setNames(lapply(classes, function(cls) {
      list(etc_seasonal = terra::ifel(h_mask == cls, combined_etc, NA))
    }), as.character(classes))
    results$monthly_etc <- monthly_series("etc", "etc_mean_mm")
  }

  # Adequacy ETc
  if ("adequacy_etc" %in% indicators && !is.null(results$seasonal_aeti) && !is.null(combined_etc)) {
    results$adequacy_etc <- Rwapor::wapor_calc_adequacy_etc(results$seasonal_aeti$raster, combined_etc)
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

  if (any(c("green_water", "blue_water") %in% indicators) && !is.null(results$monthly_aeti) && !is.null(results$monthly_precip_peff)) {
    month_keys <- intersect(names(results$monthly_aeti$rasters), names(results$monthly_precip_peff$monthly_peff))
    monthly_green <- list()
    monthly_blue <- list()

    for (month_key in month_keys) {
      monthly_green[[month_key]] <- Rwapor::wapor_calc_green_water(
        results$monthly_aeti$rasters[[month_key]],
        results$monthly_precip_peff$monthly_peff[[month_key]]
      )
      monthly_blue[[month_key]] <- Rwapor::wapor_calc_blue_water(
        results$monthly_aeti$rasters[[month_key]],
        results$monthly_precip_peff$monthly_peff[[month_key]]
      )
    }

    series_summary <- function(rs, value_name) {
      out <- data.frame(
        month_key = names(rs),
        year = as.integer(substr(names(rs), 1, 4)),
        month = as.integer(substr(names(rs), 6, 7)),
        stringsAsFactors = FALSE
      )
      out[[value_name]] <- vapply(rs, function(r) wapor_masked_global_mean(r, valid_crop_mask), numeric(1))
      out
    }
    results$monthly_green_water <- list(rasters = monthly_green, summary = series_summary(monthly_green, "green_mean_mm"))
    results$monthly_blue_water <- list(rasters = monthly_blue, summary = series_summary(monthly_blue, "blue_mean_mm"))
  }

  # Peff (monthly USDA method, summed over the season)
  if (any(c("agg_peff", "green_water", "blue_water") %in% indicators) && !is.null(results$monthly_precip_peff)) {
    results$seasonal_peff <- results$monthly_precip_peff$seasonal_peff
  }

  # Green/Blue Water
  if (any(c("green_water", "blue_water") %in% indicators) && !is.null(results$seasonal_aeti) && !is.null(results$seasonal_peff)) {
    if ("green_water" %in% indicators) results$green_water <- Rwapor::wapor_calc_green_water(results$seasonal_aeti$raster, results$seasonal_peff)
    if ("blue_water" %in% indicators)  results$blue_water <- Rwapor::wapor_calc_blue_water(results$seasonal_aeti$raster, results$seasonal_peff)
  }

  # Yield and CWP/BWP
  if (any(c("yield_npp", "cwp_bwp") %in% indicators) && !is.null(results$seasonal_biomass)) {
    yield_layers <- list()
    for (j in seq_len(nrow(crop_params))) {
      cls <- as.character(crop_params$class_value[j])
      cp <- crop_params[j, ]
      class_mask <- terra::ifel(h_mask == as.integer(cls), 1L, NA)
      yield_rast <- Rwapor::wapor_calc_yield_npp(
        npp_gc_m2 = results$seasonal_biomass_kg / 22.222,
        mc = cp$MC,
        fc = cp$fc,
        aot = cp$AOT,
        hi = cp$HI
      )
      yield_layers[[cls]] <- yield_rast * class_mask
    }
    results$yield_by_class <- yield_layers
    combined_yield <- yield_layers[[1]]
    if (length(yield_layers) > 1) {
      for (k in 2:length(yield_layers)) {
        combined_yield <- terra::cover(combined_yield, yield_layers[[k]])
      }
    }
    results$yield_raster <- combined_yield
  }

  if ("cwp_bwp" %in% indicators && !is.null(results$seasonal_aeti)) {
    if (!is.null(results$yield_raster)) {
      cwp_raster <- Rwapor::wapor_calc_cwp(results$yield_raster, results$seasonal_aeti$raster, yield_unit = "t/ha")
      results$cwp <- wapor_masked_global_mean(cwp_raster, valid_crop_mask, area = pixel_area_r)
    }
    if (!is.null(results$seasonal_biomass_t)) {
      bwp_raster <- Rwapor::wapor_calc_bwp(results$seasonal_biomass_t, results$seasonal_aeti$raster, biomass_unit = "t/ha")
      results$bwp <- wapor_masked_global_mean(bwp_raster, valid_crop_mask, area = pixel_area_r)
    }
  }

  set_names <- .wapor_kernel_set_names(job)
  results$coverage <- Filter(Negate(is.null), lapply(
    stats::setNames(set_names, set_names),
    function(key) agg[[paste0(key, "__coverage")]]
  ))
  results$processing <- plan
  results$processing_run <- list(
    output_dir = output_dir,
    manifest_path = run$manifest_path,
    n_tiles = run$n_tiles,
    n_tiles_resumed = run$n_tiles_resumed,
    n_tiles_written = run$n_tiles_written,
    aggregation_paths = vapply(job$specs, `[[`, character(1), "path")
  )

  extra_steps <- setdiff(indicators, .wapor_builtin_indicator_steps())
  extra_steps <- intersect(extra_steps, wapor_list_indicator_steps())
  if (length(extra_steps)) {
    progress_callback(0.92, "Running registered extra indicator steps...")
    ctx <- new.env(parent = emptyenv())
    ctx$indicators <- indicators
    ctx$results <- results
    ctx$progress_callback <- progress_callback
    # Dekadal stacks and weight rasters are only built if a step reads them.
    .wapor_lazy_binding(ctx, "stacks", function() {
      s <- results$dekadal_stacks %||% materialize_stacks()
      list(aeti = s$aeti, ret = s$ret, precip = s$pcp, npp = s$npp, t = s$t)
    })
    .wapor_lazy_binding(ctx, "season_weights", function() results$season_weights %||% materialize_weights())
    ctx$h_mask <- h_mask
    ctx$h_start <- h_start
    ctx$h_end <- h_end
    ctx$crop_params <- crop_params
    ctx$dekad_table <- dekad_table
    ctx$ref_year <- ref_year
    ctx$use_incremental <- isTRUE(config$incremental)
    ctx$aeti_mult <- aeti_mult
    ctx$ret_mult <- ret_mult
    ctx$pcp_mult <- precip_mult
    ctx$npp_mult <- npp_mult
    ctx$t_mult <- t_mult
    wapor_run_indicator_steps(ctx, skip = .wapor_builtin_indicator_steps())
    results <- ctx$results
  }

  # 6. Cleanup & Return
  progress_callback(0.95, "Finalizing...")
  results$crop_params <- crop_params
  return(results)
}

#' Plan a kernel job from its actual source grids
#' @keywords internal
#' @noRd
.wapor_plan_for_job <- function(job, template, processing = "auto", workers = NULL) {
  native_cells <- vapply(job$specs, function(s) {
    if (identical(s$path, "aligned")) return(as.numeric(terra::ncell(template)))
    native_r <- terra::rast(s$paths[[1]], lyrs = 1L)
    e <- .wapor_native_window_ext(native_r, template)
    if (is.null(e)) return(0)
    r <- terra::res(native_r)
    ((terra::xmax(e) - terra::xmin(e)) / r[1]) * ((terra::ymax(e) - terra::ymin(e)) / r[2])
  }, numeric(1))
  if (!length(native_cells)) native_cells <- as.numeric(terra::ncell(template))
  .wapor_plan_core(
    analysis_nrow = terra::nrow(template), analysis_ncol = terra::ncol(template),
    native_cells = native_cells,
    n_layers = nrow(job$dekad_table),
    n_targets = 1L + length(job$month_targets),
    n_profiles = nrow(job$profiles),
    processing = processing, workers = workers,
    bytes_per_file_window = max(native_cells) * 4
  )
}

#' Default AOI: the extent of the crop mask or season rasters, in EPSG:4326
#' @keywords internal
#' @noRd
.wapor_default_aoi <- function(rasters) {
  cand <- Filter(function(x) inherits(x, "SpatRaster"),
                 list(rasters$crop_mask, rasters$season_start, rasters$season_end))
  if (!length(cand)) return(NULL)
  r <- cand[[1]]
  e <- terra::ext(r)
  crs_r <- terra::crs(r)
  if (nzchar(crs_r) && !isTRUE(terra::is.lonlat(r))) {
    poly <- terra::as.polygons(e, crs = crs_r)
    e <- terra::ext(terra::project(poly, "EPSG:4326"))
  }
  bb <- c(terra::xmin(e), terra::ymin(e), terra::xmax(e), terra::ymax(e))
  log_msg(sprintf(
    "aoi_region not supplied; using the crop mask / season raster extent [%.5f, %.5f, %.5f, %.5f].",
    bb[1], bb[2], bb[3], bb[4]
  ))
  bb
}

#' Set cells outside a vector AOI to NA without changing the grid
#' @keywords internal
#' @noRd
.wapor_mask_to_region <- function(r, reg_info) {
  v <- suppressWarnings(terra::vect(reg_info$value))
  if (nzchar(terra::crs(r)) && nzchar(terra::crs(v)) &&
      !isTRUE(tryCatch(terra::same.crs(r, v), error = function(e) FALSE))) {
    v <- wapor_safe_project(v, terra::crs(r))
  }
  suppressWarnings(terra::mask(r, v, touches = TRUE))
}

#' Dekadal stack resampled onto the analysis grid (v1.0.0 layout)
#' @keywords internal
#' @noRd
.wapor_materialize_dekadal_stack <- function(paths, template, reg_info, method, dekad_keys) {
  stack <- terra::rast(lapply(paths, function(p) terra::rast(p, lyrs = 1L)))
  if (!is.null(reg_info)) {
    stack <- Rwapor::wapor_crop_to_region(stack, reg_info, do_mask = (reg_info$type == "vector"))
  }
  stack <- Rwapor::wapor_harmonize_raster(stack, template, method = method)
  names(stack) <- basename(paths)
  stack
}

#' Active binding that computes its value on first access
#' @keywords internal
#' @noRd
.wapor_lazy_binding <- function(env, name, compute) {
  cache <- NULL
  filled <- FALSE
  makeActiveBinding(name, function(value) {
    if (!missing(value)) {
      cache <<- value
      filled <<- TRUE
      return(invisible(value))
    }
    if (!filled) {
      cache <<- compute()
      filled <<- TRUE
    }
    cache
  }, env)
}

#' USDA SCS monthly effective precipitation
#' @keywords internal
#' @noRd
.wapor_usda_peff <- function(r) {
  terra::ifel(r <= 250, r * (125 - 0.2 * r) / 125, 125 + 0.1 * r)
}
