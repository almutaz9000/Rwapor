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
  tbl <- build_dekad_table("2023-01-01", "2023-02-28")
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
  # Harmonizing should error because extents don't overlap
  expect_error(rwapor_harmonize_to_template(r1, r2, method = "near"),
               "No spatial overlap")
})

test_that("harmonization works with overlapping but different extents", {
  skip_if_not_installed("terra")
  # Create source raster larger than template
  r_source <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 20,
                           ymin = 0, ymax = 20, vals = seq_len(400))
  # Template is smaller but overlaps
  r_template <- terra::rast(nrows = 10, ncols = 10, xmin = 5, xmax = 15,
                             ymin = 5, ymax = 15, vals = 1L)

  # Harmonization should succeed
  result <- rwapor_harmonize_to_template(r_source, r_template, method = "bilinear")

  expect_true(inherits(result, "SpatRaster"))
  expect_equal(dim(result)[1:2], dim(r_template)[1:2])
  expect_true(all(!is.na(terra::values(result))))
})

test_that("harmonization works for multi-layer stacks (regression test for extent mismatch)", {
  skip_if_not_installed("terra")
  # Simulate the scenario: data stack with slightly different extent than template
  # This is the regression test for the bug where aeti_stack wasn't harmonized

  # Create template (cropped to specific extent)
  template <- terra::rast(nrows = 10, ncols = 10, xmin = 30, xmax = 35,
                           ymin = 10, ymax = 15, vals = 1)

  # Create multi-layer stack with larger extent (like full raster from WaPOR)
  stack <- terra::rast(nrows = 100, ncols = 100, xmin = 25, xmax = 50,
                        ymin = 5, ymax = 30, nlyrs = 5, vals = runif(50000))
  names(stack) <- paste0("2023-01-0", 1:5)

  # Create season weights from template extent
  weights <- terra::rast(nrows = 10, ncols = 10, xmin = 30, xmax = 35,
                          ymin = 10, ymax = 15, nlyrs = 5, vals = 0.5)
  names(weights) <- names(stack)

  # Without harmonization, this operation would fail with extent mismatch
  harmonized_stack <- rwapor_harmonize_to_template(stack, template, method = "bilinear")

  # Now the multiplication should work
  result <- harmonized_stack * weights

  expect_true(inherits(result, "SpatRaster"))
  expect_equal(terra::nlyr(result), 5)
  expect_true(all(dim(result)[1:2] == dim(template)[1:2]))
})

test_that("total days and ldev computation works", {
  skip_if_not_installed("terra")
  start_r <- terra::rast(nrows = 5, ncols = 5, vals = 1)
  end_r   <- terra::rast(nrows = 5, ncols = 5, vals = 160)
  total_r <- rwapor_compute_total_days_raster(start_r, end_r)
  expect_equal(as.numeric(terra::values(total_r)[1, 1]), 160)

  ldev_r <- rwapor_compute_ldev_raster(total_r, 30, 40, 30)
  expect_equal(as.numeric(terra::values(ldev_r)[1, 1]), 60)  # 160 - 100
})

test_that("apply_masked_sum works with matching layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 0.5)
  result <- rwapor_apply_masked_sum(x, w)
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15)  # 10 * 0.5 * 3
})

test_that("apply_masked_sum honors per-layer multipliers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 0.5)
  result <- rwapor_apply_masked_sum(x, w, layer_multipliers = c(10, 10, 11))
  expect_equal(as.numeric(terra::values(result)[1, 1]), 155)
})

test_that("apply_masked_sum errors on mismatched layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 2, vals = 0.5)
  expect_error(rwapor_apply_masked_sum(x, w), "Layer count mismatch")
})

test_that("analysis layer multipliers use dekad day counts for daily-rate D variables", {
  multiplier_helper <- if (exists("get_analysis_layer_multipliers", mode = "function")) {
    get("get_analysis_layer_multipliers", mode = "function")
  } else {
    getFromNamespace("get_analysis_layer_multipliers", "Rwapor")
  }
  period_table <- data.frame(
    dekad_start = as.Date(c("2023-01-01", "2023-01-11", "2023-01-21")),
    dekad_end = as.Date(c("2023-01-10", "2023-01-20", "2023-01-31")),
    n_days = c(10L, 10L, 11L)
  )

  expect_equal(multiplier_helper("L1-AETI-D", period_table), c(10, 10, 11))
  expect_equal(multiplier_helper("L1-TBP-A", period_table), c(1, 1, 1))
})

test_that("seasonal ETc incremental honors per-layer multipliers", {
  skip_if_not_installed("terra")
  ret <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 1)
  w <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 0.5)
  result <- rwapor_calc_seasonal_etc_incremental(
    ret,
    w,
    kc_dekad = c(1, 1, 1),
    layer_multipliers = c(10, 10, 11)
  )
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15.5)
})

test_that("adequacy_etc handles zero ETc", {
  expect_true(is.na(rwapor_calc_adequacy_etc(100, 0)))
  expect_equal(rwapor_calc_adequacy_etc(400, 400), 1)
  expect_equal(rwapor_calc_adequacy_etc(300, 400), 0.75)
})

test_that("class p95 validity counts only non-missing analysis pixels", {
  skip_if_not_installed("terra")
  aeti <- terra::rast(nrows = 2, ncols = 2, vals = c(1, NA, 3, 4))
  crop_mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2))

  result <- rwapor_calc_class_p95_aeti(aeti, crop_mask, min_pixels = 2)
  result <- result[order(result$class_value), ]

  expect_equal(result$n_pixels, c(1L, 2L))
  expect_equal(result$valid, c(FALSE, TRUE))
  expect_true(is.na(result$p95_aeti[1]))
  expect_false(is.na(result$p95_aeti[2]))
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

test_that("NPP to TBP conversion works", {
  npp <- 100
  tbp <- rwapor_convert_npp_to_tbp(npp)
  expect_equal(tbp, 100 * 22.222)
})

test_that("Yield calculation from NPP works", {
  # Formula:
  # dmp = NPP * 22.222
  # agbm = (AOT * fc * (dmp / (1 - MC))) / 1000
  # yield = HI * agbm
  
  npp <- 100
  MC  <- 0.7
  fc  <- 1.6
  AOT <- 0.8
  HI  <- 1.0
  
  dmp <- 100 * 22.222
  expected_agbm <- (0.8 * 1.6 * (dmp / (1 - 0.7))) / 1000
  expected_yield <- 1.0 * expected_agbm
  
  yield <- rwapor_calc_yield_npp(npp, MC, fc, AOT, HI)
  expect_equal(yield, expected_yield)
})
