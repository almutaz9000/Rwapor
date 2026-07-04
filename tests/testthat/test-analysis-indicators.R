# =============================================================================
# Tests for analysis indicator calculation functions
# (Peff, CWP/BWP, masked sum, ETc, adequacy, P95, precip, yield, BF, green/blue water)
# Extracted from test-analysis.R to reduce its god-node edge count.
# =============================================================================

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
  multiplier_helper <- get_analysis_layer_multipliers
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

test_that("beneficial fraction and green/blue water helpers work", {
  expect_equal(wapor_calc_beneficial_fraction(50, 200), 0.25)
  expect_true(is.na(wapor_calc_beneficial_fraction(50, 0)))

  expect_equal(wapor_calc_green_water(350, 200), 200)
  expect_equal(wapor_calc_green_water(150, 200), 150)

  expect_equal(wapor_calc_blue_water(350, 200), 150)
  expect_equal(wapor_calc_blue_water(150, 200), 0)
})
