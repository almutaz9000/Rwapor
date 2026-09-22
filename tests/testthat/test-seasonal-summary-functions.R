make_seasonal_summary_fixture <- function(values = c(2, 3, 4)) {
  layers <- lapply(values, function(value) {
    terra::rast(
      nrows = 2, ncols = 2, xmin = 35, xmax = 36, ymin = 33, ymax = 34,
      crs = "EPSG:4326", vals = value
    )
  })
  raster <- do.call(c, layers)
  plan <- data.frame(
    period_id = c("D1", "D2", "D3"),
    overlap_days = c(6L, 10L, 5L),
    stringsAsFactors = FALSE
  )

  list(
    groups = list(
      D_group = list(
        code = "D",
        variable = "L1-AETI-D",
        raster = raster,
        layer_ids = plan$period_id,
        multipliers = plan$overlap_days
      )
    ),
    plan = plan,
    aggregation_rule = "weighted_sum",
    missing_periods = data.frame()
  )
}

test_that("seasonal map defaults and explicit functions have the documented semantics", {
  skip_if_not_installed("terra")

  fixture <- make_seasonal_summary_fixture()
  output_dir <- tempfile("seasonal-summary-map-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)

  local_mocked_bindings(
    download_seasonal_rasters = function(...) fixture,
    .package = "Rwapor"
  )

  default_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE
  )
  sum_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "sum"
  )
  mean_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "mean"
  )
  std_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "std"
  )
  min_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "min"
  )
  max_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "max"
  )
  median_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "median"
  )

  expect_equal(as.vector(terra::values(terra::rast(default_path))), rep(62, 4))
  expect_equal(as.vector(terra::values(terra::rast(sum_path))), rep(62, 4))
  expect_equal(as.vector(terra::values(terra::rast(mean_path))), rep(3, 4))
  expect_equal(as.vector(terra::values(terra::rast(std_path))), rep(1, 4))
  expect_equal(as.vector(terra::values(terra::rast(min_path))), rep(2, 4))
  expect_equal(as.vector(terra::values(terra::rast(max_path))), rep(4, 4))
  expect_equal(as.vector(terra::values(terra::rast(median_path))), rep(3, 4))
  expect_false(grepl("\\.sum\\.", basename(default_path)))
  expect_match(basename(sum_path), "\\.seasonal\\.sum\\.")
  expect_match(basename(median_path), "\\.seasonal\\.median\\.")
  expect_equal(terra::units(terra::rast(sum_path)), get_seasonal_output_units("L1-AETI-D", "weighted_sum"))
  expect_equal(terra::units(terra::rast(mean_path)), get_seasonal_output_units("L1-AETI-D", "weighted_mean"))
})

test_that("seasonal time series uses weighted sums and equal-step summaries", {
  skip_if_not_installed("terra")

  fixture <- make_seasonal_summary_fixture()
  local_mocked_bindings(
    download_seasonal_rasters = function(...) fixture,
    .package = "Rwapor"
  )

  default_result <- wapor_ts(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), seasonal = TRUE
  )
  median_result <- wapor_ts(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), seasonal = TRUE, fun = "median"
  )
  std_result <- wapor_ts(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), seasonal = TRUE, fun = "std"
  )

  expect_equal(default_result$seasonal_sum, 62)
  expect_equal(median_result$seasonal_median, 3)
  expect_equal(std_result$seasonal_std, 1)
  expect_equal(attr(median_result, "units"), get_seasonal_output_units("L1-AETI-D", "weighted_mean"))
  expect_equal(attr(median_result, "aggregation_rule"), "median")
})

test_that("equal-step seasonal summaries ignore missing layers and require two values for std", {
  skip_if_not_installed("terra")

  fixture <- make_seasonal_summary_fixture(c(5, NA, NA))
  output_dir <- tempfile("seasonal-summary-na-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)
  local_mocked_bindings(
    download_seasonal_rasters = function(...) fixture,
    .package = "Rwapor"
  )

  mean_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "mean"
  )
  std_path <- wapor_map(
    region = c(35, 33, 36, 34), variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-01-25"), folder = output_dir,
    seasonal = TRUE, fun = "std"
  )

  expect_equal(as.vector(terra::values(terra::rast(mean_path))), rep(5, 4))
  expect_true(all(is.na(as.vector(terra::values(terra::rast(std_path))))))
})

test_that("seasonal summary function validation fails before download", {
  expect_error(
    wapor_map(
      region = c(35, 33, 36, 34), variable = "L1-AETI-D",
      period = c("2023-01-05", "2023-01-25"), folder = tempdir(),
      seasonal = TRUE, fun = "mode"
    ),
    "'fun' must be NULL or one of"
  )
  expect_error(
    wapor_ts(
      region = c(35, 33, 36, 34), variable = "L1-AETI-D",
      period = c("2023-01-05", "2023-01-25"), seasonal = TRUE, fun = "mode"
    ),
    "'fun' must be NULL or one of"
  )
})

test_that("state and rate products cannot be explicitly seasonally summed", {
  expect_true(wapor_is_seasonally_summable("L3-AETI-M"))
  expect_false(wapor_is_seasonally_summable("L3-RSM-D"))

  options <- wapor_seasonal_summary_options(c("L3-AETI-M", "L3-RSM-D"))
  expect_false("sum" %in% unname(options$choices))
  expect_equal(options$non_summable, "L3-RSM-D")

  expect_error(
    resolve_seasonal_summary_function("L3-RSM-D", "sum"),
    "cannot be seasonally summed"
  )
  expect_error(
    wapor_map(
      region = c(35, 33, 36, 34), variable = "L3-RSM-D",
      period = c("2023-01-01", "2023-01-10"), folder = tempdir(),
      seasonal = TRUE, fun = "sum"
    ),
    "cannot be seasonally summed"
  )
  expect_error(
    wapor_ts(
      region = c(35, 33, 36, 34), variable = "L3-RSM-D",
      period = c("2023-01-01", "2023-01-10"), seasonal = TRUE, fun = "sum"
    ),
    "cannot be seasonally summed"
  )
  expect_equal(resolve_seasonal_summary_function("L3-RSM-D", NULL)$fun, "mean")
  expect_equal(resolve_seasonal_summary_function("L3-RSM-D", "std")$fun, "std")
})
