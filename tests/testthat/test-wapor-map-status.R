test_that("wapor_map status distinguishes complete and partial layer coverage", {
  complete <- Rwapor:::.wapor_map_completion_status(
    expected_urls = c("layer-1", "layer-2", "layer-3"),
    received_urls = c("layer-1", "layer-2", "layer-3"),
    failed_urls = character(),
    received_layer_names = c("2023-01-01", "2023-01-11", "2023-01-21"),
    requested_period = c("2023-01-01", "2023-01-31")
  )
  expect_identical(complete$status, "ok")
  expect_true(complete$complete)
  expect_equal(complete$expected_layers, 3L)
  expect_equal(complete$received_layers, 3L)
  expect_length(complete$failed_layers, 0L)
  expect_equal(complete$coverage_fraction, 1)

  partial <- Rwapor:::.wapor_map_completion_status(
    expected_urls = c("layer-1", "layer-2", "layer-3"),
    received_urls = c("layer-1", "layer-3"),
    failed_urls = "layer-2",
    received_layer_names = c("2023-01-01", "2023-01-21"),
    requested_period = c("2023-01-01", "2023-01-31")
  )
  expect_identical(partial$status, "partial")
  expect_false(partial$complete)
  expect_equal(partial$expected_layers, 3L)
  expect_equal(partial$received_layers, 2L)
  expect_identical(partial$failed_layers, "layer-2")
  expect_equal(partial$coverage_fraction, 2 / 3)
  expect_identical(partial$requested_period, c("2023-01-01", "2023-01-31"))
  expect_identical(partial$received_layer_names, c("2023-01-01", "2023-01-21"))
})

test_that("wapor_map status marks an all-failed run failed with zero coverage", {
  result <- Rwapor:::.wapor_map_completion_status(
    expected_urls = c("layer-1", "layer-2"),
    received_urls = character(),
    failed_urls = c("layer-1", "layer-2"),
    received_layer_names = character(),
    requested_period = c("2023-01-01", "2023-01-21")
  )
  expect_identical(result$status, "failed")
  expect_false(result$complete)
  expect_equal(result$expected_layers, 2L)
  expect_equal(result$received_layers, 0L)
  expect_equal(result$coverage_fraction, 0)
  expect_identical(result$failed_layers, c("layer-1", "layer-2"))
})

test_that("wapor_map chunk summary refuses incomplete outputs by default", {
  chunk_results <- list(
    list(status = "ok", chunk_idx = 1L, urls = c("layer-1", "layer-2"),
         layer_names = c("2023-01-01", "2023-01-11")),
    list(status = "failed", chunk_idx = 2L, urls = "layer-3", error = "HTTP 503")
  )

  expect_error(
    Rwapor:::.wapor_map_chunk_summary(
      chunk_results,
      expected_urls = c("layer-1", "layer-2", "layer-3"),
      requested_period = c("2023-01-01", "2023-01-31"),
      partial = FALSE
    ),
    "raster batch.*failed.*partial = TRUE"
  )
})

test_that("wapor_map chunk summary marks partial and all-failed outputs", {
  mixed <- list(
    list(status = "ok", chunk_idx = 1L, urls = c("layer-1", "layer-2"),
         layer_names = c("2023-01-01", "2023-01-11")),
    list(status = "failed", chunk_idx = 2L, urls = "layer-3", error = "HTTP 503")
  )
  partial <- Rwapor:::.wapor_map_chunk_summary(
    mixed,
    expected_urls = c("layer-1", "layer-2", "layer-3"),
    requested_period = c("2023-01-01", "2023-01-31"),
    partial = TRUE
  )
  expect_identical(partial$status$status, "partial")
  expect_false(partial$status$complete)
  expect_equal(partial$status$expected_layers, 3L)
  expect_equal(partial$status$received_layers, 2L)
  expect_identical(partial$status$failed_layers, "layer-3")
  expect_equal(partial$status$coverage_fraction, 2 / 3)

  failed <- list(list(status = "failed", chunk_idx = 1L,
                      urls = c("layer-1", "layer-2"), error = "HTTP 503"))
  expect_error(
    Rwapor:::.wapor_map_chunk_summary(
      failed,
      expected_urls = c("layer-1", "layer-2"),
      requested_period = c("2023-01-01", "2023-01-21"),
      partial = FALSE
    ),
    "All chunks failed.*partial = TRUE"
  )
  all_failed <- Rwapor:::.wapor_map_chunk_summary(
    failed,
    expected_urls = c("layer-1", "layer-2"),
    requested_period = c("2023-01-01", "2023-01-21"),
    partial = TRUE
  )
  expect_identical(all_failed$status$status, "failed")
  expect_equal(all_failed$status$received_layers, 0L)
  expect_equal(all_failed$status$coverage_fraction, 0)
})
