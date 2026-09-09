# R/analysis_registry.R
# =============================================================================
# Indicator Step Registry for Seasonal Analysis Engine
# =============================================================================

.indicator_registry <- new.env(parent = emptyenv())

#' Register an Indicator Step
#'
#' @param name Character. Unique identifier of the indicator step.
#' @param step_fn Function. Step execution function accepting `ctx`.
#' @param depends Character vector. Optional prerequisite step names.
#' @param description Character. Human-readable description.
#' @return Invisible list of registered steps.
#' @export
wapor_register_indicator_step <- function(name, step_fn, depends = character(0), description = "") {
  if (!is.character(name) || length(name) != 1 || !nzchar(name)) {
    stop("'name' must be a non-empty character string", call. = FALSE)
  }
  if (!is.function(step_fn)) {
    stop("'step_fn' must be a function accepting 'ctx'", call. = FALSE)
  }
  attr(step_fn, "depends") <- depends
  attr(step_fn, "description") <- description
  .indicator_registry[[name]] <- step_fn
  invisible(as.list(.indicator_registry))
}

#' List Registered Indicator Steps
#'
#' @return Character vector of registered indicator step names.
#' @export
wapor_list_indicator_steps <- function() {
  names(.indicator_registry)
}

#' Get an Indicator Step Function
#'
#' @param name Character. Name of the registered step.
#' @return The step function, or NULL if not found.
#' @export
wapor_get_indicator_step <- function(name) {
  .indicator_registry[[name]]
}

# ── 1. Seasonal AETI Step ───────────────────────────────────────────────────
step_agg_aeti <- function(ctx) {
  if (!"agg_aeti" %in% ctx$indicators && !any(c("etc", "adequacy_etc", "adequacy_p95", "cwp_bwp", "green_water", "blue_water", "beneficial_fraction") %in% ctx$indicators)) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$aeti)) return(invisible(NULL))

  ctx$progress_callback(0.35, "Computing seasonal AETI...")
  res <- Rwapor::wapor_calc_seasonal_aeti(
    aeti_dekad        = ctx$stacks$aeti,
    season_weights    = ctx$season_weights,
    crop_mask         = ctx$h_mask,
    layer_multipliers = ctx$aeti_mult,
    incremental       = ctx$use_incremental
  )
  ctx$results$seasonal_aeti <- res

  if ("agg_aeti" %in% ctx$indicators && !is.null(ctx$h_mask)) {
    ctx$results$seasonal_aeti_by_class <- wapor_summary_by_class(
      r          = res$raster,
      crop_mask  = ctx$h_mask,
      class_stats = ctx$results$class_stats,
      var_name   = "seasonal_aeti"
    )
  }

  if ("agg_aeti" %in% ctx$indicators) {
    ctx$results$monthly_aeti <- Rwapor::wapor_calc_monthly_weighted_rasters(
      x                  = ctx$stacks$aeti,
      season_weights     = ctx$season_weights,
      dekad_table        = ctx$dekad_table,
      layer_multipliers  = ctx$aeti_mult,
      incremental        = ctx$use_incremental,
      summary_mask       = ctx$results$valid_crop_mask,
      summary_value_name = "aeti_mean_mm"
    )
  }
  invisible(NULL)
}

# ── 2. Seasonal Transpiration (T) Step ──────────────────────────────────────
step_agg_t <- function(ctx) {
  if (!"agg_t" %in% ctx$indicators && !"beneficial_fraction" %in% ctx$indicators) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$t)) return(invisible(NULL))

  ctx$progress_callback(0.40, "Computing seasonal Transpiration...")
  res <- Rwapor::wapor_calc_seasonal_aeti(
    aeti_dekad        = ctx$stacks$t,
    season_weights    = ctx$season_weights,
    crop_mask         = ctx$h_mask,
    layer_multipliers = ctx$t_mult,
    incremental       = ctx$use_incremental
  )
  ctx$results$seasonal_t <- res

  if ("agg_t" %in% ctx$indicators && !is.null(ctx$h_mask)) {
    ctx$results$seasonal_t_by_class <- wapor_summary_by_class(
      r          = res$raster,
      crop_mask  = ctx$h_mask,
      class_stats = ctx$results$class_stats,
      var_name   = "seasonal_t"
    )
  }

  if ("agg_t" %in% ctx$indicators) {
    ctx$results$monthly_t <- Rwapor::wapor_calc_monthly_weighted_rasters(
      x                  = ctx$stacks$t,
      season_weights     = ctx$season_weights,
      dekad_table        = ctx$dekad_table,
      layer_multipliers  = ctx$t_mult,
      incremental        = ctx$use_incremental,
      summary_mask       = ctx$results$valid_crop_mask,
      summary_value_name = "t_mean_mm"
    )
  }
  invisible(NULL)
}

# ── 3. Seasonal RET Step ────────────────────────────────────────────────────
step_agg_ret <- function(ctx) {
  if (!"agg_ret" %in% ctx$indicators && !any(c("etc", "adequacy_etc") %in% ctx$indicators)) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$ret)) return(invisible(NULL))

  ctx$progress_callback(0.45, "Computing seasonal RET...")
  res <- Rwapor::wapor_calc_seasonal_ret(
    ret_dekad         = ctx$stacks$ret,
    season_weights    = ctx$season_weights,
    crop_mask         = ctx$h_mask,
    layer_multipliers = ctx$ret_mult,
    incremental       = ctx$use_incremental
  )
  ctx$results$seasonal_ret <- res

  if ("agg_ret" %in% ctx$indicators && !is.null(ctx$h_mask)) {
    ctx$results$seasonal_ret_by_class <- wapor_summary_by_class(
      r          = res$raster,
      crop_mask  = ctx$h_mask,
      class_stats = ctx$results$class_stats,
      var_name   = "seasonal_ret"
    )
  }

  if ("agg_ret" %in% ctx$indicators) {
    ctx$results$monthly_ret <- Rwapor::wapor_calc_monthly_weighted_rasters(
      x                  = ctx$stacks$ret,
      season_weights     = ctx$season_weights,
      dekad_table        = ctx$dekad_table,
      layer_multipliers  = ctx$ret_mult,
      incremental        = ctx$use_incremental,
      summary_mask       = ctx$results$valid_crop_mask,
      summary_value_name = "ret_mean_mm"
    )
  }
  invisible(NULL)
}

# ── 4. Seasonal Precipitation Step ──────────────────────────────────────────
step_agg_pcp <- function(ctx) {
  if (!"agg_pcp" %in% ctx$indicators && !any(c("peff", "green_water", "blue_water") %in% ctx$indicators)) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$precip)) return(invisible(NULL))

  ctx$progress_callback(0.50, "Computing seasonal Precipitation...")
  res <- Rwapor::wapor_calc_seasonal_aeti(
    aeti_dekad        = ctx$stacks$precip,
    season_weights    = ctx$season_weights,
    crop_mask         = ctx$h_mask,
    layer_multipliers = ctx$pcp_mult,
    incremental       = ctx$use_incremental
  )
  ctx$results$seasonal_pcp <- res

  if ("agg_pcp" %in% ctx$indicators && !is.null(ctx$h_mask)) {
    ctx$results$seasonal_pcp_by_class <- wapor_summary_by_class(
      r          = res$raster,
      crop_mask  = ctx$h_mask,
      class_stats = ctx$results$class_stats,
      var_name   = "seasonal_pcp"
    )
  }

  if (any(c("agg_pcp", "peff", "green_water", "blue_water") %in% ctx$indicators)) {
    ctx$results$monthly_pcp <- Rwapor::wapor_calc_monthly_weighted_rasters(
      x                  = ctx$stacks$precip,
      season_weights     = ctx$season_weights,
      dekad_table        = ctx$dekad_table,
      layer_multipliers  = ctx$pcp_mult,
      incremental        = ctx$use_incremental,
      summary_mask       = ctx$results$valid_crop_mask,
      summary_value_name = "pcp_mean_mm"
    )
  }
  invisible(NULL)
}

# ── 5. Seasonal NPP / Biomass Step ──────────────────────────────────────────
step_agg_npp <- function(ctx) {
  if (!"agg_npp" %in% ctx$indicators && !"cwp_bwp" %in% ctx$indicators) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$npp)) return(invisible(NULL))

  ctx$progress_callback(0.55, "Computing seasonal NPP / Biomass...")
  res <- Rwapor::wapor_calc_seasonal_aeti(
    aeti_dekad        = ctx$stacks$npp,
    season_weights    = ctx$season_weights,
    crop_mask         = ctx$h_mask,
    layer_multipliers = ctx$npp_mult,
    incremental       = ctx$use_incremental
  )
  ctx$results$seasonal_npp <- res

  if ("agg_npp" %in% ctx$indicators && !is.null(ctx$h_mask)) {
    ctx$results$seasonal_npp_by_class <- wapor_summary_by_class(
      r          = res$raster,
      crop_mask  = ctx$h_mask,
      class_stats = ctx$results$class_stats,
      var_name   = "seasonal_npp"
    )
  }

  if ("agg_npp" %in% ctx$indicators) {
    ctx$results$monthly_npp <- Rwapor::wapor_calc_monthly_weighted_rasters(
      x                  = ctx$stacks$npp,
      season_weights     = ctx$season_weights,
      dekad_table        = ctx$dekad_table,
      layer_multipliers  = ctx$npp_mult,
      incremental        = ctx$use_incremental,
      summary_mask       = ctx$results$valid_crop_mask,
      summary_value_name = "npp_mean_gc_m2"
    )
  }

  # Convert NPP to Biomass (TBP)
  ctx$results$seasonal_biomass <- Rwapor::wapor_convert_npp_tbp(res$raster)
  if (!is.null(ctx$h_mask)) {
    ctx$results$seasonal_biomass_by_class <- terra::zonal(ctx$results$seasonal_biomass, ctx$h_mask, fun = "mean", na.rm = TRUE)
    names(ctx$results$seasonal_biomass_by_class) <- c("class_value", "mean_seasonal_biomass_kg")
    ctx$results$seasonal_biomass_by_class$mean_seasonal_biomass_t <-
      ctx$results$seasonal_biomass_by_class$mean_seasonal_biomass_kg / 1000
    ctx$results$seasonal_biomass_by_class$mean_seasonal_biomass <-
      ctx$results$seasonal_biomass_by_class$mean_seasonal_biomass_kg
  }
  invisible(NULL)
}

# ── 6. ETc Step ─────────────────────────────────────────────────────────────
step_etc <- function(ctx) {
  if (!"etc" %in% ctx$indicators && !"adequacy_etc" %in% ctx$indicators) {
    return(invisible(NULL))
  }
  if (is.null(ctx$stacks$ret)) stop("RET stack is required for ETc/Adequacy.", call. = FALSE)

  profile_table <- wapor_build_season_profile_table(ctx$h_mask, ctx$h_start, ctx$h_end, ctx$crop_params$class_value)
  if (nrow(profile_table) == 0) return(invisible(NULL))

  kc_profiles <- list()
  profile_table$kc_key <- NA_character_
  for (i in seq_len(nrow(profile_table))) {
    profile_row <- profile_table[i, ]
    cp <- ctx$crop_params[ctx$crop_params$class_value == profile_row$class_value, , drop = FALSE]
    if (nrow(cp) == 0) next

    fixed_sum <- cp$l_ini_days + cp$l_mid_days + cp$l_late_days
    l_dev     <- as.integer(profile_row$total_days - fixed_sum)
    if (l_dev < 0L) l_dev <- 0L

    kc_daily <- Rwapor::wapor_build_kc(
      kc_ini = cp$kc_ini[1], kc_mid = cp$kc_mid[1], kc_end = cp$kc_end[1],
      l_ini = cp$l_ini_days[1], l_dev = l_dev, l_mid = cp$l_mid_days[1], l_late = cp$l_late_days[1]
    )
    season_start_date <- as.Date(sprintf("%04d-01-01", ctx$ref_year)) + profile_row$start_jd - 1L
    kc_dekad <- Rwapor::wapor_aggregate_kc(kc_daily, ctx$dekad_table, season_start_date)
    kc_key   <- paste(round(kc_dekad, 6), collapse = ",")
    profile_table$kc_key[i] <- kc_key
    if (is.null(kc_profiles[[kc_key]])) kc_profiles[[kc_key]] <- kc_dekad
  }

  unique_etc_rasters <- list()
  for (key in names(kc_profiles)) {
    unique_etc_rasters[[key]] <- Rwapor::wapor_calc_seasonal_etc(
      ctx$stacks$ret, ctx$season_weights, kc_profiles[[key]], layer_multipliers = ctx$ret_mult
    )
  }

  etc_by_class <- list()
  for (j in seq_len(nrow(ctx$crop_params))) {
    cls <- as.character(ctx$crop_params$class_value[j])
    class_profiles <- profile_table[profile_table$class_value == as.integer(cls), , drop = FALSE]
    if (nrow(class_profiles) == 0) next

    class_etc <- NULL
    for (i in seq_len(nrow(class_profiles))) {
      key <- class_profiles$kc_key[i]
      profile_mask <- terra::ifel((ctx$h_mask == as.integer(cls)) & (ctx$h_start == class_profiles$start_jd[i]) & (ctx$h_end == class_profiles$end_jd[i]), 1L, NA)
      profile_etc  <- unique_etc_rasters[[key]] * profile_mask
      class_etc    <- if (is.null(class_etc)) profile_etc else terra::cover(class_etc, profile_etc)
    }
    etc_by_class[[cls]] <- list(etc_seasonal = class_etc)
  }
  ctx$results$etc_by_class <- etc_by_class

  layer_dates <- if ("dekad_start" %in% names(ctx$dekad_table)) {
    as.Date(ctx$dekad_table$dekad_start)
  } else {
    as.Date(ctx$dekad_table$dekad_key)
  }
  month_keys <- format(layer_dates, "%Y-%m")
  month_order <- unique(month_keys)
  monthly_etc <- stats::setNames(vector("list", length(month_order)), month_order)

  for (j in seq_len(nrow(ctx$crop_params))) {
    cls <- as.character(ctx$crop_params$class_value[j])
    class_profiles <- profile_table[profile_table$class_value == as.integer(cls), , drop = FALSE]
    if (nrow(class_profiles) == 0) next

    for (i in seq_len(nrow(class_profiles))) {
      key <- class_profiles$kc_key[i]
      profile_mask <- terra::ifel(
        (ctx$h_mask == as.integer(cls)) &
          (ctx$h_start == class_profiles$start_jd[i]) &
          (ctx$h_end == class_profiles$end_jd[i]),
        1L,
        NA
      )

      for (month_key in month_order) {
        idx <- which(month_keys == month_key)
        profile_month_etc <- wapor_masked_sum(
          terra::subset(ctx$stacks$ret, idx),
          terra::subset(ctx$season_weights, idx),
          layer_multipliers = ctx$ret_mult[idx] * kc_profiles[[key]][idx],
          incremental = ctx$use_incremental
        )
        profile_month_etc <- profile_month_etc * profile_mask
        monthly_etc[[month_key]] <- if (is.null(monthly_etc[[month_key]])) {
          profile_month_etc
        } else {
          terra::cover(monthly_etc[[month_key]], profile_month_etc)
        }
      }
    }
  }

  monthly_etc_summary <- data.frame(
    month_key = names(monthly_etc),
    year = as.integer(substr(names(monthly_etc), 1, 4)),
    month = as.integer(substr(names(monthly_etc), 6, 7)),
    stringsAsFactors = FALSE
  )
  monthly_etc_summary$etc_mean_mm <- vapply(
    monthly_etc,
    function(r) wapor_masked_global_mean(r, ctx$results$valid_crop_mask),
    numeric(1)
  )
  ctx$results$monthly_etc <- list(rasters = monthly_etc, summary = monthly_etc_summary)
  invisible(NULL)
}

# ── 7. Adequacy ETc Step ────────────────────────────────────────────────────
step_adequacy_etc <- function(ctx) {
  if (!"adequacy_etc" %in% ctx$indicators) return(invisible(NULL))
  if (is.null(ctx$results$seasonal_aeti) || is.null(ctx$results$etc_by_class)) return(invisible(NULL))

  all_etc <- lapply(ctx$results$etc_by_class, function(x) x$etc_seasonal)
  if (length(all_etc) > 0) {
    combined_etc <- all_etc[[1]]
    if (length(all_etc) > 1) {
      for (k in seq_along(all_etc)[-1]) combined_etc <- terra::cover(combined_etc, all_etc[[k]])
    }
    ctx$results$adequacy_etc <- Rwapor::wapor_calc_adequacy_etc(ctx$results$seasonal_aeti$raster, combined_etc)
  }
  invisible(NULL)
}

# ── 8. Adequacy P95 Step ────────────────────────────────────────────────────
step_adequacy_p95 <- function(ctx) {
  if (!"adequacy_p95" %in% ctx$indicators) return(invisible(NULL))
  if (is.null(ctx$results$seasonal_aeti)) return(invisible(NULL))

  p95_table <- Rwapor::wapor_calc_p95_aeti(ctx$results$seasonal_aeti$raster, ctx$h_mask)
  ctx$results$p95_table <- p95_table
  ctx$results$adequacy_p95 <- Rwapor::wapor_calc_adequacy_p95(ctx$results$seasonal_aeti$raster, ctx$h_mask, p95_table)
  invisible(NULL)
}

# ── 9. Beneficial Fraction (T/AETI) Step ────────────────────────────────────
step_beneficial_fraction <- function(ctx) {
  if (!"beneficial_fraction" %in% ctx$indicators) return(invisible(NULL))
  if (is.null(ctx$results$seasonal_aeti) || is.null(ctx$results$seasonal_t)) return(invisible(NULL))

  ctx$results$beneficial_fraction <- Rwapor::wapor_calc_beneficial_fraction(
    ctx$results$seasonal_t$raster,
    ctx$results$seasonal_aeti$raster
  )
  invisible(NULL)
}

# ── 10. Peff, Green Water & Blue Water Step ─────────────────────────────────
step_peff_green_blue <- function(ctx) {
  if (!any(c("peff", "green_water", "blue_water") %in% ctx$indicators)) return(invisible(NULL))
  if (is.null(ctx$results$monthly_pcp)) return(invisible(NULL))

  peff_res <- wapor_calc_peff(ctx$results$monthly_pcp$rasters)
  ctx$results$peff_monthly <- peff_res$monthly
  ctx$results$peff_seasonal <- peff_res$seasonal

  if ("green_water" %in% ctx$indicators && !is.null(ctx$results$seasonal_aeti)) {
    ctx$results$green_water <- Rwapor::wapor_calc_green_water(ctx$results$seasonal_aeti$raster, peff_res$seasonal)
  }
  if ("blue_water" %in% ctx$indicators && !is.null(ctx$results$seasonal_aeti)) {
    ctx$results$blue_water <- Rwapor::wapor_calc_blue_water(ctx$results$seasonal_aeti$raster, peff_res$seasonal)
  }
  invisible(NULL)
}

# ── 11. Crop & Biomass Water Productivity Step ──────────────────────────────
step_cwp_bwp <- function(ctx) {
  if (!"cwp_bwp" %in% ctx$indicators) return(invisible(NULL))
  if (is.null(ctx$results$seasonal_aeti)) return(invisible(NULL))

  # BWP Raster
  if (!is.null(ctx$results$seasonal_biomass)) {
    ctx$results$bwp <- Rwapor::wapor_calc_bwp(ctx$results$seasonal_biomass, ctx$results$seasonal_aeti$raster, biomass_unit = "kg/ha")
  }

  cwp_list <- list()
  bwp_list <- list()

  for (i in seq_len(nrow(ctx$crop_params))) {
    row <- ctx$crop_params[i, ]
    cls <- as.character(row$class_value)

    cwp_val <- NA_real_
    bwp_val <- NA_real_

    if (!is.null(ctx$results$seasonal_aeti_by_class) && !is.null(ctx$results$seasonal_biomass_by_class)) {
      a_row <- ctx$results$seasonal_aeti_by_class[ctx$results$seasonal_aeti_by_class$class_value == row$class_value, ]
      b_row <- ctx$results$seasonal_biomass_by_class[ctx$results$seasonal_biomass_by_class$class_value == row$class_value, ]

      if (nrow(a_row) > 0 && nrow(b_row) > 0 && !is.na(a_row$mean_seasonal_aeti) && a_row$mean_seasonal_aeti > 0) {
        bwp_val <- Rwapor::wapor_calc_bwp(b_row$mean_seasonal_biomass_kg, a_row$mean_seasonal_aeti, biomass_unit = "kg/ha")

        if (!is.na(row$HI) && !is.na(row$MC) && !is.na(row$fc) && !is.na(row$AOT) && !is.null(ctx$results$seasonal_npp_by_class)) {
          n_row <- ctx$results$seasonal_npp_by_class[ctx$results$seasonal_npp_by_class$class_value == row$class_value, ]
          if (nrow(n_row) > 0 && !is.na(n_row$mean_seasonal_npp)) {
            yield_val <- Rwapor::wapor_calc_yield_npp(
              n_row$mean_seasonal_npp, mc = row$MC, fc = row$fc, aot = row$AOT, hi = row$HI
            )
            cwp_val <- Rwapor::wapor_calc_cwp(yield_val, a_row$mean_seasonal_aeti, yield_unit = "t/ha")
          }
        }
      }
    }
    cwp_list[[cls]] <- cwp_val
    bwp_list[[cls]] <- bwp_val
  }

  cwp_df <- data.frame(
    class_value = as.integer(names(cwp_list)),
    cwp_kg_m3   = as.numeric(unlist(cwp_list)),
    bwp_kg_m3   = as.numeric(unlist(bwp_list)),
    stringsAsFactors = FALSE
  )
  ctx$results$cwp_summary <- cwp_df
  invisible(NULL)
}

# ── 12. Spatial Variability Indicators Step ─────────────────────────────────
step_variability <- function(ctx) {
  if (!any(c("cv_aeti", "theil_aeti") %in% ctx$indicators)) return(invisible(NULL))
  if (is.null(ctx$results$seasonal_aeti)) return(invisible(NULL))

  if ("cv_aeti" %in% ctx$indicators) {
    ctx$results$cv_aeti <- wapor_calc_cv(ctx$results$seasonal_aeti$raster, ctx$h_mask)
  }
  if ("theil_aeti" %in% ctx$indicators) {
    ctx$results$theil_aeti <- wapor_calc_theil(ctx$results$seasonal_aeti$raster, ctx$h_mask)
  }
  invisible(NULL)
}

# ── Register all default steps ──────────────────────────────────────────────
wapor_register_indicator_step("agg_aeti", step_agg_aeti, description = "Seasonal AETI aggregation")
wapor_register_indicator_step("agg_t", step_agg_t, description = "Seasonal Transpiration aggregation")
wapor_register_indicator_step("agg_ret", step_agg_ret, description = "Seasonal RET aggregation")
wapor_register_indicator_step("agg_pcp", step_agg_pcp, description = "Seasonal Precipitation aggregation")
wapor_register_indicator_step("agg_npp", step_agg_npp, description = "Seasonal NPP and Biomass (TBP) aggregation")
wapor_register_indicator_step("etc", step_etc, depends = "agg_ret", description = "Crop Evapotranspiration (ETc)")
wapor_register_indicator_step("adequacy_etc", step_adequacy_etc, depends = c("agg_aeti", "etc"), description = "ETc-based Water Adequacy")
wapor_register_indicator_step("adequacy_p95", step_adequacy_p95, depends = "agg_aeti", description = "P95-based Water Adequacy")
wapor_register_indicator_step("beneficial_fraction", step_beneficial_fraction, depends = c("agg_aeti", "agg_t"), description = "Beneficial Transpiration Fraction (T/AETI)")
wapor_register_indicator_step("peff_green_blue", step_peff_green_blue, depends = c("agg_pcp", "agg_aeti"), description = "Effective Precipitation, Green & Blue Water")
wapor_register_indicator_step("cwp_bwp", step_cwp_bwp, depends = c("agg_aeti", "agg_npp"), description = "Crop and Biomass Water Productivity")
wapor_register_indicator_step("variability", step_variability, depends = "agg_aeti", description = "Spatial Uniformity & Variability (CV / Theil)")
