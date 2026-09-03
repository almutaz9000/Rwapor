test_that("download_seasonal_rasters warns and reports missing_periods when a whole code group has no URLs", {
  local_mocked_bindings(
    wapor_temporal_codes = function(variable) "D",
    wapor_generate_urls = function(...) character(0),
    .package = "Rwapor"
  )

  reg_info <- list(type = "bbox", value = c(xmin = 35, ymin = 33, xmax = 36, ymax = 34))

  expect_warning(
    expect_warning(
      result <- download_seasonal_rasters(
        variable = "L1-AETI-D",
        period = c("2023-01-01", "2023-01-31"),
        l3_code = NULL,
        reg_info = reg_info,
        folder = tempdir()
      ),
      "No URLs found"
    ),
    "INCOMPLETE"
  )

  expect_length(result$groups, 0)
  expect_true(length(result$missing_periods) > 0)
  expect_true(all(result$missing_periods %in% result$plan$period_id))
})

test_that("download_seasonal_rasters reports no missing_periods when all groups load successfully", {
  skip_if_not_installed("terra")

  r_dekad <- terra::rast(nrows = 2, ncols = 2, xmin = 35, xmax = 36, ymin = 33, ymax = 34, vals = 5)
  terra::crs(r_dekad) <- "EPSG:4326"

  local_mocked_bindings(
    wapor_temporal_codes = function(variable) "D",
    wapor_generate_urls = function(variable, l3_region = NULL, period = NULL) "http://example.com/dummy.tif",
    wapor_date_info = function(u, tres) list(start_date = "2023-01-01"),
    .package = "Rwapor"
  )
  local_mocked_bindings(
    rast = function(...) r_dekad,
    .package = "terra"
  )

  reg_info <- list(
    type = "bbox",
    value = sf::st_bbox(c(xmin = 35, ymin = 33, xmax = 36, ymax = 34), crs = 4326)
  )

  result <- download_seasonal_rasters(
    variable = "L1-AETI-D",
    period = c("2023-01-01", "2023-01-10"),
    l3_code = NULL,
    reg_info = reg_info,
    folder = tempdir()
  )

  expect_length(result$missing_periods, 0)
  expect_true(length(result$groups) > 0)
})
