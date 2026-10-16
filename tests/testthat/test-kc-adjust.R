test_that("wapor_adjust_kc_climate yields zero delta for standard sub-humid climate", {
  # Standard FAO-56 climate: u2 = 2.0 m/s, RHmin = 45%
  adj <- wapor_adjust_kc_climate(kc_mid = 1.15, kc_end = 0.60, u2 = 2.0, rh_min = 45.0, h = 1.5)
  expect_equal(adj$delta_kc, 0.0)
  expect_equal(adj$kc_mid_adj, 1.15)
  expect_equal(adj$kc_end_adj, 0.60)
})

test_that("wapor_adjust_kc_climate reproduces FAO-56 Example 26 (arid, windy)", {
  # FAO-56 Example 26: u2 = 3.2 m/s, RHmin = 30%, h = 2.5 m, Kc_mid(Tab) = 1.20
  adj <- wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 3.2, rh_min = 30.0, h = 2.5)
  expect_equal(adj$kc_mid_adj, 1.302, tolerance = 0.001)
})

test_that("wapor_adjust_kc_climate reproduces FAO-56 Example 27 (humid, calm)", {
  # FAO-56 Example 27: u2 = 1.5 m/s, RHmin = 60%, h = 2.0 m, Kc_mid(Tab) = 1.20
  adj <- wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 1.5, rh_min = 60.0, h = 2.0)
  expect_equal(adj$kc_mid_adj, 1.129, tolerance = 0.001)
})

test_that("wapor_adjust_kc_climate respects FAO-56 Eq. 65 threshold for Kc_end", {
  # When Kc_end <= 0.45, no adjustment should be applied
  adj_low <- wapor_adjust_kc_climate(
    kc_mid = 1.15, kc_end = 0.35, u2 = 4.0, rh_min = 25.0, h = 1.0
  )
  expect_equal(adj_low$kc_end_adj, 0.35)

  # When Kc_end > 0.45, adjustment is applied
  adj_high <- wapor_adjust_kc_climate(
    kc_mid = 1.15, kc_end = 0.60, u2 = 4.0, rh_min = 25.0, h = 1.0
  )
  expect_true(adj_high$kc_end_adj > 0.60)
})

test_that("wapor_adjust_kc_climate warns on out-of-bound inputs and clamps by default", {
  expect_warning(
    wapor_adjust_kc_climate(kc_mid = 1.0, u2 = 8.5, rh_min = 45.0, h = 1.0),
    "Wind speed 'u2' has values outside the FAO-56 validity range"
  )
  expect_warning(
    wapor_adjust_kc_climate(kc_mid = 1.0, u2 = 2.0, rh_min = 10.0, h = 1.0),
    "Relative humidity 'rh_min' has values outside the FAO-56 validity range"
  )
  expect_warning(
    wapor_adjust_kc_climate(kc_mid = 1.0, u2 = 2.0, rh_min = 45.0, h = 15.0),
    "Crop height 'h' has values outside the FAO-56 validity range"
  )

  # Check clamping
  suppressWarnings({
    adj <- wapor_adjust_kc_climate(kc_mid = 1.0, u2 = 8.5, rh_min = 10.0, h = 15.0)
  })
  # When clamped, u2 = 6, rh_min = 20, h = 10
  expected_delta <- (0.04 * (6 - 2) - 0.004 * (20 - 45)) * ((10 / 3)^0.3)
  expect_equal(adj$delta_kc, round(expected_delta, 4))
})

test_that("wapor_adjust_kc_climate validates input types and missing arguments", {
  expect_error(wapor_adjust_kc_climate(kc_mid = 1.0), "must all be provided")
  expect_error(wapor_adjust_kc_climate(kc_mid = "invalid", u2 = 2, rh_min = 45), "must be numeric")
  expect_error(wapor_adjust_kc_climate(kc_mid = 1.0, u2 = NA_real_, rh_min = 45), "without NA")
})

test_that("wapor_adjust_crop_params_agera5 correctly calibrates crop parameters table", {
  # Generate synthetic climate series across a 120-day season
  dates <- seq.Date(as.Date("2023-01-01"), as.Date("2023-04-30"), by = "day")
  set.seed(42)
  clim_df <- data.frame(
    date = dates,
    u2 = rep(c(2.5, 3.5, 4.0), length.out = length(dates)), # mean ~ 3.33 m/s
    rh_min = rep(c(25, 30, 35), length.out = length(dates)) # mean ~ 30 %
  )

  crop_df <- data.frame(
    class_value  = c(1, 2),
    class_name   = c("Wheat", "Maize"),
    kc_ini       = c(0.40, 0.30),
    kc_mid       = c(1.15, 1.20),
    kc_end       = c(0.30, 0.60), # Wheat <= 0.45; Maize > 0.45
    l_ini_days   = c(20L, 20L),
    l_mid_days   = c(40L, 40L),
    l_late_days  = c(30L, 30L),
    max_height_m = c(1.0, 2.0),
    stringsAsFactors = FALSE
  )

  res <- wapor_adjust_crop_params_agera5(
    crop_params  = crop_df,
    season_start = "2023-01-01",
    season_end   = "2023-04-30",
    climate_df   = clim_df
  )

  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 2)

  # Check preserved tabulated columns
  expect_equal(res$kc_mid_tab, c(1.15, 1.20))
  expect_equal(res$kc_end_tab, c(0.30, 0.60))

  # Under arid/windy conditions (u2 ~ 3.3 > 2, rh_min ~ 30 < 45), Kc_mid should increase
  expect_true(res$kc_mid[1] > 1.15)
  expect_true(res$kc_mid[2] > 1.20)

  # Wheat Kc_end (0.30 <= 0.45) should NOT change
  expect_equal(res$kc_end[1], 0.30)

  # Maize Kc_end (0.60 > 0.45) should increase
  expect_true(res$kc_end[2] > 0.60)

  # Stage climate averages should be recorded
  expect_false(any(is.na(res$u2_mid)))
  expect_false(any(is.na(res$rh_min_mid)))
  expect_false(any(is.na(res$u2_late)))
  expect_false(any(is.na(res$rh_min_late)))
})

test_that("wapor_adjust_crop_params_agera5 handles short-season proportional scaling", {
  dates <- seq.Date(as.Date("2023-01-01"), as.Date("2023-02-15"), by = "day") # 46 days
  clim_df <- data.frame(
    date = dates,
    u2 = 2.0,
    rh_min = 45.0
  )

  # Standard stages sum = 20 + 40 + 30 = 90 days > 46 days
  crop_df <- data.frame(
    class_value  = 1,
    class_name   = "ShortSeasonCrop",
    kc_ini       = 0.40,
    kc_mid       = 1.15,
    kc_end       = 0.50,
    l_ini_days   = 20L,
    l_mid_days   = 40L,
    l_late_days  = 30L,
    max_height_m = 1.0
  )

  res <- wapor_adjust_crop_params_agera5(
    crop_params  = crop_df,
    season_start = "2023-01-01",
    season_end   = "2023-02-15",
    climate_df   = clim_df
  )

  expect_equal(res$kc_mid, 1.15) # neutral climate, so unchanged
  expect_equal(res$kc_end, 0.50)
})
