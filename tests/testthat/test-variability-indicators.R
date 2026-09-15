# =============================================================================
# Tests for variability (standard deviation) indicator functions
# =============================================================================

test_that("wapor_masked_std calculates weighted standard deviation correctly", {
  skip_if_not_installed("terra")
  
  # Create a SpatRaster with n layers
  x <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3)
  # Values for the 4 pixels across 3 layers:
  # Pixel 1: 10, 20, 30
  # Pixel 2: 5, 5, 5
  # Pixel 3: 0, 10, 20
  # Pixel 4: 100, 200, 300
  terra::values(x) <- matrix(c(
    10, 20, 30,
    5,  5,  5,
    0,  10, 20,
    100, 200, 300
  ), byrow = TRUE, ncol = 3)
  
  # Season weights for the layers
  w <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3)
  terra::values(w) <- matrix(c(
    1.0, 0.5, 1.0,
    1.0, 0.5, 1.0,
    1.0, 0.5, 1.0,
    1.0, 0.5, 1.0
  ), byrow = TRUE, ncol = 3)
  
  # Let's verify mathematically for Pixel 1:
  # Values: v = [10, 20, 30]
  # Weights: w = [1.0, 0.5, 1.0]
  # Sum of weights: sum_w = 2.5
  # Weighted mean: mu = (10*1.0 + 20*0.5 + 30*1.0) / 2.5 = (10 + 10 + 30) / 2.5 = 50 / 2.5 = 20
  # Squared diffs: (v - mu)^2 = [(10-20)^2, (20-20)^2, (30-20)^2] = [100, 0, 100]
  # Weighted sum of squared diffs: sum_w_diff_sq = 1.0*100 + 0.5*0 + 1.0*100 = 200
  # Weighted variance: var = 200 / 2.5 = 80
  # Weighted standard deviation: std = sqrt(80) = 8.944272
  
  result <- wapor_masked_std(x, w)
  vals <- terra::values(result)
  
  expect_equal(as.numeric(vals[1, 1]), sqrt(80), tolerance = 1e-6)
  
  # Pixel 2: values = [5, 5, 5], so std should be 0
  expect_equal(as.numeric(vals[2, 1]), 0, tolerance = 1e-6)
})

test_that("wapor_calc_seasonal_std calculates standard deviation and crop class summaries", {
  skip_if_not_installed("terra")
  
  x <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 10)
  terra::values(x[[2]]) <- 20
  terra::values(x[[3]]) <- 30
  
  w <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 1.0)
  crop_mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2))
  
  result <- wapor_calc_seasonal_std(x, w, crop_mask = crop_mask)
  
  expect_true(inherits(result$raster, "SpatRaster"))
  expect_true(is.data.frame(result$by_class))
  expect_equal(nrow(result$by_class), 2)
  expect_equal(result$by_class$class_value, c(1, 2))
})

test_that("wapor_calc_monthly_weighted_std_rasters computes monthly variability", {
  skip_if_not_installed("terra")
  
  x <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 10)
  terra::values(x[[2]]) <- 20
  terra::values(x[[3]]) <- 30
  
  w <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 1.0)
  
  dekad_table <- data.frame(
    dekad_key = c("2023-01-01", "2023-01-11", "2023-02-01"),
    stringsAsFactors = FALSE
  )
  
  result <- wapor_calc_monthly_weighted_std_rasters(x, w, dekad_table)
  
  expect_equal(length(result$rasters), 2)
  expect_equal(names(result$rasters), c("2023-01", "2023-02"))
  
  # For 2023-01 (layers 1 and 2):
  # Values: 10, 20
  # Weights: 1.0, 1.0 -> mean = 15. std = sqrt(((10-15)^2 + (20-15)^2)/2) = sqrt((25+25)/2) = 5
  vals_jan <- terra::values(result$rasters[["2023-01"]])
  expect_equal(as.numeric(vals_jan[1, 1]), 5, tolerance = 1e-6)
  
  # For 2023-02 (layer 3 only):
  # Single value: 30. std = 0
  vals_feb <- terra::values(result$rasters[["2023-02"]])
  expect_equal(as.numeric(vals_feb[1, 1]), 0, tolerance = 1e-6)
})
