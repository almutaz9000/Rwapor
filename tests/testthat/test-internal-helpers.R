# Tests for internal helpers added in v0.9.9

test_that("get_url_chunks returns single chunk when batching FALSE", {
  urls <- paste0("url_", 1:20)
  result <- Rwapor:::get_url_chunks(urls, batching = FALSE, batch_size = 5)
  expect_length(result, 1)
  expect_equal(result[[1]], urls)
})

test_that("get_url_chunks returns single chunk when count <= batch_size", {
  urls <- paste0("url_", 1:5)
  result <- Rwapor:::get_url_chunks(urls, batching = TRUE, batch_size = 12)
  expect_length(result, 1)
})

test_that("get_url_chunks splits into correct chunks", {
  urls <- paste0("url_", 1:25)
  result <- Rwapor:::get_url_chunks(urls, batching = TRUE, batch_size = 10)
  expect_equal(length(result), 3)
  expect_equal(length(result[[1]]), 10)
  expect_equal(length(result[[3]]), 5)
  expect_setequal(unlist(result, use.names = FALSE), urls)
})

test_that("resolve_output_unit_conversion returns dekad for dekadal", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", NULL), "dekad")
})

test_that("resolve_output_unit_conversion returns none for monthly", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-M", NULL), "none")
})

test_that("resolve_output_unit_conversion respects explicit none", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", "none"), "none")
})

test_that("resolve_output_unit_conversion rejects invalid modes", {
  expect_error(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", "dekad"), "must be one of")
})

test_that("map output applies an absent WaPOR scale exactly once", {
  skip_if_not_installed("terra")
  raw <- terra::rast(nrows = 1, ncols = 1, vals = 10)
  out <- Rwapor:::.wapor_prepare_map_output(raw, "L1-AETI-D", "none")
  expect_equal(as.numeric(terra::values(out)), 1)
})

test_that("kernel profile keys rebase a historic reference year", {
  skip_if_not_installed("terra")
  template <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  start_1970 <- wapor_continuous_julian("2024-01-01", 1970)
  end_1970 <- wapor_continuous_julian("2024-01-31", 1970)
  job <- Rwapor:::.wapor_build_kernel_job(
    period = c("2024-01-01", "2024-01-31"), reference_year = 1970,
    template = template, h_mask = template,
    h_start = template * 0 + start_1970, h_end = template * 0 + end_1970,
    variables = list(), work_dir = withr::local_tempdir()
  )
  expect_equal(job$profiles$start_jd, 1L)
  expect_equal(job$profiles$end_jd, 31L)
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
  result <- Rwapor:::get_url_chunks("url_1", batching = TRUE, batch_size = 12)
  expect_length(result, 1)
  expect_equal(result[[1]], "url_1")
})
