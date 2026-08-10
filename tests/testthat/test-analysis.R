# =============================================================================
# Tests for analysis functions
# =============================================================================

test_that("crop defaults validation works", {
  expect_true(wapor_validate_crop_defaults(FAO_CROP_DEFAULTS))

  # Missing columns
  bad_df <- data.frame(crop_name = "Test", kc_ini = 0.3)
  expect_error(wapor_validate_crop_defaults(bad_df), "Missing required columns")

  # Negative Kc
  bad_df2 <- FAO_CROP_DEFAULTS
  bad_df2$kc_ini[1] <- -0.1
  expect_error(wapor_validate_crop_defaults(bad_df2), "non-negative")

  # NA stage lengths
  bad_df3 <- FAO_CROP_DEFAULTS
  bad_df3$l_ini_days[1] <- NA

  expect_error(wapor_validate_crop_defaults(bad_df3), "must not be NA")
})

test_that("wapor_list_crops returns crop names", {
  crops <- wapor_list_crops()
  expect_true(length(crops) >= 3)
  expect_true("Winter Wheat" %in% crops)
  expect_true("Sorghum" %in% crops)
  expect_true("Sugarbeet" %in% crops)
})

test_that("wapor_crop_defaults works", {
  ww <- wapor_crop_defaults("Winter Wheat")
  expect_true(!is.null(ww))
  expect_equal(nrow(ww), 1)
  expect_equal(ww$kc_mid, 1.15)

  # Case insensitive
  sg <- wapor_crop_defaults("sorghum")
  expect_true(!is.null(sg))

  # Not found
  expect_null(wapor_crop_defaults("NonexistentCrop"))
})

test_that("continuous Julian date logic works", {
  # Same year
  expect_equal(wapor_continuous_julian("2023-01-01", 2023), 1L)
  expect_equal(wapor_continuous_julian("2023-12-31", 2023), 365L)

  # Cross-year
  expect_equal(wapor_continuous_julian("2024-01-01", 2023), 366L)
  expect_equal(wapor_continuous_julian("2024-01-15", 2023), 380L)

  # Leap year
  expect_equal(wapor_continuous_julian("2024-12-31", 2024), 366L)
  expect_equal(wapor_continuous_julian("2025-01-01", 2024), 367L)
})

test_that("daily Kc curve generation works", {
  kc <- wapor_build_kc(0.4, 1.15, 0.30, 30, 60, 40, 30)
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
    kc_ini = c(0.4, 0.3),
    kc_mid = c(1.15, 1.05),
    kc_end = c(0.30, 0.55),
    l_ini_days = c(30L, 20L),
    l_mid_days = c(40L, 40L),
    l_late_days = c(30L, 30L),
    stringsAsFactors = FALSE
  )
  result <- wapor_build_kc_by_class(params, c("1" = 160, "2" = 150))
  expect_true(length(result) == 2)
  expect_equal(length(result[["1"]]), 160)
  expect_equal(length(result[["2"]]), 150)
})

test_that("Peff USDA monthly calculation works", {
  # P <= 250
  expect_equal(wapor_calc_peff_usda(0), 0)
  expect_equal(wapor_calc_peff_usda(100), 100 * (125 - 20) / 125)

  # P > 250
  expect_equal(wapor_calc_peff_usda(300), 125 + 30)

  # Vectorized
  peff <- wapor_calc_peff_usda(c(50, 120, 300))
  expect_equal(length(peff), 3)
})

test_that("CWP and BWP calculations work", {
  # 5000 kg/ha yield, 400 mm AETI
  cwp <- wapor_calc_cwp(5000, 400)
  expect_equal(cwp, 5000 / (400 * 10))  # kg/m3

  # t/ha unit
  cwp_t <- wapor_calc_cwp(5, 400, yield_unit = "t/ha")
  expect_equal(cwp_t, cwp)

  # Zero AETI returns NA
  expect_true(is.na(wapor_calc_cwp(5000, 0)))

  # BWP
  bwp <- wapor_calc_bwp(12000, 400)
  expect_equal(bwp, 12000 / (400 * 10))
})

test_that("crop mask harmonization requires SpatRaster inputs", {
  expect_error(wapor_harmonize_raster("not_a_raster", "also_not"),
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
  expect_error(wapor_harmonize_raster(r1, r2, method = "near"),
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
  result <- wapor_harmonize_raster(r_source, r_template, method = "bilinear")

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
  harmonized_stack <- wapor_harmonize_raster(stack, template, method = "bilinear")

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
  total_r <- wapor_season_days(start_r, end_r)
  expect_equal(as.numeric(terra::values(total_r)[1, 1]), 160)

  ldev_r <- wapor_season_ldev(total_r, 30, 40, 30)
  expect_equal(as.numeric(terra::values(ldev_r)[1, 1]), 60)  # 160 - 100
})

test_that("apply_masked_sum works with matching layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 0.5)
  result <- wapor_masked_sum(x, w)
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15)  # 10 * 0.5 * 3
})

test_that("apply_masked_sum honors per-layer multipliers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 0.5)
  result <- wapor_masked_sum(x, w, layer_multipliers = c(10, 10, 11))
  expect_equal(as.numeric(terra::values(result)[1, 1]), 155)
})

test_that("apply_masked_sum errors on mismatched layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 2, vals = 0.5)
  expect_error(wapor_masked_sum(x, w), "Layer count mismatch")
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
  result <- wapor_calc_seasonal_etc(
    ret,
    w,
    kc_dekad = c(1, 1, 1),
    layer_multipliers = c(10, 10, 11)
  )
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15.5)
})

test_that("adequacy_etc handles zero ETc", {
  expect_true(is.na(wapor_calc_adequacy_etc(100, 0)))
  expect_equal(wapor_calc_adequacy_etc(400, 400), 1)
  expect_equal(wapor_calc_adequacy_etc(300, 400), 0.75)
})

test_that("class p95 validity counts only non-missing analysis pixels", {
  skip_if_not_installed("terra")
  aeti <- terra::rast(nrows = 2, ncols = 2, vals = c(1, NA, 3, 4))
  crop_mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2))

  result <- wapor_calc_p95_aeti(aeti, crop_mask, min_pixels = 2)
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
  monthly <- wapor_aggregate_precip(ts)
  expect_equal(nrow(monthly), 3)
  expect_equal(monthly$p_monthly_mm[1], 62)  # 31 days * 2
  expect_equal(monthly$p_monthly_mm[2], 56)  # 28 days * 2
  expect_equal(monthly$p_monthly_mm[3], 62)  # 31 days * 2
})

test_that("NPP to TBP conversion works", {
  npp <- 100
  tbp <- wapor_convert_npp_tbp(npp)
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
  
  yield <- wapor_calc_yield_npp(npp, MC, fc, AOT, HI)
  expect_equal(yield, expected_yield)
})

test_that("wapor_calc_peff works with vectorized date overlap calculation", {
  peff_monthly <- data.frame(
    year = c(2023L, 2023L, 2023L),
    month = c(5L, 6L, 7L),
    peff_mm = c(50, 100, 80),
    stringsAsFactors = FALSE
  )

  # Standard overlap: full season is May 1 to July 31 (all 3 months fully overlap)
  total_peff_full <- wapor_calc_peff(peff_monthly, start_date = "2023-05-01", end_date = "2023-07-31")
  expect_equal(total_peff_full, 230) # 50 + 100 + 80

  # Partial overlap: season is May 16 to June 15
  # May has 31 days. May 16 to May 31 is 16 days. Overlap fraction: 16/31
  # June has 30 days. June 1 to June 15 is 15 days. Overlap fraction: 15/30 = 0.5
  total_peff_partial <- wapor_calc_peff(peff_monthly, start_date = "2023-05-16", end_date = "2023-06-15")
  expected_val <- 50 * (16 / 31) + 100 * (15 / 30)
  expect_equal(total_peff_partial, expected_val, tolerance = 1e-6)

  # No overlap: season is August 1 to August 31
  total_peff_none <- wapor_calc_peff(peff_monthly, start_date = "2023-08-01", end_date = "2023-08-31")
  expect_equal(total_peff_none, 0)
})

test_that("wapor_build_season_mask works with vectorized logic", {
  skip_if_not_installed("terra")
  start_r <- terra::rast(nrows = 5, ncols = 5, vals = 100)
  end_r   <- terra::rast(nrows = 5, ncols = 5, vals = 200)
  dates <- c("2023-04-15", "2023-06-15", "2023-08-15") # julian days in 2023: 105, 166, 227

  result <- wapor_build_season_mask(dates, start_r, end_r, reference_year = 2023)

  expect_true(inherits(result, "SpatRaster"))
  expect_equal(terra::nlyr(result), 3)
  expect_equal(names(result), as.character(as.Date(dates)))

  # Layer 1: jd = 105 (inside 100-200) -> 1
  # Layer 2: jd = 166 (inside 100-200) -> 1
  # Layer 3: jd = 227 (outside 100-200) -> 0
  expect_equal(as.numeric(terra::values(result[[1]])[1]), 1)
  expect_equal(as.numeric(terra::values(result[[2]])[1]), 1)
  expect_equal(as.numeric(terra::values(result[[3]])[1]), 0)
})

test_that("wapor_detect_aeti_anomalies correctly flags anomalies and masks invalid classes", {
  skip_if_not_installed("terra")

  # Create a mock seasonal AETI raster
  # Class 1: 40 pixels, median ~10, normal range 8-12, one low pixel at 3
  # Class 2: 5 pixels, below min_pixels (30), should be masked to NA
  aeti_vals <- c(
    rep(10, 39), 3,       # Class 1 (40 pixels)
    rep(10, 5)            # Class 2 (5 pixels)
  )
  crop_vals <- c(
    rep(1L, 40),
    rep(2L, 5)
  )

  aeti_rast <- terra::rast(nrows = 9, ncols = 5, vals = aeti_vals)
  crop_mask <- terra::rast(nrows = 9, ncols = 5, vals = crop_vals)

  result <- wapor_detect_aeti_anomalies(aeti_rast, crop_mask, threshold = 0.5, min_pixels = 30)

  expect_true(inherits(result$anomaly_map, "SpatRaster"))

  # Verify anomaly counts/stats for Class 1 (valid class)
  stats <- result$anomaly_stats
  class1_stats <- stats[stats$class_value == 1, ]
  expect_true(class1_stats$valid)
  expect_equal(class1_stats$pixel_count, 40)
  expect_equal(class1_stats$anomaly_pixels, 1) # only the value 3 is < 10 * 0.5

  # Verify Class 2 is marked invalid
  class2_stats <- stats[stats$class_value == 2, ]
  expect_false(class2_stats$valid)

  # Verify anomaly map values
  # Class 2 pixels should be NA in anomaly_map because Class 2 has < min_pixels (30)
  anom_vals <- terra::values(result$anomaly_map)
  expect_true(all(is.na(anom_vals[41:45])))

  # Class 1 normal pixels should be 0, anomaly pixel should be 1
  expect_equal(sum(anom_vals[1:40] == 1, na.rm = TRUE), 1)
  expect_equal(sum(anom_vals[1:40] == 0, na.rm = TRUE), 39)
})
