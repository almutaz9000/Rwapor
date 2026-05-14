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
  expected_peff <- wapor_calc_peff_usda(expected_ret)
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
