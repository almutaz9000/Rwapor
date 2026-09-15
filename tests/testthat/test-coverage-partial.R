test_that("incomplete seasonal coverage fails unless partial = TRUE", {
  local_mocked_bindings(
    wapor_temporal_codes = function(variable) "D",
    wapor_generate_urls = function(...) character(0),
    .package = "Rwapor"
  )

  reg_info <- list(type = "bbox", value = c(xmin = 35, ymin = 33, xmax = 36, ymax = 34))

  expect_error(
    suppressWarnings(download_seasonal_rasters(
      variable = "L1-AETI-D",
      period = c("2023-01-01", "2023-01-31"),
      l3_code = NULL,
      reg_info = reg_info,
      folder = tempdir()
    )),
    "INCOMPLETE"
  )

  expect_warning(
    result <- download_seasonal_rasters(
      variable = "L1-AETI-D",
      period = c("2023-01-01", "2023-01-31"),
      l3_code = NULL,
      reg_info = reg_info,
      folder = tempdir(),
      partial = TRUE
    ),
    "INCOMPLETE"
  )
  expect_true(length(result$missing_periods) > 0)
  expect_true(isTRUE(result$partial))
})

test_that("wapor_map and wapor_ts expose partial coverage opt-in", {
  expect_true("partial" %in% names(formals(wapor_map)))
  expect_true("partial" %in% names(formals(wapor_ts)))
})
