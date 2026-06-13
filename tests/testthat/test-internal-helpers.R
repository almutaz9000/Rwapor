# Tests for internal helpers added in v0.9.9

test_that("get_url_chunks returns single chunk when batching FALSE", {
  urls <- paste0("url_", 1:20)
  result <- get_url_chunks(urls, batching = FALSE, batch_size = 5)
  expect_length(result, 1)
  expect_equal(result[[1]], urls)
})

test_that("get_url_chunks returns single chunk when count <= batch_size", {
  urls <- paste0("url_", 1:5)
  result <- get_url_chunks(urls, batching = TRUE, batch_size = 12)
  expect_length(result, 1)
})

test_that("get_url_chunks splits into correct chunks", {
  urls <- paste0("url_", 1:25)
  result <- get_url_chunks(urls, batching = TRUE, batch_size = 10)
  expect_equal(length(result), 3)
  expect_equal(length(result[[1]]), 10)
  expect_equal(length(result[[3]]), 5)
  expect_equal(sort(unlist(result, use.names = FALSE)), sort(urls))
})

test_that("resolve_output_unit_conversion returns dekad for dekadal", {
  expect_equal(resolve_output_unit_conversion("L1-AETI-D", NULL), "dekad")
})

test_that("resolve_output_unit_conversion returns none for monthly", {
  expect_equal(resolve_output_unit_conversion("L1-AETI-M", NULL), "none")
})

test_that("resolve_output_unit_conversion respects explicit none", {
  expect_equal(resolve_output_unit_conversion("L1-AETI-D", "none"), "none")
})

test_that("resolve_output_unit_conversion rejects invalid modes", {
  expect_error(resolve_output_unit_conversion("L1-AETI-D", "dekad"), "must be one of")
})

test_that("ref_year from config takes precedence over start-date year", {
  cfg_with    <- list(period = c("2018-10-01", "2019-05-31"), ref_year = 2019L)
  cfg_without <- list(period = c("2018-10-01", "2019-05-31"))
  ref_with    <- cfg_with$ref_year    %||% as.integer(format(as.Date(cfg_with$period[1]),    "%Y"))
  ref_without <- cfg_without$ref_year %||% as.integer(format(as.Date(cfg_without$period[1]), "%Y"))
  expect_equal(ref_with,    2019L)
  expect_equal(ref_without, 2018L)
})

test_that("get_url_chunks works with a single URL", {
  result <- get_url_chunks("url_1", batching = TRUE, batch_size = 12)
  expect_length(result, 1)
  expect_equal(result[[1]], "url_1")
})