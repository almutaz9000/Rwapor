test_that("catalogue retry status policy distinguishes transient and permanent HTTP codes", {
  expect_true(Rwapor:::.wapor_is_transient_http_status(429L))
  expect_true(Rwapor:::.wapor_is_transient_http_status(503L))
  expect_false(Rwapor:::.wapor_is_transient_http_status(404L))
  expect_false(Rwapor:::.wapor_is_transient_http_status(501L))
})

test_that("remote operation retry covers a forced transient network operation", {
  attempts <- 0L
  result <- Rwapor:::.wapor_retry_remote_operation(
    function() {
      attempts <<- attempts + 1L
      if (attempts < 3L) stop("CURL error 28: Operation timed out")
      "read complete"
    },
    label = "fixture crop",
    max_retries = 3L,
    retry_delay = 0
  )
  expect_identical(result, "read complete")
  expect_equal(attempts, 3L)
})

test_that("remote retries clear cached VSI failures before another attempt", {
  attempts <- 0L
  cache_clears <- 0L
  result <- Rwapor:::.wapor_retry_remote_operation(
    function() {
      attempts <<- attempts + 1L
      if (attempts == 1L) stop("HTTP response code: 503")
      "retried successfully"
    },
    label = "fixture cached read",
    max_retries = 2L,
    retry_delay = 0,
    retry_cleanup = function() cache_clears <<- cache_clears + 1L
  )

  expect_identical(result, "retried successfully")
  expect_equal(attempts, 2L)
  expect_equal(cache_clears, 1L)
})

test_that("remote operation retry does not repeat a permanent local error", {
  attempts <- 0L
  cache_clears <- 0L
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(
      function() {
        attempts <<- attempts + 1L
        stop("Permission denied while writing output")
      },
      label = "fixture output",
      max_retries = 3L,
      retry_delay = 0,
      retry_cleanup = function() cache_clears <<- cache_clears + 1L
    ),
    "fixture output failed after 1 attempt"
  )
  expect_equal(attempts, 1L)
  expect_equal(cache_clears, 0L)
})

test_that("remote operation returning NULL fails explicitly without retry", {
  attempts <- 0L
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(
      function() {
        attempts <<- attempts + 1L
        NULL
      },
      label = "fixture reader",
      max_retries = 3L,
      retry_delay = 0
    ),
    "fixture reader failed after 1 attempt.*returned NULL"
  )
  expect_equal(attempts, 1L)
})

test_that("remote operation retry does not repeat a non-transient HTTP status", {
  attempts <- 0L
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(
      function() {
        attempts <<- attempts + 1L
        stop("HTTP response code: 501")
      },
      label = "fixture service",
      max_retries = 3L,
      retry_delay = 0
    ),
    "fixture service failed after 1 attempt"
  )
  expect_equal(attempts, 1L)
})

test_that("remote operation retry reports the final error", {
  attempts <- 0L
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(
      function() {
        attempts <<- attempts + 1L
        stop("HTTP response code: 503")
      },
      label = "fixture extraction",
      max_retries = 2L,
      retry_delay = 0
    ),
    "fixture extraction failed after 2 attempt\\(s\\): HTTP response code: 503"
  )
  expect_equal(attempts, 2L)
})

test_that("remote operation retry validates its controls", {
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(NULL),
    "operation.*function"
  )
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(identity, max_retries = 0),
    "max_retries.*positive"
  )
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(identity, retry_delay = -1),
    "retry_delay.*non-negative"
  )
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(identity, retry_cleanup = NULL),
    "retry_cleanup.*function"
  )
})

test_that("datatype probing reads a bounded leading window", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2000, ncols = 20, vals = 1)
  expect_identical(Rwapor:::.wapor_probe_datatype(r), "INT4U")
})

test_that("datatype probing does not truncate floats hidden below integer rows", {
  skip_if_not_installed("terra")
  # Top rows are exact zeros (e.g. a masked edge); fractional values below.
  vals <- c(rep(0, 20000), seq(0.01, 4.99, length.out = 980000))
  r <- terra::rast(nrows = 1000, ncols = 1000, vals = vals)
  expect_identical(Rwapor:::.wapor_probe_datatype(r), "FLT4S")

  # A later layer with fractional values must also force a float type.
  r2 <- c(terra::rast(nrows = 50, ncols = 50, vals = 1),
          terra::rast(nrows = 50, ncols = 50, vals = 0.5))
  expect_identical(Rwapor:::.wapor_probe_datatype(r2), "FLT4S")
})

test_that("wapor_write_cog writes a valid COG without creation-option noise", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 300, ncols = 300, vals = seq(0.5, 90000, length.out = 90000))
  f <- withr::local_tempfile(fileext = ".tif")
  expect_no_warning(wapor_write_cog(r, f))
  expect_equal(as.numeric(terra::values(terra::rast(f))), as.numeric(terra::values(r)),
               tolerance = 1e-6)
})
