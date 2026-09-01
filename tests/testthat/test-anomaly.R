test_that("wapor_calc_zscore computes correct temporal zscores", {
  r1 <- terra::rast(nrows = 2, ncols = 2, vals = c(10, 20, 30, 40))
  r2 <- terra::rast(nrows = 2, ncols = 2, vals = c(20, 30, 40, 50))
  s <- c(r1, r2)
  z <- wapor_calc_zscore(s)
  expect_equal(terra::nlyr(z), 2)
  # Values for layer 1 should be negative, layer 2 positive
  vals1 <- terra::values(z[[1]])
  vals2 <- terra::values(z[[2]])
  expect_true(all(vals1 < 0))
  expect_true(all(vals2 > 0))
})

test_that("wapor_calc_spatial_hotspots classifies into integer classes", {
  z <- terra::rast(nrows = 5, ncols = 1, vals = c(-3.0, -1.5, 0.0, 1.5, 3.0))
  h <- wapor_calc_spatial_hotspots(z, low = -1.96, high = 1.96)
  vals <- as.integer(terra::values(h))
  expect_equal(vals, c(-2L, -1L, 0L, 1L, 2L))
})

test_that("wapor_calc_anomaly_baseline computes difference and zscore", {
  curr <- terra::rast(nrows = 2, ncols = 2, vals = c(120, 150, 180, 200))
  base_m <- terra::rast(nrows = 2, ncols = 2, vals = c(100, 100, 100, 100))
  base_sd <- terra::rast(nrows = 2, ncols = 2, vals = c(10, 25, 20, 50))

  diff_r <- wapor_calc_anomaly_baseline(curr, base_m)
  expect_equal(as.numeric(terra::values(diff_r)), c(20, 50, 80, 100))

  z_r <- wapor_calc_anomaly_baseline(curr, base_m, base_sd)
  expect_equal(as.numeric(terra::values(z_r)), c(2.0, 2.0, 4.0, 2.0))
})
