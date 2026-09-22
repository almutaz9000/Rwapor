test_that("linear_trend returns accurate per-pixel OLS rasters", {
  s <- terra::rast(nrows = 1, ncols = 2, nlyrs = 3,
                   vals = c(1, 10, 2, 12, 3, 14))
  tr <- linear_trend(s, times = c(0, 1, 2))
  expect_named(tr, c("slope", "intercept", "r2"))
  expect_equal(as.numeric(terra::values(tr$slope)), c(1, 2), tolerance = 1e-10)
  expect_equal(as.numeric(terra::values(tr$intercept)), c(1, 10), tolerance = 1e-10)
  expect_equal(as.numeric(terra::values(tr$r2)), c(1, 1), tolerance = 1e-10)
})

test_that("specification aliases preserve anomaly behavior", {
  s <- terra::rast(nrows = 1, ncols = 1, nlyrs = 2, vals = c(1, 3))
  expect_true(inherits(zscore_anomaly(s), "SpatRaster"))
  expect_true(inherits(spatial_hotspots(terra::rast(nrows = 1, ncols = 1, vals = 2)), "SpatRaster"))
  expect_equal(as.numeric(terra::values(anomaly_vs_baseline(
    terra::rast(nrows = 1, ncols = 1, vals = 3),
    terra::rast(nrows = 1, ncols = 1, vals = 1)))), 2)
})
