# =============================================================================
# Tests for the multi-season "Smart-Linking" per-season crop_mask /
# season_start / season_end override in wapor_run_seasonal_analysis().
# See R/analysis_engine.R: config$folder/seasonal_masks/<SeasonName>_mask.tif,
# <SeasonName>_start.tif, <SeasonName>_end.tif.
# =============================================================================

test_that("multi-season analysis picks up a season-specific crop_mask and falls back when absent", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-seasonal-masks-")
  dir.create(file.path(analysis_dir, "seasonal_masks"), recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c(
    "2021-01-01", "2021-01-11", "2021-01-21",
    "2022-01-01", "2022-01-11", "2022-01-21",
    "2023-01-01", "2023-01-11", "2023-01-21"
  )
  template <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)

  var_dir <- file.path(analysis_dir, "L1-AETI-D")
  dir.create(var_dir, recursive = TRUE)
  for (d in dates) {
    r <- terra::setValues(template, rep(3, terra::ncell(template)))
    terra::writeRaster(r, file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", d)), overwrite = TRUE)
  }

  # Two non-overlapping masks: left-half columns vs right-half columns.
  vals_left  <- matrix(c(rep(1L, 2), rep(NA_integer_, 2)), nrow = 4, ncol = 4, byrow = TRUE)
  vals_right <- matrix(c(rep(NA_integer_, 2), rep(1L, 2)), nrow = 4, ncol = 4, byrow = TRUE)
  mask_left  <- terra::setValues(template, as.vector(t(vals_left)))
  mask_right <- terra::setValues(template, as.vector(t(vals_right)))
  terra::writeRaster(mask_left,  file.path(analysis_dir, "seasonal_masks", "SeasonA_mask.tif"), overwrite = TRUE)
  terra::writeRaster(mask_right, file.path(analysis_dir, "seasonal_masks", "SeasonB_mask.tif"), overwrite = TRUE)
  # SeasonC intentionally has NO *_mask.tif -- must fall back to rasters$crop_mask.

  fallback_mask <- terra::setValues(template, rep(1L, terra::ncell(template)))

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
    HI = 1, MC = 0, fc = 1, AOT = 1,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(
      "SeasonA" = c("2021-01-01", "2021-01-31"),
      "SeasonB" = c("2022-01-01", "2022-01-31"),
      "SeasonC" = c("2023-01-01", "2023-01-31")
    ),
    aeti_var = "L1-AETI-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c("agg_aeti"),
    use_crop_mask = TRUE,
    use_season_rasters = FALSE
  )

  results <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = fallback_mask)
  )

  mask_matrix <- function(season) {
    matrix(terra::values(results[[season]]$valid_crop_mask), nrow = 4, ncol = 4, byrow = TRUE)
  }

  mA <- mask_matrix("SeasonA")
  mB <- mask_matrix("SeasonB")
  mC <- mask_matrix("SeasonC")

  # SeasonA: only left two columns valid (its own mask), right two NA.
  expect_true(all(!is.na(mA[, 1:2])))
  expect_true(all(is.na(mA[, 3:4])))

  # SeasonB: only right two columns valid (its own mask), left two NA.
  expect_true(all(is.na(mB[, 1:2])))
  expect_true(all(!is.na(mB[, 3:4])))

  # SeasonC: no season-specific file -> falls back to the full fallback_mask.
  expect_true(all(!is.na(mC)))
})

test_that("a season-specific season_start/season_end overrides config$use_season_rasters = FALSE for that season only", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-seasonal-startend-")
  dir.create(file.path(analysis_dir, "seasonal_masks"), recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2021-01-01", "2021-01-11", "2021-01-21", "2022-01-01", "2022-01-11", "2022-01-21")
  template <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)

  var_dir <- file.path(analysis_dir, "L1-AETI-D")
  dir.create(var_dir, recursive = TRUE)
  for (d in dates) {
    r <- terra::setValues(template, rep(3, terra::ncell(template)))
    terra::writeRaster(r, file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", d)), overwrite = TRUE)
  }

  full_mask <- terra::setValues(template, rep(1L, terra::ncell(template)))
  terra::writeRaster(full_mask, file.path(analysis_dir, "seasonal_masks", "Short_mask.tif"), overwrite = TRUE)
  terra::writeRaster(full_mask, file.path(analysis_dir, "seasonal_masks", "Full_mask.tif"), overwrite = TRUE)

  # Only "Short" gets a shortened per-pixel season (day 1 to day 11).
  s_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  s_end_short <- terra::setValues(template, rep(11L, terra::ncell(template)))
  terra::writeRaster(s_start, file.path(analysis_dir, "seasonal_masks", "Short_start.tif"), overwrite = TRUE)
  terra::writeRaster(s_end_short, file.path(analysis_dir, "seasonal_masks", "Short_end.tif"), overwrite = TRUE)

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 5L, l_mid_days = 5L, l_late_days = 5L,
    HI = 1, MC = 0, fc = 1, AOT = 1,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(
      "Short" = c("2021-01-01", "2021-01-31"),
      "Full"  = c("2022-01-01", "2022-01-31")
    ),
    aeti_var = "L1-AETI-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c("agg_aeti"),
    use_crop_mask = TRUE,
    use_season_rasters = FALSE  # global default OFF -- per-season files should still override
  )

  results <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = full_mask)
  )

  aeti_short <- as.numeric(terra::global(results$Short$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)
  aeti_full  <- as.numeric(terra::global(results$Full$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)

  # Short: days 1-11 at AETI=3/day -> 11*3 = 33. Full: days 1-31 -> 31*3 = 93.
  expect_equal(aeti_short, 33)
  expect_equal(aeti_full, 93)
})
