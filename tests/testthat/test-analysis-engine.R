# =============================================================================
# Integration tests for wapor_run_seasonal_analysis() engine
# Extracted from test-analysis.R to give the engine test its own file.
# =============================================================================

test_that("seasonal analysis engine computes the exposed indicator set from local rasters", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-analysis-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8)
  crop_vals <- c(rep(1L, 32), rep(2L, 32))
  crop_mask <- terra::setValues(template, crop_vals)
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end <- terra::setValues(template, rep(31L, terra::ncell(template)))

  write_stack <- function(variable, layer_values) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      r <- terra::setValues(template, rep(layer_values[i], terra::ncell(template)))
      terra::writeRaster(
        r,
        file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])),
        overwrite = TRUE
      )
    }
  }

  write_stack("L1-AETI-D", c(2, 3, 4))
  write_stack("L1-RET-D", c(1, 1, 1))
  write_stack("L1-PCP-D", c(1, 1, 1))
  write_stack("L1-NPP-D", c(1, 1, 1))
  write_stack("L1-T-D", c(0.5, 0.5, 0.5))

  crop_params <- data.frame(
    class_value = c(1L, 2L),
    crop_label = c("Class 1", "Class 2"),
    kc_ini = c(1, 1),
    kc_mid = c(1, 1),
    kc_end = c(1, 1),
    l_ini_days = c(10L, 10L),
    l_mid_days = c(10L, 10L),
    l_late_days = c(11L, 11L),
    HI = c(1, 1),
    MC = c(0, 0),
    fc = c(1, 1),
    AOT = c(1, 1),
    stringsAsFactors = FALSE
  )

  config <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c(
      "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "etc",
      "adequacy_etc", "adequacy_p95", "agg_t", "beneficial_fraction",
      "agg_biomass_kg", "agg_biomass_t", "yield_npp",
      "green_water", "blue_water", "cwp_bwp"
    ),
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  results <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  raster_mean <- function(x) as.numeric(terra::global(x, "mean", na.rm = TRUE)$mean)

  expected_aeti <- 2 * 10 + 3 * 10 + 4 * 11
  expected_ret <- 10 + 10 + 11
  # USDA SCS effective-precipitation formula (mirrors wapor_calc_monthly_precip_peff_rasters)
  expected_peff <- if (expected_ret <= 250) {
    expected_ret * (125 - 0.2 * expected_ret) / 125
  } else {
    125 + 0.1 * expected_ret
  }
  expected_biomass_kg <- expected_ret * 22.222
  expected_biomass_t <- expected_biomass_kg / 1000
  expected_yield_t <- expected_biomass_t
  expected_cwp_bwp <- expected_biomass_kg / (expected_aeti * 10)

  expect_equal(sort(unique(stats::na.omit(as.vector(terra::values(results$valid_crop_mask))))), 1)
  expect_equal(wapor_masked_global_mean(results$seasonal_aeti$raster, results$valid_crop_mask), expected_aeti)
  expect_equal(raster_mean(results$seasonal_aeti$raster), expected_aeti)
  expect_equal(raster_mean(results$seasonal_ret$raster), expected_ret)
  expect_equal(raster_mean(results$seasonal_pcp), expected_ret)
  expect_equal(raster_mean(results$seasonal_peff), expected_peff)
  expect_equal(raster_mean(results$seasonal_t$raster), 0.5 * expected_ret)
  expect_equal(raster_mean(results$adequacy_etc), expected_aeti / expected_ret)
  expect_equal(raster_mean(results$adequacy_p95), 1)
  expect_equal(raster_mean(results$beneficial_fraction), (0.5 * expected_ret) / expected_aeti)
  expect_equal(raster_mean(results$green_water), expected_peff)
  expect_equal(raster_mean(results$blue_water), expected_aeti - expected_peff)
  expect_equal(raster_mean(results$seasonal_biomass_kg), expected_biomass_kg)
  expect_equal(raster_mean(results$seasonal_biomass_t), expected_biomass_t)
  expect_equal(raster_mean(results$yield_raster), expected_yield_t)
  expect_equal(results$cwp, expected_cwp_bwp)
  expect_equal(results$bwp, expected_cwp_bwp)
  expect_true(all(results$p95_table$valid))
  expect_equal(nrow(results$seasonal_biomass_by_class), 2)
  expect_equal(length(results$etc_by_class), 2)
  expect_equal(length(results$yield_by_class), 2)

  cwp_only_config <- config
  cwp_only_config$indicators <- c("agg_aeti", "cwp_bwp")

  cwp_only <- wapor_run_seasonal_analysis(
    config = cwp_only_config,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  expect_equal(cwp_only$cwp, expected_cwp_bwp)
  expect_equal(cwp_only$bwp, expected_cwp_bwp)
})

test_that("seasonal analysis engine masks indicator rasters outside crop mask", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-analysis-mask-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8)

  crop_vals <- c(rep(1L, 32), rep(NA_integer_, 32))
  crop_mask <- terra::setValues(template, crop_vals)
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end <- terra::setValues(template, rep(31L, terra::ncell(template)))

  write_stack <- function(variable, layer_values) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      r <- terra::setValues(template, rep(layer_values[i], terra::ncell(template)))
      terra::writeRaster(
        r,
        file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])),
        overwrite = TRUE
      )
    }
  }

  write_stack("L1-AETI-D", c(2, 3, 4))
  write_stack("L1-RET-D", c(1, 1, 1))
  write_stack("L1-PCP-D", c(1, 1, 1))
  write_stack("L1-NPP-D", c(1, 1, 1))
  write_stack("L1-T-D", c(0.5, 0.5, 0.5))

  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Class 1",
    kc_ini = 1,
    kc_mid = 1,
    kc_end = 1,
    l_ini_days = 10L,
    l_mid_days = 10L,
    l_late_days = 11L,
    HI = 1,
    MC = 0,
    fc = 1,
    AOT = 1,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c(
      "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "agg_t",
      "beneficial_fraction", "green_water", "blue_water",
      "agg_biomass_kg", "agg_biomass_t", "yield_npp"
    ),
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  results <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  mask_vals <- as.vector(terra::values(results$valid_crop_mask))
  outside_mask <- is.na(mask_vals)

  expect_masked <- function(r) {
    vals <- as.vector(terra::values(r))
    expect_true(all(is.na(vals[outside_mask])))
    expect_true(any(!is.na(vals[!outside_mask])))
  }

  expect_masked(results$seasonal_aeti$raster)
  expect_masked(results$seasonal_ret$raster)
  expect_masked(results$seasonal_pcp)
  expect_masked(results$seasonal_peff)
  expect_masked(results$seasonal_t$raster)
  expect_masked(results$beneficial_fraction)
  expect_masked(results$green_water)
  expect_masked(results$blue_water)
  expect_masked(results$seasonal_biomass_kg)
  expect_masked(results$seasonal_biomass_t)
  expect_masked(results$yield_raster)

  expect_true(length(results$monthly_aeti$rasters) > 0)
  expect_masked(results$monthly_aeti$rasters[[1]])
  expect_masked(results$monthly_ret$rasters[[1]])
  expect_masked(results$monthly_t$rasters[[1]])

  expect_true(length(results$monthly_precip_peff$monthly_pcp) > 0)
  expect_masked(results$monthly_precip_peff$monthly_pcp[[1]])
  expect_masked(results$monthly_precip_peff$monthly_peff[[1]])
})

test_that("seasonal analysis engine runs a registered dummy indicator without touching the engine body", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-analysis-dummy-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)
  crop_mask <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end <- terra::setValues(template, rep(31L, terra::ncell(template)))

  var_dir <- file.path(analysis_dir, "L1-AETI-D")
  dir.create(var_dir, recursive = TRUE)
  for (d in dates) {
    r <- terra::setValues(template, rep(2, terra::ncell(template)))
    terra::writeRaster(
      r,
      file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", d)),
      overwrite = TRUE
    )
  }

  dummy_name <- paste0("dummy_", gsub("[^0-9]", "", format(Sys.time(), "%H%M%OS6")))
  wapor_register_indicator_step(dummy_name, function(ctx) {
    if (!dummy_name %in% ctx$indicators) return(invisible(NULL))
    aeti <- ctx$results$seasonal_aeti
    r <- if (is.list(aeti) && !is.null(aeti$raster)) aeti$raster else aeti
    ctx$results[[dummy_name]] <- r * 0 + 42
  }, depends = "agg_aeti", description = "Dummy indicator for registry wiring")

  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Class 1",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
    HI = 1, MC = 0, fc = 1, AOT = 1,
    stringsAsFactors = FALSE
  )

  results <- wapor_run_seasonal_analysis(
    config = list(
      period = c("2023-01-01", "2023-01-31"),
      ref_year = 2023,
      aeti_var = "L1-AETI-D",
      data_source = "local",
      folder = analysis_dir,
      indicators = c("agg_aeti", dummy_name),
      use_crop_mask = TRUE,
      use_season_rasters = TRUE
    ),
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  expect_true(!is.null(results[[dummy_name]]))
  expect_s4_class(results[[dummy_name]], "SpatRaster")
  expect_equal(as.numeric(terra::global(results[[dummy_name]], "mean", na.rm = TRUE)$mean), 42)
})

test_that("seasonal green/blue water sum the monthly splits, not the seasonal totals", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-greenblue-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  # January is wet with little use; February is dry with high use.
  dates <- c("2023-01-01", "2023-01-11", "2023-01-21", "2023-02-01", "2023-02-11", "2023-02-21")
  template <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)
  write_stack <- function(variable, layer_values) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      r <- terra::setValues(template, rep(layer_values[i], terra::ncell(template)))
      terra::writeRaster(r, file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])), overwrite = TRUE)
    }
  }
  write_stack("L1-AETI-D", c(1, 1, 1, 5, 5, 5))    # mm/day: Jan 31 mm, Feb 140 mm
  write_stack("L1-PCP-D", c(10, 10, 10, 0, 0, 0))  # mm/day: Jan 310 mm, Feb 0 mm

  config <- list(
    period = c("2023-01-01", "2023-02-28"),
    aeti_var = "L1-AETI-D",
    precip_var = "L1-PCP-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c("agg_aeti", "agg_pcp", "agg_peff", "green_water", "blue_water")
  )
  results <- wapor_run_seasonal_analysis(config = config, crop_params = wapor_crop_defaults("Winter Wheat"),
                                         rasters = list(template = template))
  raster_mean <- function(x) as.numeric(terra::global(x, "mean", na.rm = TRUE)$mean)

  peff_jan <- 125 + 0.1 * 310  # USDA-SCS, P > 250 mm/month
  aeti_jan <- 31
  aeti_feb <- 5 * 28
  expected_green <- min(aeti_jan, peff_jan) + min(aeti_feb, 0)
  expected_blue  <- max(0, aeti_jan - peff_jan) + max(0, aeti_feb - 0)

  expect_equal(raster_mean(results$green_water), expected_green)
  expect_equal(raster_mean(results$blue_water), expected_blue)
  expect_equal(raster_mean(results$green_water + results$blue_water), aeti_jan + aeti_feb)
  # The seasonal-total shortcut would give green = min(171, 156) = 156.
  expect_false(isTRUE(all.equal(raster_mean(results$green_water), min(aeti_jan + aeti_feb, peff_jan))))
})

test_that("local files saved as mm/dekad are not multiplied by the days again", {
  skip_if_not_installed("terra")
  root <- withr::local_tempdir()
  dates <- c("2024-07-01", "2024-07-11", "2024-07-21")
  n_days <- c(10, 10, 11)
  template <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)
  # AETI of 1 mm/day, saved per dekad as mm/day, mm/dekad (wapor_map() default) or a mix.
  write_case <- function(case, conversions) {
    var_dir <- file.path(root, case, "L1-AETI-D")
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      factor <- if (conversions[i] == "dekad") n_days[i] else 1
      r <- assign_raster_metadata(terra::setValues(template, factor), "L1-AETI-D", conversions[i])
      terra::writeRaster(r, file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", dates[i])), overwrite = TRUE)
    }
    file.path(root, case)
  }
  seasonal <- function(folder) {
    res <- wapor_run_seasonal_analysis(
      config = list(period = c("2024-07-01", "2024-07-31"), aeti_var = "L1-AETI-D", data_source = "local",
                    folder = folder, indicators = "agg_aeti"),
      crop_params = wapor_crop_defaults("Winter Wheat"), rasters = list(template = template))
    as.numeric(terra::global(res$seasonal_aeti$raster, "mean")$mean)
  }
  expect_equal(seasonal(write_case("per_day", rep("none", 3))), 31)
  expect_equal(seasonal(write_case("per_dekad", rep("dekad", 3))), 31)
  expect_equal(seasonal(write_case("mixed", c("none", "dekad", "none"))), 31)
})

test_that("layer multipliers invert the saved temporal conversion", {
  dt <- data.frame(dekad_key = c("2024-02-21", "2024-03-01"), n_days = c(9, 10))
  dir <- withr::local_tempdir()
  paths <- file.path(dir, c("a.tif", "b.tif"))
  r <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  terra::units(r) <- "mm/month"; terra::writeRaster(r, paths[1])
  terra::units(r) <- "mm/day";   terra::writeRaster(r, paths[2])
  # Feb 2024 has 29 days: a mm/month file holds 29 x the daily rate.
  expect_equal(get_analysis_layer_multipliers("L1-AETI-D", dt, paths = paths), c(9 / 29, 10))
  expect_equal(get_analysis_layer_multipliers("L1-AETI-D", dt), c(9, 10))
})
