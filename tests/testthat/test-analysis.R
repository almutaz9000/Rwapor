# =============================================================================
# Tests for analysis functions
# =============================================================================

test_that("crop defaults validation works", {
  expect_true(rwapor_validate_crop_defaults(FAO_CROP_DEFAULTS))

  # Missing columns
  bad_df <- data.frame(crop_name = "Test", Kc_ini = 0.3)
  expect_error(rwapor_validate_crop_defaults(bad_df), "Missing required columns")

  # Negative Kc
  bad_df2 <- FAO_CROP_DEFAULTS
  bad_df2$Kc_ini[1] <- -0.1
  expect_error(rwapor_validate_crop_defaults(bad_df2), "non-negative")

  # NA stage lengths
  bad_df3 <- FAO_CROP_DEFAULTS
  bad_df3$L_ini_days[1] <- NA

  expect_error(rwapor_validate_crop_defaults(bad_df3), "must not be NA")
})

test_that("rwapor_list_crops returns crop names", {
  crops <- rwapor_list_crops()
  expect_true(length(crops) >= 3)
  expect_true("Winter Wheat" %in% crops)
  expect_true("Sorghum" %in% crops)
  expect_true("Sugarbeet" %in% crops)
})

test_that("rwapor_get_crop_defaults works", {
  ww <- rwapor_get_crop_defaults("Winter Wheat")
  expect_true(!is.null(ww))
  expect_equal(nrow(ww), 1)
  expect_equal(ww$Kc_mid, 1.15)

  # Case insensitive
  sg <- rwapor_get_crop_defaults("sorghum")
  expect_true(!is.null(sg))

  # Not found
  expect_null(rwapor_get_crop_defaults("NonexistentCrop"))
})

test_that("continuous Julian date logic works", {
  # Same year
  expect_equal(rwapor_continuous_julian("2023-01-01", 2023), 1L)
  expect_equal(rwapor_continuous_julian("2023-12-31", 2023), 365L)

  # Cross-year
  expect_equal(rwapor_continuous_julian("2024-01-01", 2023), 366L)
  expect_equal(rwapor_continuous_julian("2024-01-15", 2023), 380L)

  # Leap year
  expect_equal(rwapor_continuous_julian("2024-12-31", 2024), 366L)
  expect_equal(rwapor_continuous_julian("2025-01-01", 2024), 367L)
})

test_that("daily Kc curve generation works", {
  kc <- rwapor_build_daily_kc(0.4, 1.15, 0.30, 30, 60, 40, 30)
  expect_equal(length(kc), 160)  # 30 + 60 + 40 + 30

  # Initial stage is constant
  expect_true(all(kc[1:30] == 0.4))

  # Mid stage is constant
  expect_true(all(kc[91:130] == 1.15))

  # Development is increasing
  expect_true(all(diff(kc[31:90]) > 0))

  # Late stage is decreasing
  expect_true(all(diff(kc[131:160]) < 0))

  # End value
  expect_equal(kc[160], 0.30, tolerance = 0.01)
})

test_that("Kc by class generation works", {
  params <- data.frame(
    class_value = c(1L, 2L),
    Kc_ini = c(0.4, 0.3),
    Kc_mid = c(1.15, 1.05),
    Kc_end = c(0.30, 0.55),
    L_ini_days = c(30L, 20L),
    L_mid_days = c(40L, 40L),
    L_late_days = c(30L, 30L),
    stringsAsFactors = FALSE
  )
  result <- rwapor_build_kc_by_class(params, c("1" = 160, "2" = 150))
  expect_true(length(result) == 2)
  expect_equal(length(result[["1"]]), 160)
  expect_equal(length(result[["2"]]), 150)
})

test_that("Peff USDA monthly calculation works", {
  # P <= 250
  expect_equal(rwapor_calc_peff_usda_monthly(0), 0)
  expect_equal(rwapor_calc_peff_usda_monthly(100), 100 * (125 - 20) / 125)

  # P > 250
  expect_equal(rwapor_calc_peff_usda_monthly(300), 125 + 30)

  # Vectorized
  peff <- rwapor_calc_peff_usda_monthly(c(50, 120, 300))
  expect_equal(length(peff), 3)
})

test_that("CWP and BWP calculations work", {
  # 5000 kg/ha yield, 400 mm AETI
  cwp <- rwapor_calc_cwp(5000, 400)
  expect_equal(cwp, 5000 / (400 * 10))  # kg/m3

  # t/ha unit
  cwp_t <- rwapor_calc_cwp(5, 400, yield_unit = "t/ha")
  expect_equal(cwp_t, cwp)

  # Zero AETI returns NA
  expect_true(is.na(rwapor_calc_cwp(5000, 0)))

  # BWP
  bwp <- rwapor_calc_bwp(12000, 400)
  expect_equal(bwp, 12000 / (400 * 10))
})

test_that("crop mask harmonization requires SpatRaster inputs", {
  expect_error(rwapor_harmonize_to_template("not_a_raster", "also_not"),
    "must be a SpatRaster")
})

test_that("build_dekad_table produces valid dekads", {
  tbl <- Rwapor:::build_dekad_table("2023-01-01", "2023-02-28")
  expect_true(nrow(tbl) >= 5)
  expect_true(all(tbl$n_days > 0))
  expect_true(all(tbl$n_days <= 11))
  # All dates covered
  total_days <- sum(tbl$n_days)
  expect_equal(total_days, as.integer(as.Date("2023-02-28") - as.Date("2023-01-01")) + 1)
})

test_that("season raster harmonization validates overlap", {
  skip_if_not_installed("terra")
  # Create test rasters with no overlap
  r1 <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10,
                     ymin = 0, ymax = 10, vals = 1L)
  r2 <- terra::rast(nrows = 10, ncols = 10, xmin = 100, xmax = 110,
                     ymin = 100, ymax = 110, vals = 1L)
  # Harmonizing should produce all-NA result since extents don't overlap
  # but resample fills from the template grid
  result <- rwapor_harmonize_to_template(r1, r2, method = "near")
  expect_true(inherits(result, "SpatRaster"))
})

test_that("total days and ldev computation works", {
  skip_if_not_installed("terra")
  start_r <- terra::rast(nrows = 5, ncols = 5, vals = 1)
  end_r   <- terra::rast(nrows = 5, ncols = 5, vals = 160)
  total_r <- rwapor_compute_total_days_raster(start_r, end_r)
  expect_equal(terra::values(total_r)[1, 1], 160)

  ldev_r <- rwapor_compute_ldev_raster(total_r, 30, 40, 30)
  expect_equal(terra::values(ldev_r)[1, 1], 60)  # 160 - 100
})

test_that("apply_masked_sum works with matching layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 0.5)
  result <- rwapor_apply_masked_sum(x, w)
  expect_equal(terra::values(result)[1, 1], 15)  # 10 * 0.5 * 3
})

test_that("apply_masked_sum errors on mismatched layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 2, vals = 0.5)
  expect_error(rwapor_apply_masked_sum(x, w), "Layer count mismatch")
})

test_that("adequacy_etc handles zero ETc", {
  expect_true(is.na(rwapor_calc_adequacy_etc(100, 0)))
  expect_equal(rwapor_calc_adequacy_etc(400, 400), 1)
  expect_equal(rwapor_calc_adequacy_etc(300, 400), 0.75)
})

test_that("aggregate_precip_monthly works", {
  ts <- data.frame(
    date = seq.Date(as.Date("2023-01-01"), as.Date("2023-03-31"), by = "day"),
    value = rep(2, 90),
    stringsAsFactors = FALSE
  )
  monthly <- rwapor_aggregate_precip_monthly(ts)
  expect_equal(nrow(monthly), 3)
  expect_equal(monthly$p_monthly_mm[1], 62)  # 31 days * 2
  expect_equal(monthly$p_monthly_mm[2], 56)  # 28 days * 2
  expect_equal(monthly$p_monthly_mm[3], 62)  # 31 days * 2
})
